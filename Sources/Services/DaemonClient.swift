import Foundation

/// Client that wraps the `colima` CLI binary via Process().
/// No Go daemon required — all operations shell out directly.
actor DaemonClient {
    static let shared = DaemonClient()

    init() {}

    func status(profile: String = "default") async throws -> VMStatusInfo {
        do {
            let output = try await exec("colima", ["status", "--profile", profile, "--json"])
            if let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return VMStatusInfo(
                    running: true,
                    profile: json["display_name"] as? String ?? profile,
                    arch: json["arch"] as? String ?? "",
                    runtime: json["runtime"] as? String ?? "",
                    mountType: json["mount_type"] as? String ?? "",
                    dockerSocket: json["docker_socket"] as? String ?? "",
                    cpu: json["cpu"] as? Int ?? 0,
                    memory: json["memory"] as? Int64 ?? 0,
                    disk: json["disk"] as? Int64 ?? 0,
                    version: try await version()
                )
            }
            return VMStatusInfo(running: true, profile: profile, version: try await version())
        } catch {
            // If status command fails, VM is not running
            return VMStatusInfo(running: false)
        }
    }

    func start(profile: String = "default", config: ColimaStartConfig? = nil) async throws {
        var args = ["colima", "start", profile]
        if let c = config {
            if c.cpus > 0 { args += ["--cpus", "\(c.cpus)"] }
            if c.memory > 0 { args += ["--memory", "\(c.memory)"] }
            if c.disk > 0 { args += ["--disk", "\(c.disk)"] }
            if !c.vmType.isEmpty { args += ["--vm-type", c.vmType] }
            if !c.runtime.isEmpty { args += ["--runtime", c.runtime] }
            if !c.mountType.isEmpty { args += ["--mount-type", c.mountType] }
            if c.kubernetes { args += ["--kubernetes"] }
        }
        _ = try await exec(args[0], Array(args.dropFirst()))
    }

    func stop(profile: String = "default", force: Bool = false) async throws {
        var args = ["stop", profile]
        if force { args += ["--force"] }
        _ = try await exec("colima", args)
    }

    func restart(profile: String = "default") async throws {
        _ = try await exec("colima", "restart", profile)
    }

    func delete(profile: String = "default", data: Bool = false, force: Bool = false) async throws {
        var args = ["delete", profile]
        if data { args += ["--data"] }
        if force { args += ["--force"] }
        _ = try await exec("colima", args)
    }

    func version() async throws -> String {
        let output = try await exec("colima", ["version"])
        // Parse "colima version 0.10.1" from first line
        let firstLine = output.components(separatedBy: "\n").first ?? ""
        return firstLine.replacingOccurrences(of: "colima version ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listProfiles() async throws -> [ProfileListItem] {
        let output = try await exec("colima", "list", "--json")
        var profiles: [ProfileListItem] = []
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                profiles.append(ProfileListItem(
                    name: json["name"] as? String ?? "",
                    status: json["status"] as? String ?? "Unknown",
                    arch: json["arch"] as? String ?? "",
                    cpus: json["cpus"] as? Int ?? 0,
                    memory: json["memory"] as? Int64 ?? 0,
                    disk: json["disk"] as? Int64 ?? 0,
                    runtime: json["runtime"] as? String ?? ""
                ))
            }
        }
        return profiles
    }

    func sshConfig(profile: String = "default") async throws -> String {
        return try await exec("colima", "ssh-config", "--profile", profile)
    }

    func update(profile: String = "default") async throws {
        _ = try await exec("colima", "update", profile)
    }

    func prune(all: Bool = false) async throws {
        var args = ["prune", "--force"]
        if all { args += ["--all"] }
        _ = try await exec("colima", args)
    }

    func kubernetesStart(profile: String = "default") async throws {
        _ = try await exec("colima", "kubernetes", "start", "--profile", profile)
    }

    func kubernetesStop(profile: String = "default") async throws {
        _ = try await exec("colima", "kubernetes", "stop", "--profile", profile)
    }

    func kubernetesReset(profile: String = "default") async throws {
        _ = try await exec("colima", "kubernetes", "reset", "--profile", profile)
    }

    func kubectlExec(_ command: String) async throws -> String {
        let args = command.components(separatedBy: " ")
        return try await exec("kubectl", args)
    }

    func processList(profile: String = "default") async throws -> String {
        return try await exec("colima", "ssh", "--profile", profile, "--", "ps", "aux")
    }

    func killProcess(profile: String = "default", pid: Int, signal: Int = 9) async throws {
        _ = try await exec("colima", "ssh", "--profile", profile, "--", "kill", "-\(signal)", "\(pid)")
    }

    func switchProfile(name: String) async throws {
        _ = try await exec("colima", "stop")
        _ = try await exec("colima", "start", "--profile", name)
    }

    // MARK: - Configuration (read/write YAML directly — NEVER use colima template)

    func readConfig(profile: String = "default") async throws -> ColimaConfig {
        let path = configPath(profile: profile)
        guard FileManager.default.fileExists(atPath: path) else {
            throw DaemonError.commandFailed("readConfig", 1, "Config file not found: \(path)")
        }
        let yaml = try String(contentsOfFile: path, encoding: .utf8)
        return ColimaConfig.fromYAML(yaml)
    }

    func writeConfig(profile: String = "default", config: ColimaConfig) async throws {
        let path = configPath(profile: profile)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try config.toYAML().write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func configPath(profile: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.colima/\(profile)/colima.yaml"
    }

    // MARK: - Process Execution

    private func exec(_ command: String, _ args: String...) async throws -> String {
        try await exec(command, args)
    }

    private func exec(_ command: String, _ args: [String]) async throws -> String {
        let process = Process()
        let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        // Resolve full path for known commands
        if command == "colima" || command == "docker" || command == "kubectl" {
            let resolvedCommand = searchPaths.map { "\($0)/\(command)" }
                .first { FileManager.default.fileExists(atPath: $0) } ?? command
            process.executableURL = URL(fileURLWithPath: resolvedCommand)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
        }

        // Ensure PATH includes homebrew so colima can find limactl, qemu, etc.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(data: errData, encoding: .utf8) ?? ""
            throw DaemonError.commandFailed(command, process.terminationStatus, errOutput.isEmpty ? output : errOutput)
        }

        return output
    }
}

// MARK: - Types

struct VMStatusInfo {
    var running: Bool
    var profile: String = "default"
    var arch: String = ""
    var runtime: String = ""
    var mountType: String = ""
    var ipAddress: String = ""
    var dockerSocket: String = ""
    var cpu: Int = 0
    var memory: Int64 = 0
    var disk: Int64 = 0
    var version: String = ""
}

struct ColimaStartConfig {
    var cpus: Int = 0
    var memory: Int = 0
    var disk: Int = 0
    var vmType: String = ""
    var runtime: String = ""
    var mountType: String = ""
    var kubernetes: Bool = false
}

struct ProfileListItem {
    var name: String
    var status: String
    var arch: String
    var cpus: Int
    var memory: Int64
    var disk: Int64
    var runtime: String
}

// MARK: - Errors

enum DaemonError: Error, LocalizedError {
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code, let msg): return "\(cmd) failed (\(code)): \(msg)"
        }
    }
}

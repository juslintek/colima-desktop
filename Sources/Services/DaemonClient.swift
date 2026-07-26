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
                let driverStr = json["driver"] as? String ?? ""
                let vmTypeFromDriver: String = {
                    if driverStr.lowercased().contains("virtualization") { return "vz" }
                    if driverStr.lowercased().contains("qemu") { return "qemu" }
                    if driverStr.lowercased().contains("krunkit") { return "krunkit" }
                    return driverStr
                }()
                return VMStatusInfo(
                    running: true,
                    profile: json["display_name"] as? String ?? profile,
                    arch: json["arch"] as? String ?? "",
                    runtime: json["runtime"] as? String ?? "",
                    mountType: json["mount_type"] as? String ?? "",
                    vmType: vmTypeFromDriver,
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

    /// Real Lima VMs via `limactl list --json` (one JSON object per line).
    func listMachines() async throws -> [[String: Any]] {
        let output = try await exec("limactl", "list", "--json")
        var machines: [[String: Any]] = []
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                machines.append(json)
            }
        }
        return machines
    }

    func sshConfig(profile: String = "default") async throws -> String {
        return try await exec("colima", "ssh-config", "--profile", profile)
    }

    func update(profile: String = "default") async throws {
        _ = try await exec("colima", "--profile", profile, "update")
    }

    func prune(profile: String = "default", all: Bool = false) async throws {
        var args = ["--profile", profile, "prune", "--force"]
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

    func kubectlExec(_ command: String, profile: String = "default") async throws -> String {
        let args = command.components(separatedBy: " ")
        return try await exec("kubectl", ["--context", "colima-\(profile)"] + args)
    }

    func processList(profile: String = "default") async throws -> String {
        return try await exec("colima", "ssh", "--profile", profile, "--", "ps", "aux")
    }

    func killProcess(profile: String = "default", pid: Int, signal: Int = 9) async throws {
        _ = try await exec("colima", "ssh", "--profile", profile, "--", "kill", "-\(signal)", "\(pid)")
    }

    // MARK: - Configuration (read/write YAML directly — NEVER use colima template)

    func readConfig(profile: String = "default") async throws -> ColimaConfig {
        let path = configPath(profile: profile)
        guard FileManager.default.fileExists(atPath: path) else {
            throw DaemonError.commandFailed("readConfig", 1, "Config file not found: \(path)")
        }
        let yaml = try String(contentsOfFile: path, encoding: .utf8)
        // Surface a structurally-unsafe config with actionable context instead
        // of silently loading a lossy best-effort model. When this throws, the
        // model is never populated from the file, so the write guard below then
        // refuses to overwrite the config we failed to parse.
        do {
            return try ColimaConfig.parse(yaml)
        } catch let error as ColimaConfig.ParseError {
            throw DaemonError.commandFailed(
                "readConfig", 2,
                "\(path) exists but could not be parsed. \(error.localizedDescription) "
                    + "Fix it with Edit YAML before saving so its contents are not lost."
            )
        }
    }

    func writeConfig(profile: String = "default", config: ColimaConfig) async throws {
        let path = configPath(profile: profile)
        // Never silently overwrite a config we did not successfully load. A
        // config that originated from a real load carries the file's
        // `sourceYAML`; a blank/reconstructed model (empty `sourceYAML`) written
        // over an existing file would drop every unknown key, so refuse it and
        // surface an actionable error. Writing a fresh config to a new profile
        // (no file yet) is still allowed.
        if FileManager.default.fileExists(atPath: path), (config.sourceYAML ?? "").isEmpty {
            throw DaemonError.commandFailed(
                "writeConfig", 2,
                "Refusing to overwrite \(path): its current contents were not loaded, so "
                    + "unknown keys would be lost. Reopen the profile to load the existing config, "
                    + "or use Edit YAML to inspect it."
            )
        }
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try config.toYAML().write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func configPath(profile: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.colima/\(profile)/colima.yaml"
    }

    // MARK: - Template (base config for newly created VMs — read/write YAML directly)
    //
    // Mirrors the daemon's GetTemplate/SetTemplate contract
    // (daemon/internal/server/config_server.go): the template YAML file is read
    // and written directly — never the interactive `colima template` editor,
    // which opens $EDITOR and cannot be scripted. The default profile resolves
    // to ~/.colima/_templates/default.yaml (byte-identical to the daemon and the
    // colima CLI); a named profile resolves to a profile-scoped override
    // ~/.colima/_templates/<profile>.yaml so editing one profile's template
    // never clobbers the shared default other new VMs rely on.

    /// Read the template for a profile. Falls back to the shared default
    /// template when a profile-scoped override does not exist, and returns an
    /// empty config when no template exists at all (daemon parity: an absent
    /// template yields an empty ColimaConfig rather than an error).
    func getTemplate(profile: String = "default") async throws -> ColimaConfig {
        let path = ColimaTemplate.path(profile: profile, colimaHome: colimaHome())
        if FileManager.default.fileExists(atPath: path) {
            let yaml = try String(contentsOfFile: path, encoding: .utf8)
            return ColimaTemplate.decode(yaml)
        }
        let defaultPath = ColimaTemplate.defaultPath(colimaHome: colimaHome())
        if path != defaultPath, FileManager.default.fileExists(atPath: defaultPath) {
            let yaml = try String(contentsOfFile: defaultPath, encoding: .utf8)
            return ColimaTemplate.decode(yaml)
        }
        return ColimaConfig()
    }

    /// Write the template for a profile, creating the templates directory when
    /// needed. Saving through `setTemplate` and reading back through
    /// `getTemplate` returns equivalent content (Property 18).
    func setTemplate(profile: String = "default", config: ColimaConfig) async throws {
        let path = ColimaTemplate.path(profile: profile, colimaHome: colimaHome())
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try ColimaTemplate.encode(config).write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func colimaHome() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.colima"
    }

    // MARK: - Process Execution

    /// True if the `colima` binary is present in a known location.
    func isInstalled() -> Bool {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .contains { FileManager.default.fileExists(atPath: "\($0)/colima") }
    }

    /// Install Colima (and the docker CLI) via Homebrew. Long-running.
    func install() async throws {
        _ = try await exec("brew", ["install", "colima", "docker"])
    }

    private func exec(_ command: String, _ args: String...) async throws -> String {
        try await exec(command, args)
    }

    private func exec(_ command: String, _ args: [String]) async throws -> String {
        let process = Process()
        let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        // Resolve full path for known commands
        if command == "colima" || command == "docker" || command == "kubectl" || command == "limactl" {
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
        // Drain stdout+stderr concurrently BEFORE waiting. Reading after waitUntilExit()
        // deadlocks when a command emits more than the ~64KB pipe buffer (e.g. `colima
        // start` logs, `docker logs`): the child blocks on write and never exits.
        let outHandle = pipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        async let outRead = Task.detached { outHandle.readDataToEndOfFile() }.value
        async let errRead = Task.detached { errHandle.readDataToEndOfFile() }.value
        let data = await outRead
        let errData = await errRead
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
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
    var vmType: String = ""
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
    case invalidProfile(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let code, let msg): return "\(cmd) failed (\(code)): \(msg)"
        case .invalidProfile(let profile): return "Invalid profile name: \(profile)"
        }
    }
}

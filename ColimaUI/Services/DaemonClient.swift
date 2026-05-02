import Foundation

/// Client for the colima-ui Go daemon over Unix domain socket gRPC.
/// Manages daemon lifecycle (launch, health check, restart on crash).
actor DaemonClient {
    private let socketPath: String
    private var daemonProcess: Process?
    private var isConnected = false

    static let shared = DaemonClient()

    init(socketPath: String = "/tmp/colima-ui.sock") {
        self.socketPath = socketPath
    }

    // MARK: - Daemon Lifecycle

    func ensureRunning() async throws {
        if isConnected { return }
        try await startDaemon()
    }

    private func startDaemon() async throws {
        let daemonPath = Bundle.main.path(forAuxiliaryExecutable: "colima-daemon")
            ?? "/usr/local/bin/colima-daemon"

        guard FileManager.default.fileExists(atPath: daemonPath) else {
            throw DaemonError.daemonNotFound(daemonPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: daemonPath)
        process.arguments = ["--socket", socketPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleCrash() }
        }

        try process.run()
        daemonProcess = process

        // Wait for socket to appear
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: socketPath) {
                isConnected = true
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        throw DaemonError.connectionTimeout
    }

    private func handleCrash() {
        isConnected = false
        // Auto-restart after 1 second
        Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await startDaemon()
        }
    }

    func shutdown() {
        daemonProcess?.terminate()
        daemonProcess = nil
        isConnected = false
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    // MARK: - gRPC Calls (using Process-based CLI bridge for now)
    // In production, this would use grpc-swift NIO client.
    // For initial implementation, we bridge via colima CLI commands.

    func status(profile: String = "default") async throws -> VMStatusInfo {
        let output = try await exec("colima", "status", "--profile", profile, "--json")
        // Parse colima status output
        if output.contains("not running") {
            return VMStatusInfo(running: false)
        }
        return VMStatusInfo(
            running: true,
            profile: profile,
            version: try await version()
        )
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
        let output = try await exec("colima", "version")
        // Parse "colima version 0.10.1"
        return output.components(separatedBy: " ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    // MARK: - Process Execution

    private func exec(_ command: String, _ args: String...) async throws -> String {
        try await exec(command, args)
    }

    private func exec(_ command: String, _ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args

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
    case daemonNotFound(String)
    case connectionTimeout
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .daemonNotFound(let path): return "Daemon not found at \(path)"
        case .connectionTimeout: return "Daemon connection timeout"
        case .commandFailed(let cmd, let code, let msg): return "\(cmd) failed (\(code)): \(msg)"
        }
    }
}

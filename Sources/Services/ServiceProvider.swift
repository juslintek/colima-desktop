import Foundation

/// A single atomic snapshot of the profile-bound service context. Rebinding
/// replaces the Docker actor and profile together; callers never observe a new
/// profile paired with the previous profile's socket.
private final class ProfileServiceContext {
    struct Snapshot {
        let profile: String
        let docker: DockerClient
    }

    private let lock = NSLock()
    private var value: Snapshot

    init(profile: String) {
        value = Snapshot(profile: profile, docker: DockerClient(profile: profile))
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func rebind(to profile: String) throws {
        let trimmed = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == profile,
              !profile.contains("/"),
              !profile.contains("\\"),
              profile != ".",
              profile != ".." else {
            throw DaemonError.invalidProfile(profile)
        }

        let replacement = Snapshot(profile: profile, docker: DockerClient(profile: profile))
        lock.lock()
        value = replacement
        lock.unlock()
    }
}

/// Protocol defining all backend operations.
/// AppState calls these methods. In tests, MockServiceProvider is used.
/// In production, RealServiceProvider wraps DaemonClient + DockerClient.
protocol ServiceProvider {
    // VM
    func startVM(profile: String) async throws
    func stopVM(profile: String, force: Bool) async throws
    func restartVM(profile: String) async throws
    func deleteVM(profile: String, data: Bool) async throws
    func vmStatus(profile: String) async throws -> VMStatusInfo
    func vmVersion() async throws -> String
    func updateVM(profile: String) async throws
    func pruneVM(profile: String, all: Bool) async throws
    func sshConfig(profile: String) async throws -> String

    // Profiles
    func listProfiles() async throws -> [ProfileListItem]
    func createProfile(name: String, config: ColimaStartConfig) async throws
    func deleteProfile(name: String, data: Bool) async throws
    func cloneProfile(source: String, dest: String) async throws

    // Machines (Lima VMs)
    func listMachines() async throws -> [[String: Any]]

    // Kubernetes
    func k8sStart(profile: String) async throws
    func k8sStop(profile: String) async throws
    func k8sReset(profile: String) async throws
    func kubectlExec(_ command: String, profile: String) async throws -> String

    // Containers
    func listContainers() async throws -> [[String: Any]]
    func startContainer(id: String) async throws
    func stopContainer(id: String) async throws
    func killContainer(id: String) async throws
    func restartContainer(id: String) async throws
    func pauseContainer(id: String) async throws
    func unpauseContainer(id: String) async throws
    func removeContainer(id: String) async throws
    func createContainer(name: String, image: String) async throws -> String
    func createContainer(name: String, image: String, options: ContainerCreateOptions) async throws -> String
    func renameContainer(id: String, newName: String) async throws
    func containerLogs(id: String) async throws -> String
    func inspectContainer(id: String) async throws -> String
    func containerTop(id: String) async throws -> String
    func containerStats(id: String) async throws -> String
    func containerChanges(id: String) async throws -> String
    func pruneContainers() async throws

    // Images
    func listImages() async throws -> [[String: Any]]
    func pullImage(name: String) async throws
    func pullImage(name: String, onProgress: @escaping (ImagePullProgress) -> Void) async throws
    func removeImage(id: String) async throws
    func inspectImage(name: String) async throws -> String
    func imageHistory(name: String) async throws -> String
    func tagImage(name: String, repo: String, tag: String) async throws
    func pushImage(name: String) async throws
    func searchImages(term: String) async throws -> [[String: Any]]
    func pruneImages() async throws

    // Volumes
    func listVolumes() async throws -> [[String: Any]]
    func createVolume(name: String) async throws
    func removeVolume(name: String) async throws
    func inspectVolume(name: String) async throws -> String
    func pruneVolumes() async throws

    // Networks
    func listNetworks() async throws -> [[String: Any]]
    func createNetwork(name: String) async throws
    func removeNetwork(name: String) async throws
    func inspectNetwork(id: String) async throws -> String
    func connectNetwork(networkId: String, containerId: String) async throws
    func disconnectNetwork(networkId: String, containerId: String) async throws
    func pruneNetworks() async throws

    // Monitoring
    func processList(profile: String) async throws -> String
    func killProcess(profile: String, pid: Int) async throws

    // Streaming
    func streamEvents(handler: @escaping (DockerEvent) -> Void) -> Task<Void, Never>?
    func streamLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never>?
    func streamStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never>?

    // Profile switching
    func switchProfile(name: String) async throws

    // Configuration
    func readConfig(profile: String) async throws -> ColimaConfig
    func writeConfig(profile: String, config: ColimaConfig) async throws

    // Template (base config for newly created VMs — GetTemplate / SetTemplate)
    func getTemplate(profile: String) async throws -> ColimaConfig
    func setTemplate(profile: String, config: ColimaConfig) async throws

    // Command execution
    func executeCommand(tool: String, args: [String], profile: String?) async throws -> String

    // AI Models
    func modelList(runner: String, profile: String) async throws -> [AIModelInfo]
    func modelPull(name: String, runner: String, profile: String) async throws
    func modelRun(name: String, runner: String, profile: String) async throws
    func modelServe(name: String?, runner: String, port: Int?, profile: String) async throws
    func modelStop(name: String, profile: String) async throws

    // Installation
    func isColimaInstalled() async -> Bool
    func installColima() async throws
}

/// Real implementation using DaemonClient + DockerClient
class RealServiceProvider: ServiceProvider {
    private let daemon = DaemonClient.shared
    private let context: ProfileServiceContext
    private var docker: DockerClient { context.snapshot().docker }

    init(profile: String = "default") {
        self.context = ProfileServiceContext(profile: profile)
    }

    // MARK: - VM

    func startVM(profile: String) async throws {
        try await daemon.start(profile: profile)
    }

    func stopVM(profile: String, force: Bool) async throws {
        try await daemon.stop(profile: profile, force: force)
    }

    func restartVM(profile: String) async throws {
        try await daemon.restart(profile: profile)
    }

    func deleteVM(profile: String, data: Bool) async throws {
        try await daemon.delete(profile: profile, data: data, force: true)
    }

    func vmStatus(profile: String) async throws -> VMStatusInfo {
        return try await daemon.status(profile: profile)
    }

    func vmVersion() async throws -> String {
        return try await daemon.version()
    }

    func updateVM(profile: String = "default") async throws {
        try await daemon.update(profile: profile)
    }

    func pruneVM(profile: String = "default", all: Bool) async throws {
        try await daemon.prune(profile: profile, all: all)
    }

    func sshConfig(profile: String) async throws -> String {
        return try await daemon.sshConfig(profile: profile)
    }

    // MARK: - Profiles

    func listProfiles() async throws -> [ProfileListItem] {
        return try await daemon.listProfiles()
    }

    func createProfile(name: String, config: ColimaStartConfig) async throws {
        try await daemon.start(profile: name, config: config)
    }

    func deleteProfile(name: String, data: Bool) async throws {
        try await daemon.delete(profile: name, data: data, force: true)
    }

    func cloneProfile(source: String, dest: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["colima", "clone", source, dest]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw DaemonError.commandFailed("colima clone", process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Machines

    func listMachines() async throws -> [[String: Any]] {
        try await daemon.listMachines()
    }

    // MARK: - Kubernetes

    func k8sStart(profile: String) async throws {
        try await daemon.kubernetesStart(profile: profile)
    }

    func k8sStop(profile: String) async throws {
        try await daemon.kubernetesStop(profile: profile)
    }

    func k8sReset(profile: String) async throws {
        try await daemon.kubernetesReset(profile: profile)
    }

    func kubectlExec(_ command: String, profile: String = "default") async throws -> String {
        return try await daemon.kubectlExec(command, profile: profile)
    }

    // MARK: - Containers

    func listContainers() async throws -> [[String: Any]] {
        return try await docker.listContainers()
    }

    func startContainer(id: String) async throws {
        try await docker.startContainer(id: id)
    }

    func stopContainer(id: String) async throws {
        try await docker.stopContainer(id: id)
    }

    func killContainer(id: String) async throws {
        try await docker.killContainer(id: id)
    }

    func restartContainer(id: String) async throws {
        try await docker.restartContainer(id: id)
    }

    func pauseContainer(id: String) async throws {
        try await docker.pauseContainer(id: id)
    }

    func unpauseContainer(id: String) async throws {
        try await docker.unpauseContainer(id: id)
    }

    func removeContainer(id: String) async throws {
        try await docker.removeContainer(id: id, force: true)
    }

    func createContainer(name: String, image: String) async throws -> String {
        return try await docker.createContainer(name: name, image: image)
    }

    func createContainer(name: String, image: String, options: ContainerCreateOptions) async throws -> String {
        var config: [String: Any] = [:]
        var hostConfig: [String: Any] = [
            "AutoRemove": options.autoRemove,
            "Privileged": options.privileged,
            "ReadonlyRootfs": options.readOnlyRootFilesystem,
            "Init": options.useInit,
            "RestartPolicy": ["Name": options.restartPolicy, "MaximumRetryCount": 0],
        ]
        if options.autoRemove {
            // Docker rejects AutoRemove combined with a restart policy.
            hostConfig["RestartPolicy"] = ["Name": "no", "MaximumRetryCount": 0]
        }
        config["HostConfig"] = hostConfig
        if !options.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config["Cmd"] = ["/bin/sh", "-lc", options.command]
        }
        if !options.entrypoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config["Entrypoint"] = options.entrypoint
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
        }
        if !options.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config["WorkingDir"] = options.workingDirectory
        }
        let platform = options.platform == "auto" ? nil : options.platform
        return try await docker.createContainer(name: name, image: image, platform: platform, config: config)
    }

    func renameContainer(id: String, newName: String) async throws {
        try await docker.renameContainer(id: id, newName: newName)
    }

    func containerLogs(id: String) async throws -> String {
        return try await docker.containerLogs(id: id)
    }

    func inspectContainer(id: String) async throws -> String {
        let json = try await docker.inspectContainer(id: id)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func containerTop(id: String) async throws -> String {
        let json = try await docker.containerTop(id: id)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func containerStats(id: String) async throws -> String {
        let json = try await docker.containerStats(id: id)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func containerChanges(id: String) async throws -> String {
        let json = try await docker.containerChanges(id: id)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func pruneContainers() async throws {
        _ = try await docker.pruneContainers()
    }

    // MARK: - Images

    func listImages() async throws -> [[String: Any]] {
        return try await docker.listImages()
    }

    func pullImage(name: String) async throws {
        try await docker.pullImage(name: name)
    }

    func pullImage(name: String, onProgress: @escaping (ImagePullProgress) -> Void) async throws {
        // Real OBSERVED progress: DockerClient reads the Docker Engine
        // `/images/create` stream directly over the profile-scoped unix socket
        // and reports per-layer progressDetail as it arrives.
        try await docker.pullImageStreaming(name: name, onProgress: onProgress)
    }

    func removeImage(id: String) async throws {
        try await docker.removeImage(name: id)
    }

    func inspectImage(name: String) async throws -> String {
        let json = try await docker.inspectImage(name: name)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func imageHistory(name: String) async throws -> String {
        let json = try await docker.imageHistory(name: name)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func tagImage(name: String, repo: String, tag: String) async throws {
        try await docker.tagImage(name: name, repo: repo, tag: tag)
    }

    func pushImage(name: String) async throws {
        throw ServiceProviderError.unsupported(
            "Registry push requires an authenticated credential handoff, which is not available in this app build. Use the profile-scoped Runtime command palette: docker push \(name)"
        )
    }

    func searchImages(term: String) async throws -> [[String: Any]] {
        return try await docker.searchImages(term: term)
    }

    func pruneImages() async throws {
        _ = try await docker.pruneImages()
    }

    // MARK: - Volumes

    func listVolumes() async throws -> [[String: Any]] {
        let result = try await docker.listVolumes()
        return result["Volumes"] as? [[String: Any]] ?? []
    }

    func createVolume(name: String) async throws {
        _ = try await docker.createVolume(name: name)
    }

    func removeVolume(name: String) async throws {
        try await docker.removeVolume(name: name)
    }

    func inspectVolume(name: String) async throws -> String {
        let json = try await docker.inspectVolume(name: name)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func pruneVolumes() async throws {
        _ = try await docker.pruneVolumes()
    }

    // MARK: - Networks

    func listNetworks() async throws -> [[String: Any]] {
        return try await docker.listNetworks()
    }

    func createNetwork(name: String) async throws {
        _ = try await docker.createNetwork(name: name)
    }

    func removeNetwork(name: String) async throws {
        try await docker.removeNetwork(id: name)
    }

    func inspectNetwork(id: String) async throws -> String {
        let json = try await docker.inspectNetwork(id: id)
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func connectNetwork(networkId: String, containerId: String) async throws {
        try await docker.connectNetwork(networkId: networkId, containerId: containerId)
    }

    func disconnectNetwork(networkId: String, containerId: String) async throws {
        try await docker.disconnectNetwork(networkId: networkId, containerId: containerId)
    }

    func pruneNetworks() async throws {
        _ = try await docker.pruneNetworks()
    }

    // MARK: - Monitoring

    func processList(profile: String) async throws -> String {
        return try await daemon.processList(profile: profile)
    }

    func killProcess(profile: String, pid: Int) async throws {
        try await daemon.killProcess(profile: profile, pid: pid)
    }

    // MARK: - Streaming

    func streamEvents(handler: @escaping (DockerEvent) -> Void) -> Task<Void, Never>? {
        let boundDocker = docker
        return Task {
            let stream = await boundDocker.streamEvents(handler: handler)
            await withTaskCancellationHandler {
                await stream.value
            } onCancel: {
                stream.cancel()
            }
        }
    }

    func streamLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never>? {
        let boundDocker = docker
        return Task {
            let stream = await boundDocker.streamLogs(containerId: containerId, handler: handler)
            await withTaskCancellationHandler {
                await stream.value
            } onCancel: {
                stream.cancel()
            }
        }
    }

    func streamStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never>? {
        let boundDocker = docker
        return Task {
            let stream = await boundDocker.streamStats(containerId: containerId, handler: handler)
            await withTaskCancellationHandler {
                await stream.value
            } onCancel: {
                stream.cancel()
            }
        }
    }

    // MARK: - Profile Switching

    func switchProfile(name: String) async throws {
        try context.rebind(to: name)
    }

    // MARK: - Configuration

    func readConfig(profile: String) async throws -> ColimaConfig {
        return try await daemon.readConfig(profile: profile)
    }

    func writeConfig(profile: String, config: ColimaConfig) async throws {
        try await daemon.writeConfig(profile: profile, config: config)
    }

    // MARK: - Template

    func getTemplate(profile: String) async throws -> ColimaConfig {
        return try await daemon.getTemplate(profile: profile)
    }

    func setTemplate(profile: String, config: ColimaConfig) async throws {
        try await daemon.setTemplate(profile: profile, config: config)
    }

    // MARK: - Command Execution

    func executeCommand(tool: String, args: [String], profile: String? = nil) async throws -> String {
        let profile = profile ?? context.snapshot().profile
        var scopedTool = tool
        var scopedArgs = args
        var additionalEnvironment: [String: String] = [:]

        switch tool {
        case "colima":
            scopedArgs = ["--profile", profile] + removingOption(["--profile", "-p"], from: args)
        case "kubectl":
            scopedArgs = ["--context", "colima-\(profile)"] + removingOption(["--context"], from: args)
        case "docker":
            let socket = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".colima/\(profile)/docker.sock").path
            additionalEnvironment["DOCKER_HOST"] = "unix://\(socket)"
        case "nerdctl":
            // Colima's wrapper enters the selected VM/runtime. Calling a host
            // nerdctl binary would otherwise use whichever global context wins.
            scopedTool = "colima"
            scopedArgs = ["--profile", profile, "nerdctl", "--"] + args
        case "incus":
            // Incus runs in the selected Colima VM; do not target a host remote.
            scopedTool = "colima"
            scopedArgs = ["--profile", profile, "ssh", "--", "incus"] + args
        default:
            break
        }

        let process = Process()
        let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let resolved = searchPaths.map { "\($0)/\(scopedTool)" }
            .first { FileManager.default.fileExists(atPath: $0) } ?? scopedTool
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = scopedArgs
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        if tool == "docker" { env.removeValue(forKey: "DOCKER_CONTEXT") }
        for (key, value) in additionalEnvironment { env[key] = value }
        process.environment = env
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        try process.run()
        // Drain concurrently before waiting (avoid >64KB pipe-buffer deadlock).
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
            throw DaemonError.commandFailed(scopedTool, process.terminationStatus, errOutput.isEmpty ? output : errOutput)
        }
        return output
    }

    private func removingOption(_ optionNames: Set<String>, from args: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < args.count {
            let argument = args[index]
            if optionNames.contains(argument) {
                index += min(2, args.count - index)
                continue
            }
            if optionNames.contains(where: { argument.hasPrefix("\($0)=") }) {
                index += 1
                continue
            }
            result.append(argument)
            index += 1
        }
        return result
    }

    func isColimaInstalled() async -> Bool { await daemon.isInstalled() }
    func installColima() async throws { try await daemon.install() }

    // MARK: - AI Models

    func modelList(runner: String, profile: String = "default") async throws -> [AIModelInfo] {
        let output = try await executeCommand(tool: "colima", args: ["model", "list", "--runner", runner], profile: profile)
        return AIModelInfo.parse(output)
    }

    func modelPull(name: String, runner: String, profile: String = "default") async throws {
        _ = try await executeCommand(tool: "colima", args: ["model", "pull", name, "--runner", runner], profile: profile)
    }

    func modelRun(name: String, runner: String, profile: String = "default") async throws {
        _ = try await executeCommand(tool: "colima", args: ["model", "run", name, "--runner", runner], profile: profile)
    }

    func modelServe(name: String?, runner: String, port: Int?, profile: String = "default") async throws {
        var args = ["model", "serve"]
        if let name { args.append(name) }
        args += ["--runner", runner]
        if let port { args += ["--port", "\(port)"] }
        _ = try await executeCommand(tool: "colima", args: args, profile: profile)
    }

    func modelStop(name: String, profile: String = "default") async throws {
        // Stop a running/serving model (docker stop the model container)
        _ = try await executeCommand(tool: "docker", args: ["stop", name], profile: profile)
    }
}

enum ServiceProviderError: LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message): return message
        }
    }
}

extension ServiceProvider {
    func createContainer(name: String, image: String, options: ContainerCreateOptions) async throws -> String {
        try await createContainer(name: name, image: image)
    }

    /// Default fallback for providers that do not stream observed progress:
    /// perform the plain pull and report a single terminal snapshot. The real
    /// and mock providers override this with progress-reporting variants.
    func pullImage(name: String, onProgress: @escaping (ImagePullProgress) -> Void) async throws {
        try await pullImage(name: name)
        onProgress(ImagePullProgress(status: "Complete", finished: true))
    }
}

// Make DaemonClient.exec accessible to RealServiceProvider

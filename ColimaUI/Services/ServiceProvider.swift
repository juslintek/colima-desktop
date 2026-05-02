import Foundation

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
    func updateVM() async throws
    func pruneVM(all: Bool) async throws
    func sshConfig(profile: String) async throws -> String

    // Profiles
    func listProfiles() async throws -> [ProfileListItem]
    func createProfile(name: String, config: ColimaStartConfig) async throws
    func deleteProfile(name: String, data: Bool) async throws
    func cloneProfile(source: String, dest: String) async throws

    // Kubernetes
    func k8sStart(profile: String) async throws
    func k8sStop(profile: String) async throws
    func k8sReset(profile: String) async throws
    func kubectlExec(_ command: String) async throws -> String

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
}

/// Real implementation using DaemonClient + DockerClient
class RealServiceProvider: ServiceProvider {
    private let daemon = DaemonClient.shared
    private var docker: DockerClient

    init(profile: String = "default") {
        self.docker = DockerClient(profile: profile)
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

    func updateVM() async throws {
        try await daemon.update()
    }

    func pruneVM(all: Bool) async throws {
        try await daemon.prune(all: all)
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

    func kubectlExec(_ command: String) async throws -> String {
        return try await daemon.kubectlExec(command)
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
        // Push requires auth — for now just validate the image exists
        _ = try await docker.inspectImage(name: name)
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
}

// Make DaemonClient.exec accessible to RealServiceProvider

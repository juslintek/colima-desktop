import Testing
import Foundation
@testable import ColimaDesktop

/// Tests that run against a real Colima/Docker instance.
/// Requires: colima running with Docker socket at ~/.colima/default/docker.sock
@Suite("RealBackend", .serialized)
struct RealBackendTests {
    let services: RealServiceProvider

    init() {
        services = RealServiceProvider()
    }

    // MARK: - Prerequisites

    @Test("Docker socket exists and is reachable")
    func dockerSocketReachable() async throws {
        let containers = try await services.listContainers()
        #expect(containers is [[String: Any]])
    }

    // MARK: - VM Lifecycle

    @Test("vmStatus returns running state")
    func vmStatus() async throws {
        let status = try await services.vmStatus(profile: "default")
        #expect(status.running == true)
        #expect(!status.profile.isEmpty)
    }

    @Test("vmVersion returns non-empty version")
    func vmVersion() async throws {
        let version = try await services.vmVersion()
        #expect(!version.isEmpty)
        #expect(version.contains("."))
    }

    @Test("sshConfig returns valid SSH config")
    func sshConfig() async throws {
        let config = try await services.sshConfig(profile: "default")
        #expect(config.contains("Host"))
    }

    // MARK: - Container Operations

    @Test("listContainers returns array")
    func listContainers() async throws {
        let containers = try await services.listContainers()
        #expect(containers is [[String: Any]])
    }

    @Test("createContainer creates and appears in list")
    func createContainer() async throws {
        let id = try await services.createContainer(name: "test-create", image: "alpine:latest")
        #expect(!id.isEmpty)
        let containers = try await services.listContainers()
        let found = containers.contains { ($0["Id"] as? String)?.hasPrefix(id.prefix(12).description) == true }
        #expect(found)
        // Cleanup
        try await services.removeContainer(id: "test-create")
    }

    @Test("startContainer changes state to running")
    func startContainer() async throws {
        _ = try await services.createContainer(name: "test-start", image: "alpine:latest")
        try await services.startContainer(id: "test-start")
        let containers = try await services.listContainers()
        let container = containers.first { ($0["Names"] as? [String])?.first?.contains("test-start") == true }
        #expect(container?["State"] as? String == "running")
        // Cleanup
        try await services.killContainer(id: "test-start")
        try await services.removeContainer(id: "test-start")
    }

    @Test("stopContainer changes state to exited")
    func stopContainer() async throws {
        _ = try await services.createContainer(name: "test-stop", image: "alpine:latest")
        try await services.startContainer(id: "test-stop")
        try await services.stopContainer(id: "test-stop")
        let containers = try await services.listContainers()
        let container = containers.first { ($0["Names"] as? [String])?.first?.contains("test-stop") == true }
        #expect(container?["State"] as? String == "exited")
        try await services.removeContainer(id: "test-stop")
    }

    @Test("killContainer terminates container")
    func killContainer() async throws {
        _ = try await services.createContainer(name: "test-kill", image: "alpine:latest")
        try await services.startContainer(id: "test-kill")
        try await services.killContainer(id: "test-kill")
        try await Task.sleep(nanoseconds: 500_000_000) // Wait for state to update
        let containers = try await services.listContainers()
        let container = containers.first { ($0["Names"] as? [String])?.first?.contains("test-kill") == true }
        #expect(container?["State"] as? String == "exited")
        try await services.removeContainer(id: "test-kill")
    }

    @Test("restartContainer keeps running")
    func restartContainer() async throws {
        _ = try await services.createContainer(name: "test-restart", image: "alpine:latest")
        try await services.startContainer(id: "test-restart")
        try await services.restartContainer(id: "test-restart")
        let containers = try await services.listContainers()
        let container = containers.first { ($0["Names"] as? [String])?.first?.contains("test-restart") == true }
        #expect(container?["State"] as? String == "running")
        try await services.killContainer(id: "test-restart")
        try await services.removeContainer(id: "test-restart")
    }

    @Test("pauseContainer and unpauseContainer")
    func pauseUnpause() async throws {
        _ = try await services.createContainer(name: "test-pause", image: "alpine:latest")
        try await services.startContainer(id: "test-pause")
        try await services.pauseContainer(id: "test-pause")
        var containers = try await services.listContainers()
        var container = containers.first { ($0["Names"] as? [String])?.first?.contains("test-pause") == true }
        #expect(container?["State"] as? String == "paused")
        try await services.unpauseContainer(id: "test-pause")
        containers = try await services.listContainers()
        container = containers.first { ($0["Names"] as? [String])?.first?.contains("test-pause") == true }
        #expect(container?["State"] as? String == "running")
        try await services.killContainer(id: "test-pause")
        try await services.removeContainer(id: "test-pause")
    }

    @Test("removeContainer removes from list")
    func removeContainer() async throws {
        _ = try await services.createContainer(name: "test-remove", image: "alpine:latest")
        try await services.removeContainer(id: "test-remove")
        let containers = try await services.listContainers()
        let found = containers.contains { ($0["Names"] as? [String])?.first?.contains("test-remove") == true }
        #expect(!found)
    }

    @Test("renameContainer changes name")
    func renameContainer() async throws {
        _ = try await services.createContainer(name: "test-rename-old", image: "alpine:latest")
        try await services.renameContainer(id: "test-rename-old", newName: "test-rename-new")
        let containers = try await services.listContainers()
        let found = containers.contains { ($0["Names"] as? [String])?.first?.contains("test-rename-new") == true }
        #expect(found)
        try await services.removeContainer(id: "test-rename-new")
    }

    @Test("containerLogs returns string")
    func containerLogs() async throws {
        _ = try await services.createContainer(name: "test-logs", image: "alpine:latest")
        try await services.startContainer(id: "test-logs")
        let logs = try await services.containerLogs(id: "test-logs")
        #expect(logs is String)
        try await services.killContainer(id: "test-logs")
        try await services.removeContainer(id: "test-logs")
    }

    @Test("inspectContainer returns JSON")
    func inspectContainer() async throws {
        _ = try await services.createContainer(name: "test-inspect", image: "alpine:latest")
        let json = try await services.inspectContainer(id: "test-inspect")
        #expect(json.contains("test-inspect"))
        try await services.removeContainer(id: "test-inspect")
    }

    @Test("containerTop returns process list")
    func containerTop() async throws {
        _ = try await services.createContainer(name: "test-top", image: "alpine:latest")
        try await services.startContainer(id: "test-top")
        let top = try await services.containerTop(id: "test-top")
        #expect(!top.isEmpty)
        try await services.killContainer(id: "test-top")
        try await services.removeContainer(id: "test-top")
    }

    @Test("containerStats returns stats JSON")
    func containerStats() async throws {
        _ = try await services.createContainer(name: "test-stats", image: "alpine:latest")
        try await services.startContainer(id: "test-stats")
        let stats = try await services.containerStats(id: "test-stats")
        #expect(!stats.isEmpty)
        try await services.killContainer(id: "test-stats")
        try await services.removeContainer(id: "test-stats")
    }

    @Test("containerChanges returns diff")
    func containerChanges() async throws {
        let name = "test-changes-\(Int.random(in: 1000...9999))"
        _ = try await services.createContainer(name: name, image: "alpine:latest")
        try await services.startContainer(id: name)
        let changes = try await services.containerChanges(id: name)
        #expect(changes is String) // May be empty "[]" for fresh containers
        try await services.killContainer(id: name)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await services.removeContainer(id: name)
    }

    @Test("pruneContainers removes stopped containers")
    func pruneContainers() async throws {
        _ = try await services.createContainer(name: "test-prune-c", image: "alpine:latest")
        try await services.pruneContainers()
        let containers = try await services.listContainers()
        let found = containers.contains { ($0["Names"] as? [String])?.first?.contains("test-prune-c") == true }
        #expect(!found)
    }

    // MARK: - Image Operations

    @Test("listImages returns array")
    func listImages() async throws {
        let images = try await services.listImages()
        #expect(!images.isEmpty)
    }

    @Test("pullImage downloads image")
    func pullImage() async throws {
        try await services.pullImage(name: "alpine:latest")
        let images = try await services.listImages()
        let found = images.contains { ($0["RepoTags"] as? [String])?.contains("alpine:latest") == true }
        #expect(found)
    }

    @Test("inspectImage returns JSON")
    func inspectImage() async throws {
        try await services.pullImage(name: "alpine:latest")
        let json = try await services.inspectImage(name: "alpine:latest")
        #expect(json.contains("alpine"))
    }

    @Test("imageHistory returns history")
    func imageHistory() async throws {
        try await services.pullImage(name: "alpine:latest")
        let history = try await services.imageHistory(name: "alpine:latest")
        #expect(!history.isEmpty)
    }

    @Test("tagImage creates new tag")
    func tagImage() async throws {
        try await services.pullImage(name: "alpine:latest")
        try await services.tagImage(name: "alpine:latest", repo: "test-tag-img", tag: "v1")
        let images = try await services.listImages()
        let found = images.contains { ($0["RepoTags"] as? [String])?.contains("test-tag-img:v1") == true }
        #expect(found)
        try await services.removeImage(id: "test-tag-img:v1")
    }

    @Test("removeImage removes from list")
    func removeImage() async throws {
        try await services.pullImage(name: "alpine:latest")
        try await services.tagImage(name: "alpine:latest", repo: "test-rm-img", tag: "v1")
        try await services.removeImage(id: "test-rm-img:v1")
        let images = try await services.listImages()
        let found = images.contains { ($0["RepoTags"] as? [String])?.contains("test-rm-img:v1") == true }
        #expect(!found)
    }

    @Test("searchImages returns results")
    func searchImages() async throws {
        let results = try await services.searchImages(term: "alpine")
        #expect(!results.isEmpty)
    }

    @Test("pruneImages completes without error")
    func pruneImages() async throws {
        try await services.pruneImages()
    }

    @Test("pushImage validates image exists")
    func pushImage() async throws {
        try await services.pullImage(name: "alpine:latest")
        try await services.pushImage(name: "alpine:latest")
    }

    // MARK: - Volume Operations

    @Test("listVolumes returns array")
    func listVolumes() async throws {
        let volumes = try await services.listVolumes()
        #expect(volumes is [[String: Any]])
    }

    @Test("createVolume creates and appears in list")
    func createVolume() async throws {
        try await services.createVolume(name: "test-vol")
        let volumes = try await services.listVolumes()
        let found = volumes.contains { ($0["Name"] as? String) == "test-vol" }
        #expect(found)
        try await services.removeVolume(name: "test-vol")
    }

    @Test("removeVolume removes from list")
    func removeVolume() async throws {
        try await services.createVolume(name: "test-vol-rm")
        try await services.removeVolume(name: "test-vol-rm")
        let volumes = try await services.listVolumes()
        let found = volumes.contains { ($0["Name"] as? String) == "test-vol-rm" }
        #expect(!found)
    }

    @Test("inspectVolume returns JSON")
    func inspectVolume() async throws {
        try await services.createVolume(name: "test-vol-inspect")
        let json = try await services.inspectVolume(name: "test-vol-inspect")
        #expect(json.contains("test-vol-inspect"))
        try await services.removeVolume(name: "test-vol-inspect")
    }

    @Test("pruneVolumes completes without error")
    func pruneVolumes() async throws {
        try await services.createVolume(name: "test-vol-prune")
        try await services.pruneVolumes()
    }

    // MARK: - Network Operations

    @Test("listNetworks returns array with defaults")
    func listNetworks() async throws {
        let networks = try await services.listNetworks()
        #expect(!networks.isEmpty)
        let names = networks.compactMap { $0["Name"] as? String }
        #expect(names.contains("bridge"))
    }

    @Test("createNetwork creates and appears in list")
    func createNetwork() async throws {
        try await services.createNetwork(name: "test-net")
        let networks = try await services.listNetworks()
        let found = networks.contains { ($0["Name"] as? String) == "test-net" }
        #expect(found)
        try await services.removeNetwork(name: "test-net")
    }

    @Test("removeNetwork removes from list")
    func removeNetwork() async throws {
        try await services.createNetwork(name: "test-net-rm")
        try await services.removeNetwork(name: "test-net-rm")
        let networks = try await services.listNetworks()
        let found = networks.contains { ($0["Name"] as? String) == "test-net-rm" }
        #expect(!found)
    }

    @Test("inspectNetwork returns JSON")
    func inspectNetwork() async throws {
        try await services.createNetwork(name: "test-net-inspect")
        let json = try await services.inspectNetwork(id: "test-net-inspect")
        #expect(json.contains("test-net-inspect"))
        try await services.removeNetwork(name: "test-net-inspect")
    }

    @Test("connectNetwork and disconnectNetwork")
    func connectDisconnectNetwork() async throws {
        try await services.createNetwork(name: "test-net-conn")
        _ = try await services.createContainer(name: "test-net-container", image: "alpine:latest")
        try await services.startContainer(id: "test-net-container")
        try await services.connectNetwork(networkId: "test-net-conn", containerId: "test-net-container")
        try await services.disconnectNetwork(networkId: "test-net-conn", containerId: "test-net-container")
        try await services.killContainer(id: "test-net-container")
        try await services.removeContainer(id: "test-net-container")
        try await services.removeNetwork(name: "test-net-conn")
    }

    @Test("pruneNetworks completes without error")
    func pruneNetworks() async throws {
        try await services.createNetwork(name: "test-net-prune")
        try await services.pruneNetworks()
    }

    // MARK: - Profile Operations

    @Test("listProfiles returns at least default")
    func listProfiles() async throws {
        let profiles = try await services.listProfiles()
        #expect(!profiles.isEmpty)
        #expect(profiles.contains { $0.name == "default" })
    }

    // MARK: - Streaming

    @Test("streamEvents returns a task")
    func streamEvents() async throws {
        let task = services.streamEvents { _ in }
        #expect(task != nil)
        task?.cancel()
    }

    @Test("streamLogs returns a task")
    func streamLogs() async throws {
        _ = try await services.createContainer(name: "test-stream-logs", image: "alpine:latest")
        try await services.startContainer(id: "test-stream-logs")
        let task = services.streamLogs(containerId: "test-stream-logs") { _ in }
        #expect(task != nil)
        task?.cancel()
        try await services.killContainer(id: "test-stream-logs")
        try await services.removeContainer(id: "test-stream-logs")
    }

    @Test("streamStats returns a task")
    func streamStats() async throws {
        _ = try await services.createContainer(name: "test-stream-stats", image: "alpine:latest")
        try await services.startContainer(id: "test-stream-stats")
        let task = services.streamStats(containerId: "test-stream-stats") { _ in }
        #expect(task != nil)
        task?.cancel()
        try await services.killContainer(id: "test-stream-stats")
        try await services.removeContainer(id: "test-stream-stats")
    }

    // MARK: - AppState Integration

    @Test("AppState with MockServiceProvider works")
    func appStateWithMock() async throws {
        let state = AppState(services: MockServiceProvider())
        await state.refreshAll()
        #expect(!state.containers.isEmpty)
        #expect(!state.images.isEmpty)
    }
}

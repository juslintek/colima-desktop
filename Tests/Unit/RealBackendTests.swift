import Testing
import Foundation
@testable import ColimaDesktopKit

/// TRUE end-to-end tests against a real Colima VM + Docker socket, exercising
/// RealServiceProvider and DockerClient for real (no mocks).
///
/// SAFETY: runs ONLY when opted in via env (`COLIMA_DESKTOP_REAL_E2E=1`) AND the
/// resolved profile is a dedicated e2e profile (never `default`) AND its socket
/// is reachable. Every created Docker resource uses the `colima-desktop-e2e-*`
/// prefix and is cleaned up (per-test backstop + final sweep). Skipped cleanly
/// in CI / Tart VM (no nested virt). See Tests/Support/RealE2ESupport.swift and
/// docs/e2e-real-mode-execution.md.
@Suite("RealBackend", .serialized, .enabled(if: RealE2E.canRun))
struct RealBackendTests {
    let services: RealServiceProvider

    init() async throws {
        let provider = RealServiceProvider(profile: RealE2E.profile)
        services = provider
        // Base image used across container tests (idempotent/fast; bounded).
        try await withTimeout(120) { try await provider.pullImage(name: "alpine:latest") }
    }

    // MARK: - Helpers

    private func containerNames(all: Bool = true) async throws -> [String] {
        let list = try await services.listContainers()
        return list.compactMap { ($0["Names"] as? [String])?.first }
    }

    private func containerExists(_ name: String) async throws -> Bool {
        try await containerNames().contains { $0.contains(name) }
    }

    private func containerState(_ name: String) async throws -> String? {
        let list = try await services.listContainers()
        return list.first { ($0["Names"] as? [String])?.first?.contains(name) == true }?["State"] as? String
    }

    /// Create a prefixed container, run `body(name)`, then always clean up.
    @discardableResult
    private func withContainer(
        image: String = "alpine:latest",
        started: Bool = false,
        _ body: (String) async throws -> Void
    ) async throws -> String {
        let name = RealE2E.resourceName("ctr")
        _ = try await withTimeout(60) { try await services.createContainer(name: name, image: image) }
        if started { try await withTimeout(60) { try await services.startContainer(id: name) } }
        do { try await body(name) } catch {
            try? await services.killContainer(id: name)
            try? await services.removeContainer(id: name)
            throw error
        }
        try? await services.killContainer(id: name)
        try? await services.removeContainer(id: name)
        return name
    }

    // MARK: - VM / status

    @Test("vmStatus reports the dedicated profile running with docker runtime")
    func vmStatus() async throws {
        let status = try await withTimeout(20) { try await services.vmStatus(profile: RealE2E.profile) }
        #expect(status.running == true)
        #expect(status.runtime == "docker")
        #expect(!status.version.isEmpty)
        #expect(status.cpu >= 1)
        #expect(status.memory > 0)
    }

    @Test("vmVersion returns a dotted version string")
    func vmVersion() async throws {
        let version = try await services.vmVersion()
        #expect(!version.isEmpty)
        #expect(version.contains("."))
    }

    @Test("sshConfig contains a Host entry")
    func sshConfig() async throws {
        let config = try await services.sshConfig(profile: RealE2E.profile)
        #expect(config.contains("Host"))
    }

    @Test("listProfiles includes the dedicated e2e profile")
    func listProfiles() async throws {
        let profiles = try await services.listProfiles()
        #expect(!profiles.isEmpty)
        #expect(profiles.contains { $0.name == RealE2E.profile })
    }

    // MARK: - Containers (lifecycle)

    @Test("create makes a container that appears in the list")
    func createContainer() async throws {
        try await withContainer { name in
            let exists = try await containerExists(name)
            #expect(exists)
        }
    }

    @Test("start transitions a container to running")
    func startContainer() async throws {
        try await withContainer { name in
            try await services.startContainer(id: name)
            let ok = try await pollUntil { try await containerState(name) == "running" }
            #expect(ok)
        }
    }

    @Test("stop transitions a running container to exited")
    func stopContainer() async throws {
        try await withContainer(started: true) { name in
            try await services.stopContainer(id: name)
            let ok = try await pollUntil { try await containerState(name) == "exited" }
            #expect(ok)
        }
    }

    @Test("kill transitions a running container to exited")
    func killContainer() async throws {
        try await withContainer(started: true) { name in
            try await services.killContainer(id: name)
            let ok = try await pollUntil { try await containerState(name) == "exited" }
            #expect(ok)
        }
    }

    @Test("restart leaves the container running")
    func restartContainer() async throws {
        try await withContainer(started: true) { name in
            try await services.restartContainer(id: name)
            let ok = try await pollUntil { try await containerState(name) == "running" }
            #expect(ok)
        }
    }

    @Test("pause then unpause toggles paused/running")
    func pauseUnpause() async throws {
        try await withContainer(started: true) { name in
            try await services.pauseContainer(id: name)
            let paused = try await pollUntil { try await containerState(name) == "paused" }
            #expect(paused)
            try await services.unpauseContainer(id: name)
            let resumed = try await pollUntil { try await containerState(name) == "running" }
            #expect(resumed)
        }
    }

    @Test("remove deletes the container from the list")
    func removeContainer() async throws {
        let name = RealE2E.resourceName("ctr")
        _ = try await services.createContainer(name: name, image: "alpine:latest")
        let existsBefore = try await containerExists(name)
        #expect(existsBefore)
        try await services.removeContainer(id: name)
        let gone = try await pollUntil { try await !containerExists(name) }
        #expect(gone)
    }

    @Test("rename changes the container name")
    func renameContainer() async throws {
        let old = RealE2E.resourceName("ctr-old")
        let new = RealE2E.resourceName("ctr-new")
        _ = try await services.createContainer(name: old, image: "alpine:latest")
        do {
            try await services.renameContainer(id: old, newName: new)
            let hasNew = try await containerExists(new)
            let hasOld = try await containerExists(old)
            #expect(hasNew)
            #expect(!hasOld)
        } catch { try? await services.removeContainer(id: old); throw error }
        try? await services.removeContainer(id: new)
    }

    @Test("logs returns a string for a started container")
    func containerLogs() async throws {
        try await withContainer(started: true) { name in
            let logs = try await services.containerLogs(id: name)
            #expect(logs is String)
        }
    }

    @Test("inspect returns JSON referencing the container name")
    func inspectContainer() async throws {
        try await withContainer { name in
            let json = try await services.inspectContainer(id: name)
            #expect(json.contains(name))
        }
    }

    @Test("top returns a process table for a started container")
    func containerTop() async throws {
        try await withContainer(started: true) { name in
            let top = try await services.containerTop(id: name)
            #expect(!top.isEmpty)
        }
    }

    @Test("stats returns a stats payload for a started container")
    func containerStats() async throws {
        try await withContainer(started: true) { name in
            let stats = try await withTimeout(20) { try await services.containerStats(id: name) }
            #expect(!stats.isEmpty)
        }
    }

    @Test("changes returns a diff payload")
    func containerChanges() async throws {
        try await withContainer(started: true) { name in
            let changes = try await services.containerChanges(id: name)
            #expect(changes is String)
        }
    }

    @Test("prune removes a stopped prefixed container")
    func pruneContainers() async throws {
        let name = RealE2E.resourceName("ctr-prune")
        _ = try await services.createContainer(name: name, image: "alpine:latest")
        try await services.pruneContainers()
        let gone = try await !containerExists(name)
        #expect(gone)
    }

    // MARK: - Containers (error paths)

    @Test("inspect of a missing container throws a Docker API error")
    func inspectMissingThrows() async throws {
        do {
            _ = try await services.inspectContainer(id: RealE2E.resourceName("missing"))
            Issue.record("Expected inspect of a missing container to throw")
        } catch { /* expected: Docker 404 */ }
    }

    @Test("create from a nonexistent image throws 404")
    func createBadImageThrows() async throws {
        let name = RealE2E.resourceName("ctr-badimg")
        do {
            _ = try await services.createContainer(name: name, image: "no.such/image:doesnotexist-\(name)")
            Issue.record("Expected create from a nonexistent image to throw")
        } catch { /* expected: Docker 404 */ }
        try? await services.removeContainer(id: name)
    }

    // MARK: - Images

    @Test("listImages includes the pulled base image")
    func listImages() async throws {
        let images = try await services.listImages()
        let tags = images.compactMap { ($0["RepoTags"] as? [String]) }.flatMap { $0 }
        #expect(tags.contains("alpine:latest"))
    }

    @Test("pull then inspect/history works for the base image")
    func pullInspectHistory() async throws {
        try await withTimeout(120) { try await services.pullImage(name: "alpine:latest") }
        let json = try await services.inspectImage(name: "alpine:latest")
        #expect(json.contains("alpine") || json.contains("RepoTags"))
        let history = try await services.imageHistory(name: "alpine:latest")
        #expect(!history.isEmpty)
    }

    @Test("tag creates a prefixed tag, then remove deletes it")
    func tagAndRemoveImage() async throws {
        let repo = RealE2E.resourceName("img")
        try await services.tagImage(name: "alpine:latest", repo: repo, tag: "v1")
        var images = try await services.listImages()
        #expect(images.contains { ($0["RepoTags"] as? [String])?.contains("\(repo):v1") == true })
        try await services.removeImage(id: "\(repo):v1")
        images = try await services.listImages()
        #expect(!images.contains { ($0["RepoTags"] as? [String])?.contains("\(repo):v1") == true })
    }

    @Test("searchImages returns results for a common term")
    func searchImages() async throws {
        let results = try await withTimeout(30) { try await services.searchImages(term: "alpine") }
        #expect(!results.isEmpty)
    }

    @Test("pruneImages completes without throwing")
    func pruneImages() async throws {
        try await services.pruneImages()
    }

    // MARK: - Volumes

    @Test("volume create → appears → inspect → remove → gone")
    func volumeLifecycle() async throws {
        let name = RealE2E.resourceName("vol")
        try await services.createVolume(name: name)
        do {
            let vols = try await services.listVolumes()
            #expect(vols.contains { ($0["Name"] as? String) == name })
            let json = try await services.inspectVolume(name: name)
            #expect(json.contains(name))
        } catch { try? await services.removeVolume(name: name); throw error }
        try await services.removeVolume(name: name)
        let after = try await services.listVolumes()
        #expect(!after.contains { ($0["Name"] as? String) == name })
    }

    @Test("pruneVolumes completes without throwing")
    func pruneVolumes() async throws {
        try await services.pruneVolumes()
    }

    // MARK: - Networks

    @Test("listNetworks includes the default bridge")
    func listNetworks() async throws {
        let networks = try await services.listNetworks()
        #expect(!networks.isEmpty)
        #expect(networks.compactMap { $0["Name"] as? String }.contains("bridge"))
    }

    @Test("network create → appears → inspect → remove → gone")
    func networkLifecycle() async throws {
        let name = RealE2E.resourceName("net")
        try await services.createNetwork(name: name)
        do {
            let nets = try await services.listNetworks()
            #expect(nets.contains { ($0["Name"] as? String) == name })
            let json = try await services.inspectNetwork(id: name)
            #expect(json.contains(name))
        } catch { try? await services.removeNetwork(name: name); throw error }
        try await services.removeNetwork(name: name)
        let after = try await services.listNetworks()
        #expect(!after.contains { ($0["Name"] as? String) == name })
    }

    @Test("connect then disconnect a container to a created network")
    func connectDisconnectNetwork() async throws {
        let net = RealE2E.resourceName("net-conn")
        try await services.createNetwork(name: net)
        do {
            try await withContainer(started: true) { ctr in
                try await services.connectNetwork(networkId: net, containerId: ctr)
                try await services.disconnectNetwork(networkId: net, containerId: ctr)
            }
        } catch { try? await services.removeNetwork(name: net); throw error }
        try await services.removeNetwork(name: net)
    }

    @Test("pruneNetworks completes without throwing")
    func pruneNetworks() async throws {
        try await services.pruneNetworks()
    }

    // MARK: - Streaming

    @Test("streamEvents returns a cancellable task")
    func streamEvents() async throws {
        let task = services.streamEvents { _ in }
        #expect(task != nil)
        task?.cancel()
    }

    @Test("streamLogs returns a cancellable task for a started container")
    func streamLogs() async throws {
        try await withContainer(started: true) { name in
            let task = services.streamLogs(containerId: name) { _ in }
            #expect(task != nil)
            task?.cancel()
        }
    }

    @Test("streamStats returns a cancellable task for a started container")
    func streamStats() async throws {
        try await withContainer(started: true) { name in
            let task = services.streamStats(containerId: name) { _ in }
            #expect(task != nil)
            task?.cancel()
        }
    }

    // MARK: - Final sweep (best-effort cleanup of any prefixed leftovers)

    @Test("zzz final sweep removes any leftover prefixed resources")
    func finalSweep() async throws {
        let containers = try await services.listContainers()
        for c in containers {
            guard let name = (c["Names"] as? [String])?.first, name.contains(RealE2E.prefix) else { continue }
            try? await services.killContainer(id: name)
            try? await services.removeContainer(id: name)
        }
        let vols = try await services.listVolumes()
        for v in vols where (v["Name"] as? String)?.contains(RealE2E.prefix) == true {
            try? await services.removeVolume(name: v["Name"] as! String)
        }
        let nets = try await services.listNetworks()
        for n in nets where (n["Name"] as? String)?.contains(RealE2E.prefix) == true {
            try? await services.removeNetwork(name: n["Name"] as! String)
        }
        let leftover = try await containerNames().filter { $0.contains(RealE2E.prefix) }
        #expect(leftover.isEmpty)
    }
}

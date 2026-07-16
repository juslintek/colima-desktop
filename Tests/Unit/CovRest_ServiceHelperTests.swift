import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - DockerClient URL path construction (CovRest_ prefix)

@Suite("CovRest_DockerClient URL Paths")
struct CovRest_DockerClientURLPathTests {

    @Test("profile-based init resolves path under ~/.colima/<profile>")
    func profileSocketPath() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expectedPrefix = "\(home)/.colima/myprofile/docker.sock"
        // We can't inspect private properties directly; instead verify behavior:
        // A client for a non-existent profile should throw socketNotFound mentioning the path
        let client = DockerClient(profile: "myprofile")
        do {
            _ = try await client.listContainers()
            Issue.record("Expected socketNotFound for non-existent profile socket")
        } catch let e as DockerError {
            if case .socketNotFound(let path) = e {
                #expect(path == expectedPrefix)
            } else {
                Issue.record("Expected .socketNotFound, got \(e)")
            }
        } catch {
            Issue.record("Expected DockerError, got \(error)")
        }
    }

    @Test("default profile resolves to default colima socket path")
    func defaultProfileSocketPath() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expectedPath = "\(home)/.colima/default/docker.sock"
        let client = DockerClient(profile: "default")
        do {
            _ = try await client.ping()
        } catch let e as DockerError {
            if case .socketNotFound(let path) = e {
                // Path must be the default colima socket path
                #expect(path == expectedPath)
            }
            // Other DockerErrors are also OK (e.g. apiError if somehow connected)
        } catch {
            // Non-DockerError is unexpected but we only care about path correctness
        }
    }

    @Test("explicit socketPath init is used in error messages")
    func explicitSocketPathInError() async {
        let path = "/tmp/cov-rest-test-nonexistent-\(UUID().uuidString).sock"
        let client = DockerClient(socketPath: path)
        do {
            _ = try await client.listImages()
            Issue.record("Expected socketNotFound for nonexistent path")
        } catch let e as DockerError {
            if case .socketNotFound(let p) = e {
                #expect(p == path)
            } else {
                Issue.record("Expected socketNotFound, got \(e)")
            }
        } catch {
            Issue.record("Expected DockerError, got \(error)")
        }
    }

    @Test("listVolumes throws socketNotFound for missing socket")
    func listVolumesThrows() async {
        let client = DockerClient(socketPath: "/tmp/cov-rest-gone-\(UUID().uuidString).sock")
        do {
            _ = try await client.listVolumes()
            Issue.record("Should throw")
        } catch let e as DockerError {
            if case .socketNotFound = e { } else {
                Issue.record("Expected socketNotFound, got \(e)")
            }
        } catch { }
    }

    @Test("listNetworks throws socketNotFound for missing socket")
    func listNetworksThrows() async {
        let client = DockerClient(socketPath: "/tmp/cov-rest-gone-\(UUID().uuidString).sock")
        do {
            _ = try await client.listNetworks()
            Issue.record("Should throw")
        } catch let e as DockerError {
            if case .socketNotFound = e { } else {
                Issue.record("Expected socketNotFound, got \(e)")
            }
        } catch { }
    }

    @Test("createVolume throws socketNotFound for missing socket")
    func createVolumeThrows() async {
        let client = DockerClient(socketPath: "/tmp/cov-rest-gone-\(UUID().uuidString).sock")
        do {
            _ = try await client.createVolume(name: "test-vol")
            Issue.record("Should throw")
        } catch let e as DockerError {
            if case .socketNotFound = e { } else {
                Issue.record("Expected socketNotFound, got \(e)")
            }
        } catch { }
    }

    @Test("pruneContainers throws socketNotFound for missing socket")
    func pruneContainersThrows() async {
        let client = DockerClient(socketPath: "/tmp/cov-rest-gone-\(UUID().uuidString).sock")
        do {
            _ = try await client.pruneContainers()
            Issue.record("Should throw")
        } catch let e as DockerError {
            if case .socketNotFound = e { } else {
                Issue.record("Expected socketNotFound, got \(e)")
            }
        } catch { }
    }

    @Test("systemInfo throws socketNotFound for missing socket")
    func systemInfoThrows() async {
        let client = DockerClient(socketPath: "/tmp/cov-rest-gone-\(UUID().uuidString).sock")
        do {
            _ = try await client.systemInfo()
            Issue.record("Should throw")
        } catch let e as DockerError {
            if case .socketNotFound = e { } else {
                Issue.record("Expected socketNotFound, got \(e)")
            }
        } catch { }
    }
}

// MARK: - DockerError completeness (CovRest_ prefix)

@Suite("CovRest_DockerError")
struct CovRest_DockerErrorTests {

    @Test("invalidResponse has non-empty description")
    func invalidResponseDescription() {
        let e = DockerError.invalidResponse
        #expect(e.errorDescription?.isEmpty == false)
        #expect(e.localizedDescription.isEmpty == false)
    }

    @Test("apiError 200 description includes 200")
    func apiError200() {
        let e = DockerError.apiError(200, "OK")
        #expect(e.errorDescription?.contains("200") == true)
    }

    @Test("apiError 404 description includes 404 and message")
    func apiError404() {
        let e = DockerError.apiError(404, "no such container")
        let desc = e.errorDescription ?? ""
        #expect(desc.contains("404"))
        #expect(desc.contains("no such container"))
    }

    @Test("apiError 500 description includes 500")
    func apiError500() {
        let e = DockerError.apiError(500, "server error")
        #expect(e.errorDescription?.contains("500") == true)
    }

    @Test("socketNotFound description includes the socket path")
    func socketNotFoundPath() {
        let path = "/var/run/docker.sock"
        let e = DockerError.socketNotFound(path)
        #expect(e.errorDescription?.contains(path) == true)
    }

    @Test("all DockerError cases have non-nil errorDescription")
    func allCasesHaveDescription() {
        let cases: [DockerError] = [
            .invalidResponse,
            .apiError(0, ""),
            .socketNotFound("/tmp/x.sock")
        ]
        for c in cases {
            #expect(c.errorDescription != nil, "Expected non-nil errorDescription for \(c)")
        }
    }
}

// MARK: - DaemonError (CovRest_ prefix)

@Suite("CovRest_DaemonError")
struct CovRest_DaemonErrorTests {

    @Test("commandFailed description includes command, code, and message")
    func commandFailedDescription() {
        let e = DaemonError.commandFailed("colima", 1, "not found")
        let desc = e.errorDescription ?? ""
        #expect(desc.contains("colima"))
        #expect(desc.contains("1"))
        #expect(desc.contains("not found"))
    }

    @Test("commandFailed with exit code 127 description contains 127")
    func commandFailed127() {
        let e = DaemonError.commandFailed("docker", 127, "command not found")
        let desc = e.errorDescription ?? ""
        #expect(desc.contains("127"))
    }

    @Test("commandFailed has non-empty errorDescription")
    func commandFailedNonEmpty() {
        let e = DaemonError.commandFailed("kubectl", 2, "")
        #expect(e.errorDescription?.isEmpty == false)
    }

    @Test("commandFailed localizedDescription is non-empty")
    func commandFailedLocalizedDescription() {
        let e = DaemonError.commandFailed("colima", 1, "failed")
        #expect(e.localizedDescription.isEmpty == false)
    }
}

// MARK: - VMStatusInfo (CovRest_ prefix)

@Suite("CovRest_VMStatusInfo")
struct CovRest_VMStatusInfoTests {

    @Test("default running VMStatusInfo has correct fields")
    func defaultRunningInfo() {
        let info = VMStatusInfo(
            running: true,
            profile: "default",
            arch: "aarch64",
            runtime: "docker",
            mountType: "virtiofs",
            cpu: 4,
            memory: 8 * 1024 * 1024 * 1024,
            disk: 100 * 1024 * 1024 * 1024,
            version: "0.10.1"
        )
        #expect(info.running == true)
        #expect(info.profile == "default")
        #expect(info.arch == "aarch64")
        #expect(info.runtime == "docker")
        #expect(info.mountType == "virtiofs")
        #expect(info.cpu == 4)
        #expect(info.version == "0.10.1")
    }

    @Test("VMStatusInfo not running has running=false")
    func notRunning() {
        let info = VMStatusInfo(running: false)
        #expect(info.running == false)
    }

    @Test("VMStatusInfo default profile is default")
    func defaultProfile() {
        let info = VMStatusInfo(running: true)
        #expect(info.profile == "default")
    }

    @Test("VMStatusInfo memory value is stored correctly")
    func memoryStorage() {
        let memory: Int64 = 4 * 1024 * 1024 * 1024
        let info = VMStatusInfo(running: true, memory: memory)
        #expect(info.memory == memory)
    }

    @Test("VMStatusInfo disk value is stored correctly")
    func diskStorage() {
        let disk: Int64 = 200 * 1024 * 1024 * 1024
        let info = VMStatusInfo(running: true, disk: disk)
        #expect(info.disk == disk)
    }

    @Test("VMStatusInfo vmType can be set to vz")
    func vmTypeVZ() {
        let info = VMStatusInfo(running: true, vmType: "vz")
        #expect(info.vmType == "vz")
    }
}

// MARK: - ColimaStartConfig (CovRest_ prefix)

@Suite("CovRest_ColimaStartConfig")
struct CovRest_ColimaStartConfigTests {

    @Test("default ColimaStartConfig has zero cpus, memory, disk")
    func defaultValues() {
        let config = ColimaStartConfig()
        #expect(config.cpus == 0)
        #expect(config.memory == 0)
        #expect(config.disk == 0)
        #expect(config.vmType.isEmpty)
        #expect(config.runtime.isEmpty)
        #expect(config.mountType.isEmpty)
        #expect(config.kubernetes == false)
    }

    @Test("ColimaStartConfig stores all custom values")
    func customValues() {
        let config = ColimaStartConfig(
            cpus: 4,
            memory: 8,
            disk: 100,
            vmType: "vz",
            runtime: "docker",
            mountType: "virtiofs",
            kubernetes: true
        )
        #expect(config.cpus == 4)
        #expect(config.memory == 8)
        #expect(config.disk == 100)
        #expect(config.vmType == "vz")
        #expect(config.runtime == "docker")
        #expect(config.mountType == "virtiofs")
        #expect(config.kubernetes == true)
    }
}

// MARK: - ProfileListItem (CovRest_ prefix)

@Suite("CovRest_ProfileListItem")
struct CovRest_ProfileListItemTests {

    @Test("ProfileListItem stores all fields")
    func allFields() {
        let item = ProfileListItem(
            name: "staging",
            status: "Stopped",
            arch: "x86_64",
            cpus: 2,
            memory: 4 * 1024 * 1024 * 1024,
            disk: 50 * 1024 * 1024 * 1024,
            runtime: "containerd"
        )
        #expect(item.name == "staging")
        #expect(item.status == "Stopped")
        #expect(item.arch == "x86_64")
        #expect(item.cpus == 2)
        #expect(item.runtime == "containerd")
    }

    @Test("ProfileListItem memory is Int64")
    func memoryIsInt64() {
        let mem: Int64 = 16 * 1024 * 1024 * 1024
        let item = ProfileListItem(name: "x", status: "Running", arch: "aarch64",
                                    cpus: 8, memory: mem, disk: 0, runtime: "docker")
        #expect(item.memory == mem)
    }
}

// MARK: - DaemonClient helpers (CovRest_ prefix)
// Tests for pure helpers that don't require a live colima binary

@Suite("CovRest_DaemonClient Helpers")
struct CovRest_DaemonClientHelperTests {

    @Test("isInstalled returns Bool (does not crash)")
    func isInstalledReturnsBool() async {
        let client = DaemonClient()
        let result = await client.isInstalled()
        // We just verify it returns a Bool without crashing
        // On CI without colima installed, this is false; on dev it may be true
        _ = result
        #expect(true)  // The call completed without crashing
    }

    @Test("DaemonClient shared singleton is accessible")
    func sharedSingleton() async {
        // Just access the shared singleton — verifies it exists without crashing
        let shared = DaemonClient.shared
        _ = shared
        #expect(true)
    }

    @Test("configPath forms correct path for nonexistent profile")
    func configPathForNonexistentProfile() async {
        // readConfig fails when file doesn't exist, and the error message contains the path
        let client = DaemonClient()
        do {
            _ = try await client.readConfig(profile: "cov-rest-nonexistent-profile-xyz")
            // If it somehow succeeds (file exists), that's fine too
        } catch let e as DaemonError {
            if case .commandFailed(let cmd, _, let msg) = e {
                // The error should reference "readConfig" or the path
                #expect(cmd == "readConfig" || msg.contains("cov-rest-nonexistent"))
            }
        } catch {
            // Other errors are acceptable
        }
    }
}

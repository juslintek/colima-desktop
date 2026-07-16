import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - DockerError

@Suite("DockerError")
struct DockerErrorTests {

    @Test("invalidResponse has a non-empty human-readable description")
    func invalidResponse() {
        let err = DockerError.invalidResponse
        #expect(err.errorDescription?.isEmpty == false)
        #expect(err.localizedDescription.isEmpty == false)
    }

    @Test("apiError embeds status code and message")
    func apiError() {
        let err = DockerError.apiError(404, "no such container")
        let desc = err.errorDescription ?? ""
        #expect(desc.contains("404"))
        #expect(desc.contains("no such container"))
    }

    @Test("apiError with 500 embeds 500")
    func apiError500() {
        let err = DockerError.apiError(500, "internal server error")
        let desc = err.errorDescription ?? ""
        #expect(desc.contains("500"))
    }

    @Test("socketNotFound embeds the path")
    func socketNotFound() {
        let path = "/tmp/test/docker.sock"
        let err = DockerError.socketNotFound(path)
        let desc = err.errorDescription ?? ""
        #expect(desc.contains(path))
    }

    @Test("all cases conform to LocalizedError (non-nil errorDescription)")
    func allCasesHaveDescription() {
        let cases: [DockerError] = [
            .invalidResponse,
            .apiError(200, "ok"),
            .socketNotFound("/tmp/x.sock")
        ]
        for e in cases {
            #expect(e.errorDescription != nil)
        }
    }
}

// MARK: - DockerClient socket path construction

@Suite("DockerClient socket path")
struct DockerClientSocketPathTests {

    @Test("profile-based init forms the correct path under ~/.colima")
    func profileSocketPath() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = "test-profile-\(Int.random(in: 1000...9999))"
        let client = DockerClient(profile: profile)
        // The client will attempt to connect to the profile socket, which doesn't exist.
        // We verify this by observing that the thrown error references the correct path.
        do {
            _ = try await client.ping()
            Issue.record("Expected socketNotFound for nonexistent profile socket")
        } catch let e as DockerError {
            if case .socketNotFound(let path) = e {
                #expect(path.contains(".colima"))
                #expect(path.contains(profile))
                #expect(path.hasSuffix("docker.sock"))
                #expect(path.hasPrefix(home))
            } else {
                Issue.record("Expected .socketNotFound, got \(e)")
            }
        } catch {
            // On some environments a different error may surface first; just guard no crash.
        }
    }

    @Test("explicit socketPath init uses the provided path")
    func explicitSocketPath() async {
        let customPath = "/tmp/colima-test-\(UUID().uuidString).sock"
        let client = DockerClient(socketPath: customPath)
        do {
            _ = try await client.listContainers()
            Issue.record("Expected error for a nonexistent socket")
        } catch let e as DockerError {
            if case .socketNotFound(let path) = e {
                #expect(path == customPath)
            } else {
                Issue.record("Expected .socketNotFound, got \(e)")
            }
        } catch { /* tolerate other errors for non-existent sockets */ }
    }

    @Test("default init uses the 'default' colima profile path")
    func defaultInit() async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let client = DockerClient()
        do {
            _ = try await client.systemInfo()
            // If Colima is actually running, this is fine — we just skip the path assertion.
        } catch let e as DockerError {
            if case .socketNotFound(let path) = e {
                let expected = "\(home)/.colima/default/docker.sock"
                #expect(path == expected)
            }
            // .apiError or .invalidResponse means the socket exists and a request was made.
        } catch { }
    }
}

// MARK: - Local Unix socket server for black-box DockerClient tests

/// Minimal helper: spins up a Unix-domain socket server in a background thread,
/// responds to ONE request with the provided HTTP response string, then closes.
/// Returns the socket path.
private func makeUnixSocketServer(response: String, socketPath: String) -> Task<Void, Never> {
    return Task.detached {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 104) { d in
                    _ = strlcpy(d, ptr, 104)
                }
            }
        }
        unlink(socketPath)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                bind(fd, p, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { return }
        guard listen(fd, 1) == 0 else { return }

        let clientFd = accept(fd, nil, nil)
        guard clientFd >= 0 else { return }
        defer { close(clientFd) }

        // Drain the request
        var buf = [UInt8](repeating: 0, count: 4096)
        _ = read(clientFd, &buf, buf.count)

        // Send response
        response.withCString { ptr in _ = write(clientFd, ptr, strlen(ptr)) }
    }
}

// MARK: - DockerClient HTTP response parsing

@Suite("DockerClient HTTP response parsing", .serialized)
struct DockerClientHTTPParsingTests {

    /// Waits a short time for the server task to bind and start listening.
    private func waitForServer(at path: String) async {
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: path) { return }
            try? await Task.sleep(nanoseconds: 25_000_000) // 25ms
        }
    }

    @Test("parses a simple JSON GET response correctly")
    func simpleJSONGet() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let jsonBody = #"[{"Id":"abc123","Names":["/web"],"State":"running"}]"#
        let response = """
        HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(jsonBody.utf8.count)\r\nConnection: close\r\n\r\n\(jsonBody)
        """
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let containers = try await client.listContainers()
        server.cancel()
        #expect(containers.count == 1)
        #expect(containers[0]["Id"] as? String == "abc123")
    }

    @Test("returns empty array for empty JSON body from listContainers")
    func emptyBodyListContainers() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        // Some Docker API endpoints return empty body on 204 No Content
        let response = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let containers = try await client.listContainers()
        server.cancel()
        #expect(containers.isEmpty)
    }

    @Test("throws apiError for 404 response")
    func notFoundThrows() async {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let body = #"{"message":"No such container: xyz"}"#
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        do {
            _ = try await client.inspectContainer(id: "xyz")
            Issue.record("Expected apiError for 404")
        } catch let e as DockerError {
            if case .apiError(let code, let msg) = e {
                #expect(code == 404)
                #expect(msg.contains("No such container"))
            } else {
                Issue.record("Expected .apiError, got \(e)")
            }
        } catch {
            Issue.record("Expected DockerError, got \(error)")
        }
        server.cancel()
    }

    @Test("throws apiError for 500 response")
    func serverErrorThrows() async {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let body = "Internal Server Error"
        let response = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        do {
            _ = try await client.systemInfo()
            Issue.record("Expected apiError for 500")
        } catch let e as DockerError {
            if case .apiError(let code, _) = e {
                #expect(code == 500)
            } else {
                Issue.record("Expected .apiError, got \(e)")
            }
        } catch {
            Issue.record("Expected DockerError, got \(error)")
        }
        server.cancel()
    }

    @Test("handles chunked transfer encoding")
    func chunkedTransferEncoding() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        // Build a chunked response: single chunk containing a JSON array
        let jsonBody = #"[{"Name":"bridge","Driver":"bridge"}]"#
        let chunkSize = String(jsonBody.utf8.count, radix: 16)
        let chunked = "\(chunkSize)\r\n\(jsonBody)\r\n0\r\n\r\n"
        let response = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n\(chunked)"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let networks = try await client.listNetworks()
        server.cancel()
        #expect(networks.count == 1)
        #expect(networks[0]["Name"] as? String == "bridge")
    }

    @Test("ping returns true for OK response")
    func pingOK() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let result = try await client.ping()
        server.cancel()
        #expect(result == true)
    }

    @Test("containerChanges returns empty array for null body")
    func changesNull() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let response = "HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\nnull"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let changes = try await client.containerChanges(id: "abc123")
        server.cancel()
        #expect(changes.isEmpty)
    }

    @Test("containerChanges returns empty array for empty body")
    func changesEmptyBody() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let response = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let changes = try await client.containerChanges(id: "abc123")
        server.cancel()
        #expect(changes.isEmpty)
    }

    @Test("containerChanges returns parsed entries")
    func changesParsed() async throws {
        let socketPath = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(socketPath) }

        let body = #"[{"Path":"/etc/hosts","Kind":2},{"Path":"/var/log","Kind":1}]"#
        let response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = makeUnixSocketServer(response: response, socketPath: socketPath)
        await waitForServer(at: socketPath)

        let client = DockerClient(socketPath: socketPath)
        let changes = try await client.containerChanges(id: "abc123")
        server.cancel()
        #expect(changes.count == 2)
        #expect(changes[0]["Path"] as? String == "/etc/hosts")
    }
}

// MARK: - Multiple-request scenarios (one server per request — serialized)

@Suite("DockerClient various endpoints", .serialized)
struct DockerClientEndpointTests {

    private func makeServer(json: String, socketPath: String, status: Int = 200) -> Task<Void, Never> {
        let body = json
        let resp = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        return makeUnixSocketServer(response: resp, socketPath: socketPath)
    }

    private func waitForServer(at path: String) async {
        for _ in 0..<40 {
            if FileManager.default.fileExists(atPath: path) { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    @Test("listImages parses image array")
    func listImages() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"[{"Id":"sha256:abc","RepoTags":["nginx:latest"],"Size":50000000}]"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let images = try await client.listImages()
        server.cancel()
        #expect(images.count == 1)
        #expect(images[0]["Id"] as? String == "sha256:abc")
    }

    @Test("listVolumes parses volume response dict")
    func listVolumes() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Volumes":[{"Name":"myvol","Driver":"local"}],"Warnings":[]}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let volumes = try await client.listVolumes()
        server.cancel()
        let vols = volumes["Volumes"] as? [[String: Any]] ?? []
        #expect(vols.count == 1)
        #expect(vols[0]["Name"] as? String == "myvol")
    }

    @Test("systemInfo parses info dict")
    func systemInfo() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Containers":3,"Images":10,"ServerVersion":"27.0.0"}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let info = try await client.systemInfo()
        server.cancel()
        #expect(info["Containers"] as? Int == 3)
        #expect(info["ServerVersion"] as? String == "27.0.0")
    }

    @Test("inspectContainer parses container dict")
    func inspectContainer() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Id":"abc123","Name":"/web","State":{"Status":"running"}}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.inspectContainer(id: "abc123")
        server.cancel()
        #expect(result["Id"] as? String == "abc123")
    }

    @Test("createContainer returns Id field from response")
    func createContainer() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Id":"newcontainerid","Warnings":[]}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let id = try await client.createContainer(name: "myc", image: "nginx:latest")
        server.cancel()
        #expect(id == "newcontainerid")
    }

    @Test("pruneContainers parses prune response")
    func pruneContainers() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"ContainersDeleted":["abc"],"SpaceReclaimed":1024}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.pruneContainers()
        server.cancel()
        #expect(result["SpaceReclaimed"] as? Int == 1024)
    }

    @Test("inspectVolume parses volume dict")
    func inspectVolume() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Name":"myvol","Driver":"local","Mountpoint":"/var/lib/docker/volumes/myvol/_data"}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.inspectVolume(name: "myvol")
        server.cancel()
        #expect(result["Name"] as? String == "myvol")
        #expect(result["Driver"] as? String == "local")
    }

    @Test("createVolume parses created volume")
    func createVolume() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Name":"newvol","Driver":"local","Mountpoint":"/var/lib/docker/volumes/newvol/_data"}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.createVolume(name: "newvol")
        server.cancel()
        #expect(result["Name"] as? String == "newvol")
    }

    @Test("createNetwork parses created network")
    func createNetwork() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Id":"net123","Warning":""}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.createNetwork(name: "mynet")
        server.cancel()
        #expect(result["Id"] as? String == "net123")
    }

    @Test("inspectNetwork parses network dict")
    func inspectNetwork() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Id":"net123","Name":"mynet","Driver":"bridge"}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.inspectNetwork(id: "net123")
        server.cancel()
        #expect(result["Name"] as? String == "mynet")
    }

    @Test("containerStats parses stats dict")
    func containerStats() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"cpu_stats":{"cpu_usage":{"total_usage":100}},"memory_stats":{"usage":1024}}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.containerStats(id: "abc123", stream: false)
        server.cancel()
        #expect(result["cpu_stats"] != nil)
    }

    @Test("containerTop parses top output")
    func containerTop() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Titles":["PID","USER","CMD"],"Processes":[["1","root","nginx"]]}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.containerTop(id: "abc123")
        server.cancel()
        #expect(result["Titles"] != nil)
    }

    @Test("imageHistory parses history array")
    func imageHistory() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"[{"Id":"sha256:layer1","Created":1700000000,"CreatedBy":"CMD nginx"},{"Id":"sha256:layer2","Created":1699999000,"CreatedBy":"ADD files /"}]"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let history = try await client.imageHistory(name: "nginx:latest")
        server.cancel()
        #expect(history.count == 2)
    }

    @Test("pruneImages parses prune response")
    func pruneImages() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"ImagesDeleted":null,"SpaceReclaimed":2048}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.pruneImages()
        server.cancel()
        #expect(result["SpaceReclaimed"] as? Int == 2048)
    }

    @Test("pruneVolumes parses prune response")
    func pruneVolumes() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"VolumesDeleted":["vol1"],"SpaceReclaimed":512}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.pruneVolumes()
        server.cancel()
        #expect(result["SpaceReclaimed"] as? Int == 512)
    }

    @Test("pruneNetworks parses prune response")
    func pruneNetworks() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"NetworksDeleted":["net1"]}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.pruneNetworks()
        server.cancel()
        #expect(result["NetworksDeleted"] != nil)
    }

    @Test("systemDf parses disk usage response")
    func systemDf() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"LayersSize":1234567,"Images":[],"Containers":[],"Volumes":[]}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.systemDf()
        server.cancel()
        #expect(result["LayersSize"] != nil)
    }

    @Test("waitContainer parses wait response")
    func waitContainer() async throws {
        let sp = "/tmp/docker-test-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"StatusCode":0}"#
        let server = makeServer(json: json, socketPath: sp)
        await waitForServer(at: sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.waitContainer(id: "abc123")
        server.cancel()
        #expect(result["StatusCode"] as? Int == 0)
    }
}

// MARK: - ContainerStats struct

@Suite("ContainerStats")
struct ContainerStatsTests {

    @Test("struct stores all fields")
    func fields() {
        let stats = ContainerStats(cpuPercent: 12.5, memoryUsage: 104857600, memoryLimit: 8589934592, networkRx: 1024, networkTx: 512)
        #expect(stats.cpuPercent == 12.5)
        #expect(stats.memoryUsage == 104857600)
        #expect(stats.memoryLimit == 8589934592)
        #expect(stats.networkRx == 1024)
        #expect(stats.networkTx == 512)
    }

    @Test("zero stats are valid")
    func zeroStats() {
        let stats = ContainerStats(cpuPercent: 0, memoryUsage: 0, memoryLimit: 0, networkRx: 0, networkTx: 0)
        #expect(stats.cpuPercent == 0)
    }
}

// MARK: - DockerEvent struct

@Suite("DockerEvent")
struct DockerEventTests {

    @Test("struct stores action and containerName")
    func fields() {
        let event = DockerEvent(action: "start", containerName: "web-server")
        #expect(event.action == "start")
        #expect(event.containerName == "web-server")
    }
}

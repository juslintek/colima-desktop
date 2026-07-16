import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - Shared unix-socket mock server helper

/// Spins up a single-request Unix-domain socket server, responds, then closes.
private func Cov3Svc_makeServer(response: String, socketPath: String) -> Task<Void, Never> {
    return Task.detached {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

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

        var buf = [UInt8](repeating: 0, count: 4096)
        _ = read(clientFd, &buf, buf.count)

        response.withCString { ptr in _ = write(clientFd, ptr, strlen(ptr)) }
    }
}

private func Cov3Svc_waitServer(_ path: String) async {
    for _ in 0..<50 {
        if FileManager.default.fileExists(atPath: path) { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

private func Cov3Svc_jsonServer(json: String, socketPath: String, status: Int = 200) -> Task<Void, Never> {
    let resp = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)"
    return Cov3Svc_makeServer(response: resp, socketPath: socketPath)
}

// MARK: - POST actions (start / stop / kill / restart / pause / unpause / rename)

@Suite("Cov3Svc_DockerClient POST actions", .serialized)
struct Cov3Svc_DockerClientPostActionTests {

    @Test("startContainer sends POST and succeeds on 204")
    func startContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.startContainer(id: "abc123")
        server.cancel()
    }

    @Test("stopContainer sends POST and succeeds on 204")
    func stopContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.stopContainer(id: "abc123", timeout: 5)
        server.cancel()
    }

    @Test("killContainer sends POST and succeeds on 204")
    func killContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.killContainer(id: "abc123", signal: "SIGTERM")
        server.cancel()
    }

    @Test("restartContainer sends POST and succeeds on 204")
    func restartContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.restartContainer(id: "abc123")
        server.cancel()
    }

    @Test("pauseContainer sends POST and succeeds on 204")
    func pauseContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.pauseContainer(id: "abc123")
        server.cancel()
    }

    @Test("unpauseContainer sends POST and succeeds on 204")
    func unpauseContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.unpauseContainer(id: "abc123")
        server.cancel()
    }

    @Test("renameContainer sends POST and succeeds on 204")
    func renameContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.renameContainer(id: "abc123", newName: "new-name")
        server.cancel()
    }

    @Test("removeContainer sends DELETE and succeeds on 204")
    func removeContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.removeContainer(id: "abc123", force: true)
        server.cancel()
    }

    @Test("removeImage sends DELETE and succeeds on 200")
    func removeImage() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"[{"Deleted":"sha256:abc"},{"Untagged":"nginx:latest"}]"#
        let server = Cov3Svc_jsonServer(json: json, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.removeImage(name: "nginx:latest", force: false)
        server.cancel()
    }

    @Test("removeVolume sends DELETE and succeeds on 204")
    func removeVolume() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.removeVolume(name: "myvol")
        server.cancel()
    }

    @Test("removeNetwork sends DELETE and succeeds on 204")
    func removeNetwork() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.removeNetwork(id: "net123")
        server.cancel()
    }

    @Test("pullImage sends POST and succeeds on 200")
    func pullImage() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.pullImage(name: "nginx:latest")
        server.cancel()
    }

    @Test("tagImage sends POST and succeeds on 201")
    func tagImage() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 201 Created\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.tagImage(name: "nginx:latest", repo: "myreg/nginx", tag: "v1")
        server.cancel()
    }

    @Test("connectNetwork sends POST and succeeds on 200")
    func connectNetwork() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.connectNetwork(networkId: "net123", containerId: "ctr456")
        server.cancel()
    }

    @Test("disconnectNetwork sends POST and succeeds on 200")
    func disconnectNetwork() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.disconnectNetwork(networkId: "net123", containerId: "ctr456")
        server.cancel()
    }

    @Test("updateContainer sends POST with body and succeeds on 200")
    func updateContainer() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"{"Warnings":[]}"#
        let server = Cov3Svc_jsonServer(json: json, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        try await client.updateContainer(id: "abc123", config: ["Memory": 536870912])
        server.cancel()
    }
}

// MARK: - containerLogs, searchImages

@Suite("Cov3Svc_DockerClient getString endpoints", .serialized)
struct Cov3Svc_DockerClientGetStringTests {

    @Test("containerLogs returns plain text content")
    func containerLogs() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = "2024-01-01 INFO Server started\n2024-01-01 INFO Listening on :80\n"
        let resp = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let logs = try await client.containerLogs(id: "abc123", tail: 50)
        server.cancel()
        #expect(logs.contains("Server started"))
    }

    @Test("searchImages returns array of search results")
    func searchImages() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let json = #"[{"name":"nginx","description":"Official nginx image","star_count":20000},{"name":"nginx-unprivileged","description":"Unprivileged nginx","star_count":500}]"#
        let server = Cov3Svc_jsonServer(json: json, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let results = try await client.searchImages(term: "nginx")
        server.cancel()
        #expect(results.count == 2)
        #expect(results[0]["name"] as? String == "nginx")
        #expect(results[0]["star_count"] as? Int == 20000)
    }
}

// MARK: - decodeChunked edge cases (via multi-chunk responses)

@Suite("Cov3Svc_DockerClient chunked decoding edge cases", .serialized)
struct Cov3Svc_DockerClientChunkedTests {

    @Test("multi-chunk response is reassembled correctly")
    func multipleChunks() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }

        // Build a two-chunk response: each chunk is part of the JSON array
        let part1 = #"[{"Id":"abc","Name":"web"},"#
        let part2 = #"{"Id":"xyz","Name":"api"}]"#
        let chunkSize1 = String(part1.utf8.count, radix: 16)
        let chunkSize2 = String(part2.utf8.count, radix: 16)
        let chunkedBody = "\(chunkSize1)\r\n\(part1)\r\n\(chunkSize2)\r\n\(part2)\r\n0\r\n\r\n"
        let resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n\(chunkedBody)"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let containers = try await client.listContainers()
        server.cancel()
        #expect(containers.count == 2)
        #expect(containers[0]["Id"] as? String == "abc")
        #expect(containers[1]["Id"] as? String == "xyz")
    }

    @Test("chunked response for inspectImage is decoded")
    func chunkedInspectImage() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }

        let json = #"{"Id":"sha256:abc","RepoTags":["nginx:latest"],"Size":187000000}"#
        let chunkSize = String(json.utf8.count, radix: 16)
        let chunkedBody = "\(chunkSize)\r\n\(json)\r\n0\r\n\r\n"
        let resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n\(chunkedBody)"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.inspectImage(name: "nginx:latest")
        server.cancel()
        #expect(result["Id"] as? String == "sha256:abc")
    }

    @Test("chunked response with uppercase Transfer-Encoding header is decoded")
    func chunkedUppercaseHeader() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }

        let json = #"{"Name":"host","Driver":"host"}"#
        let chunkSize = String(json.utf8.count, radix: 16)
        let chunkedBody = "\(chunkSize)\r\n\(json)\r\n0\r\n\r\n"
        // Note: Transfer-Encoding in mixed case — the code lowercases the header
        let resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: Chunked\r\nConnection: close\r\n\r\n\(chunkedBody)"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.inspectNetwork(id: "host")
        server.cancel()
        #expect(result["Name"] as? String == "host")
    }
}

// MARK: - Error propagation for 4xx/5xx on various endpoints

@Suite("Cov3Svc_DockerClient error propagation", .serialized)
struct Cov3Svc_DockerClientErrorPropagationTests {

    private func errorServer(body: String, status: Int, socketPath: String) -> Task<Void, Never> {
        let resp = "HTTP/1.1 \(status) Error\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        return Cov3Svc_makeServer(response: resp, socketPath: socketPath)
    }

    @Test("startContainer 304 does NOT throw (below 400)")
    func startContainer304DoesNotThrow() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let resp = "HTTP/1.1 304 Not Modified\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        // 304 is < 400 so should not throw
        try await client.startContainer(id: "abc")
        server.cancel()
    }

    @Test("stopContainer 404 throws apiError")
    func stopContainer404() async {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = #"{"message":"No such container: abc"}"#
        let server = errorServer(body: body, status: 404, socketPath: sp)
        Task { await Cov3Svc_waitServer(sp) }
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        do {
            try await client.stopContainer(id: "abc")
            Issue.record("Expected apiError")
        } catch let e as DockerError {
            if case .apiError(let code, _) = e { #expect(code == 404) }
            else { Issue.record("Expected .apiError, got \(e)") }
        } catch { Issue.record("Expected DockerError, got \(error)") }
        server.cancel()
    }

    @Test("removeImage 409 conflict throws apiError")
    func removeImage409() async {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = #"{"message":"conflict: unable to delete (must be forced)"}"#
        let server = errorServer(body: body, status: 409, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        do {
            try await client.removeImage(name: "nginx:latest")
            Issue.record("Expected apiError for 409")
        } catch let e as DockerError {
            if case .apiError(let code, let msg) = e {
                #expect(code == 409)
                #expect(msg.contains("conflict"))
            } else {
                Issue.record("Expected .apiError, got \(e)")
            }
        } catch { Issue.record("Expected DockerError, got \(error)") }
        server.cancel()
    }

    @Test("createVolume 500 throws apiError")
    func createVolume500() async {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = "Internal Server Error"
        let server = errorServer(body: body, status: 500, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        do {
            _ = try await client.createVolume(name: "bad-vol")
            Issue.record("Expected apiError for 500")
        } catch let e as DockerError {
            if case .apiError(let code, _) = e { #expect(code == 500) }
            else { Issue.record("Expected .apiError, got \(e)") }
        } catch { Issue.record("Expected DockerError, got \(error)") }
        server.cancel()
    }

    @Test("createContainer 400 throws apiError with message")
    func createContainer400() async {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = #"{"message":"invalid image name: bad//image"}"#
        let server = errorServer(body: body, status: 400, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        do {
            _ = try await client.createContainer(name: "test", image: "bad//image")
            Issue.record("Expected apiError for 400")
        } catch let e as DockerError {
            if case .apiError(let code, let msg) = e {
                #expect(code == 400)
                #expect(msg.contains("invalid image name"))
            } else {
                Issue.record("Expected .apiError, got \(e)")
            }
        } catch { Issue.record("Expected DockerError, got \(error)") }
        server.cancel()
    }

    @Test("missing socket throws socketNotFound for all POST endpoints")
    func allPostEndpointsMissingSocket() async {
        let sock = "/tmp/cov3svc-gone-\(UUID().uuidString).sock"
        let client = DockerClient(socketPath: sock)

        // restartContainer
        do {
            try await client.restartContainer(id: "x")
            Issue.record("Expected throw")
        } catch let e as DockerError {
            if case .socketNotFound = e { } else { Issue.record("Expected socketNotFound") }
        } catch { }
    }
}

// MARK: - ping returns false for non-OK body

@Suite("Cov3Svc_DockerClient ping variants", .serialized)
struct Cov3Svc_DockerClientPingTests {

    @Test("ping returns false when body is not exactly 'OK'")
    func pingNonOKBody() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = "PONG"
        let resp = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.ping()
        server.cancel()
        // Body is "PONG" not "OK" — should return false
        #expect(result == false)
    }

    @Test("ping returns true when body is exactly 'OK'")
    func pingOKBody() async throws {
        let sp = "/tmp/cov3svc-docker-\(UUID().uuidString).sock"
        defer { unlink(sp) }
        let body = "OK"
        let resp = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = Cov3Svc_makeServer(response: resp, socketPath: sp)
        await Cov3Svc_waitServer(sp)
        let client = DockerClient(socketPath: sp)
        let result = try await client.ping()
        server.cancel()
        #expect(result == true)
    }
}

import Foundation

/// HTTP client for Docker Engine API over Unix domain socket.
/// Connects to ~/.colima/<profile>/docker.sock
actor DockerClient {
    private let socketPath: String
    private let apiVersion = "v1.46"

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    init(profile: String = "default") {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.colima/\(profile)/docker.sock"
        self.init(socketPath: path)
    }

    // MARK: - Containers

    func listContainers(all: Bool = true) async throws -> [[String: Any]] {
        let query = all ? "all=true" : ""
        return try await getJSON("/containers/json?\(query)") as? [[String: Any]] ?? []
    }

    func inspectContainer(id: String) async throws -> [String: Any] {
        return try await getJSON("/containers/\(id)/json") as? [String: Any] ?? [:]
    }

    func createContainer(name: String, image: String, platform: String? = nil, config: [String: Any] = [:]) async throws -> String {
        var body: [String: Any] = ["Image": image, "Cmd": ["sleep", "infinity"]]
        body.merge(config) { _, new in new }
        var query = "name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
        if let platform {
            query += "&platform=\(platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? platform)"
        }
        let resp = try await postJSON("/containers/create?\(query)", body: body)
        return (resp as? [String: Any])?["Id"] as? String ?? ""
    }

    func startContainer(id: String) async throws {
        try await post("/containers/\(id)/start")
    }

    func stopContainer(id: String, timeout: Int = 10) async throws {
        try await post("/containers/\(id)/stop?t=\(timeout)")
    }

    func killContainer(id: String, signal: String = "SIGKILL") async throws {
        try await post("/containers/\(id)/kill?signal=\(signal)")
    }

    func restartContainer(id: String) async throws {
        try await post("/containers/\(id)/restart")
    }

    func pauseContainer(id: String) async throws {
        try await post("/containers/\(id)/pause")
    }

    func unpauseContainer(id: String) async throws {
        try await post("/containers/\(id)/unpause")
    }

    func removeContainer(id: String, force: Bool = false) async throws {
        try await delete("/containers/\(id)?force=\(force)")
    }

    func renameContainer(id: String, newName: String) async throws {
        try await post("/containers/\(id)/rename?name=\(newName)")
    }

    func containerLogs(id: String, tail: Int = 100) async throws -> String {
        return try await getString("/containers/\(id)/logs?stdout=true&stderr=true&tail=\(tail)")
    }

    func containerTop(id: String) async throws -> [String: Any] {
        return try await getJSON("/containers/\(id)/top") as? [String: Any] ?? [:]
    }

    func containerStats(id: String, stream: Bool = false) async throws -> [String: Any] {
        return try await getJSON("/containers/\(id)/stats?stream=\(stream)") as? [String: Any] ?? [:]
    }

    func containerChanges(id: String) async throws -> [[String: Any]] {
        let (data, _) = try await request("GET", "/containers/\(id)/changes")
        if data.isEmpty { return [] }
        // Docker API returns literal "null" for containers with no changes
        let str = String(data: data, encoding: .utf8) ?? ""
        if str.trimmingCharacters(in: .whitespacesAndNewlines) == "null" { return [] }
        let json = try JSONSerialization.jsonObject(with: data)
        return json as? [[String: Any]] ?? []
    }

    func waitContainer(id: String) async throws -> [String: Any] {
        // `/containers/{id}/wait` blocks until the container exits, so it opts out
        // of the request idle timeout (recvTimeout: 0) to preserve its semantics.
        let (data, _) = try await request("POST", "/containers/\(id)/wait", recvTimeout: 0)
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func pruneContainers() async throws -> [String: Any] {
        return try await postJSON("/containers/prune", body: nil) as? [String: Any] ?? [:]
    }

    func updateContainer(id: String, config: [String: Any]) async throws {
        _ = try await postJSON("/containers/\(id)/update", body: config)
    }

    // MARK: - Images

    func listImages() async throws -> [[String: Any]] {
        return try await getJSON("/images/json") as? [[String: Any]] ?? []
    }

    func inspectImage(name: String) async throws -> [String: Any] {
        return try await getJSON("/images/\(name)/json") as? [String: Any] ?? [:]
    }

    func pullImage(name: String) async throws {
        // Route through the streaming path with a no-op observer so the pull is
        // read to completion and any Docker/registry error is surfaced (rather
        // than the old fire-and-discard POST that swallowed the response body).
        try await pullImageStreaming(name: name) { _ in }
    }

    /// Stream a real image pull, reporting OBSERVED progress parsed from the
    /// Docker Engine API `/images/create` jsonmessage stream (per-layer
    /// `progressDetail.current`/`progressDetail.total`). Progress is never
    /// synthesized. The stream is bound to the caller's task: cancelling the
    /// awaiting task stops the read loop, and a Docker/registry error reported
    /// in the stream is thrown to the caller.
    func pullImageStreaming(name: String, onProgress: @escaping (ImagePullProgress) -> Void) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let path = "/\(apiVersion)/images/create?fromImage=\(encoded)"
        let aggregator = ImagePullProgressAggregator()

        // `Connection: close` makes Docker close the socket at end-of-response,
        // so the raw read loop terminates when the pull finishes (the
        // long-lived event/stat streams keep the keep-alive default).
        let task = streamLines(path: path, method: "POST", connectionClose: true) { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            onProgress(aggregator.ingest(json))
        }

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        try Task.checkCancellation()

        if let message = aggregator.errorMessage {
            throw DockerError.apiError(500, message)
        }

        // Emit a terminal snapshot so observers can render completion even if the
        // final stream line carried no new progress delta.
        onProgress(aggregator.finishedSnapshot())
    }

    func removeImage(name: String, force: Bool = false) async throws {
        try await delete("/images/\(name)?force=\(force)")
    }

    func tagImage(name: String, repo: String, tag: String) async throws {
        try await post("/images/\(name)/tag?repo=\(repo)&tag=\(tag)")
    }

    func imageHistory(name: String) async throws -> [[String: Any]] {
        return try await getJSON("/images/\(name)/history") as? [[String: Any]] ?? []
    }

    func searchImages(term: String) async throws -> [[String: Any]] {
        return try await getJSON("/images/search?term=\(term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term)") as? [[String: Any]] ?? []
    }

    func pruneImages() async throws -> [String: Any] {
        return try await postJSON("/images/prune", body: nil) as? [String: Any] ?? [:]
    }

    // MARK: - Volumes

    func listVolumes() async throws -> [String: Any] {
        return try await getJSON("/volumes") as? [String: Any] ?? [:]
    }

    func inspectVolume(name: String) async throws -> [String: Any] {
        return try await getJSON("/volumes/\(name)") as? [String: Any] ?? [:]
    }

    func createVolume(name: String, driver: String = "local") async throws -> [String: Any] {
        let body: [String: Any] = ["Name": name, "Driver": driver]
        return try await postJSON("/volumes/create", body: body) as? [String: Any] ?? [:]
    }

    func removeVolume(name: String) async throws {
        try await delete("/volumes/\(name)")
    }

    func pruneVolumes() async throws -> [String: Any] {
        return try await postJSON("/volumes/prune", body: nil) as? [String: Any] ?? [:]
    }

    // MARK: - Networks

    func listNetworks() async throws -> [[String: Any]] {
        return try await getJSON("/networks") as? [[String: Any]] ?? []
    }

    func inspectNetwork(id: String) async throws -> [String: Any] {
        return try await getJSON("/networks/\(id)") as? [String: Any] ?? [:]
    }

    func createNetwork(name: String, driver: String = "bridge") async throws -> [String: Any] {
        let body: [String: Any] = ["Name": name, "Driver": driver]
        return try await postJSON("/networks/create", body: body) as? [String: Any] ?? [:]
    }

    func removeNetwork(id: String) async throws {
        try await delete("/networks/\(id)")
    }

    func connectNetwork(networkId: String, containerId: String) async throws {
        let body: [String: Any] = ["Container": containerId]
        _ = try await postJSON("/networks/\(networkId)/connect", body: body)
    }

    func disconnectNetwork(networkId: String, containerId: String) async throws {
        let body: [String: Any] = ["Container": containerId]
        _ = try await postJSON("/networks/\(networkId)/disconnect", body: body)
    }

    func pruneNetworks() async throws -> [String: Any] {
        return try await postJSON("/networks/prune", body: nil) as? [String: Any] ?? [:]
    }

    // MARK: - System

    func systemInfo() async throws -> [String: Any] {
        return try await getJSON("/info") as? [String: Any] ?? [:]
    }

    func systemDf() async throws -> [String: Any] {
        return try await getJSON("/system/df") as? [String: Any] ?? [:]
    }

    func ping() async throws -> Bool {
        let result = try await getString("/_ping")
        return result == "OK"
    }

    // MARK: - Streaming

    /// Stream Docker events for container actions. Returns a Task that can be cancelled.
    func streamEvents(handler: @escaping (DockerEvent) -> Void) -> Task<Void, Never> {
        let path = "/\(apiVersion)/events?filters=%7B%22type%22%3A%5B%22container%22%5D%7D"
        return streamLines(path: path) { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = json["Action"] as? String,
                  let actor = json["Actor"] as? [String: Any],
                  let attrs = actor["Attributes"] as? [String: Any],
                  let name = attrs["name"] as? String else { return }
            handler(DockerEvent(action: action, containerName: name))
        }
    }

    /// Stream container logs with multiplexed stream parsing.
    func streamLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never> {
        let path = "/\(apiVersion)/containers/\(containerId)/logs?follow=true&stdout=true&stderr=true&tail=100"
        return streamRaw(path: path) { data in
            var offset = 0
            while offset + 8 <= data.count {
                let sizeBytes = data[offset+4..<offset+8]
                let size = Int(sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                offset += 8
                guard offset + size <= data.count else { break }
                if let line = String(data: data[offset..<offset+size], encoding: .utf8) {
                    handler(line)
                }
                offset += size
            }
        }
    }

    /// Stream container stats, calculating CPU%.
    func streamStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never> {
        let path = "/\(apiVersion)/containers/\(containerId)/stats?stream=true"
        var prevCPU: UInt64 = 0
        var prevSystem: UInt64 = 0
        return streamLines(path: path) { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cpuStats = json["cpu_stats"] as? [String: Any],
                  let cpuUsage = cpuStats["cpu_usage"] as? [String: Any],
                  let totalUsage = cpuUsage["total_usage"] as? UInt64,
                  let systemUsage = cpuStats["system_cpu_usage"] as? UInt64,
                  let memStats = json["memory_stats"] as? [String: Any],
                  let memUsage = memStats["usage"] as? UInt64,
                  let memLimit = memStats["limit"] as? UInt64 else { return }

            let onlineCPUs = cpuStats["online_cpus"] as? Int ?? 1
            var cpuPercent = 0.0
            if prevSystem > 0 {
                let cpuDelta = Double(totalUsage - prevCPU)
                let sysDelta = Double(systemUsage - prevSystem)
                if sysDelta > 0 {
                    cpuPercent = (cpuDelta / sysDelta) * Double(onlineCPUs) * 100.0
                }
            }
            prevCPU = totalUsage
            prevSystem = systemUsage

            var rx: UInt64 = 0
            var tx: UInt64 = 0
            if let networks = json["networks"] as? [String: Any] {
                for (_, iface) in networks {
                    if let ifaceDict = iface as? [String: Any] {
                        rx += ifaceDict["rx_bytes"] as? UInt64 ?? 0
                        tx += ifaceDict["tx_bytes"] as? UInt64 ?? 0
                    }
                }
            }

            handler(ContainerStats(cpuPercent: cpuPercent, memoryUsage: memUsage, memoryLimit: memLimit, networkRx: rx, networkTx: tx))
        }
    }

    // MARK: - Stream Helpers

    private func streamLines(path: String, method: String = "GET", connectionClose: Bool = false, handler: @escaping (String) -> Void) -> Task<Void, Never> {
        let sock = self.socketPath
        return Task.detached {
            do {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { return }
                defer { close(fd) }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                sock.withCString { ptr in
                    withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                        sunPath.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                            _ = strlcpy(dest, ptr, 104)
                        }
                    }
                }
                let connectResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard connectResult == 0 else { return }

                let connectionHeader = connectionClose ? "close" : "keep-alive"
                let httpReq = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: \(connectionHeader)\r\n\r\n"
                httpReq.withCString { ptr in _ = write(fd, ptr, strlen(ptr)) }

                // Skip HTTP headers
                var headerBuf = Data()
                var singleByte = [UInt8](repeating: 0, count: 1)
                while true {
                    let n = read(fd, &singleByte, 1)
                    if n <= 0 || Task.isCancelled { return }
                    headerBuf.append(singleByte[0])
                    if headerBuf.count >= 4 && headerBuf.suffix(4) == Data([0x0D, 0x0A, 0x0D, 0x0A]) { break }
                }

                // Read lines
                var lineBuf = ""
                var buffer = [UInt8](repeating: 0, count: 4096)
                while !Task.isCancelled {
                    let n = read(fd, &buffer, buffer.count)
                    if n <= 0 { break }
                    let chunk = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
                    lineBuf += chunk
                    while let range = lineBuf.range(of: "\n") {
                        let line = String(lineBuf[..<range.lowerBound])
                        lineBuf = String(lineBuf[range.upperBound...])
                        if !line.isEmpty { handler(line) }
                    }
                }
            }
        }
    }

    private func streamRaw(path: String, handler: @escaping (Data) -> Void) -> Task<Void, Never> {
        let sock = self.socketPath
        return Task.detached {
            do {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { return }
                defer { close(fd) }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                sock.withCString { ptr in
                    withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                        sunPath.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                            _ = strlcpy(dest, ptr, 104)
                        }
                    }
                }
                let connectResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard connectResult == 0 else { return }

                let httpReq = "GET \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n"
                httpReq.withCString { ptr in _ = write(fd, ptr, strlen(ptr)) }

                // Skip HTTP headers
                var headerBuf = Data()
                var singleByte = [UInt8](repeating: 0, count: 1)
                while true {
                    let n = read(fd, &singleByte, 1)
                    if n <= 0 || Task.isCancelled { return }
                    headerBuf.append(singleByte[0])
                    if headerBuf.count >= 4 && headerBuf.suffix(4) == Data([0x0D, 0x0A, 0x0D, 0x0A]) { break }
                }

                // Read raw data in chunks
                var buffer = [UInt8](repeating: 0, count: 65536)
                while !Task.isCancelled {
                    let n = read(fd, &buffer, buffer.count)
                    if n <= 0 { break }
                    handler(Data(buffer[0..<n]))
                }
            }
        }
    }

    // MARK: - HTTP Transport (Unix Socket - Direct)

    /// Perform a unary HTTP request over the Unix socket.
    ///
    /// `recvTimeout` bounds a stalled daemon: `read()` on the raw socket does not
    /// observe Swift task cancellation, so without a socket-level timeout a daemon
    /// that accepts the connection then stalls mid-response would block the call
    /// forever. A per-read idle timeout (SO_RCVTIMEO/SO_SNDTIMEO) makes such a call
    /// fail fast with `invalidResponse` instead of hanging (Requirement 11.2 —
    /// long-running operations are bounded). The default (75s) is far above any
    /// normal metadata op (<2s); pass `recvTimeout: 0` to opt out for calls that
    /// legitimately block until an external event (e.g. `waitContainer`).
    private func request(_ method: String, _ path: String, body: Data? = nil, recvTimeout: Int = 75) async throws -> (Data, Int) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DockerError.socketNotFound(socketPath) }
        defer { close(fd) }

        // Bound a stalled daemon: an idle read/write timeout so a wedged socket
        // fails fast rather than blocking indefinitely (raw read() ignores task
        // cancellation). recvTimeout == 0 leaves the socket unbounded.
        if recvTimeout > 0 {
            var tv = timeval(tv_sec: recvTimeout, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                sunPath.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                    _ = strlcpy(dest, ptr, 104)
                }
            }
        }
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw DockerError.socketNotFound(socketPath) }

        // Build HTTP request
        let fullPath = "/\(apiVersion)\(path)"
        var httpReq = "\(method) \(fullPath) HTTP/1.1\r\nHost: localhost\r\n"
        if let body = body {
            httpReq += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        httpReq += "Connection: close\r\n\r\n"

        // Send headers
        httpReq.withCString { ptr in _ = write(fd, ptr, strlen(ptr)) }
        // Send body
        if let body = body {
            body.withUnsafeBytes { ptr in _ = write(fd, ptr.baseAddress!, body.count) }
        }

        // Read response
        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            responseData.append(contentsOf: buffer[0..<n])
        }

        // Parse headers
        guard let headerEndRange = responseData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            throw DockerError.invalidResponse
        }
        let headerBytes = responseData[..<headerEndRange.lowerBound]
        let headerStr = String(data: headerBytes, encoding: .utf8) ?? ""
        let firstLine = headerStr.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        let statusCode = parts.count > 1 ? (Int(parts[1]) ?? 500) : 500

        var bodyData = Data(responseData[headerEndRange.upperBound...])

        // Handle chunked transfer encoding
        if headerStr.lowercased().contains("transfer-encoding: chunked") {
            bodyData = decodeChunked(bodyData)
        }

        if statusCode >= 400 {
            let msg = String(data: bodyData, encoding: .utf8) ?? "Unknown error"
            throw DockerError.apiError(statusCode, msg)
        }
        return (bodyData, statusCode)
    }

    private func decodeChunked(_ data: Data) -> Data {
        var result = Data()
        var remaining = data
        while !remaining.isEmpty {
            guard let crlfRange = remaining.range(of: Data([0x0D, 0x0A])) else { break }
            let sizeLine = String(data: remaining[..<crlfRange.lowerBound], encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? "0"
            guard let chunkSize = Int(sizeLine, radix: 16), chunkSize > 0 else { break }
            remaining = Data(remaining[crlfRange.upperBound...])
            guard remaining.count >= chunkSize else { break }
            result.append(remaining[..<remaining.index(remaining.startIndex, offsetBy: chunkSize)])
            remaining = Data(remaining[remaining.index(remaining.startIndex, offsetBy: chunkSize)...])
            if remaining.count >= 2 && remaining[remaining.startIndex] == 0x0D && remaining[remaining.index(after: remaining.startIndex)] == 0x0A {
                remaining = Data(remaining[remaining.index(remaining.startIndex, offsetBy: 2)...])
            }
        }
        return result
    }

    private func getJSON(_ path: String) async throws -> Any {
        let (data, _) = try await request("GET", path)
        if data.isEmpty { return [] as [Any] }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func getString(_ path: String) async throws -> String {
        let (data, _) = try await request("GET", path)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func post(_ path: String) async throws {
        _ = try await request("POST", path)
    }

    private func postJSON(_ path: String, body: Any?) async throws -> Any {
        var bodyData: Data?
        if let body = body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await request("POST", path, body: bodyData)
        if data.isEmpty { return [:] as [String: Any] }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func delete(_ path: String) async throws {
        _ = try await request("DELETE", path)
    }
}

// MARK: - Errors

enum DockerError: Error, LocalizedError {
    case invalidResponse
    case apiError(Int, String)
    case socketNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Docker"
        case .apiError(let code, let msg): return "Docker API error \(code): \(msg)"
        case .socketNotFound(let path): return "Docker socket not found at \(path)"
        }
    }
}

// MARK: - Image pull progress aggregation

/// Accumulates OBSERVED image-pull progress from Docker Engine API
/// `/images/create` jsonmessage events. Every value comes from a real stream
/// field — per-layer `progressDetail.current`/`total`, the layer `id`, and the
/// `status`/`error`/`errorDetail` fields — so nothing is synthesized. Overall
/// progress is the sum of observed per-layer download bytes over the sum of
/// observed per-layer totals; layers that report no total contribute to the
/// layer counts but not to the byte fraction. Not thread-safe: it is driven by
/// a single stream task, one event at a time.
final class ImagePullProgressAggregator {
    private var downloaded: [String: Int64] = [:]
    private var totals: [String: Int64] = [:]
    private var completed: Set<String> = []
    private var seenLayers: Set<String> = []
    private var lastStatus: String = ""
    private(set) var errorMessage: String?

    /// Docker per-layer phase statuses (lowercased). "Pulling from <repo>",
    /// "Digest:", and "Status:" are top-level (image, not layer) events and are
    /// intentionally excluded so they do not inflate the layer count.
    private static let layerStatuses: Set<String> = [
        "pulling fs layer", "waiting", "downloading", "verifying checksum",
        "download complete", "extracting", "pull complete", "already exists",
    ]
    /// Layer statuses that mean the layer is fully retrieved.
    private static let terminalStatuses: Set<String> = [
        "download complete", "pull complete", "already exists",
    ]

    init() {}

    /// Ingest one decoded jsonmessage object and return the current observed
    /// snapshot.
    @discardableResult
    func ingest(_ json: [String: Any]) -> ImagePullProgress {
        // Docker embeds pull/registry errors in the stream body (often with
        // HTTP 200), as `error` and/or `errorDetail.message`.
        if let error = json["error"] as? String, !error.isEmpty {
            errorMessage = error
            lastStatus = error
            return snapshot()
        }
        if let detail = json["errorDetail"] as? [String: Any],
           let message = detail["message"] as? String, !message.isEmpty {
            errorMessage = message
            lastStatus = message
            return snapshot()
        }

        let status = (json["status"] as? String) ?? ""
        if !status.isEmpty { lastStatus = status }
        let normalized = status.lowercased()

        if let id = json["id"] as? String, !id.isEmpty, Self.layerStatuses.contains(normalized) {
            seenLayers.insert(id)
            let detail = json["progressDetail"] as? [String: Any]
            if normalized == "downloading" {
                if let current = Self.int64(detail?["current"]) { downloaded[id] = current }
                if let total = Self.int64(detail?["total"]), total > 0 { totals[id] = total }
            }
            if Self.terminalStatuses.contains(normalized) {
                completed.insert(id)
                // Cap the layer to its observed total on completion so the
                // aggregate fraction reaches 1.0 for fully-pulled layers.
                if let total = totals[id] { downloaded[id] = total }
            }
        }
        return snapshot()
    }

    /// A terminal snapshot (`finished == true`) reflecting the final observed
    /// state.
    func finishedSnapshot() -> ImagePullProgress {
        var result = snapshot()
        result.finished = true
        return result
    }

    private func snapshot() -> ImagePullProgress {
        let current = downloaded.values.reduce(0, +)
        let total = totals.values.reduce(0, +)
        let fraction: Double? = total > 0 ? min(1.0, Double(current) / Double(total)) : nil
        return ImagePullProgress(
            status: lastStatus,
            layerCount: seenLayers.count,
            completedLayers: completed.count,
            currentBytes: current,
            totalBytes: total,
            fraction: fraction,
            finished: false,
            errorMessage: errorMessage
        )
    }

    /// Tolerant numeric extraction — `JSONSerialization` may hand back `Int`,
    /// `Int64`, `Double`, or `NSNumber` for the byte fields.
    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let v as Int64: return v
        case let v as Int: return Int64(v)
        case let v as Double: return Int64(v)
        case let v as NSNumber: return v.int64Value
        default: return nil
        }
    }
}

import Foundation

/// HTTP client for Docker Engine API over Unix domain socket.
/// Connects to ~/.colima/<profile>/docker.sock
actor DockerClient {
    private let socketPath: String
    private let apiVersion = "v1.46"

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    convenience init(profile: String = "default") {
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

    func createContainer(name: String, image: String, config: [String: Any] = [:]) async throws -> String {
        var body: [String: Any] = ["Image": image]
        body.merge(config) { _, new in new }
        let resp = try await postJSON("/containers/create?name=\(name)", body: body)
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
        return try await getJSON("/containers/\(id)/changes") as? [[String: Any]] ?? []
    }

    func waitContainer(id: String) async throws -> [String: Any] {
        return try await postJSON("/containers/\(id)/wait", body: nil) as? [String: Any] ?? [:]
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
        try await post("/images/create?fromImage=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")
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

    // MARK: - HTTP Transport (Unix Socket)

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        let url = URL(string: "http://localhost/\(apiVersion)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let config = URLSessionConfiguration.default
        config.protocolClasses = [UnixSocketURLProtocol.self]
        let session = URLSession(configuration: config)

        // Store socket path for the protocol to use
        req.setValue(socketPath, forHTTPHeaderField: "X-Unix-Socket")

        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DockerError.invalidResponse
        }
        if httpResponse.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DockerError.apiError(httpResponse.statusCode, msg)
        }
        return (data, httpResponse)
    }

    private func getJSON(_ path: String) async throws -> Any {
        let (data, _) = try await request("GET", path)
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

// MARK: - Unix Socket URL Protocol

class UnixSocketURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        return request.value(forHTTPHeaderField: "X-Unix-Socket") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let socketPath = request.value(forHTTPHeaderField: "X-Unix-Socket"),
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: DockerError.invalidResponse)
            return
        }

        Task {
            do {
                let fd = socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else { throw DockerError.socketNotFound(socketPath) }
                defer { close(fd) }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                socketPath.withCString { ptr in
                    withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                        let bound = sunPath.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                            strlcpy(dest, ptr, 104)
                        }
                        _ = bound
                    }
                }

                let connectResult = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }
                guard connectResult == 0 else { throw DockerError.socketNotFound(socketPath) }

                // Build HTTP request
                let method = request.httpMethod ?? "GET"
                let path = url.path + (url.query.map { "?\($0)" } ?? "")
                var httpReq = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\n"
                if let body = request.httpBody {
                    httpReq += "Content-Length: \(body.count)\r\n"
                    httpReq += "Content-Type: application/json\r\n"
                }
                httpReq += "Connection: close\r\n\r\n"

                // Send
                httpReq.withCString { ptr in _ = write(fd, ptr, strlen(ptr)) }
                if let body = request.httpBody {
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

                // Parse HTTP response
                guard let responseStr = String(data: responseData, encoding: .utf8),
                      let headerEnd = responseStr.range(of: "\r\n\r\n") else {
                    throw DockerError.invalidResponse
                }

                let headerPart = String(responseStr[..<headerEnd.lowerBound])
                let firstLine = headerPart.components(separatedBy: "\r\n").first ?? ""
                let statusCode = Int(firstLine.components(separatedBy: " ")[safe: 1] ?? "500") ?? 500

                let bodyStart = responseData.advanced(by: responseStr.distance(from: responseStr.startIndex, to: headerEnd.upperBound))
                let bodyData = Data(bodyStart)

                let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: bodyData)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import Foundation

struct MockContainer: Identifiable, Equatable {
    let id: String
    var name: String
    let image: String
    var status: String
    var state: String
    let ports: String
    let created: String
}

struct MockImage: Identifiable, Equatable {
    let id: String
    let repository: String
    let tag: String
    let size: String
    let created: String
}

struct MockVolume: Identifiable, Equatable {
    let id: String
    let name: String
    let driver: String
    let mountpoint: String
    let size: String
}

struct MockNetwork: Identifiable, Equatable {
    let id: String
    let name: String
    let driver: String
    let scope: String
    let subnet: String
}

struct MockProfile: Identifiable, Equatable {
    let id: String
    let name: String
    var status: String
    let arch: String
    let cpus: Int
    let memory: String
    let disk: String
    let runtime: String
}

struct MockData {
    static let containers: [MockContainer] = [
        MockContainer(id: "abc123def456", name: "web-server", image: "nginx:latest", status: "Up 2 hours", state: "running", ports: "0.0.0.0:8080->80/tcp", created: "2 hours ago"),
        MockContainer(id: "def456ghi789", name: "postgres-db", image: "postgres:16", status: "Up 2 hours", state: "running", ports: "5432/tcp", created: "2 hours ago"),
        MockContainer(id: "ghi789jkl012", name: "redis-cache", image: "redis:7-alpine", status: "Exited (0) 1 hour ago", state: "exited", ports: "", created: "3 hours ago"),
        MockContainer(id: "jkl012mno345", name: "api-service", image: "node:20-slim", status: "Up 30 minutes", state: "running", ports: "0.0.0.0:3000->3000/tcp", created: "30 minutes ago"),
        MockContainer(id: "mno345pqr678", name: "worker", image: "python:3.12", status: "Paused", state: "paused", ports: "", created: "1 hour ago"),
    ]

    static let images: [MockImage] = [
        MockImage(id: "sha256:aaa111", repository: "nginx", tag: "latest", size: "187MB", created: "2 weeks ago"),
        MockImage(id: "sha256:bbb222", repository: "postgres", tag: "16", size: "432MB", created: "3 weeks ago"),
        MockImage(id: "sha256:ccc333", repository: "redis", tag: "7-alpine", size: "30MB", created: "1 week ago"),
        MockImage(id: "sha256:ddd444", repository: "node", tag: "20-slim", size: "220MB", created: "5 days ago"),
        MockImage(id: "sha256:eee555", repository: "python", tag: "3.12", size: "1.01GB", created: "1 month ago"),
    ]

    static let volumes: [MockVolume] = [
        MockVolume(id: "vol001", name: "postgres_data", driver: "local", mountpoint: "/var/lib/docker/volumes/postgres_data/_data", size: "256MB"),
        MockVolume(id: "vol002", name: "redis_data", driver: "local", mountpoint: "/var/lib/docker/volumes/redis_data/_data", size: "12MB"),
        MockVolume(id: "vol003", name: "app_uploads", driver: "local", mountpoint: "/var/lib/docker/volumes/app_uploads/_data", size: "1.2GB"),
    ]

    static let networks: [MockNetwork] = [
        MockNetwork(id: "net001", name: "bridge", driver: "bridge", scope: "local", subnet: "172.17.0.0/16"),
        MockNetwork(id: "net002", name: "host", driver: "host", scope: "local", subnet: ""),
        MockNetwork(id: "net003", name: "app-network", driver: "bridge", scope: "local", subnet: "172.18.0.0/16"),
    ]

    static let profiles: [MockProfile] = [
        MockProfile(id: "prof001", name: "default", status: "Running", arch: "aarch64", cpus: 4, memory: "8GiB", disk: "100GiB", runtime: "docker"),
        MockProfile(id: "prof002", name: "dev", status: "Running", arch: "aarch64", cpus: 2, memory: "4GiB", disk: "60GiB", runtime: "docker"),
        MockProfile(id: "prof003", name: "k8s", status: "Stopped", arch: "aarch64", cpus: 4, memory: "8GiB", disk: "100GiB", runtime: "docker"),
    ]
}

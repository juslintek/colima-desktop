import Foundation

/// Mock implementation of ServiceProvider for UI testing and previews.
/// Returns static data from MockData, simulates state changes in-memory.
class MockServiceProvider: ServiceProvider {
    var containers: [MockContainer] = MockData.containers
    var images: [MockImage] = MockData.images
    var volumes: [MockVolume] = MockData.volumes
    var networks: [MockNetwork] = MockData.networks
    var profiles: [MockProfile] = MockData.profiles
    var vmRunning = true
    var k8sRunning = false

    // MARK: - VM

    func startVM(profile: String) async throws { vmRunning = true }
    func stopVM(profile: String, force: Bool) async throws { vmRunning = false }
    func restartVM(profile: String) async throws { vmRunning = true }
    func deleteVM(profile: String, data: Bool) async throws { vmRunning = false }
    func vmStatus(profile: String) async throws -> VMStatusInfo {
        VMStatusInfo(
            running: vmRunning,
            profile: profile,
            arch: "aarch64",
            runtime: "docker",
            mountType: "virtiofs",
            cpu: 4,
            memory: 8 * 1024 * 1024 * 1024,
            disk: 100 * 1024 * 1024 * 1024,
            version: "0.10.1"
        )
    }
    func vmVersion() async throws -> String { "0.10.1" }
    func updateVM() async throws {}
    func pruneVM(all: Bool) async throws {}
    func sshConfig(profile: String) async throws -> String {
        "Host colima\n  HostName 192.168.106.2\n  User colima\n  Port 22"
    }

    // MARK: - Profiles

    func listProfiles() async throws -> [ProfileListItem] {
        profiles.map { ProfileListItem(name: $0.name, status: $0.status, arch: $0.arch, cpus: $0.cpus, memory: Int64($0.cpus) * 1024*1024*1024, disk: 100*1024*1024*1024, runtime: $0.runtime) }
    }
    func createProfile(name: String, config: ColimaStartConfig) async throws {
        profiles.append(MockProfile(id: UUID().uuidString, name: name, status: "Stopped", arch: "aarch64", cpus: config.cpus, memory: "\(config.memory)GiB", disk: "60GiB", runtime: config.runtime))
    }
    func deleteProfile(name: String, data: Bool) async throws {
        profiles.removeAll { $0.name == name }
    }
    func cloneProfile(source: String, dest: String) async throws {
        guard let src = profiles.first(where: { $0.name == source }) else { return }
        profiles.append(MockProfile(id: UUID().uuidString, name: dest, status: "Stopped", arch: src.arch, cpus: src.cpus, memory: src.memory, disk: src.disk, runtime: src.runtime))
    }

    // MARK: - Kubernetes

    func k8sStart(profile: String) async throws { k8sRunning = true }
    func k8sStop(profile: String) async throws { k8sRunning = false }
    func k8sReset(profile: String) async throws { k8sRunning = false }
    func kubectlExec(_ command: String) async throws -> String { "mock kubectl output" }

    // MARK: - Containers

    func listContainers() async throws -> [[String: Any]] {
        containers.map { c in
            ["Id": c.id, "Names": ["/\(c.name)"], "Image": c.image, "Status": c.status, "State": c.state] as [String: Any]
        }
    }
    func startContainer(id: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].state = "running"; containers[i].status = "Up just now"
    }
    func stopContainer(id: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].state = "exited"; containers[i].status = "Exited (0) just now"
    }
    func killContainer(id: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].state = "exited"; containers[i].status = "Exited (137) just now"
    }
    func restartContainer(id: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].state = "running"; containers[i].status = "Up just now"
    }
    func pauseContainer(id: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].state = "paused"; containers[i].status = "Paused"
    }
    func unpauseContainer(id: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].state = "running"; containers[i].status = "Up just now"
    }
    func removeContainer(id: String) async throws {
        containers.removeAll { $0.name == id || $0.id == id }
    }
    func createContainer(name: String, image: String) async throws -> String {
        let id = UUID().uuidString.prefix(12).description
        containers.append(MockContainer(id: id, name: name, image: image, status: "Created", state: "created", ports: "", created: "just now"))
        return id
    }
    func renameContainer(id: String, newName: String) async throws {
        guard let i = containers.firstIndex(where: { $0.name == id || $0.id == id }) else { return }
        containers[i].name = newName
    }
    func containerLogs(id: String) async throws -> String { "2024-01-01 mock log line 1\n2024-01-01 mock log line 2" }
    func inspectContainer(id: String) async throws -> String { "{\"Id\":\"\(id)\",\"State\":{\"Status\":\"running\"}}" }
    func containerTop(id: String) async throws -> String { "{\"Processes\":[[\"root\",\"1\",\"0.0\",\"sh\"]]}" }
    func containerStats(id: String) async throws -> String { "{\"cpu_percent\":2.5,\"memory_usage\":104857600}" }
    func containerChanges(id: String) async throws -> String { "[{\"Path\":\"/tmp\",\"Kind\":1}]" }
    func pruneContainers() async throws {
        containers.removeAll { $0.state == "exited" }
    }

    // MARK: - Images

    func listImages() async throws -> [[String: Any]] {
        images.map { img in
            ["Id": img.id, "RepoTags": ["\(img.repository):\(img.tag)"], "Size": Int64(100_000_000)] as [String: Any]
        }
    }
    func pullImage(name: String) async throws {
        images.append(MockImage(id: "sha256:\(UUID().uuidString.prefix(6))", repository: name, tag: "latest", size: "100MB", created: "just now"))
    }
    func removeImage(id: String) async throws { images.removeAll { $0.id == id } }
    func inspectImage(name: String) async throws -> String { "{\"Id\":\"\(name)\",\"RepoTags\":[\"\(name):latest\"]}" }
    func imageHistory(name: String) async throws -> String { "[{\"Created\":1700000000,\"CreatedBy\":\"CMD [\\\"sh\\\"]\"}]" }
    func tagImage(name: String, repo: String, tag: String) async throws {}
    func pushImage(name: String) async throws {}
    func searchImages(term: String) async throws -> [[String: Any]] {
        [["name": term, "description": "Mock result", "star_count": 100, "is_official": true]]
    }
    func pruneImages() async throws {}

    // MARK: - Volumes

    func listVolumes() async throws -> [[String: Any]] {
        volumes.map { v in ["Name": v.name, "Driver": v.driver, "Mountpoint": v.mountpoint] as [String: Any] }
    }
    func createVolume(name: String) async throws {
        volumes.append(MockVolume(id: UUID().uuidString, name: name, driver: "local", mountpoint: "/var/lib/docker/volumes/\(name)/_data", size: "0B"))
    }
    func removeVolume(name: String) async throws { volumes.removeAll { $0.name == name } }
    func inspectVolume(name: String) async throws -> String { "{\"Name\":\"\(name)\",\"Driver\":\"local\"}" }
    func pruneVolumes() async throws {}

    // MARK: - Networks

    func listNetworks() async throws -> [[String: Any]] {
        networks.map { n in ["Id": n.id, "Name": n.name, "Driver": n.driver, "Scope": n.scope, "IPAM": ["Config": [["Subnet": n.subnet]]]] as [String: Any] }
    }
    func createNetwork(name: String) async throws {
        networks.append(MockNetwork(id: UUID().uuidString, name: name, driver: "bridge", scope: "local", subnet: "172.19.0.0/16"))
    }
    func removeNetwork(name: String) async throws { networks.removeAll { $0.name == name } }
    func inspectNetwork(id: String) async throws -> String { "{\"Id\":\"\(id)\",\"Name\":\"\(id)\",\"Driver\":\"bridge\"}" }
    func connectNetwork(networkId: String, containerId: String) async throws {}
    func disconnectNetwork(networkId: String, containerId: String) async throws {}
    func pruneNetworks() async throws {}

    // MARK: - Monitoring

    func processList(profile: String) async throws -> String { "USER PID %CPU COMMAND\nroot 1 0.0 init" }
    func killProcess(profile: String, pid: Int) async throws {}

    // MARK: - Streaming

    func streamEvents(handler: @escaping (DockerEvent) -> Void) -> Task<Void, Never>? { nil }
    func streamLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never>? { nil }
    func streamStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never>? { nil }

    // MARK: - Profile Switching

    func switchProfile(name: String) async throws {}

    // MARK: - Configuration

    func readConfig(profile: String) async throws -> ColimaConfig {
        var config = ColimaConfig()
        config.mounts = [
            ColimaConfig.Mount(location: "~", writable: true),
            ColimaConfig.Mount(location: "/tmp/colima", writable: true)
        ]
        config.provision = [ColimaConfig.Provision(mode: "system", script: "apt-get update")]
        config.env = ["DOCKER_BUILDKIT": "1"]
        return config
    }

    func writeConfig(profile: String, config: ColimaConfig) async throws {}

    // MARK: - Command Execution

    func executeCommand(tool: String, args: [String]) async throws -> String {
        "mock output for \(tool) \(args.joined(separator: " "))"
    }
}

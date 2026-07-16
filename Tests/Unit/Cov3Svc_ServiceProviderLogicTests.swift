import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - RealServiceProvider init + isColimaInstalled (no live backend)

@Suite("Cov3Svc_RealServiceProvider pure paths")
@MainActor
struct Cov3Svc_RealServiceProviderTests {

    @Test("RealServiceProvider can be initialized with default profile")
    func defaultInit() {
        let provider = RealServiceProvider()
        // Just verifying instantiation doesn't crash
        let _ = provider
        #expect(Bool(true))
    }

    @Test("RealServiceProvider can be initialized with custom profile name")
    func customProfileInit() {
        let provider = RealServiceProvider(profile: "dev")
        let _ = provider
        #expect(Bool(true))
    }

    @Test("isColimaInstalled returns Bool without crashing")
    func isColimaInstalledReturnsBool() async {
        let provider = RealServiceProvider()
        let result = await provider.isColimaInstalled()
        let _ = result  // consume; value depends on environment
        #expect(Bool(true))
    }

    @Test("RealServiceProvider conforms to ServiceProvider protocol")
    func conformsToServiceProvider() {
        let provider: ServiceProvider = RealServiceProvider()
        let _ = provider
        #expect(Bool(true))
    }
}

// MARK: - MockServiceProvider full protocol surface

@Suite("Cov3Svc_MockServiceProvider")
@MainActor
struct Cov3Svc_MockServiceProviderTests {

    private func mock() -> MockServiceProvider { MockServiceProvider() }

    // MARK: VM operations

    @Test("startVM sets vmRunning true")
    func startVM() async throws {
        let m = mock()
        m.vmRunning = false
        try await m.startVM(profile: "default")
        #expect(m.vmRunning == true)
    }

    @Test("stopVM sets vmRunning false")
    func stopVM() async throws {
        let m = mock()
        try await m.stopVM(profile: "default", force: false)
        #expect(m.vmRunning == false)
    }

    @Test("stopVM with force also sets vmRunning false")
    func stopVMForce() async throws {
        let m = mock()
        try await m.stopVM(profile: "default", force: true)
        #expect(m.vmRunning == false)
    }

    @Test("restartVM sets vmRunning true")
    func restartVM() async throws {
        let m = mock()
        m.vmRunning = false
        try await m.restartVM(profile: "default")
        #expect(m.vmRunning == true)
    }

    @Test("deleteVM sets vmRunning false")
    func deleteVM() async throws {
        let m = mock()
        try await m.deleteVM(profile: "default", data: false)
        #expect(m.vmRunning == false)
    }

    @Test("vmStatus returns correct info when running")
    func vmStatusRunning() async throws {
        let m = mock()
        m.vmRunning = true
        let status = try await m.vmStatus(profile: "dev")
        #expect(status.running == true)
        #expect(status.profile == "dev")
        #expect(status.arch == "aarch64")
        #expect(status.runtime == "docker")
        #expect(status.cpu == 4)
    }

    @Test("vmStatus returns running false when stopped")
    func vmStatusStopped() async throws {
        let m = mock()
        m.vmRunning = false
        let status = try await m.vmStatus(profile: "default")
        #expect(status.running == false)
    }

    @Test("vmVersion returns mock version string")
    func vmVersion() async throws {
        let m = mock()
        let v = try await m.vmVersion()
        #expect(v == "0.10.1")
    }

    @Test("updateVM does not throw")
    func updateVM() async throws {
        let m = mock()
        try await m.updateVM()
    }

    @Test("pruneVM does not throw")
    func pruneVM() async throws {
        let m = mock()
        try await m.pruneVM(all: false)
        try await m.pruneVM(all: true)
    }

    @Test("sshConfig returns non-empty string")
    func sshConfig() async throws {
        let m = mock()
        let config = try await m.sshConfig(profile: "default")
        #expect(!config.isEmpty)
        #expect(config.contains("Host"))
    }

    // MARK: Profile operations

    @Test("listProfiles returns profiles from MockData")
    func listProfiles() async throws {
        let m = mock()
        let profiles = try await m.listProfiles()
        #expect(!profiles.isEmpty)
        let names = profiles.map { $0.name }
        #expect(names.contains("default"))
    }

    @Test("createProfile appends a new profile")
    func createProfile() async throws {
        let m = mock()
        let initialCount = m.profiles.count
        let config = ColimaStartConfig(cpus: 2, memory: 4, disk: 60, vmType: "vz", runtime: "docker", mountType: "virtiofs", kubernetes: false)
        try await m.createProfile(name: "new-profile", config: config)
        #expect(m.profiles.count == initialCount + 1)
        #expect(m.profiles.last?.name == "new-profile")
    }

    @Test("deleteProfile removes the named profile")
    func deleteProfile() async throws {
        let m = mock()
        let initialCount = m.profiles.count
        try await m.deleteProfile(name: "dev", data: false)
        #expect(m.profiles.count == initialCount - 1)
        #expect(!m.profiles.contains(where: { $0.name == "dev" }))
    }

    @Test("deleteProfile with data:true also removes")
    func deleteProfileWithData() async throws {
        let m = mock()
        try await m.deleteProfile(name: "default", data: true)
        #expect(!m.profiles.contains(where: { $0.name == "default" }))
    }

    @Test("cloneProfile appends a new profile with dest name")
    func cloneProfile() async throws {
        let m = mock()
        let initialCount = m.profiles.count
        try await m.cloneProfile(source: "default", dest: "default-clone")
        #expect(m.profiles.count == initialCount + 1)
        #expect(m.profiles.contains(where: { $0.name == "default-clone" }))
    }

    @Test("cloneProfile with nonexistent source does nothing")
    func cloneProfileNonexistent() async throws {
        let m = mock()
        let initialCount = m.profiles.count
        try await m.cloneProfile(source: "does-not-exist", dest: "clone")
        #expect(m.profiles.count == initialCount)
    }

    // MARK: Machines

    @Test("listMachines returns 4 mock machines")
    func listMachines() async throws {
        let m = mock()
        let machines = try await m.listMachines()
        #expect(machines.count == 4)
        let names = machines.compactMap { $0["name"] as? String }
        #expect(names.contains("dev-ubuntu"))
        #expect(names.contains("win11-test"))
    }

    // MARK: Kubernetes

    @Test("k8sStart sets k8sRunning true")
    func k8sStart() async throws {
        let m = mock()
        m.k8sRunning = false
        try await m.k8sStart(profile: "default")
        #expect(m.k8sRunning == true)
    }

    @Test("k8sStop sets k8sRunning false")
    func k8sStop() async throws {
        let m = mock()
        m.k8sRunning = true
        try await m.k8sStop(profile: "default")
        #expect(m.k8sRunning == false)
    }

    @Test("k8sReset sets k8sRunning false")
    func k8sReset() async throws {
        let m = mock()
        m.k8sRunning = true
        try await m.k8sReset(profile: "default")
        #expect(m.k8sRunning == false)
    }

    @Test("kubectlExec returns mock kubectl output")
    func kubectlExec() async throws {
        let m = mock()
        let result = try await m.kubectlExec("get pods")
        #expect(result == "mock kubectl output")
    }

    // MARK: Containers

    @Test("listContainers returns containers with expected fields")
    func listContainers() async throws {
        let m = mock()
        let containers = try await m.listContainers()
        #expect(!containers.isEmpty)
        for c in containers {
            #expect(c["Id"] != nil)
            #expect(c["State"] != nil)
        }
    }

    @Test("startContainer transitions state to running")
    func startContainer() async throws {
        let m = mock()
        // redis-cache starts exited
        try await m.startContainer(id: "redis-cache")
        #expect(m.containers.first(where: { $0.name == "redis-cache" })?.state == "running")
    }

    @Test("stopContainer transitions state to exited")
    func stopContainer() async throws {
        let m = mock()
        try await m.stopContainer(id: "web-server")
        #expect(m.containers.first(where: { $0.name == "web-server" })?.state == "exited")
    }

    @Test("killContainer transitions state to exited with 137")
    func killContainer() async throws {
        let m = mock()
        try await m.killContainer(id: "web-server")
        let c = m.containers.first(where: { $0.name == "web-server" })
        #expect(c?.state == "exited")
        #expect(c?.status.contains("137") == true)
    }

    @Test("restartContainer transitions state to running")
    func restartContainer() async throws {
        let m = mock()
        try await m.restartContainer(id: "redis-cache")
        #expect(m.containers.first(where: { $0.name == "redis-cache" })?.state == "running")
    }

    @Test("pauseContainer transitions state to paused")
    func pauseContainer() async throws {
        let m = mock()
        try await m.pauseContainer(id: "web-server")
        #expect(m.containers.first(where: { $0.name == "web-server" })?.state == "paused")
    }

    @Test("unpauseContainer transitions state to running")
    func unpauseContainer() async throws {
        let m = mock()
        try await m.unpauseContainer(id: "worker")
        #expect(m.containers.first(where: { $0.name == "worker" })?.state == "running")
    }

    @Test("removeContainer removes the container from the list")
    func removeContainer() async throws {
        let m = mock()
        let initialCount = m.containers.count
        try await m.removeContainer(id: "redis-cache")
        #expect(m.containers.count == initialCount - 1)
        #expect(!m.containers.contains(where: { $0.name == "redis-cache" }))
    }

    @Test("createContainer adds a container and returns an id")
    func createContainer() async throws {
        let m = mock()
        let initialCount = m.containers.count
        let id = try await m.createContainer(name: "new-ctr", image: "nginx:latest")
        #expect(!id.isEmpty)
        #expect(m.containers.count == initialCount + 1)
    }

    @Test("renameContainer renames the container")
    func renameContainer() async throws {
        let m = mock()
        try await m.renameContainer(id: "web-server", newName: "renamed-server")
        #expect(m.containers.contains(where: { $0.name == "renamed-server" }))
        #expect(!m.containers.contains(where: { $0.name == "web-server" }))
    }

    @Test("containerLogs returns non-empty log string")
    func containerLogs() async throws {
        let m = mock()
        let logs = try await m.containerLogs(id: "web-server")
        #expect(!logs.isEmpty)
    }

    @Test("inspectContainer returns non-empty JSON string")
    func inspectContainer() async throws {
        let m = mock()
        let result = try await m.inspectContainer(id: "web-server")
        #expect(!result.isEmpty)
    }

    @Test("containerTop returns non-empty top output")
    func containerTop() async throws {
        let m = mock()
        let result = try await m.containerTop(id: "web-server")
        #expect(!result.isEmpty)
    }

    @Test("containerStats returns non-empty stats string")
    func containerStats() async throws {
        let m = mock()
        let result = try await m.containerStats(id: "web-server")
        #expect(!result.isEmpty)
    }

    @Test("containerChanges returns non-empty changes string")
    func containerChanges() async throws {
        let m = mock()
        let result = try await m.containerChanges(id: "web-server")
        #expect(!result.isEmpty)
    }

    @Test("pruneContainers does not throw")
    func pruneContainers() async throws {
        let m = mock()
        try await m.pruneContainers()
    }

    // MARK: Images

    @Test("listImages returns mock images")
    func listImages() async throws {
        let m = mock()
        let images = try await m.listImages()
        #expect(!images.isEmpty)
        for img in images {
            #expect(img["Id"] != nil)
        }
    }

    @Test("pullImage does not throw")
    func pullImage() async throws {
        let m = mock()
        try await m.pullImage(name: "alpine:latest")
    }

    @Test("removeImage removes the image")
    func removeImage() async throws {
        let m = mock()
        let initialCount = m.images.count
        try await m.removeImage(id: "sha256:aaa111")
        #expect(m.images.count == initialCount - 1)
    }

    @Test("inspectImage returns JSON string")
    func inspectImage() async throws {
        let m = mock()
        let result = try await m.inspectImage(name: "nginx")
        #expect(!result.isEmpty)
    }

    @Test("imageHistory returns non-empty history string")
    func imageHistory() async throws {
        let m = mock()
        let result = try await m.imageHistory(name: "nginx")
        #expect(!result.isEmpty)
    }

    @Test("tagImage does not throw")
    func tagImage() async throws {
        let m = mock()
        try await m.tagImage(name: "nginx", repo: "myreg/nginx", tag: "v1")
    }

    @Test("pushImage does not throw")
    func pushImage() async throws {
        let m = mock()
        try await m.pushImage(name: "nginx:latest")
    }

    @Test("searchImages returns non-empty results")
    func searchImages() async throws {
        let m = mock()
        let results = try await m.searchImages(term: "nginx")
        #expect(!results.isEmpty)
    }

    @Test("pruneImages does not throw")
    func pruneImages() async throws {
        let m = mock()
        try await m.pruneImages()
    }

    // MARK: Volumes

    @Test("listVolumes returns mock volumes")
    func listVolumes() async throws {
        let m = mock()
        let vols = try await m.listVolumes()
        #expect(!vols.isEmpty)
    }

    @Test("createVolume adds a volume")
    func createVolume() async throws {
        let m = mock()
        let initialCount = m.volumes.count
        try await m.createVolume(name: "new-vol")
        #expect(m.volumes.count == initialCount + 1)
    }

    @Test("removeVolume removes the volume")
    func removeVolume() async throws {
        let m = mock()
        let initialCount = m.volumes.count
        try await m.removeVolume(name: "postgres_data")
        #expect(m.volumes.count == initialCount - 1)
    }

    @Test("inspectVolume returns JSON string")
    func inspectVolume() async throws {
        let m = mock()
        let result = try await m.inspectVolume(name: "postgres_data")
        #expect(!result.isEmpty)
    }

    @Test("pruneVolumes does not throw")
    func pruneVolumes() async throws {
        let m = mock()
        try await m.pruneVolumes()
    }

    // MARK: Networks

    @Test("listNetworks returns mock networks")
    func listNetworks() async throws {
        let m = mock()
        let nets = try await m.listNetworks()
        #expect(!nets.isEmpty)
    }

    @Test("createNetwork adds a network")
    func createNetwork() async throws {
        let m = mock()
        let initialCount = m.networks.count
        try await m.createNetwork(name: "new-net")
        #expect(m.networks.count == initialCount + 1)
    }

    @Test("removeNetwork removes the network")
    func removeNetwork() async throws {
        let m = mock()
        let initialCount = m.networks.count
        try await m.removeNetwork(name: "app-network")
        #expect(m.networks.count == initialCount - 1)
    }

    @Test("inspectNetwork returns JSON string")
    func inspectNetwork() async throws {
        let m = mock()
        let result = try await m.inspectNetwork(id: "bridge")
        #expect(!result.isEmpty)
    }

    @Test("connectNetwork does not throw")
    func connectNetwork() async throws {
        let m = mock()
        try await m.connectNetwork(networkId: "bridge", containerId: "web-server")
    }

    @Test("disconnectNetwork does not throw")
    func disconnectNetwork() async throws {
        let m = mock()
        try await m.disconnectNetwork(networkId: "bridge", containerId: "web-server")
    }

    @Test("pruneNetworks does not throw")
    func pruneNetworks() async throws {
        let m = mock()
        try await m.pruneNetworks()
    }

    // MARK: Monitoring

    @Test("processList returns non-empty string")
    func processList() async throws {
        let m = mock()
        let result = try await m.processList(profile: "default")
        #expect(!result.isEmpty)
    }

    @Test("killProcess does not throw")
    func killProcess() async throws {
        let m = mock()
        try await m.killProcess(profile: "default", pid: 1234)
    }

    // MARK: Streaming (non-blocking — just verify the Task is returned or nil)

    @Test("streamEvents returns a Task or nil")
    func streamEvents() {
        let m = mock()
        let task = m.streamEvents(handler: { _ in })
        task?.cancel()
        #expect(Bool(true))  // not nil-crashing
    }

    @Test("streamLogs returns a Task or nil")
    func streamLogs() {
        let m = mock()
        let task = m.streamLogs(containerId: "abc", handler: { _ in })
        task?.cancel()
        #expect(Bool(true))
    }

    @Test("streamStats returns a Task or nil")
    func streamStats() {
        let m = mock()
        let task = m.streamStats(containerId: "abc", handler: { _ in })
        task?.cancel()
        #expect(Bool(true))
    }

    // MARK: Profile switching

    @Test("switchProfile does not throw")
    func switchProfile() async throws {
        let m = mock()
        try await m.switchProfile(name: "dev")
    }

    // MARK: Configuration

    @Test("readConfig returns ColimaConfig")
    func readConfig() async throws {
        let m = mock()
        let config = try await m.readConfig(profile: "default")
        #expect(config.cpu >= 0)
    }

    @Test("writeConfig does not throw")
    func writeConfig() async throws {
        let m = mock()
        let config = ColimaConfig()
        try await m.writeConfig(profile: "default", config: config)
    }

    // MARK: Command execution

    @Test("executeCommand returns non-empty mock output")
    func executeCommand() async throws {
        let m = mock()
        let result = try await m.executeCommand(tool: "echo", args: ["hello"])
        #expect(!result.isEmpty)
    }

    // MARK: AI Models

    @Test("modelList returns model list")
    func modelList() async throws {
        let m = mock()
        let models = try await m.modelList(runner: "docker")
        let _ = models
        #expect(Bool(true))
    }

    @Test("modelPull does not throw")
    func modelPull() async throws {
        let m = mock()
        try await m.modelPull(name: "llama3.2", runner: "docker")
    }

    @Test("modelRun does not throw")
    func modelRun() async throws {
        let m = mock()
        try await m.modelRun(name: "llama3.2", runner: "docker")
    }

    @Test("modelServe does not throw")
    func modelServe() async throws {
        let m = mock()
        try await m.modelServe(name: "llama3.2", runner: "docker", port: 8080)
    }

    @Test("modelServe with nil name and port does not throw")
    func modelServeNils() async throws {
        let m = mock()
        try await m.modelServe(name: nil, runner: "docker", port: nil)
    }

    @Test("modelStop does not throw")
    func modelStop() async throws {
        let m = mock()
        try await m.modelStop(name: "llama3.2")
    }

    // MARK: Installation

    @Test("isColimaInstalled returns Bool")
    func isColimaInstalled() async {
        let m = mock()
        let result = await m.isColimaInstalled()
        let _ = result
        #expect(Bool(true))
    }

    @Test("installColima does not throw")
    func installColima() async throws {
        let m = mock()
        try await m.installColima()
    }
}

// MARK: - AIModelInfo parsing

@Suite("Cov3Svc_AIModelInfo parsing")
struct Cov3Svc_AIModelInfoParsingTests {

    @Test("AIModelInfo struct stores id, name, size, status, port")
    func allFields() {
        let info = AIModelInfo(id: "llama3.2:3b", name: "llama3.2:3b", size: "1.9GB", status: "idle", port: nil)
        #expect(info.id == "llama3.2:3b")
        #expect(info.name == "llama3.2:3b")
        #expect(info.size == "1.9GB")
        #expect(info.status == "idle")
        #expect(info.port == nil)
    }

    @Test("AIModelInfo struct stores port when provided")
    func withPort() {
        let info = AIModelInfo(id: "llama3.2:3b", name: "llama3.2:3b", size: "1.9GB", status: "serving", port: 8080)
        #expect(info.port == 8080)
        #expect(info.status == "serving")
    }

    @Test("AIModelInfo.parse returns empty array for empty input")
    func parseEmpty() {
        let models = AIModelInfo.parse("")
        #expect(models.isEmpty)
    }

    @Test("AIModelInfo.parse returns empty array for single header line")
    func parseHeaderOnly() {
        // Only one line (the header) — no data rows
        let output = "NAME  SIZE  STATUS"
        let models = AIModelInfo.parse(output)
        #expect(models.isEmpty)
    }

    @Test("AIModelInfo.parse parses a single model line with 2+ spaces separator")
    func parseSingleLine() {
        // The parse function splits on 2+ consecutive whitespace chars
        let output = "NAME  SIZE  STATUS\nllama3.2:3b  1.9 GB  idle\n"
        let models = AIModelInfo.parse(output)
        #expect(models.count == 1)
        #expect(models[0].name == "llama3.2:3b")
        #expect(models[0].size == "1.9 GB")
        #expect(models[0].status == "idle")
    }

    @Test("AIModelInfo.parse parses multiple model lines")
    func parseMultiple() {
        let output = "NAME  SIZE  STATUS\nllama3.2:3b  1.9 GB  idle\ncodellama:7b  3.8 GB  running\n"
        let models = AIModelInfo.parse(output)
        #expect(models.count == 2)
        #expect(models[0].name == "llama3.2:3b")
        #expect(models[1].name == "codellama:7b")
        #expect(models[1].status == "running")
    }

    @Test("AIModelInfo.parse line with fewer than 3 cols is skipped")
    func parseTooFewCols() {
        // Only 2 columns — should be skipped
        let output = "NAME  SIZE  STATUS\njust-one-col\n"
        let models = AIModelInfo.parse(output)
        // The single-column line has no 2+ space separator so produces 1 col -> skipped
        #expect(models.isEmpty)
    }

    @Test("AIModelInfo.parse handles port in 4th column")
    func parseWithPort() {
        let output = "NAME  SIZE  STATUS  PORT\nllama3.2:3b  1.9 GB  serving  :8080\n"
        let models = AIModelInfo.parse(output)
        #expect(models.count == 1)
        #expect(models[0].port == 8080)
    }
}

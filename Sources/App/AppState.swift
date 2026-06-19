import SwiftUI
import AppKit

class AppState: ObservableObject {
    @Published var selectedTab: NavigationItem = .dashboard
    @Published var vmRunning: Bool = true
    @Published var toastMessage: String?
    @Published var isToastVisible: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showConfirmation: Bool = false
    @Published var confirmationAction: (() -> Void)?
    @Published var confirmationMessage: String = ""
    @Published var colimaVersion: String = "0.10.1"

    let isUITesting = CommandLine.arguments.contains("--ui-testing")

    // VM Resources (populated from colima status --json)
    @Published var vmCPU: Int = 0
    @Published var vmMemory: Int64 = 0
    @Published var vmDisk: Int64 = 0
    @Published var vmRuntime: String = ""
    @Published var vmArch: String = ""
    @Published var vmMountType: String = ""
    @Published var vmType: String = ""
    @Published var vmDriver: String = ""

    @Published var colimaConfig: ColimaConfig?

    // Installation onboarding
    @Published var colimaInstalled: Bool = true
    @Published var isInstallingColima: Bool = false

    @Published var containers: [MockContainer] = []
    @Published var images: [MockImage] = []
    @Published var volumes: [MockVolume] = []
    @Published var networks: [MockNetwork] = []
    @Published var profiles: [MockProfile] = []
    @Published var machines: [MockVM] = []
    @Published var aiModels: [AIModelInfo] = []
    @Published var k8sRunning: Bool = false
    var k8sEnabled: Bool { k8sRunning }
    @Published var memoryGovernorTier: Int = 0
    @Published var activeProfile: String = "default"
    @Published var selectedContainerName: String?
    @Published var selectedImageId: String?
    @Published var selectedVolumeName: String?
    @Published var selectedNetworkName: String?
    @Published var selectedPodName: String?
    @Published var selectedK8sService: String?
    @Published var selectedK8sDeployment: String?
    @Published var selectedK8sNode: String?
    @Published var selectedMachine: String?

    // MARK: - Sheet State

    @Published var activeSheet: SheetType?
    @Published var showCommandPalette: Bool = false
    @Published var showSetupWizard: Bool = false
    @Published var sheetEntityName: String = ""
    @Published var sheetContent: String = ""
    @Published var sheetLogs: [String] = []
    @Published var sheetCommand: String = ""
    @Published var sheetTool: String = ""
    @Published var sheetSearchTerm: String = ""

    enum SheetType: Identifiable {
        case inspect, logs, terminal, stats, history, changes, search, commandRunner, copyFiles, createContainer
        var id: Self { self }
    }

    // MARK: - Service Layer

    let services: ServiceProvider
    private var eventStreamTask: Task<Void, Never>?

    init(services: ServiceProvider = RealServiceProvider()) {
        self.services = services
        // Deterministic deep-link for screenshots/testing: `--open-tab <name>`.
        if let i = CommandLine.arguments.firstIndex(of: "--open-tab"),
           i + 1 < CommandLine.arguments.count,
           let tab = NavigationItem(rawValue: CommandLine.arguments[i + 1]) {
            selectedTab = tab
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshAll()
                self.startEventStream()
            }
        }
    }

    private func startEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = services.streamEvents { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshContainers()
            }
        }
    }

    @MainActor func switchProfile(name: String) async {
        isLoading = true
        do {
            try await services.switchProfile(name: name)
            activeProfile = name
            eventStreamTask?.cancel()
            await refreshAll()
            startEventStream()
            showToast("Switched to profile: \(name)")
        } catch {
            showError("Failed to switch profile: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func startStreamingLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never>? {
        return services.streamLogs(containerId: containerId, handler: handler)
    }

    func startStreamingStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never>? {
        return services.streamStats(containerId: containerId, handler: handler)
    }

    @MainActor func installColima() {
        guard !isInstallingColima else { return }
        isInstallingColima = true
        Task { @MainActor in
            do {
                try await services.installColima()
                colimaInstalled = await services.isColimaInstalled()
                if colimaInstalled { await refreshAll() }
            } catch {
                errorMessage = "Failed to install Colima: \(error.localizedDescription)"
            }
            isInstallingColima = false
        }
    }

    @MainActor func refreshAll() async {
        colimaInstalled = await services.isColimaInstalled()
        guard colimaInstalled else { vmRunning = false; return }
        await refreshContainers()
        await refreshImages()
        await refreshVolumes()
        await refreshNetworks()
        await refreshProfiles()
        await refreshMachines()
        await refreshAIModels()
        do {
            let status = try await services.vmStatus(profile: activeProfile)
            vmRunning = status.running
            if !status.version.isEmpty { colimaVersion = status.version }
            vmCPU = status.cpu
            vmMemory = status.memory
            vmDisk = status.disk
            vmRuntime = status.runtime
            vmArch = status.arch
            vmMountType = status.mountType
            vmType = status.vmType
        } catch {
            vmRunning = false
        }
    }

    // MARK: - Validation

    func validateContainerName(_ name: String) -> String? {
        guard !name.isEmpty else { return "Name is required" }
        guard name.count <= 128 else { return "Name must be 128 characters or fewer" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "Container name must contain only alphanumeric characters, dashes, and underscores"
        }
        return nil
    }

    func validateImageName(_ name: String) -> String? {
        guard !name.isEmpty else { return "Image name is required" }
        let pattern = #"^[a-zA-Z0-9][a-zA-Z0-9._/-]*(:[a-zA-Z0-9._-]+|@sha256:[a-fA-F0-9]{64})?$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            return "Image name must match repo[:tag] or repo@sha256:digest format"
        }
        return nil
    }

    func validateVolumeName(_ name: String) -> String? {
        guard !name.isEmpty else { return "Volume name is required" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "Volume name must contain only alphanumeric characters, dashes, underscores, and dots"
        }
        return nil
    }

    func validateNetworkName(_ name: String) -> String? {
        guard !name.isEmpty else { return "Network name is required" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "Network name must contain only alphanumeric characters, dashes, underscores, and dots"
        }
        return nil
    }

    func validateProfileName(_ name: String) -> String? {
        guard !name.isEmpty else { return "Profile name is required" }
        guard name.count <= 64 else { return "Profile name must be 64 characters or fewer" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return "Profile name must contain only alphanumeric characters, dashes, and underscores"
        }
        return nil
    }

    // MARK: - Toast / Error / Confirmation

    func showToast(_ message: String) {
        toastMessage = message
        isToastVisible = true
        let delay: Double = 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.isToastVisible = false
        }
    }

    func showError(_ message: String) {
        errorMessage = message
        showToast("⚠️ \(message)")
    }

    func requiresVM(_ action: String) -> Bool {
        guard vmRunning else {
            showError("VM is not running. Start Colima before using \(action).")
            return false
        }
        return true
    }

    func requestConfirmation(_ message: String, action: @escaping () -> Void) {
        confirmationMessage = message
        confirmationAction = action
        showConfirmation = true
    }

    // MARK: - Refresh (real services only)

    @MainActor func refreshContainers() async {
        do {
            let raw = try await services.listContainers()
            containers = raw.map { dict in
                MockContainer(
                    id: dict["Id"] as? String ?? "",
                    name: (dict["Names"] as? [String])?.first?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "",
                    image: dict["Image"] as? String ?? "",
                    status: dict["Status"] as? String ?? "",
                    state: dict["State"] as? String ?? "",
                    ports: "",
                    created: ""
                )
            }
        } catch {
            showError("Failed to refresh containers: \(error.localizedDescription)")
        }
    }

    @MainActor func refreshImages() async {
        do {
            let raw = try await services.listImages()
            images = raw.map { dict in
                let repoTags = dict["RepoTags"] as? [String] ?? ["<none>:<none>"]
                let parts = (repoTags.first ?? "<none>:<none>").split(separator: ":", maxSplits: 1)
                return MockImage(
                    id: dict["Id"] as? String ?? "",
                    repository: String(parts.first ?? "<none>"),
                    tag: parts.count > 1 ? String(parts[1]) : "<none>",
                    size: "\((dict["Size"] as? Int64 ?? 0) / 1_000_000)MB",
                    created: ""
                )
            }
        } catch {
            showError("Failed to refresh images: \(error.localizedDescription)")
        }
    }

    @MainActor func refreshVolumes() async {
        do {
            let raw = try await services.listVolumes()
            volumes = raw.map { dict in
                MockVolume(
                    id: dict["Name"] as? String ?? UUID().uuidString,
                    name: dict["Name"] as? String ?? "",
                    driver: dict["Driver"] as? String ?? "local",
                    mountpoint: dict["Mountpoint"] as? String ?? "",
                    size: ""
                )
            }
        } catch {
            showError("Failed to refresh volumes: \(error.localizedDescription)")
        }
    }

    @MainActor func refreshNetworks() async {
        do {
            let raw = try await services.listNetworks()
            networks = raw.map { dict in
                let ipam = dict["IPAM"] as? [String: Any]
                let configs = ipam?["Config"] as? [[String: Any]]
                let subnet = configs?.first?["Subnet"] as? String ?? ""
                return MockNetwork(
                    id: dict["Id"] as? String ?? "",
                    name: dict["Name"] as? String ?? "",
                    driver: dict["Driver"] as? String ?? "",
                    scope: dict["Scope"] as? String ?? "",
                    subnet: subnet
                )
            }
        } catch {
            showError("Failed to refresh networks: \(error.localizedDescription)")
        }
    }

    @MainActor func refreshProfiles() async {
        do {
            let raw = try await services.listProfiles()
            profiles = raw.map { item in
                MockProfile(
                    id: item.name,
                    name: item.name,
                    status: item.status,
                    arch: item.arch,
                    cpus: item.cpus,
                    memory: "\(item.memory / (1024*1024*1024))GiB",
                    disk: "\(item.disk / (1024*1024*1024))GiB",
                    runtime: item.runtime
                )
            }
        } catch {
            showError("Failed to refresh profiles: \(error.localizedDescription)")
        }
    }

    @MainActor func refreshMachines() async {
        do {
            let raw = try await services.listMachines()
            machines = raw.map { m in
                let bytes = { (v: Any?) -> Int in (v as? Int) ?? Int((v as? Int64) ?? 0) }
                return MockVM(
                    id: m["name"] as? String ?? UUID().uuidString,
                    name: m["name"] as? String ?? "",
                    os: MockVM.VMOS(rawValue: (m["os"] as? String ?? "linux")) ?? .linux,
                    status: (m["status"] as? String ?? "").lowercased(),
                    cpus: m["cpus"] as? Int ?? 0,
                    memory: bytes(m["memory"]) / (1024*1024*1024),
                    disk: bytes(m["disk"]) / (1024*1024*1024),
                    arch: m["arch"] as? String ?? ""
                )
            }
        } catch {
            machines = []
        }
    }

    @MainActor func refreshAIModels(runner: String = "docker") async {
        do {
            aiModels = try await services.modelList(runner: runner)
        } catch {
            // Model commands fail if vmType != krunkit — expected
            aiModels = []
        }
    }

    // MARK: - VM Lifecycle

    func startVM() {
        Task { @MainActor in
            do {
                try await services.startVM(profile: activeProfile)
                vmRunning = true
                showToast("Colima VM started")
                await refreshAll()
            } catch { showError(error.localizedDescription) }
        }
    }

    func stopVM() {
        Task { @MainActor in
            do {
                try await services.stopVM(profile: activeProfile, force: false)
                vmRunning = false
                showToast("Colima VM stopped")
            } catch { showError(error.localizedDescription) }
        }
    }

    func restartVM() {
        Task { @MainActor in
            do {
                try await services.restartVM(profile: activeProfile)
                vmRunning = true
                showToast("Colima VM restarted")
                await refreshAll()
            } catch { showError(error.localizedDescription) }
        }
    }

    func deleteVM(hard: Bool) {
        Task { @MainActor in
            do {
                try await services.deleteVM(profile: activeProfile, data: hard)
                vmRunning = false
                if hard { containers = []; images = []; volumes = []; networks = [] }
                showToast(hard ? "Colima VM deleted with all data" : "Colima VM deleted (data preserved)")
            } catch { showError(error.localizedDescription) }
        }
    }

    func sshVM() {
        guard requiresVM("SSH") else { return }
        sheetEntityName = "colima"
        sheetCommand = "colima ssh"
        activeSheet = .terminal
    }

    func showSSHConfig() {
        guard requiresVM("SSH Config") else { return }
        Task { @MainActor in
            do {
                let config = try await services.sshConfig(profile: activeProfile)
                sheetEntityName = "SSH Config"
                sheetContent = config
                activeSheet = .inspect
            } catch { showError(error.localizedDescription) }
        }
    }

    func updateColima() {
        guard requiresVM("Update") else { return }
        Task { @MainActor in
            do {
                try await services.updateVM()
                showToast("Colima updated to latest")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pruneSystem() {
        guard requiresVM("Prune") else { return }
        pruneColima(all: true)
    }

    func pruneColima(all: Bool) {
        guard requiresVM("Prune") else { return }
        Task { @MainActor in
            do {
                try await services.pruneVM(all: all)
                showToast(all ? "All cached data pruned" : "Colima cache pruned")
            } catch { showError(error.localizedDescription) }
        }
    }

    func showVersion() { showToast("Colima version \(colimaVersion)") }
    func generateTemplate() { showToast("Config template generated") }
    func loadTemplate() { showToast("Template loaded") }
    func saveTemplate() { showToast("Template saved") }

    // MARK: - Container actions

    func startContainer(name: String) {
        guard requiresVM("Start Container") else { return }
        Task { @MainActor in
            do {
                try await services.startContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' started")
            } catch { showError(error.localizedDescription) }
        }
    }

    func stopContainer(name: String) {
        guard requiresVM("Stop Container") else { return }
        Task { @MainActor in
            do {
                try await services.stopContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' stopped")
            } catch { showError(error.localizedDescription) }
        }
    }

    func killContainer(name: String) {
        guard requiresVM("Kill Container") else { return }
        Task { @MainActor in
            do {
                try await services.killContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' killed")
            } catch { showError(error.localizedDescription) }
        }
    }

    func restartContainer(name: String) {
        guard requiresVM("Restart Container") else { return }
        Task { @MainActor in
            do {
                try await services.restartContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' restarted")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pauseContainer(name: String) {
        guard requiresVM("Pause Container") else { return }
        Task { @MainActor in
            do {
                try await services.pauseContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' paused")
            } catch { showError(error.localizedDescription) }
        }
    }

    func unpauseContainer(name: String) {
        guard requiresVM("Unpause Container") else { return }
        Task { @MainActor in
            do {
                try await services.unpauseContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' unpaused")
            } catch { showError(error.localizedDescription) }
        }
    }

    func removeContainer(name: String) {
        guard requiresVM("Remove Container") else { return }
        Task { @MainActor in
            do {
                try await services.removeContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' removed")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pruneContainers() {
        guard requiresVM("Prune Containers") else { return }
        Task { @MainActor in
            do {
                try await services.pruneContainers()
                await refreshContainers()
                showToast("Exited containers pruned")
            } catch { showError(error.localizedDescription) }
        }
    }

    func createContainer(name: String, image: String) {
        guard requiresVM("Create Container") else { return }
        if let err = validateContainerName(name) { showError(err); return }
        if let err = validateImageName(image) { showError(err); return }
        Task { @MainActor in
            do {
                _ = try await services.createContainer(name: name, image: image)
                await refreshContainers()
                showToast("Container '\(name)' created")
            } catch { showError(error.localizedDescription) }
        }
    }

    func renameContainer(oldName: String, newName: String) {
        guard requiresVM("Rename Container") else { return }
        if let err = validateContainerName(newName) { showError(err); return }
        Task { @MainActor in
            do {
                try await services.renameContainer(id: oldName, newName: newName)
                await refreshContainers()
                showToast("Container renamed to '\(newName)'")
            } catch { showError(error.localizedDescription) }
        }
    }

    func logsContainer(name: String) {
        guard requiresVM("Logs") else { return }
        Task { @MainActor in
            do {
                let logs = try await services.containerLogs(id: name)
                sheetEntityName = name
                sheetLogs = logs.components(separatedBy: "\n")
                activeSheet = .logs
            } catch { showError(error.localizedDescription) }
        }
    }

    func inspectContainer(name: String) {
        guard requiresVM("Inspect") else { return }
        Task { @MainActor in
            do {
                let json = try await services.inspectContainer(id: name)
                sheetEntityName = name
                sheetContent = json
                activeSheet = .inspect
            } catch { showError(error.localizedDescription) }
        }
    }

    func execContainer(name: String) {
        guard requiresVM("Exec") else { return }
        sheetEntityName = name
        sheetCommand = "docker exec -it \(name) sh"
        activeSheet = .terminal
    }

    func topContainer(name: String) {
        guard requiresVM("Top") else { return }
        sheetEntityName = name
        activeSheet = .stats
    }

    func statsContainer(name: String) {
        guard requiresVM("Stats") else { return }
        sheetEntityName = name
        activeSheet = .stats
    }

    func exportContainer(name: String) {
        guard requiresVM("Export") else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).tar"
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK {
            showToast("Container '\(name)' exported to \(panel.url?.lastPathComponent ?? "")")
        }
    }

    func changesContainer(name: String) {
        guard requiresVM("Changes") else { return }
        sheetEntityName = name
        activeSheet = .changes
    }

    func waitContainer(name: String) { guard requiresVM("Wait") else { return }; showToast("Waiting for container '\(name)' to exit…") }

    func attachContainer(name: String) {
        guard requiresVM("Attach") else { return }
        sheetEntityName = name
        sheetCommand = "docker attach \(name)"
        activeSheet = .terminal
    }

    func updateContainerResources(name: String) { guard requiresVM("Update Resources") else { return }; showToast("Resources updated: \(name)") }
    func copyContainer(name: String) {
        guard requiresVM("Copy") else { return }
        sheetEntityName = name
        activeSheet = .copyFiles
    }

    // MARK: - Image actions

    func pullImage(name: String) {
        guard requiresVM("Pull Image") else { return }
        if let err = validateImageName(name) { showError(err); return }
        Task { @MainActor in
            do {
                try await services.pullImage(name: name)
                await refreshImages()
                showToast("Image '\(name):latest' pulled")
            } catch { showError(error.localizedDescription) }
        }
    }

    func removeImage(id: String) {
        guard requiresVM("Remove Image") else { return }
        Task { @MainActor in
            do {
                try await services.removeImage(id: id)
                await refreshImages()
                showToast("Image '\(id)' removed")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pruneImages() {
        guard requiresVM("Prune Images") else { return }
        Task { @MainActor in
            do {
                try await services.pruneImages()
                await refreshImages()
                showToast("Unused images pruned")
            } catch { showError(error.localizedDescription) }
        }
    }

    func inspectImage(repo: String) {
        guard requiresVM("Inspect Image") else { return }
        Task { @MainActor in
            do {
                let json = try await services.inspectImage(name: repo)
                sheetEntityName = repo
                sheetContent = json
                activeSheet = .inspect
            } catch { showError(error.localizedDescription) }
        }
    }

    func historyImage(repo: String) {
        guard requiresVM("Image History") else { return }
        sheetEntityName = repo
        activeSheet = .history
    }

    func tagImage(repo: String, newTag: String) {
        guard requiresVM("Tag Image") else { return }
        Task { @MainActor in
            do {
                try await services.tagImage(name: repo, repo: repo, tag: newTag)
                showToast("Tagged \(repo) as \(newTag)")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pushImage(repo: String) {
        guard requiresVM("Push Image") else { return }
        Task { @MainActor in
            do {
                try await services.pushImage(name: repo)
                showToast("Push: \(repo)")
            } catch { showError(error.localizedDescription) }
        }
    }

    func exportImage(repo: String) {
        guard requiresVM("Export Image") else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(repo.replacingOccurrences(of: "/", with: "_")).tar"
        panel.allowedContentTypes = [.data]
        if panel.runModal() == .OK {
            showToast("Image '\(repo)' exported to \(panel.url?.lastPathComponent ?? "")")
        }
    }

    func importImage(path: String) {
        guard requiresVM("Import Image") else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let img = MockImage(id: "sha256:\(UUID().uuidString.prefix(6))", repository: url.deletingPathExtension().lastPathComponent, tag: "imported", size: "100MB", created: "just now")
            images.append(img)
            showToast("Image imported from \(url.lastPathComponent)")
        }
    }

    func searchImages(term: String) {
        guard requiresVM("Search Images") else { return }
        sheetSearchTerm = term
        activeSheet = .search
    }

    // MARK: - Volume actions

    func createVolume(name: String) {
        guard requiresVM("Create Volume") else { return }
        if let err = validateVolumeName(name) { showError(err); return }
        Task { @MainActor in
            do {
                try await services.createVolume(name: name)
                await refreshVolumes()
                showToast("Volume '\(name)' created")
            } catch { showError(error.localizedDescription) }
        }
    }

    func removeVolume(name: String) {
        guard requiresVM("Remove Volume") else { return }
        Task { @MainActor in
            do {
                try await services.removeVolume(name: name)
                await refreshVolumes()
                showToast("Volume '\(name)' removed")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pruneVolumes() {
        guard requiresVM("Prune Volumes") else { return }
        Task { @MainActor in
            do {
                try await services.pruneVolumes()
                await refreshVolumes()
                showToast("Unused volumes pruned")
            } catch { showError(error.localizedDescription) }
        }
    }

    func inspectVolume(name: String) {
        guard requiresVM("Inspect Volume") else { return }
        Task { @MainActor in
            do {
                let json = try await services.inspectVolume(name: name)
                sheetEntityName = name
                sheetContent = json
                activeSheet = .inspect
            } catch { showError(error.localizedDescription) }
        }
    }

    // MARK: - Network actions

    func createNetwork(name: String) {
        guard requiresVM("Create Network") else { return }
        if let err = validateNetworkName(name) { showError(err); return }
        Task { @MainActor in
            do {
                try await services.createNetwork(name: name)
                await refreshNetworks()
                showToast("Network '\(name)' created")
            } catch { showError(error.localizedDescription) }
        }
    }

    func removeNetwork(name: String) {
        guard requiresVM("Remove Network") else { return }
        Task { @MainActor in
            do {
                try await services.removeNetwork(name: name)
                await refreshNetworks()
                showToast("Network '\(name)' removed")
            } catch { showError(error.localizedDescription) }
        }
    }

    func pruneNetworks() {
        guard requiresVM("Prune Networks") else { return }
        Task { @MainActor in
            do {
                try await services.pruneNetworks()
                await refreshNetworks()
                showToast("Unused networks pruned")
            } catch { showError(error.localizedDescription) }
        }
    }

    func inspectNetwork(name: String) {
        guard requiresVM("Inspect Network") else { return }
        Task { @MainActor in
            do {
                let json = try await services.inspectNetwork(id: name)
                sheetEntityName = name
                sheetContent = json
                activeSheet = .inspect
            } catch { showError(error.localizedDescription) }
        }
    }

    func connectNetwork(network: String, container: String) {
        guard requiresVM("Connect Network") else { return }
        Task { @MainActor in
            do {
                try await services.connectNetwork(networkId: network, containerId: container)
                showToast("Connected \(container) to \(network)")
            } catch { showError(error.localizedDescription) }
        }
    }

    func disconnectNetwork(network: String, container: String) {
        guard requiresVM("Disconnect Network") else { return }
        Task { @MainActor in
            do {
                try await services.disconnectNetwork(networkId: network, containerId: container)
                showToast("Disconnected \(container) from \(network)")
            } catch { showError(error.localizedDescription) }
        }
    }

    // MARK: - Profile actions

    func startProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.startVM(profile: name)
                await refreshProfiles()
                showToast("Profile '\(name)' started")
            } catch { showError(error.localizedDescription) }
        }
    }

    func stopProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.stopVM(profile: name, force: false)
                await refreshProfiles()
                showToast("Profile '\(name)' stopped")
            } catch { showError(error.localizedDescription) }
        }
    }

    func restartProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.restartVM(profile: name)
                await refreshProfiles()
                showToast("Profile '\(name)' restarted")
            } catch { showError(error.localizedDescription) }
        }
    }

    func deleteProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.deleteProfile(name: name, data: true)
                await refreshProfiles()
                showToast("Profile '\(name)' deleted")
            } catch { showError(error.localizedDescription) }
        }
    }

    func createProfile(name: String, cpus: Int, memory: String, runtime: String) {
        if let err = validateProfileName(name) { showError(err); return }
        Task { @MainActor in
            do {
                let memGB = Int(memory.replacingOccurrences(of: "GiB", with: "")) ?? 4
                let config = ColimaStartConfig(cpus: cpus, memory: memGB, runtime: runtime)
                try await services.createProfile(name: name, config: config)
                await refreshProfiles()
                showToast("Profile '\(name)' created")
            } catch { showError(error.localizedDescription) }
        }
    }

    func cloneProfile(source: String, dest: String) {
        if let err = validateProfileName(dest) { showError(err); return }
        Task { @MainActor in
            do {
                try await services.cloneProfile(source: source, dest: dest)
                await refreshProfiles()
                showToast("Profile '\(source)' cloned to '\(dest)'")
            } catch { showError(error.localizedDescription) }
        }
    }

    func switchProfile(name: String) { activeProfile = name; showToast("Switched to profile '\(name)'") }

    // MARK: - Kubernetes actions

    func enableKubernetes() {
        guard requiresVM("Kubernetes") else { return }
        Task { @MainActor in
            do {
                try await services.k8sStart(profile: activeProfile)
                k8sRunning = true
                showToast("Kubernetes enabled")
            } catch { showError(error.localizedDescription) }
        }
    }

    func disableKubernetes() {
        guard requiresVM("Kubernetes") else { return }
        Task { @MainActor in
            do {
                try await services.k8sStop(profile: activeProfile)
                k8sRunning = false
                showToast("Kubernetes disabled")
            } catch { showError(error.localizedDescription) }
        }
    }

    func resetKubernetes() {
        guard requiresVM("Kubernetes") else { return }
        Task { @MainActor in
            do {
                try await services.k8sReset(profile: activeProfile)
                k8sRunning = false
                showToast("Kubernetes reset")
            } catch { showError(error.localizedDescription) }
        }
    }

    // MARK: - Config

    func loadConfiguration() {
        Task { @MainActor in
            do {
                colimaConfig = try await services.readConfig(profile: activeProfile)
            } catch {
                showError("Failed to load config: \(error.localizedDescription)")
            }
        }
    }

    func saveConfig(config: ColimaConfig) {
        Task { @MainActor in
            do {
                try await services.writeConfig(profile: activeProfile, config: config)
                colimaConfig = config
                // Restart to apply changes
                if vmRunning {
                    try await services.restartVM(profile: activeProfile)
                    showToast("Configuration saved and VM restarted")
                } else {
                    showToast("Configuration saved")
                }
            } catch {
                showError("Failed to save config: \(error.localizedDescription)")
            }
        }
    }

    func saveConfig() { showToast("Use Save Configuration button in the config view") }

    func resetConfig() {
        colimaConfig = ColimaConfig()
        showToast("Configuration reset to defaults")
    }

    func editYAML() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.colima/\(activeProfile)/colima.yaml"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Runtime Controls

    func executeCommand(tool: String, args: [String], completion: @escaping (String) -> Void) {
        Task {
            do {
                let output = try await services.executeCommand(tool: tool, args: args)
                await MainActor.run { completion(output) }
            } catch {
                await MainActor.run { completion("Error: \(error.localizedDescription)") }
            }
        }
    }

    func switchDockerContext(profile: String) { guard requiresVM("Docker Context") else { return }; showToast("Docker context: colima-\(profile)") }

    func nerdctlCommand(cmd: String) {
        guard requiresVM("nerdctl") else { return }
        sheetTool = "nerdctl"
        activeSheet = .commandRunner
    }

    func incusCommand(cmd: String) {
        guard requiresVM("incus") else { return }
        sheetTool = "incus"
        activeSheet = .commandRunner
    }

    func switchRuntime(to runtime: String) { showToast("Runtime switching to \(runtime) (requires restart)") }
    func updateRuntime() { guard requiresVM("Update Runtime") else { return }; showToast("Runtime updated") }
}

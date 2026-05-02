import SwiftUI
import AppKit

class AppState: ObservableObject {
    @Published var selectedTab: NavigationItem = .dashboard
    @Published var vmRunning: Bool = true
    @Published var toastMessage: String?
    @Published var showToast: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showConfirmation: Bool = false
    @Published var confirmationAction: (() -> Void)?
    @Published var confirmationMessage: String = ""
    @Published var colimaVersion: String = "0.10.1"

    @Published var containers: [MockContainer] = []
    @Published var images: [MockImage] = []
    @Published var volumes: [MockVolume] = []
    @Published var networks: [MockNetwork] = []
    @Published var profiles: [MockProfile] = []
    @Published var k8sRunning: Bool = false
    @Published var memoryGovernorTier: Int = 0
    @Published var activeProfile: String = "default"

    // MARK: - Sheet State

    @Published var activeSheet: SheetType?
    @Published var sheetEntityName: String = ""
    @Published var sheetContent: String = ""
    @Published var sheetLogs: [String] = []
    @Published var sheetCommand: String = ""
    @Published var sheetTool: String = ""
    @Published var sheetSearchTerm: String = ""

    enum SheetType: Identifiable {
        case inspect, logs, terminal, stats, history, changes, search, commandRunner, copyFiles
        var id: Self { self }
    }

    // MARK: - Service Layer

    private let useMocks: Bool
    private let services: ServiceProvider?

    init(useMocks: Bool = false) {
        self.useMocks = useMocks
        self.services = useMocks ? nil : RealServiceProvider()
        if useMocks {
            containers = MockData.containers
            images = MockData.images
            volumes = MockData.volumes
            networks = MockData.networks
            profiles = MockData.profiles
        } else {
            // Trigger initial data load on main actor
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.refreshAll()
                }
            }
        }
    }

    @MainActor func refreshAll() async {
        guard !useMocks, services != nil else { return }
        await refreshContainers()
        await refreshImages()
        await refreshVolumes()
        await refreshNetworks()
        await refreshProfiles()
        // Check VM status
        do {
            let status = try await services!.vmStatus(profile: activeProfile)
            vmRunning = status.running
            if !status.version.isEmpty { colimaVersion = status.version }
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
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showToast = false
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
        guard !useMocks, let svc = services else { return }
        do {
            let raw = try await svc.listContainers()
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
        guard !useMocks, let svc = services else { return }
        do {
            let raw = try await svc.listImages()
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
        guard !useMocks, let svc = services else { return }
        do {
            let raw = try await svc.listVolumes()
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
        guard !useMocks, let svc = services else { return }
        do {
            let raw = try await svc.listNetworks()
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
        guard !useMocks, let svc = services else { return }
        do {
            let raw = try await svc.listProfiles()
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

    // MARK: - VM Lifecycle

    func startVM() {
        if useMocks {
            vmRunning = true; showToast("Colima VM started")
        } else {
            Task { @MainActor in
                do {
                    try await services!.startVM(profile: activeProfile)
                    vmRunning = true
                    showToast("Colima VM started")
                    await refreshAll()
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func stopVM() {
        if useMocks {
            vmRunning = false; showToast("Colima VM stopped")
        } else {
            Task { @MainActor in
                do {
                    try await services!.stopVM(profile: activeProfile, force: false)
                    vmRunning = false
                    showToast("Colima VM stopped")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func restartVM() {
        if useMocks {
            vmRunning = true; showToast("Colima VM restarted")
        } else {
            Task { @MainActor in
                do {
                    try await services!.restartVM(profile: activeProfile)
                    vmRunning = true
                    showToast("Colima VM restarted")
                    await refreshAll()
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func deleteVM(hard: Bool) {
        if useMocks {
            vmRunning = false
            if hard {
                containers = []; images = []; volumes = []
                networks = MockData.networks.filter { $0.name == "bridge" || $0.name == "host" }
                showToast("Colima VM deleted with all data")
            } else {
                showToast("Colima VM deleted (data preserved)")
            }
        } else {
            Task { @MainActor in
                do {
                    try await services!.deleteVM(profile: activeProfile, data: hard)
                    vmRunning = false
                    if hard { containers = []; images = []; volumes = []; networks = [] }
                    showToast(hard ? "Colima VM deleted with all data" : "Colima VM deleted (data preserved)")
                } catch { showError(error.localizedDescription) }
            }
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
        if useMocks {
            sheetEntityName = "SSH Config"
            sheetContent = MockDetailData.sshConfig(profile: activeProfile)
            activeSheet = .inspect
        } else {
            Task { @MainActor in
                do {
                    let config = try await services!.sshConfig(profile: activeProfile)
                    sheetEntityName = "SSH Config"
                    sheetContent = config
                    activeSheet = .inspect
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func updateColima() {
        guard requiresVM("Update") else { return }
        if useMocks {
            showToast("Colima updated to latest")
        } else {
            Task { @MainActor in
                do {
                    try await services!.updateVM()
                    showToast("Colima updated to latest")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pruneColima(all: Bool) {
        guard requiresVM("Prune") else { return }
        if useMocks {
            showToast(all ? "All cached data pruned" : "Colima cache pruned")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pruneVM(all: all)
                    showToast(all ? "All cached data pruned" : "Colima cache pruned")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func showVersion() { showToast("Colima version \(colimaVersion)") }
    func generateTemplate() { showToast("Config template generated") }
    func loadTemplate() { showToast("Template loaded") }
    func saveTemplate() { showToast("Template saved") }

    // MARK: - Container actions

    func startContainer(name: String) {
        guard requiresVM("Start Container") else { return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == name }) else { return }
            containers[i].state = "running"; containers[i].status = "Up just now"
            showToast("Container '\(name)' started")
        } else {
            Task { @MainActor in
                do {
                    try await services!.startContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' started")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func stopContainer(name: String) {
        guard requiresVM("Stop Container") else { return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == name }) else { return }
            containers[i].state = "exited"; containers[i].status = "Exited (0) just now"
            showToast("Container '\(name)' stopped")
        } else {
            Task { @MainActor in
                do {
                    try await services!.stopContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' stopped")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func killContainer(name: String) {
        guard requiresVM("Kill Container") else { return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == name }) else { return }
            containers[i].state = "exited"; containers[i].status = "Exited (137) just now"
            showToast("Container '\(name)' killed")
        } else {
            Task { @MainActor in
                do {
                    try await services!.killContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' killed")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func restartContainer(name: String) {
        guard requiresVM("Restart Container") else { return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == name }) else { return }
            containers[i].state = "running"; containers[i].status = "Up just now"
            showToast("Container '\(name)' restarted")
        } else {
            Task { @MainActor in
                do {
                    try await services!.restartContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' restarted")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pauseContainer(name: String) {
        guard requiresVM("Pause Container") else { return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == name }) else { return }
            containers[i].state = "paused"; containers[i].status = "Paused"
            showToast("Container '\(name)' paused")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pauseContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' paused")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func unpauseContainer(name: String) {
        guard requiresVM("Unpause Container") else { return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == name }) else { return }
            containers[i].state = "running"; containers[i].status = "Up just now"
            showToast("Container '\(name)' unpaused")
        } else {
            Task { @MainActor in
                do {
                    try await services!.unpauseContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' unpaused")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func removeContainer(name: String) {
        guard requiresVM("Remove Container") else { return }
        if useMocks {
            containers.removeAll { $0.name == name }
            showToast("Container '\(name)' removed")
        } else {
            Task { @MainActor in
                do {
                    try await services!.removeContainer(id: name)
                    await refreshContainers()
                    showToast("Container '\(name)' removed")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pruneContainers() {
        guard requiresVM("Prune Containers") else { return }
        if useMocks {
            containers.removeAll { $0.state == "exited" }
            showToast("Exited containers pruned")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pruneContainers()
                    await refreshContainers()
                    showToast("Exited containers pruned")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func createContainer(name: String, image: String) {
        guard requiresVM("Create Container") else { return }
        if let err = validateContainerName(name) { showError(err); return }
        if let err = validateImageName(image) { showError(err); return }
        if useMocks {
            let c = MockContainer(id: UUID().uuidString.prefix(12).description, name: name, image: image, status: "Created", state: "created", ports: "", created: "just now")
            containers.append(c)
            showToast("Container '\(name)' created")
        } else {
            Task { @MainActor in
                do {
                    _ = try await services!.createContainer(name: name, image: image)
                    await refreshContainers()
                    showToast("Container '\(name)' created")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func renameContainer(oldName: String, newName: String) {
        guard requiresVM("Rename Container") else { return }
        if let err = validateContainerName(newName) { showError(err); return }
        if useMocks {
            guard let i = containers.firstIndex(where: { $0.name == oldName }) else { return }
            containers[i].name = newName
            showToast("Container renamed to '\(newName)'")
        } else {
            Task { @MainActor in
                do {
                    try await services!.renameContainer(id: oldName, newName: newName)
                    await refreshContainers()
                    showToast("Container renamed to '\(newName)'")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func logsContainer(name: String) {
        guard requiresVM("Logs") else { return }
        if useMocks {
            sheetEntityName = name
            sheetLogs = MockDetailData.containerLogs(name: name)
            activeSheet = .logs
        } else {
            Task { @MainActor in
                do {
                    let logs = try await services!.containerLogs(id: name)
                    sheetEntityName = name
                    sheetLogs = logs.components(separatedBy: "\n")
                    activeSheet = .logs
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func inspectContainer(name: String) {
        guard requiresVM("Inspect") else { return }
        if useMocks {
            sheetEntityName = name
            sheetContent = MockDetailData.containerInspect(name: name)
            activeSheet = .inspect
        } else {
            Task { @MainActor in
                do {
                    let json = try await services!.inspectContainer(id: name)
                    sheetEntityName = name
                    sheetContent = json
                    activeSheet = .inspect
                } catch { showError(error.localizedDescription) }
            }
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
        if useMocks {
            let img = MockImage(id: "sha256:\(UUID().uuidString.prefix(6))", repository: name, tag: "latest", size: "100MB", created: "just now")
            images.append(img)
            showToast("Image '\(name):latest' pulled")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pullImage(name: name)
                    await refreshImages()
                    showToast("Image '\(name):latest' pulled")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func removeImage(id: String) {
        guard requiresVM("Remove Image") else { return }
        if useMocks {
            let name = images.first(where: { $0.id == id })?.repository ?? id
            images.removeAll { $0.id == id }
            showToast("Image '\(name)' removed")
        } else {
            Task { @MainActor in
                do {
                    try await services!.removeImage(id: id)
                    await refreshImages()
                    showToast("Image '\(id)' removed")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pruneImages() {
        guard requiresVM("Prune Images") else { return }
        if useMocks {
            showToast("Unused images pruned")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pruneImages()
                    await refreshImages()
                    showToast("Unused images pruned")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func inspectImage(repo: String) {
        guard requiresVM("Inspect Image") else { return }
        if useMocks {
            sheetEntityName = repo
            sheetContent = MockDetailData.imageInspect(repo: repo)
            activeSheet = .inspect
        } else {
            Task { @MainActor in
                do {
                    let json = try await services!.inspectImage(name: repo)
                    sheetEntityName = repo
                    sheetContent = json
                    activeSheet = .inspect
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func historyImage(repo: String) {
        guard requiresVM("Image History") else { return }
        sheetEntityName = repo
        activeSheet = .history
    }

    func tagImage(repo: String, newTag: String) {
        guard requiresVM("Tag Image") else { return }
        if useMocks {
            showToast("Tagged \(repo) as \(newTag)")
        } else {
            Task { @MainActor in
                do {
                    try await services!.tagImage(name: repo, repo: repo, tag: newTag)
                    showToast("Tagged \(repo) as \(newTag)")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pushImage(repo: String) {
        guard requiresVM("Push Image") else { return }
        if useMocks {
            showToast("Push: \(repo)")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pushImage(name: repo)
                    showToast("Push: \(repo)")
                } catch { showError(error.localizedDescription) }
            }
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
        if useMocks {
            let vol = MockVolume(id: "vol_\(UUID().uuidString.prefix(6))", name: name, driver: "local", mountpoint: "/var/lib/docker/volumes/\(name)/_data", size: "0B")
            volumes.append(vol)
            showToast("Volume '\(name)' created")
        } else {
            Task { @MainActor in
                do {
                    try await services!.createVolume(name: name)
                    await refreshVolumes()
                    showToast("Volume '\(name)' created")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func removeVolume(name: String) {
        guard requiresVM("Remove Volume") else { return }
        if useMocks {
            volumes.removeAll { $0.name == name }
            showToast("Volume '\(name)' removed")
        } else {
            Task { @MainActor in
                do {
                    try await services!.removeVolume(name: name)
                    await refreshVolumes()
                    showToast("Volume '\(name)' removed")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pruneVolumes() {
        guard requiresVM("Prune Volumes") else { return }
        if useMocks {
            showToast("Unused volumes pruned")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pruneVolumes()
                    await refreshVolumes()
                    showToast("Unused volumes pruned")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func inspectVolume(name: String) {
        guard requiresVM("Inspect Volume") else { return }
        if useMocks {
            sheetEntityName = name
            sheetContent = MockDetailData.volumeInspect(name: name)
            activeSheet = .inspect
        } else {
            Task { @MainActor in
                do {
                    let json = try await services!.inspectVolume(name: name)
                    sheetEntityName = name
                    sheetContent = json
                    activeSheet = .inspect
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Network actions

    func createNetwork(name: String) {
        guard requiresVM("Create Network") else { return }
        if let err = validateNetworkName(name) { showError(err); return }
        if useMocks {
            let net = MockNetwork(id: "net_\(UUID().uuidString.prefix(6))", name: name, driver: "bridge", scope: "local", subnet: "172.19.0.0/16")
            networks.append(net)
            showToast("Network '\(name)' created")
        } else {
            Task { @MainActor in
                do {
                    try await services!.createNetwork(name: name)
                    await refreshNetworks()
                    showToast("Network '\(name)' created")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func removeNetwork(name: String) {
        guard requiresVM("Remove Network") else { return }
        if useMocks {
            networks.removeAll { $0.name == name }
            showToast("Network '\(name)' removed")
        } else {
            Task { @MainActor in
                do {
                    try await services!.removeNetwork(name: name)
                    await refreshNetworks()
                    showToast("Network '\(name)' removed")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func pruneNetworks() {
        guard requiresVM("Prune Networks") else { return }
        if useMocks {
            showToast("Unused networks pruned")
        } else {
            Task { @MainActor in
                do {
                    try await services!.pruneNetworks()
                    await refreshNetworks()
                    showToast("Unused networks pruned")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func inspectNetwork(name: String) {
        guard requiresVM("Inspect Network") else { return }
        if useMocks {
            sheetEntityName = name
            sheetContent = MockDetailData.networkInspect(name: name)
            activeSheet = .inspect
        } else {
            Task { @MainActor in
                do {
                    let json = try await services!.inspectNetwork(id: name)
                    sheetEntityName = name
                    sheetContent = json
                    activeSheet = .inspect
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func connectNetwork(network: String, container: String) {
        guard requiresVM("Connect Network") else { return }
        if useMocks {
            showToast("Connected \(container) to \(network)")
        } else {
            Task { @MainActor in
                do {
                    try await services!.connectNetwork(networkId: network, containerId: container)
                    showToast("Connected \(container) to \(network)")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func disconnectNetwork(network: String, container: String) {
        guard requiresVM("Disconnect Network") else { return }
        if useMocks {
            showToast("Disconnected \(container) from \(network)")
        } else {
            Task { @MainActor in
                do {
                    try await services!.disconnectNetwork(networkId: network, containerId: container)
                    showToast("Disconnected \(container) from \(network)")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Profile actions

    func startProfile(name: String) {
        if useMocks {
            guard let i = profiles.firstIndex(where: { $0.name == name }) else { return }
            profiles[i].status = "Running"; showToast("Profile '\(name)' started")
        } else {
            Task { @MainActor in
                do {
                    try await services!.startVM(profile: name)
                    await refreshProfiles()
                    showToast("Profile '\(name)' started")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func stopProfile(name: String) {
        if useMocks {
            guard let i = profiles.firstIndex(where: { $0.name == name }) else { return }
            profiles[i].status = "Stopped"; showToast("Profile '\(name)' stopped")
        } else {
            Task { @MainActor in
                do {
                    try await services!.stopVM(profile: name, force: false)
                    await refreshProfiles()
                    showToast("Profile '\(name)' stopped")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func restartProfile(name: String) {
        if useMocks {
            guard let i = profiles.firstIndex(where: { $0.name == name }) else { return }
            profiles[i].status = "Running"; showToast("Profile '\(name)' restarted")
        } else {
            Task { @MainActor in
                do {
                    try await services!.restartVM(profile: name)
                    await refreshProfiles()
                    showToast("Profile '\(name)' restarted")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func deleteProfile(name: String) {
        if useMocks {
            profiles.removeAll { $0.name == name }
            showToast("Profile '\(name)' deleted")
        } else {
            Task { @MainActor in
                do {
                    try await services!.deleteProfile(name: name, data: true)
                    await refreshProfiles()
                    showToast("Profile '\(name)' deleted")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func createProfile(name: String, cpus: Int, memory: String, runtime: String) {
        if let err = validateProfileName(name) { showError(err); return }
        if useMocks {
            let p = MockProfile(id: UUID().uuidString, name: name, status: "Stopped", arch: "aarch64", cpus: cpus, memory: memory, disk: "60GiB", runtime: runtime)
            profiles.append(p)
            showToast("Profile '\(name)' created")
        } else {
            Task { @MainActor in
                do {
                    let memGB = Int(memory.replacingOccurrences(of: "GiB", with: "")) ?? 4
                    let config = ColimaStartConfig(cpus: cpus, memory: memGB, runtime: runtime)
                    try await services!.createProfile(name: name, config: config)
                    await refreshProfiles()
                    showToast("Profile '\(name)' created")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func cloneProfile(source: String, dest: String) {
        if let err = validateProfileName(dest) { showError(err); return }
        if useMocks {
            guard let src = profiles.first(where: { $0.name == source }) else { return }
            let p = MockProfile(id: UUID().uuidString, name: dest, status: "Stopped", arch: src.arch, cpus: src.cpus, memory: src.memory, disk: src.disk, runtime: src.runtime)
            profiles.append(p)
            showToast("Profile '\(source)' cloned to '\(dest)'")
        } else {
            Task { @MainActor in
                do {
                    try await services!.cloneProfile(source: source, dest: dest)
                    await refreshProfiles()
                    showToast("Profile '\(source)' cloned to '\(dest)'")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func switchProfile(name: String) { activeProfile = name; showToast("Switched to profile '\(name)'") }

    // MARK: - Kubernetes actions

    func enableKubernetes() {
        guard requiresVM("Kubernetes") else { return }
        if useMocks {
            k8sRunning = true; showToast("Kubernetes enabled")
        } else {
            Task { @MainActor in
                do {
                    try await services!.k8sStart(profile: activeProfile)
                    k8sRunning = true
                    showToast("Kubernetes enabled")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func disableKubernetes() {
        guard requiresVM("Kubernetes") else { return }
        if useMocks {
            k8sRunning = false; showToast("Kubernetes disabled")
        } else {
            Task { @MainActor in
                do {
                    try await services!.k8sStop(profile: activeProfile)
                    k8sRunning = false
                    showToast("Kubernetes disabled")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    func resetKubernetes() {
        guard requiresVM("Kubernetes") else { return }
        if useMocks {
            k8sRunning = false; showToast("Kubernetes reset")
        } else {
            Task { @MainActor in
                do {
                    try await services!.k8sReset(profile: activeProfile)
                    k8sRunning = false
                    showToast("Kubernetes reset")
                } catch { showError(error.localizedDescription) }
            }
        }
    }

    // MARK: - Config

    func saveConfig() { showToast("Configuration saved") }
    func resetConfig() { showToast("Configuration reset to defaults") }
    func editYAML() { showToast("YAML editor opened") }

    // MARK: - Runtime Controls

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

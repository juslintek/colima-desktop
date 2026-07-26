import SwiftUI
import AppKit

class AppState: ObservableObject {
    @Published var selectedTab: NavigationItem = .dashboard
    // Production starts in an honest loading/stopped state. The first refresh
    // selects a real profile and applies its status before exposing resources.
    @Published var vmRunning: Bool = false
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

    // MARK: - Dependency management (Requirement 10 / DependencyManager)

    /// Live per-tool dependency classification for `colima`, `lima`, `qemu`,
    /// `krunkit`, `docker-cli`, and `kubectl`. Populated by `checkDependencies()`
    /// from the REAL host state (never hardcoded) — Requirement 10.1 / Property 20.
    @Published var dependencyStatuses: [DependencyStatus] = []
    /// Tools with an install currently in flight (drives per-row busy state).
    @Published var installingTools: Set<DependencyTool> = []

    /// The macOS DependencyManager: real host detection + install-path offers.
    let dependencyManager = DependencyManager()

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
    @Published var imagePullStatus: [String: String] = [:]
    /// OBSERVED per-image pull progress, updated live from the Docker Engine
    /// pull stream (per-layer progressDetail). Keyed by image name.
    @Published var imagePullProgress: [String: ImagePullProgress] = [:]

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
        case inspect, logs, terminal, stats, history, changes, search, commandRunner, copyFiles, createContainer, templateEditor
        var id: Self { self }
    }

    // MARK: - Template editor state (GetTemplate / SetTemplate)

    /// Editable YAML text shown in the template editor sheet.
    @Published var templateYAML: String = ""
    /// The profile whose template is currently loaded in the editor.
    @Published var templateProfile: String = "default"
    /// Validation feedback for the current `templateYAML` (empty when valid).
    @Published var templateValidationMessage: String = ""
    /// True while the template is being read from or written to disk.
    @Published var isTemplateLoading: Bool = false

    // MARK: - Service Layer

    let services: ServiceProvider
    private var eventStreamTask: Task<Void, Never>?
    private var profileStreamTasks: [Task<Void, Never>] = []
    private var imagePullTasks: [String: Task<Void, Never>] = [:]
    private var didInitializeProfileContext = false

    init(services: ServiceProvider = RealServiceProvider()) {
        self.services = services
        // Mock mode intentionally represents a running sample VM. Production
        // providers remain stopped/loading until their first real status read.
        if services is MockServiceProvider { vmRunning = true }
        // Deterministic deep-link for screenshots/testing: `--open-tab <name>`.
        if let i = CommandLine.arguments.firstIndex(of: "--open-tab"),
           i + 1 < CommandLine.arguments.count,
           let tab = NavigationItem(rawValue: CommandLine.arguments[i + 1]) {
            selectedTab = tab
        }
        // Skip real backend calls when running as a test host.
        // Detection: XCTestConfigurationFilePath is set by xcodebuild test.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
            || CommandLine.arguments.contains("--backend-mock") {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshAll()
            }
        }
    }

    @MainActor
    private func startEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
        guard vmRunning else { return }
        let profile = activeProfile
        eventStreamTask = services.streamEvents { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // A cancelled socket stream can still deliver a buffered event.
                // Never let an event from the previous profile refresh the new one.
                guard self.activeProfile == profile, self.vmRunning else { return }
                await self.refreshContainers()
            }
        }
    }

    @MainActor func switchProfile(name: String) async {
        guard name != activeProfile else { return }
        guard !isLoading else { return }
        guard profiles.contains(where: { $0.name == name }) else {
            showError("Profile '\(name)' no longer exists. Refresh the profile list and try again.")
            return
        }

        let previousProfile = activeProfile
        isLoading = true
        cancelProfileStreams()
        do {
            // This is a context rebind only. It must never stop or start a VM.
            try await services.switchProfile(name: name)
            activeProfile = name
            didInitializeProfileContext = true
            guard await refreshAll() else {
                try await services.switchProfile(name: previousProfile)
                activeProfile = previousProfile
                didInitializeProfileContext = true
                _ = await refreshAll()
                showError("Failed to refresh profile '\(name)'; kept '\(previousProfile)' selected.")
                isLoading = false
                return
            }
            showToast("Switched to profile: \(name)")
        } catch {
            // The visible selection changes only after the provider rebinds.
            // Best-effort restore keeps service and UI context aligned.
            try? await services.switchProfile(name: previousProfile)
            activeProfile = previousProfile
            didInitializeProfileContext = true
            _ = await refreshAll()
            showError("Failed to switch profile: \(error.localizedDescription)")
        }
        isLoading = false
    }

    @MainActor func startStreamingLogs(containerId: String, handler: @escaping (String) -> Void) -> Task<Void, Never>? {
        guard vmRunning, let task = services.streamLogs(containerId: containerId, handler: handler) else { return nil }
        profileStreamTasks.append(task)
        return task
    }

    @MainActor func startStreamingStats(containerId: String, handler: @escaping (ContainerStats) -> Void) -> Task<Void, Never>? {
        guard vmRunning, let task = services.streamStats(containerId: containerId, handler: handler) else { return nil }
        profileStreamTasks.append(task)
        return task
    }

    @MainActor private func cancelProfileStreams() {
        eventStreamTask?.cancel()
        eventStreamTask = nil
        profileStreamTasks.forEach { $0.cancel() }
        profileStreamTasks.removeAll()
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

    /// Run the live dependency checks off the main actor and publish the
    /// per-tool statuses. Reflects the REAL host state (Requirement 10.1); safe
    /// to call repeatedly (e.g. a "Re-check" button on the onboarding screen).
    @MainActor func checkDependencies() async {
        let manager = dependencyManager
        dependencyStatuses = await Task.detached(priority: .utility) { manager.checkAll() }.value
    }

    /// Offer and perform an install for a single tracked tool (Requirement 10.2).
    /// The install runs off the main actor; cancellation, offline, and
    /// permission-denied outcomes are surfaced with remediation context
    /// (Requirements 10.3–10.5), and dependencies are re-checked on success.
    @MainActor func installDependency(_ tool: DependencyTool) {
        guard !installingTools.contains(tool) else { return }
        installingTools.insert(tool)
        let manager = dependencyManager
        Task { @MainActor in
            let outcome = await Task.detached(priority: .utility) { await manager.install(tool) }.value
            switch outcome {
            case .installed:
                showToast("\(tool.displayName) installed")
                await checkDependencies()
                colimaInstalled = await services.isColimaInstalled()
                if colimaInstalled { await refreshAll() }
            case .cancelled(let message),
                 .offline(let message),
                 .permissionDenied(let message),
                 .failed(let message):
                showError(message)
            }
            installingTools.remove(tool)
        }
    }

    @discardableResult
    @MainActor func refreshAll() async -> Bool {
        colimaInstalled = await services.isColimaInstalled()
        guard colimaInstalled else {
            cancelProfileStreams()
            profiles = []
            clearProfileResources()
            applyStoppedStatus()
            return false
        }

        // Profile inventory and active VM status are authoritative. Never touch
        // a Docker socket until the service has rebound to a known profile and
        // that profile has been confirmed running.
        let listedProfiles: [ProfileListItem]
        do {
            listedProfiles = try await services.listProfiles()
            applyProfiles(listedProfiles)
        } catch {
            cancelProfileStreams()
            profiles = []
            clearProfileResources()
            applyStoppedStatus()
            showError("Failed to refresh profiles: \(error.localizedDescription)")
            return false
        }

        if !didInitializeProfileContext || !listedProfiles.contains(where: { $0.name == activeProfile }) {
            let target = preferredInitialProfile(from: listedProfiles) ?? activeProfile
            do {
                cancelProfileStreams()
                try await services.switchProfile(name: target)
                activeProfile = target
                didInitializeProfileContext = true
            } catch {
                clearProfileResources()
                applyStoppedStatus()
                showError("Failed to select profile '\(target)': \(error.localizedDescription)")
                return false
            }
        }

        let status: VMStatusInfo
        do {
            status = try await services.vmStatus(profile: activeProfile)
        } catch {
            cancelProfileStreams()
            clearProfileResources()
            applyStoppedStatus()
            await refreshMachines()
            return false
        }

        applyStatus(status)
        await refreshMachines()

        guard status.running else {
            cancelProfileStreams()
            clearProfileResources()
            return true
        }

        await refreshContainers()
        await refreshImages()
        await refreshVolumes()
        await refreshNetworks()
        await refreshAIModels()
        startEventStream()
        return true
    }

    @MainActor private func preferredInitialProfile(from listedProfiles: [ProfileListItem]) -> String? {
        guard !listedProfiles.isEmpty else { return nil }
        let names = Set(listedProfiles.map(\.name))
        let environment = ProcessInfo.processInfo.environment

        let argumentProfile: String? = {
            if let index = CommandLine.arguments.firstIndex(of: "--profile"), index + 1 < CommandLine.arguments.count {
                return CommandLine.arguments[index + 1]
            }
            return CommandLine.arguments
                .first(where: { $0.hasPrefix("--profile=") })
                .map { String($0.dropFirst("--profile=".count)) }
        }()

        if let requested = argumentProfile, names.contains(requested) { return requested }
        if let requested = environment["COLIMA_DESKTOP_PROFILE"], names.contains(requested) { return requested }
        if let requested = environment["COLIMA_DESKTOP_TEST_PROFILE"],
           requested != "default",
           requested.localizedCaseInsensitiveContains("e2e"),
           names.contains(requested) {
            return requested
        }

        let running = listedProfiles
            .filter { $0.status.localizedCaseInsensitiveContains("running") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if running.contains(where: { $0.name == "default" }) { return "default" }
        if let firstRunning = running.first { return firstRunning.name }
        if names.contains("default") { return "default" }
        return listedProfiles.map(\.name).sorted().first
    }

    @MainActor private func applyProfiles(_ raw: [ProfileListItem]) {
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
    }

    @MainActor private func applyStatus(_ status: VMStatusInfo) {
        vmRunning = status.running
        if !status.version.isEmpty { colimaVersion = status.version }
        vmCPU = status.cpu
        vmMemory = status.memory
        vmDisk = status.disk
        vmRuntime = status.runtime
        vmArch = status.arch
        vmMountType = status.mountType
        vmType = status.vmType
    }

    @MainActor private func applyStoppedStatus() {
        vmRunning = false
        vmCPU = 0
        vmMemory = 0
        vmDisk = 0
        vmRuntime = ""
        vmArch = ""
        vmMountType = ""
        vmType = ""
    }

    @MainActor private func clearProfileResources() {
        containers = []
        images = []
        volumes = []
        networks = []
        aiModels = []
        k8sRunning = false
        selectedContainerName = nil
        selectedImageId = nil
        selectedVolumeName = nil
        selectedNetworkName = nil
        selectedPodName = nil
        selectedK8sService = nil
        selectedK8sDeployment = nil
        selectedK8sNode = nil
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

    /// Invoke the armed confirmation action (the user confirmed) and clear the
    /// pending confirmation state. This is the single place where a destructive
    /// mutation's RPC is actually issued. Mirrors the confirmation dialog's
    /// "Confirm" button.
    func confirmPendingAction() {
        let action = confirmationAction
        showConfirmation = false
        confirmationAction = nil
        confirmationMessage = ""
        action?()
    }

    /// Dismiss the armed confirmation WITHOUT invoking its action (the user
    /// denied or dismissed). Issues no RPC. Mirrors the dialog's "Cancel" button.
    func cancelPendingConfirmation() {
        showConfirmation = false
        confirmationAction = nil
        confirmationMessage = ""
    }

    // MARK: - Destructive Docker mutation confirmation gates (Property 13)
    //
    // Every destructive Docker mutation — container remove/kill/prune, image
    // remove/prune, volume remove/prune, network remove/prune — is routed
    // through one of these gates. A gate only *arms* a pending confirmation via
    // `requestConfirmation`: it sets `confirmationMessage`, stores the mutation
    // in `confirmationAction`, and raises `showConfirmation`. It issues NO RPC
    // until `confirmPendingAction()` runs the stored action, so denying or
    // dismissing the confirmation (`cancelPendingConfirmation()`, or the
    // dialog's Cancel) issues no call. These gates never present a modal
    // (no NSAlert / NSSavePanel / NSOpenPanel / runModal), so the
    // destructive-confirmation guarantee is assertable in headless tests.

    /// Arm confirmation for removing a container. Issues no RPC until confirmed.
    func confirmRemoveContainer(name: String) {
        requestConfirmation("Remove container '\(name)'?") { [weak self] in
            self?.removeContainer(name: name)
        }
    }

    /// Arm confirmation for force-killing a container. Issues no RPC until confirmed.
    func confirmKillContainer(name: String) {
        requestConfirmation("Force-kill container '\(name)'?") { [weak self] in
            self?.killContainer(name: name)
        }
    }

    /// Arm confirmation for pruning stopped containers. Issues no RPC until confirmed.
    func confirmPruneContainers() {
        requestConfirmation("Prune all stopped containers? This cannot be undone.") { [weak self] in
            self?.pruneContainers()
        }
    }

    /// Arm confirmation for removing an image. Issues no RPC until confirmed.
    func confirmRemoveImage(id: String) {
        requestConfirmation("Remove image '\(id)'?") { [weak self] in
            self?.removeImage(id: id)
        }
    }

    /// Arm confirmation for pruning unused images. Issues no RPC until confirmed.
    func confirmPruneImages() {
        requestConfirmation("Prune every unused image? Removed layers may need to be downloaded again.") { [weak self] in
            self?.pruneImages()
        }
    }

    /// Arm confirmation for removing a volume. Issues no RPC until confirmed.
    func confirmRemoveVolume(name: String) {
        requestConfirmation("Remove volume '\(name)'? Its data cannot be recovered.") { [weak self] in
            self?.removeVolume(name: name)
        }
    }

    /// Arm confirmation for pruning unused volumes. Issues no RPC until confirmed.
    func confirmPruneVolumes() {
        requestConfirmation("Prune every unused volume? Volume data cannot be recovered.") { [weak self] in
            self?.pruneVolumes()
        }
    }

    /// Arm confirmation for removing a network. Issues no RPC until confirmed.
    func confirmRemoveNetwork(name: String) {
        requestConfirmation("Remove network '\(name)'?") { [weak self] in
            self?.removeNetwork(name: name)
        }
    }

    /// Arm confirmation for pruning unused networks. Issues no RPC until confirmed.
    func confirmPruneNetworks() {
        requestConfirmation("Prune every unused custom network?") { [weak self] in
            self?.pruneNetworks()
        }
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
                let reference = repoTags.first ?? "<none>:<none>"
                let parts = splitImageReference(reference)
                return MockImage(
                    id: dict["Id"] as? String ?? "",
                    repository: parts.repository,
                    tag: parts.tag,
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
            applyProfiles(raw)
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
            aiModels = try await services.modelList(runner: runner, profile: activeProfile)
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
                cancelProfileStreams()
                applyStoppedStatus()
                clearProfileResources()
                await refreshProfiles()
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
                cancelProfileStreams()
                applyStoppedStatus()
                clearProfileResources()
                await refreshProfiles()
                showToast(hard ? "Colima VM deleted with all data" : "Colima VM deleted (data preserved)")
            } catch { showError(error.localizedDescription) }
        }
    }

    func sshVM() {
        guard requiresVM("SSH") else { return }
        sheetEntityName = "colima"
        sheetCommand = "colima --profile \(activeProfile) ssh"
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
        let profile = activeProfile
        Task { @MainActor in
            do {
                try await services.updateVM(profile: profile)
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
        let profile = activeProfile
        Task { @MainActor in
            do {
                try await services.pruneVM(profile: profile, all: all)
                showToast(all ? "All cached data pruned" : "Colima cache pruned")
            } catch { showError(error.localizedDescription) }
        }
    }

    func showVersion() { showToast("Colima version \(colimaVersion)") }
    func generateTemplate() { saveTemplate() }

    func loadTemplate() {
        guard !(services is MockServiceProvider) else {
            showToast("Template picker is disabled for the mock backend")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.yaml, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let yaml = try String(contentsOf: url, encoding: .utf8)
            let config = ColimaConfig.fromYAML(yaml)
            colimaConfig = config
            showToast("Loaded template '\(url.lastPathComponent)'. Review it, then save to apply.")
        } catch {
            showError("Failed to load template: \(error.localizedDescription)")
        }
    }

    func saveTemplate() {
        guard !(services is MockServiceProvider) else {
            showToast("Template picker is disabled for the mock backend")
            return
        }
        let config = colimaConfig
        Task { @MainActor in
            do {
                let current: ColimaConfig
                if let config {
                    current = config
                } else {
                    current = try await services.readConfig(profile: activeProfile)
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.yaml, .plainText]
                panel.nameFieldStringValue = "colima-\(activeProfile).yaml"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try current.toYAML().write(to: url, atomically: true, encoding: .utf8)
                showToast("Template saved to \(url.lastPathComponent)")
            } catch {
                showError("Failed to save template: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Template editor (GetTemplate / SetTemplate, profile-scoped)

    /// Read the active profile's template via `GetTemplate` and present the
    /// editor sheet. The editor edits YAML directly and saves via `SetTemplate`.
    @MainActor func openTemplateEditor() {
        templateProfile = activeProfile
        isTemplateLoading = true
        templateValidationMessage = ""
        activeSheet = .templateEditor
        Task { @MainActor in
            do {
                let config = try await services.getTemplate(profile: templateProfile)
                templateYAML = ColimaTemplate.encode(config)
            } catch {
                templateYAML = ColimaTemplate.encode(ColimaConfig())
                showError("Failed to load template for '\(templateProfile)': \(error.localizedDescription)")
            }
            isTemplateLoading = false
        }
    }

    /// Re-read the template from disk, discarding unsaved edits in the editor.
    @MainActor func reloadTemplateFromDisk() {
        let profile = templateProfile
        isTemplateLoading = true
        templateValidationMessage = ""
        Task { @MainActor in
            do {
                let config = try await services.getTemplate(profile: profile)
                templateYAML = ColimaTemplate.encode(config)
                showToast("Template reloaded for '\(profile)'")
            } catch {
                showError("Failed to reload template for '\(profile)': \(error.localizedDescription)")
            }
            isTemplateLoading = false
        }
    }

    /// Validate the current editor YAML. Sets `templateValidationMessage` and
    /// returns true only when the content is acceptable.
    @discardableResult
    @MainActor func validateTemplateYAML() -> Bool {
        let issues = ColimaTemplate.validationIssues(templateYAML)
        templateValidationMessage = issues.isEmpty ? "" : issues.joined(separator: "\n")
        return issues.isEmpty
    }

    /// Validate and persist the edited template via `SetTemplate`. Refuses to
    /// save invalid YAML and surfaces the validation issues instead.
    @MainActor func saveTemplateEdits() {
        guard validateTemplateYAML() else {
            showError("Template not saved — fix validation issues first.")
            return
        }
        let profile = templateProfile
        let config = ColimaTemplate.decode(templateYAML)
        isTemplateLoading = true
        Task { @MainActor in
            do {
                try await services.setTemplate(profile: profile, config: config)
                showToast("Template saved for '\(profile)'. Applies to newly created VMs.")
                activeSheet = nil
            } catch {
                showError("Failed to save template for '\(profile)': \(error.localizedDescription)")
            }
            isTemplateLoading = false
        }
    }

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
        createContainer(name: name, image: image, options: ContainerCreateOptions(), start: false)
    }

    func createContainer(name: String, image: String, options: ContainerCreateOptions, start: Bool) {
        guard requiresVM("Create Container") else { return }
        if let err = validateContainerName(name) { showError(err); return }
        if let err = validateImageName(image) { showError(err); return }
        if options.autoRemove && options.restartPolicy != "no" {
            showError("Auto-remove cannot be combined with a restart policy.")
            return
        }
        Task { @MainActor in
            do {
                let id = try await services.createContainer(name: name, image: image, options: options)
                if start {
                    // Start only after Docker confirms creation; this avoids the
                    // previous create/start race against a not-yet-existing name.
                    try await services.startContainer(id: id.isEmpty ? name : id)
                }
                await refreshContainers()
                showToast(start ? "Container '\(name)' created and started" : "Container '\(name)' created")
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
        let socket = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colima/\(activeProfile)/docker.sock").path
        sheetCommand = "DOCKER_HOST=unix://\(socket) docker exec -it \(name) sh"
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                _ = try await services.executeCommand(
                    tool: "docker",
                    args: ["container", "export", "--output", url.path, name],
                    profile: activeProfile
                )
                showToast("Container '\(name)' exported to \(url.lastPathComponent)")
            } catch { showError("Failed to export container: \(error.localizedDescription)") }
        }
    }

    func changesContainer(name: String) {
        guard requiresVM("Changes") else { return }
        sheetEntityName = name
        activeSheet = .changes
    }

    func waitContainer(name: String) {
        guard requiresVM("Wait") else { return }
        showError("Container wait is not exposed by the current service contract.")
    }

    func attachContainer(name: String) {
        guard requiresVM("Attach") else { return }
        sheetEntityName = name
        let socket = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colima/\(activeProfile)/docker.sock").path
        sheetCommand = "DOCKER_HOST=unix://\(socket) docker attach \(name)"
        activeSheet = .terminal
    }

    func updateContainerResources(name: String) {
        guard requiresVM("Update Resources") else { return }
        showError("Resource updates require explicit limits; this UI does not collect them yet and made no change.")
    }
    func copyContainer(name: String) {
        guard requiresVM("Copy") else { return }
        sheetEntityName = name
        activeSheet = .copyFiles
    }

    func copyContainerFiles(args: [String]) {
        guard requiresVM("Copy Files") else { return }
        Task { @MainActor in
            do {
                _ = try await services.executeCommand(tool: "docker", args: args, profile: activeProfile)
                showToast("File copy completed")
            } catch { showError("File copy failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Image actions

    func pullImage(name: String) {
        guard requiresVM("Pull Image") else { return }
        if let err = validateImageName(name) { showError(err); return }
        imagePullTasks[name]?.cancel()
        imagePullStatus[name] = "Connecting to Docker Engine…"
        imagePullProgress[name] = ImagePullProgress(status: "Connecting to Docker Engine…")
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // OBSERVED progress: the provider streams real per-layer
                // progressDetail from the Docker Engine `/images/create` stream.
                try await services.pullImage(name: name) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        // Drop late events from a cancelled/replaced pull.
                        guard self.imagePullTasks[name] != nil else { return }
                        self.imagePullProgress[name] = progress
                        self.imagePullStatus[name] = progress.summary
                    }
                }
                try Task.checkCancellation()
                await refreshImages()
                var done = imagePullProgress[name] ?? ImagePullProgress()
                done.finished = true
                imagePullProgress[name] = done
                imagePullStatus[name] = "Complete — verified in local image list"
                showToast("Image '\(name)' pulled")
            } catch is CancellationError {
                imagePullStatus[name] = "Cancellation requested; Docker may finish the current layer"
            } catch {
                imagePullStatus[name] = "Failed: \(error.localizedDescription)"
                showError(error.localizedDescription)
            }
            imagePullTasks[name] = nil
        }
        imagePullTasks[name] = task
    }

    func cancelImagePull(name: String) {
        imagePullTasks[name]?.cancel()
        imagePullStatus[name] = "Cancellation requested; Docker may finish the current layer"
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
        let destinationRepository = imageRepository(from: repo)
        Task { @MainActor in
            do {
                try await services.tagImage(name: repo, repo: destinationRepository, tag: newTag)
                await refreshImages()
                showToast("Tagged \(repo) as \(destinationRepository):\(newTag)")
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                _ = try await services.executeCommand(
                    tool: "docker",
                    args: ["image", "save", "--output", url.path, repo],
                    profile: activeProfile
                )
                showToast("Image '\(repo)' exported to \(url.lastPathComponent)")
            } catch { showError("Failed to export image: \(error.localizedDescription)") }
        }
    }

    func importImage(path: String) {
        guard requiresVM("Import Image") else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                _ = try await services.executeCommand(
                    tool: "docker",
                    args: ["image", "load", "--input", url.path],
                    profile: activeProfile
                )
                await refreshImages()
                showToast("Image imported from \(url.lastPathComponent)")
            } catch { showError("Failed to import image: \(error.localizedDescription)") }
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
                if name == activeProfile {
                    await refreshAll()
                } else {
                    await refreshProfiles()
                }
                showToast("Profile '\(name)' started")
            } catch { showError(error.localizedDescription) }
        }
    }

    func stopProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.stopVM(profile: name, force: false)
                if name == activeProfile {
                    cancelProfileStreams()
                    applyStoppedStatus()
                    clearProfileResources()
                }
                await refreshProfiles()
                showToast("Profile '\(name)' stopped")
            } catch { showError(error.localizedDescription) }
        }
    }

    func restartProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.restartVM(profile: name)
                if name == activeProfile {
                    cancelProfileStreams()
                    await refreshAll()
                } else {
                    await refreshProfiles()
                }
                showToast("Profile '\(name)' restarted")
            } catch { showError(error.localizedDescription) }
        }
    }

    func deleteProfile(name: String) {
        Task { @MainActor in
            do {
                try await services.deleteProfile(name: name, data: true)
                if name == activeProfile {
                    cancelProfileStreams()
                    didInitializeProfileContext = false
                    applyStoppedStatus()
                    clearProfileResources()
                }
                await refreshProfiles()
                if name == activeProfile { await refreshAll() }
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
        // Reset the known fields to defaults but retain the loaded document's
        // source, so unknown foreign keys survive a reset-then-save and the
        // write guard still recognizes this config as originating from a real
        // load (Requirement 7.4 / Property 19 / never-silently-overwrite).
        var defaults = ColimaConfig()
        defaults.sourceYAML = colimaConfig?.sourceYAML
        colimaConfig = defaults
        showToast("Configuration reset to defaults")
    }

    func editYAML() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/.colima/\(activeProfile)/colima.yaml"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Runtime Controls

    func executeCommand(tool: String, args: [String], completion: @escaping (String) -> Void) {
        let profile = activeProfile
        Task {
            do {
                let output = try await services.executeCommand(tool: tool, args: args, profile: profile)
                await MainActor.run { completion(output) }
            } catch {
                await MainActor.run { completion("Error: \(error.localizedDescription)") }
            }
        }
    }

    func switchDockerContext(profile: String) {
        guard requiresVM("Docker Context") else { return }
        showToast("This app is already bound to '\(activeProfile)' without changing your global Docker context.")
    }

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

    func switchRuntime(to runtime: String) {
        guard ["docker", "containerd", "incus"].contains(runtime) else {
            showError("Unsupported runtime '\(runtime)'.")
            return
        }
        let profile = activeProfile
        Task { @MainActor in
            do {
                var config = try await services.readConfig(profile: profile)
                guard config.runtime != runtime else {
                    showToast("Runtime is already \(runtime)")
                    return
                }
                config.runtime = runtime
                try await services.writeConfig(profile: profile, config: config)
                colimaConfig = config
                if vmRunning { try await services.restartVM(profile: profile) }
                let status = try await services.vmStatus(profile: profile)
                applyStatus(status)
                if status.runtime == runtime {
                    showToast("Runtime switched to \(runtime)")
                    await refreshAll()
                } else {
                    showError("Saved runtime '\(runtime)', but the running VM still reports '\(status.runtime)'. Recreate the VM to apply this runtime change.")
                }
            } catch { showError("Failed to switch runtime: \(error.localizedDescription)") }
        }
    }

    func updateRuntime() {
        guard requiresVM("Update Runtime") else { return }
        let profile = activeProfile
        Task { @MainActor in
            do {
                try await services.updateVM(profile: profile)
                await refreshAll()
                showToast("Runtime update completed for '\(profile)'")
            } catch { showError("Runtime update failed: \(error.localizedDescription)") }
        }
    }

    private func imageRepository(from reference: String) -> String {
        if let digest = reference.range(of: "@sha256:") { return String(reference[..<digest.lowerBound]) }
        guard let colon = reference.lastIndex(of: ":") else { return reference }
        let slash = reference.lastIndex(of: "/")
        if let slash, colon < slash { return reference }
        return String(reference[..<colon])
    }

    private func splitImageReference(_ reference: String) -> (repository: String, tag: String) {
        if let digest = reference.range(of: "@sha256:") {
            return (String(reference[..<digest.lowerBound]), String(reference[digest.lowerBound...]))
        }
        guard let colon = reference.lastIndex(of: ":") else { return (reference, "<none>") }
        if let slash = reference.lastIndex(of: "/"), colon < slash { return (reference, "<none>") }
        return (String(reference[..<colon]), String(reference[reference.index(after: colon)...]))
    }
}

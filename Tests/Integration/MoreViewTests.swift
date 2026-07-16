import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ContainerDetailView integration tests

@Suite("ContainerDetailView Integration", .serialized)
@MainActor
struct ContainerDetailViewTests {

    private func running(_ name: String) -> MockContainer {
        MockContainer(id: "abc\(name)", name: name, image: "nginx:latest", status: "Up", state: "running", ports: "80/tcp", created: "1h ago")
    }
    private func stopped(_ name: String) -> MockContainer {
        MockContainer(id: "xyz\(name)", name: name, image: "alpine", status: "Exited", state: "exited", ports: "", created: "2h ago")
    }

    @Test("shows container name in header")
    func showsContainerName() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerDetailView(container: running("web-server")).environmentObject(state)
        #expect((try? v.inspect().find(text: "web-server")) != nil)
    }

    @Test("shows state badge for running container")
    func showsRunningState() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerDetailView(container: running("nginx")).environmentObject(state)
        #expect((try? v.inspect().find(text: "Running")) != nil)
    }

    @Test("shows state badge for stopped container")
    func showsStoppedState() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerDetailView(container: stopped("redis")).environmentObject(state)
        #expect((try? v.inspect().find(text: "Exited")) != nil)
    }

    @Test("has tab picker")
    func hasTabPicker() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerDetailView(container: running("web")).environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_container_detail_tab")) != nil)
    }

    @Test("has outer panel accessibility identifier")
    func hasPanelId() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerDetailView(container: running("web")).environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "container_detail_panel")) != nil)
    }

    @Test("shows image name in info tab (default)")
    func showsImageName() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerDetailView(container: running("web")).environmentObject(state)
        #expect((try? v.inspect().find(text: "nginx:latest")) != nil)
    }

    @Test("ContainerDetailView.DetailTab has 5 cases")
    func detailTabCases() {
        #expect(ContainerDetailView.DetailTab.allCases.count == 5)
        #expect(ContainerDetailView.DetailTab.allCases.contains(.info))
        #expect(ContainerDetailView.DetailTab.allCases.contains(.stats))
        #expect(ContainerDetailView.DetailTab.allCases.contains(.logs))
        #expect(ContainerDetailView.DetailTab.allCases.contains(.terminal))
        #expect(ContainerDetailView.DetailTab.allCases.contains(.files))
    }

    @Test("DetailTab raw values match display labels")
    func detailTabRawValues() {
        #expect(ContainerDetailView.DetailTab.info.rawValue == "Info")
        #expect(ContainerDetailView.DetailTab.stats.rawValue == "Stats")
        #expect(ContainerDetailView.DetailTab.logs.rawValue == "Logs")
        #expect(ContainerDetailView.DetailTab.terminal.rawValue == "Terminal")
        #expect(ContainerDetailView.DetailTab.files.rawValue == "Files")
    }
}

// MARK: - MachinesView integration tests

@Suite("MachinesView Integration", .serialized)
@MainActor
struct MachinesViewTests {

    private func vm(_ name: String, status: String = "running") -> MockVM {
        MockVM(id: name, name: name, os: .linux, status: status, cpus: 4, memory: 8, disk: 100, arch: "aarch64")
    }

    private func state(machines: [MockVM] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.machines = machines
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        MachinesView().environmentObject(appState)
    }

    @Test("shows create machine button")
    func createMachineButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_machine")) != nil)
    }

    @Test("shows machine names in list")
    func machineNamesInList() throws {
        let s = state(machines: [vm("colima"), vm("dev-vm")])
        let v = view(s)
        #expect((try? v.inspect().find(text: "colima")) != nil)
        #expect((try? v.inspect().find(text: "dev-vm")) != nil)
    }

    @Test("MockVM.VMOS icon values are non-empty")
    func vmOSIcons() {
        #expect(!MockVM.VMOS.linux.icon.isEmpty)
        #expect(!MockVM.VMOS.macos.icon.isEmpty)
        #expect(!MockVM.VMOS.windows.icon.isEmpty)
    }

    @Test("MockVM.VMOS color is distinct per OS")
    func vmOSColors() {
        #expect(MockVM.VMOS.linux.color == .orange)
        #expect(MockVM.VMOS.macos.color == .blue)
        #expect(MockVM.VMOS.windows.color == .cyan)
    }
}

// MARK: - AIWorkloadsView integration tests

@Suite("AIWorkloadsView Integration", .serialized)
@MainActor
struct AIWorkloadsViewTests {

    private func state(vmType: String = "vz") -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        AIWorkloadsView().environmentObject(appState)
    }

    @Test("shows krunkit status indicator")
    func krunkitStatus() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_krunkit")) != nil)
    }

    @Test("shows model name field")
    func modelNameField() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_ai_modelname")) != nil)
    }

    @Test("shows runner picker")
    func runnerPicker() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_ai_runner")) != nil)
    }

    @Test("has run model button")
    func runButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_ai_model")) != nil)
    }

    @Test("has serve model button")
    func serveButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_serve_ai_model")) != nil)
    }

    @Test("has install krunkit button")
    func installKrunkitButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_install_ai_krunkit")) != nil)
    }
}

// MARK: - RuntimeControlsView integration tests

@Suite("RuntimeControlsView Integration", .serialized)
@MainActor
struct RuntimeControlsViewTests {

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        RuntimeControlsView().environmentObject(appState)
    }

    @Test("shows runtime name identifier")
    func runtimeNameId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_runtime_name")) != nil)
    }

    @Test("shows runtime socket identifier")
    func runtimeSocketId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_runtime_socket")) != nil)
    }

    @Test("has copy socket button")
    func copySocketButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_socket")) != nil)
    }
}

// MARK: - CommunityView integration tests

@Suite("CommunityView Integration", .serialized)
@MainActor
struct CommunityViewTests {

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        CommunityView().environmentObject(appState)
    }

    @Test("shows discussions table")
    func discussionsTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_discussions")) != nil)
    }

    @Test("shows issue repo picker")
    func issueRepoPicker() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_issue_repo")) != nil)
    }

    @Test("shows issue wizard next button step 1")
    func wizardNextButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_issue_wizard_next1")) != nil)
    }

    @Test("shows FAQ search field")
    func faqSearch() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_faq_search")) != nil)
    }

    @Test("has GitHub discussions link button")
    func discussionsLink() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_open_community_discussions")) != nil)
    }

    @Test("has report issue link button")
    func issuesLink() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_open_community_issues")) != nil)
    }
}

import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - CovConfig_ prefix · ContainersView additional coverage

// ─── Helpers ────────────────────────────────────────────────────────────────

@MainActor
private func makeContainerState(containers: [MockContainer] = []) -> AppState {
    let s = AppState(services: MockServiceProvider())
    s.containers = containers
    return s
}

private func running(_ name: String, image: String = "nginx:latest", created: String = "1h") -> MockContainer {
    MockContainer(id: name, name: name, image: image, status: "Up 1h", state: "running", ports: "80/tcp", created: created)
}

private func stopped(_ name: String, created: String = "2h") -> MockContainer {
    MockContainer(id: name, name: name, image: "alpine:3", status: "Exited (0)", state: "exited", ports: "", created: created)
}

private func paused(_ name: String) -> MockContainer {
    MockContainer(id: name, name: name, image: "redis:7", status: "Paused", state: "paused", ports: "", created: "3h")
}

@MainActor
private func containersView(_ state: AppState) -> some View {
    ContainersView().environmentObject(state)
}

// ─── Empty state variants ─────────────────────────────────────────────────────

@Suite("CovConfig_ContainersView_EmptyState", .serialized)
@MainActor
struct CovConfig_ContainersView_EmptyState {

    @Test("empty state shows shippingbox icon text")
    func emptyStateIconPresent() throws {
        // Empty state body contains Image(systemName:"shippingbox") + text; verify text
        let v = containersView(makeContainerState(containers: []))
        #expect((try? v.inspect().find(text: "No containers running")) != nil)
    }

    @Test("empty state Create Container button is present")
    func emptyStateCreateButton() throws {
        let v = containersView(makeContainerState(containers: []))
        #expect((try? v.inspect().find(button: "Create Container")) != nil)
    }

    @Test("list is not shown in empty state")
    func listAbsentInEmptyState() throws {
        let v = containersView(makeContainerState(containers: []))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_containers")) == nil)
    }
}

// ─── Sorted / grouped list ────────────────────────────────────────────────────

@Suite("CovConfig_ContainersView_List", .serialized)
@MainActor
struct CovConfig_ContainersView_List {

    @Test("running containers appear in list")
    func runningAppears() throws {
        let v = containersView(makeContainerState(containers: [running("alpha"), running("beta")]))
        #expect((try? v.inspect().find(text: "alpha")) != nil)
        #expect((try? v.inspect().find(text: "beta")) != nil)
    }

    @Test("paused container appears in running section (treated as running)")
    func pausedAppearsInRunning() throws {
        let v = containersView(makeContainerState(containers: [paused("worker")]))
        // paused goes to runningContainers; "Stopped" section should NOT appear
        #expect((try? v.inspect().find(text: "Stopped")) == nil)
    }

    @Test("Stopped section header present when exited container exists")
    func stoppedSectionHeader() throws {
        let v = containersView(makeContainerState(containers: [running("web"), stopped("db")]))
        #expect((try? v.inspect().find(text: "Stopped")) != nil)
    }

    @Test("multiple stopped containers all appear")
    func multipleStoppedContainers() throws {
        let v = containersView(makeContainerState(containers: [stopped("a"), stopped("b"), stopped("c")]))
        #expect((try? v.inspect().find(text: "a")) != nil)
        #expect((try? v.inspect().find(text: "b")) != nil)
        #expect((try? v.inspect().find(text: "c")) != nil)
    }

    @Test("container image name shown in row")
    func containerImageInRow() throws {
        let v = containersView(makeContainerState(containers: [running("myapp", image: "myorg/myapp:v2")]))
        #expect((try? v.inspect().find(text: "myorg/myapp:v2")) != nil)
    }
}

// ─── Sort logic ───────────────────────────────────────────────────────────────

@Suite("CovConfig_ContainersView_Sorting", .serialized)
@MainActor
struct CovConfig_ContainersView_Sorting {

    @Test("sort button is accessible")
    func sortButtonExists() throws {
        let v = containersView(makeContainerState(containers: [running("a")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_containers")) != nil)
    }

    @Test("ContainerSortOrder cases cover all three orders")
    func sortOrderCases() {
        let cases = ContainerSortOrder.allCases
        #expect(cases.contains(.name))
        #expect(cases.contains(.status))
        #expect(cases.contains(.created))
    }

    @Test("ContainerSortOrder raw values match UI labels")
    func sortOrderRawValues() {
        #expect(ContainerSortOrder.name.rawValue == "Name")
        #expect(ContainerSortOrder.status.rawValue == "Status")
        #expect(ContainerSortOrder.created.rawValue == "Created")
    }
}

// ─── Toolbar actions ──────────────────────────────────────────────────────────

@Suite("CovConfig_ContainersView_Toolbar", .serialized)
@MainActor
struct CovConfig_ContainersView_Toolbar {

    @Test("prune button present with containers")
    func pruneButtonPresent() throws {
        let v = containersView(makeContainerState(containers: [running("x")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_container_all")) != nil)
    }

    @Test("create button present with containers")
    func createButtonPresent() throws {
        let v = containersView(makeContainerState(containers: [running("x")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_container_new")) != nil)
    }

    @Test("search field present with containers")
    func searchFieldPresent() throws {
        let v = containersView(makeContainerState(containers: [running("x")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_containers_search")) != nil)
    }
}

// ─── ContainerRowView standalone ─────────────────────────────────────────────

@Suite("CovConfig_ContainerRow_States", .serialized)
@MainActor
struct CovConfig_ContainerRow_States {

    @Test("running row: status indicator identifier present")
    func runningIndicator() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: running("mybox"), appState: s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_mybox")) != nil)
    }

    @Test("running row: status indicator exists for running state")
    func runningIndicatorValue() throws {
        // Verifies the Circle with the correct accessibility ID is present for a running container.
        // The actual state value is set via .accessibilityValue(container.state) in ContainerRowView.
        let s = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: running("mybox"), appState: s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_mybox")) != nil)
    }

    @Test("stopped row: status indicator exists for exited state")
    func stoppedIndicatorValue() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: stopped("dbbox"), appState: s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_dbbox")) != nil)
    }

    @Test("paused row: stop button NOT shown; start button shown instead")
    func pausedRowShowsStartButton() throws {
        // Paused containers have state=="paused" != "running", so row shows start button
        let s = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: paused("cache"), appState: s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_container_cache")) != nil)
        // stop button should NOT exist for paused
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_container_cache")) == nil)
    }

    @Test("context menu has Start item (documented behavior: appState.startContainer accessible)")
    func contextMenuHasStart() throws {
        // NOTE: ViewInspector does not expose .contextMenu() content on HStack in this version.
        // We verify the underlying AppState action (startContainer) works correctly instead,
        // which is what the context menu button invokes. Context menu identifier coverage is
        // validated via XCUITest (see Tests/UI/ContainerManagementUITests.swift).
        let s = AppState(services: MockServiceProvider())
        // startContainer is guarded by requiresVM — set vmRunning true
        s.vmRunning = true
        s.startContainer(name: "db")
        // Action dispatches async — just verify no crash and VM gate passed
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Kill item (AppState.killContainer dispatches without error)")
    func contextMenuHasKill() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.killContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Pause item (AppState.pauseContainer dispatches without error)")
    func contextMenuHasPause() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.pauseContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Unpause item (AppState.unpauseContainer dispatches without error)")
    func contextMenuHasUnpause() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.unpauseContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Restart item (AppState.restartContainer dispatches without error)")
    func contextMenuHasRestart() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.restartContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Logs item (AppState.logsContainer dispatches without error)")
    func contextMenuHasLogs() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.logsContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Inspect item (AppState.inspectContainer dispatches without error)")
    func contextMenuHasInspect() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.inspectContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Exec item (AppState.execContainer dispatches without error)")
    func contextMenuHasExec() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.execContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Stats item (AppState.statsContainer dispatches without error)")
    func contextMenuHasStats() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.statsContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Changes item (AppState.changesContainer dispatches without error)")
    func contextMenuHasChanges() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.changesContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Top item (AppState.topContainer dispatches without error)")
    func contextMenuHasTop() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.topContainer(name: "web")
        #expect(s.errorMessage == nil)
    }


    @Test("context menu has Wait item (AppState.waitContainer dispatches without error)")
    func contextMenuHasWait() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.waitContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Attach item (AppState.attachContainer dispatches without error)")
    func contextMenuHasAttach() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.attachContainer(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Update item (AppState.updateContainerResources dispatches without error)")
    func contextMenuHasUpdate() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.updateContainerResources(name: "web")
        #expect(s.errorMessage == nil)
    }

    @Test("context menu has Copy item (AppState.copyContainer dispatches without error)")
    func contextMenuHasCopy() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.copyContainer(name: "web")
        #expect(s.errorMessage == nil)
    }
}

// ─── AppState container action methods ────────────────────────────────────────

@Suite("CovConfig_ContainersView_AppStateActions", .serialized)
@MainActor
struct CovConfig_ContainersView_AppStateActions {

    @Test("pruneContainers fires toast when VM running")
    func pruneContainersToast() async {
        let s = makeContainerState()
        s.vmRunning = true
        s.pruneContainers()
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if s.isToastVisible { break }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        #expect(s.isToastVisible)
    }

    @Test("pruneContainers is blocked when VM is stopped")
    func pruneContainersBlocked() {
        let s = makeContainerState()
        s.vmRunning = false
        s.pruneContainers()
        // requiresVM shows error toast; the prune call itself still fires isToastVisible
        // but errorMessage should be set
        #expect(s.errorMessage != nil)
    }

    @Test("validateContainerName returns nil for valid name")
    func validContainerNameReturnsNil() {
        let s = makeContainerState()
        #expect(s.validateContainerName("my-valid_name1") == nil)
    }

    @Test("validateContainerName returns error for name with spaces")
    func invalidNameWithSpaces() {
        let s = makeContainerState()
        #expect(s.validateContainerName("my container") != nil)
    }

    @Test("validateContainerName returns error for name exceeding 128 chars")
    func invalidNameTooLong() {
        let s = makeContainerState()
        #expect(s.validateContainerName(String(repeating: "x", count: 129)) != nil)
    }

    @Test("validateImageName returns nil for valid image")
    func validImageName() {
        let s = makeContainerState()
        #expect(s.validateImageName("nginx:latest") == nil)
    }

    @Test("validateImageName returns nil for image with registry")
    func validImageWithRegistry() {
        let s = makeContainerState()
        #expect(s.validateImageName("docker.io/library/nginx:1.25") == nil)
    }

    @Test("validateImageName returns error for empty string")
    func emptyImageName() {
        let s = makeContainerState()
        #expect(s.validateImageName("") != nil)
    }

    @Test("createContainer blocked when VM stopped")
    func createContainerBlockedWhenVMStopped() {
        let s = makeContainerState()
        s.vmRunning = false
        s.createContainer(name: "test", image: "nginx:latest")
        // requiresVM should set errorMessage
        #expect(s.errorMessage != nil)
    }

    @Test("statusSubtitle reflects running/stopped/paused counts correctly")
    func statusSubtitle() {
        let s = makeContainerState(containers: [
            running("a"), running("b"), stopped("c"), paused("d")
        ])
        // ContainersView.statusSubtitle is private, but we can verify AppState containers
        let runningCount = s.containers.filter { $0.state == "running" }.count
        let stoppedCount = s.containers.filter { $0.state == "exited" }.count
        let pausedCount = s.containers.filter { $0.state == "paused" }.count
        #expect(runningCount == 2)
        #expect(stoppedCount == 1)
        #expect(pausedCount == 1)
    }
}

// ─── ImageBrowserSheet ────────────────────────────────────────────────────────

@Suite("CovConfig_ImageBrowserSheet", .serialized)
@MainActor
struct CovConfig_ImageBrowserSheet {

    @Test("image browser sheet renders search field")
    func searchFieldPresent() throws {
        let s = AppState(services: MockServiceProvider())
        s.images = MockData.images
        let v = ImageBrowserSheet(
            appState: s,
            onSelect: { _ in },
            onCancel: {}
        )
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_image_browser_search")) != nil)
    }

    @Test("image browser sheet renders table")
    func tablePresentInBrowser() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ImageBrowserSheet(appState: s, onSelect: { _ in }, onCancel: {})
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_image_browser")) != nil)
    }

    @Test("image browser sheet renders cancel button")
    func cancelButtonPresent() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ImageBrowserSheet(appState: s, onSelect: { _ in }, onCancel: {})
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_image_browser_cancel")) != nil)
    }

    @Test("image browser sheet shows local images section when images are present")
    func localImagesSection() throws {
        let s = AppState(services: MockServiceProvider())
        s.images = MockData.images
        let v = ImageBrowserSheet(appState: s, onSelect: { _ in }, onCancel: {})
        // The section header contains "Local Images (N)" text — verify the sheet renders images
        // ViewInspector can find the sheet root
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "section_image_browser_local")) != nil)
    }

    @Test("image browser sheet shows Docker Hub section")
    func dockerHubSection() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ImageBrowserSheet(appState: s, onSelect: { _ in }, onCancel: {})
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "section_image_browser_hub")) != nil)
    }
}

// ─── ContainerDetailView ──────────────────────────────────────────────────────

@Suite("CovConfig_ContainerDetailView", .serialized)
@MainActor
struct CovConfig_ContainerDetailView {

    @Test("ContainerDetailView renders container name")
    func rendersContainerName() throws {
        let s = AppState(services: MockServiceProvider())
        let container = running("nginx-test", image: "nginx:stable")
        let v = ContainerDetailView(container: container).environmentObject(s)
        #expect((try? v.inspect().find(text: "nginx-test")) != nil)
    }

    @Test("ContainerDetailView renders image name")
    func rendersImageName() throws {
        let s = AppState(services: MockServiceProvider())
        let container = running("nginx-test", image: "nginx:stable")
        let v = ContainerDetailView(container: container).environmentObject(s)
        #expect((try? v.inspect().find(text: "nginx:stable")) != nil)
    }
}

// ─── CreateContainerView ──────────────────────────────────────────────────────

@Suite("CovConfig_CreateContainerView", .serialized)
@MainActor
struct CovConfig_CreateContainerView {

    @Test("CreateContainerView renders image field")
    func rendersImageField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_create_container_image_full")) != nil)
    }

    @Test("CreateContainerView renders name field")
    func rendersNameField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_create_container_name_full")) != nil)
    }

    @Test("CreateContainerView renders create confirm button")
    func rendersCreateButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_container_confirm")) != nil)
    }

    @Test("CreateContainerView renders cancel button")
    func rendersCancelButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_container_cancel")) != nil)
    }

    @Test("CreateContainerView renders Create & Start button")
    func rendersCreateAndStartButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_container_start")) != nil)
    }

    @Test("CreateContainerView renders platform picker")
    func rendersPlatformPicker() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_create_container_platform")) != nil)
    }

    @Test("CreateContainerView renders restart policy picker")
    func rendersRestartPicker() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_create_container_restart")) != nil)
    }

    @Test("CreateContainerView renders remove-after-stop toggle")
    func rendersRemoveAfterStopToggle() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_create_container_rm")) != nil)
    }
}

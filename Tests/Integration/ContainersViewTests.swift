import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ContainersView integration tests

@Suite("ContainersView Integration", .serialized)
@MainActor
struct ContainersViewTests {

    private func running(_ name: String, image: String = "nginx:latest") -> MockContainer {
        MockContainer(id: name, name: name, image: image, status: "Up", state: "running", ports: "80/tcp", created: "now")
    }
    private func stopped(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "alpine", status: "Exited", state: "exited", ports: "", created: "now")
    }
    private func paused(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "redis:7", status: "Paused", state: "paused", ports: "", created: "now")
    }

    private func stateWith(containers: [MockContainer]) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.containers = containers
        return s
    }

    @ViewBuilder
    private func view(_ state: AppState) -> some View {
        ContainersView().environmentObject(state)
    }

    // MARK: Empty state

    @Test("shows empty state when containers list is empty")
    func emptyState() throws {
        let state = stateWith(containers: [])
        let v = view(state)
        // The empty state view contains "No containers running"
        #expect((try? v.inspect().find(text: "No containers running")) != nil)
    }

    @Test("shows Create Container button in empty state")
    func emptyStateButton() throws {
        let state = stateWith(containers: [])
        let v = view(state)
        #expect((try? v.inspect().find(button: "Create Container")) != nil)
    }

    // MARK: Container list

    @Test("shows container list when containers are present")
    func containerListVisible() throws {
        let state = stateWith(containers: [running("web"), stopped("db")])
        let v = view(state)
        // The table has the accessibility identifier
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_containers")) != nil)
    }

    @Test("shows running container names in the list")
    func runningContainerNames() throws {
        let state = stateWith(containers: [running("web-server"), running("api-server")])
        let v = view(state)
        #expect((try? v.inspect().find(text: "web-server")) != nil)
        #expect((try? v.inspect().find(text: "api-server")) != nil)
    }

    @Test("shows stopped container names in the list")
    func stoppedContainerNames() throws {
        let state = stateWith(containers: [running("web"), stopped("redis")])
        let v = view(state)
        #expect((try? v.inspect().find(text: "redis")) != nil)
    }

    @Test("shows Stopped section for exited containers")
    func stoppedSection() throws {
        let state = stateWith(containers: [running("web"), stopped("db")])
        let v = view(state)
        // The section header "Stopped" should appear
        #expect((try? v.inspect().find(text: "Stopped")) != nil)
    }

    @Test("no Stopped section when all containers are running")
    func noStoppedSection() throws {
        let state = stateWith(containers: [running("web"), running("api")])
        let v = view(state)
        // No stopped section when all are running
        #expect((try? v.inspect().find(text: "Stopped")) == nil)
    }

    @Test("toolbar has sort menu button")
    func sortButton() throws {
        let state = stateWith(containers: [running("web")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_containers")) != nil)
    }

    @Test("toolbar has create container button")
    func createButton() throws {
        let state = stateWith(containers: [running("web")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_container_new")) != nil)
    }

    @Test("toolbar has prune button")
    func pruneButton() throws {
        let state = stateWith(containers: [running("web")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_container_all")) != nil)
    }

    @Test("toolbar has search field")
    func searchField() throws {
        let state = stateWith(containers: [running("web")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_containers_search")) != nil)
    }

    // MARK: Container row

    @Test("running container shows stop button in row")
    func runningContainerStopButton() throws {
        let state = stateWith(containers: [running("web")])
        state.isUITesting.self  // just access the property
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_container_web")) != nil)
    }

    @Test("stopped container shows start button in row")
    func stoppedContainerStartButton() throws {
        let state = stateWith(containers: [stopped("db")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_container_db")) != nil)
    }

    @Test("container row shows remove button")
    func containerRemoveButton() throws {
        let state = stateWith(containers: [running("web")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_container_web")) != nil)
    }

    @Test("status indicator identifier is correct for running container")
    func runningStatusIndicator() throws {
        let state = stateWith(containers: [running("web")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_web")) != nil)
    }

    @Test("status indicator identifier is correct for stopped container")
    func stoppedStatusIndicator() throws {
        let state = stateWith(containers: [stopped("db")])
        let v = view(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_db")) != nil)
    }

    @Test("container row shows image name")
    func containerImageName() throws {
        let state = stateWith(containers: [running("web", image: "nginx:latest")])
        let v = view(state)
        #expect((try? v.inspect().find(text: "nginx:latest")) != nil)
    }
}

// MARK: - ContainerRowView standalone tests

@Suite("ContainerRowView Integration", .serialized)
@MainActor
struct ContainerRowViewTests {

    private func running(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "alpine", status: "Up", state: "running", ports: "", created: "now")
    }
    private func stopped(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "alpine", status: "Exited", state: "exited", ports: "", created: "now")
    }
    private func paused(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "redis:7", status: "Paused", state: "paused", ports: "", created: "now")
    }

    @Test("row shows container name")
    func containerNameLabel() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: running("mycontainer"), appState: state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_container_mycontainer")) != nil)
    }

    @Test("running row has stop button")
    func runningHasStopButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: running("web"), appState: state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_container_web")) != nil)
    }

    @Test("stopped row has start button")
    func stoppedHasStartButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: stopped("db"), appState: state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_container_db")) != nil)
    }

    @Test("row has remove button")
    func rowHasRemoveButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ContainerRowView(container: running("web"), appState: state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_container_web")) != nil)
    }
}

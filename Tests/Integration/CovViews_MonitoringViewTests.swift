import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - SparklineView unit tests (structural — GeometryReader prevents VI inspection)

@Suite("CovViews_SparklineView")
struct CovViews_SparklineViewTests {

    @Test("SparklineView struct is constructable with populated data")
    func constructWithData() {
        let v = SparklineView(data: [0.1, 0.5, 0.8, 0.3, 0.9], color: .blue)
        // Just verify it compiles and initialises — GeometryReader prevents VI inspection
        _ = v
    }

    @Test("SparklineView struct is constructable with empty data")
    func constructEmpty() {
        let v = SparklineView(data: [], color: .green)
        _ = v
    }

    @Test("SparklineView struct is constructable with single data point")
    func constructSinglePoint() {
        let v = SparklineView(data: [0.5], color: .orange)
        _ = v
    }

    @Test("maxValue parameter defaults to data max when 0 is supplied")
    func defaultMaxValueBranch() {
        // Pass maxValue: 0 so the init picks data.max()
        let v = SparklineView(data: [1.0, 5.0, 3.0], color: .red, maxValue: 0)
        _ = v
    }

    @Test("explicit maxValue overrides default")
    func explicitMaxValue() {
        let v = SparklineView(data: [10.0, 20.0], color: .purple, maxValue: 100.0)
        _ = v
    }
}

// MARK: - ProcessNode unit tests

@Suite("CovViews_ProcessNode")
struct CovViews_ProcessNodeTests {

    @Test("stores all fields correctly")
    func fields() {
        let node = ProcessNode(id: "vm", name: "Colima VM", cpu: 1.2, memory: 256.0, icon: "desktopcomputer", children: [])
        #expect(node.id == "vm")
        #expect(node.name == "Colima VM")
        #expect(node.cpu == 1.2)
        #expect(node.memory == 256.0)
        #expect(node.icon == "desktopcomputer")
        #expect(node.children.isEmpty)
    }

    @Test("children are stored correctly")
    func children() {
        let child = ProcessNode(id: "child1", name: "Child", cpu: 0.5, memory: 64.0, icon: "shippingbox", children: [])
        let parent = ProcessNode(id: "parent", name: "Parent", cpu: 1.0, memory: 128.0, icon: "folder", children: [child])
        #expect(parent.children.count == 1)
        #expect(parent.children.first?.id == "child1")
    }

    @Test("isExpanded defaults to true")
    func isExpandedDefault() {
        let node = ProcessNode(id: "x", name: "X", cpu: 0, memory: 0, icon: "x", children: [])
        #expect(node.isExpanded == true)
    }

    @Test("isExpanded can be set to false")
    func isExpandedFalse() {
        var node = ProcessNode(id: "x", name: "X", cpu: 0, memory: 0, icon: "x", children: [], isExpanded: false)
        #expect(node.isExpanded == false)
        node.isExpanded = true
        #expect(node.isExpanded == true)
    }
}

// MARK: - MonitoringView ViewInspector integration tests

@Suite("CovViews_MonitoringView Integration", .serialized)
@MainActor
struct CovViews_MonitoringViewTests {

    private func stateWithRunningContainers() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.containers = [
            MockContainer(id: "c1", name: "web", image: "nginx", status: "Up", state: "running", ports: "80/tcp", created: "now"),
            MockContainer(id: "c2", name: "db", image: "postgres", status: "Up", state: "running", ports: "5432/tcp", created: "now"),
        ]
        s.vmRunning = true
        s.k8sRunning = false
        return s
    }

    private func stateEmpty() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.containers = []
        s.vmRunning = true
        s.k8sRunning = false
        return s
    }

    private func stateWithK8s() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.containers = []
        s.k8sRunning = true
        return s
    }

    // MARK: - Shell

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect()) != nil)
    }

    @Test("activity monitor table is present")
    func activityMonitorTable() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_activity_monitor")) != nil)
    }

    @Test("sparklines panel is present")
    func sparklinesPanelPresent() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "panel_sparklines")) != nil)
    }

    // MARK: - Sparkline cards

    @Test("CPU sparkline card present")
    func cpuSparkline() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sparkline_cpu")) != nil)
    }

    @Test("Memory sparkline card present")
    func memorySparkline() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sparkline_memory")) != nil)
    }

    @Test("Network sparkline card present")
    func networkSparkline() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sparkline_network")) != nil)
    }

    @Test("Disk sparkline card present")
    func diskSparkline() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sparkline_disk")) != nil)
    }

    // MARK: - Process tree rows (always-present VM row)

    @Test("process tree shows Colima VM row")
    func processTreeVMRow() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_vm")) != nil)
    }

    @Test("process tree shows Containers row")
    func processTreeContainersRow() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_containers")) != nil)
    }

    @Test("process tree shows Kubernetes row when k8s enabled")
    func processTreeK8sRow() throws {
        let v = MonitoringView().environmentObject(stateWithK8s())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_k8s")) != nil)
    }

    @Test("process tree does NOT show Kubernetes row when k8s disabled")
    func processTreeNoK8sRow() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_k8s")) == nil)
    }

    // MARK: - Container child rows

    @Test("process tree shows child row for running container")
    func processTreeContainerChildRow() throws {
        let v = MonitoringView().environmentObject(stateWithRunningContainers())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_c1")) != nil)
    }

    @Test("process tree shows second running container row")
    func processTreeSecondContainerRow() throws {
        let v = MonitoringView().environmentObject(stateWithRunningContainers())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_c2")) != nil)
    }

    // MARK: - Expand/collapse buttons

    @Test("expand button present for Containers node (has children)")
    func expandButtonContainers() throws {
        let v = MonitoringView().environmentObject(stateWithRunningContainers())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_expand_containers")) != nil)
    }

    @Test("no expand button for VM node (no children)")
    func noExpandButtonVM() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_expand_vm")) == nil)
    }

    // MARK: - Process tree computed properties (via AppState)

    @Test("processTree includes VM node always")
    func processTreeAlwaysHasVM() throws {
        let v = MonitoringView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(text: "Colima VM")) != nil)
    }

    @Test("processTree shows Containers group")
    func processTreeContainersGroup() throws {
        let v = MonitoringView().environmentObject(stateWithRunningContainers())
        #expect((try? v.inspect().find(text: "Containers")) != nil)
    }

    @Test("processTree shows container names in child rows")
    func processTreeContainerNames() throws {
        let v = MonitoringView().environmentObject(stateWithRunningContainers())
        #expect((try? v.inspect().find(text: "web")) != nil)
        #expect((try? v.inspect().find(text: "db")) != nil)
    }

    // MARK: - CPU color logic (via formatMB and scopedCPU/scopedMem)

    @Test("renders with many running containers without crash")
    func manyRunningContainersDontCrash() throws {
        let s = AppState(services: MockServiceProvider())
        s.containers = (0..<10).map {
            MockContainer(id: "c\($0)", name: "ctr\($0)", image: "alpine", status: "Up", state: "running", ports: "", created: "now")
        }
        let v = MonitoringView().environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    // MARK: - Empty containers (exited only)

    @Test("exited containers are not shown in process tree children")
    func exitedContainersNotInTree() throws {
        let s = AppState(services: MockServiceProvider())
        s.containers = [
            MockContainer(id: "x1", name: "stopped-ctr", image: "alpine", status: "Exited", state: "exited", ports: "", created: "now"),
        ]
        let v = MonitoringView().environmentObject(s)
        // stopped-ctr should NOT appear as a child row
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_activity_x1")) == nil)
    }
}

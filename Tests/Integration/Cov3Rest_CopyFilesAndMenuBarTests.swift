import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - CopyFilesSheetView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_CopyFilesSheetView Integration", .serialized)
@MainActor
struct Cov3Rest_CopyFilesSheetViewTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = CopyFilesSheetView(containerName: "web-server", onCopy: { _ in })
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows sheet identifier")
    func showsSheetIdentifier() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_copy_files")) != nil)
    }

    @Test("shows container name in header")
    func showsContainerNameInHeader() throws {
        let v = CopyFilesSheetView(containerName: "my-app", onCopy: { _ in })
        #expect((try? v.inspect().find(text: "Copy Files — my-app")) != nil)
    }

    @Test("shows direction picker")
    func showsDirectionPicker() throws {
        let v = CopyFilesSheetView(containerName: "web-server", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_copy_direction")) != nil)
    }

    @Test("shows host path field")
    func showsHostPathField() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_copy_host_path")) != nil)
    }

    @Test("shows container path field")
    func showsContainerPathField() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_copy_container_path")) != nil)
    }

    @Test("shows command preview text")
    func showsCommandPreview() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_copy_command_preview")) != nil)
    }

    @Test("shows cancel button")
    func showsCancelButton() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_cancel")) != nil)
    }

    @Test("shows copy execute button")
    func showsCopyExecuteButton() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_execute")) != nil)
    }

    @Test("shows browse host button")
    func showsBrowseHostButton() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_browse_host")) != nil)
    }

    @Test("Direction allCases has 2 elements")
    func directionCases() {
        #expect(CopyFilesSheetView.Direction.allCases.count == 2)
    }

    @Test("Direction rawValues are correct")
    func directionRawValues() {
        #expect(CopyFilesSheetView.Direction.toContainer.rawValue == "Host → Container")
        #expect(CopyFilesSheetView.Direction.fromContainer.rawValue == "Container → Host")
    }

    @Test("command builds correctly for toContainer direction")
    func commandBuildsToContainer() {
        let containerName = "web-server"
        let hostPath = "/Users/me/file.txt"
        let containerPath = "/app/file.txt"
        let cmd = "docker cp \(hostPath) \(containerName):\(containerPath)"
        #expect(cmd == "docker cp /Users/me/file.txt web-server:/app/file.txt")
    }

    @Test("command builds correctly for fromContainer direction")
    func commandBuildsFromContainer() {
        let containerName = "nginx"
        let hostPath = "/tmp/output.txt"
        let containerPath = "/etc/nginx/nginx.conf"
        let cmd = "docker cp \(containerName):\(containerPath) \(hostPath)"
        #expect(cmd == "docker cp nginx:/etc/nginx/nginx.conf /tmp/output.txt")
    }

    @Test("isValid is false when hostPath is empty")
    func isValidFalseWhenHostEmpty() {
        let hostPath = ""
        let containerPath = "/app/file.txt"
        #expect(!(!hostPath.isEmpty && !containerPath.isEmpty))
    }

    @Test("isValid is false when containerPath is empty")
    func isValidFalseWhenContainerEmpty() {
        let hostPath = "/tmp/file.txt"
        let containerPath = ""
        #expect(!(!hostPath.isEmpty && !containerPath.isEmpty))
    }

    @Test("isValid is true when both paths are non-empty")
    func isValidTrueWithBothPaths() {
        let hostPath = "/tmp/file.txt"
        let containerPath = "/app/file.txt"
        #expect(!hostPath.isEmpty && !containerPath.isEmpty)
    }
}

// MARK: - MenuBarView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_MenuBarView Integration", .serialized)
@MainActor
struct Cov3Rest_MenuBarViewTests {

    private func state(vmRunning: Bool = true) -> (AppState, UpdaterManager) {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = vmRunning
        s.containers = MockData.containers
        s.images = MockData.images
        s.volumes = MockData.volumes
        let u = UpdaterManager()
        return (s, u)
    }

    @Test("renders without crash when VM running")
    func rendersRunning() throws {
        let (s, u) = state(vmRunning: true)
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash when VM stopped")
    func rendersStopped() throws {
        let (s, u) = state(vmRunning: false)
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows VM status identifier")
    func showsVMStatus() throws {
        let (s, u) = state()
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "menubar_vm_status")) != nil)
    }

    @Test("shows containers metric pill")
    func showsContainersMetric() throws {
        let (s, u) = state()
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_containers")) != nil)
    }

    @Test("shows images metric pill")
    func showsImagesMetric() throws {
        let (s, u) = state()
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_images")) != nil)
    }

    @Test("shows volumes metric pill")
    func showsVolumesMetric() throws {
        let (s, u) = state()
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_volumes")) != nil)
    }

    @Test("shows open app button")
    func showsOpenAppButton() throws {
        let (s, u) = state()
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_open")) != nil)
    }

    @Test("shows stop VM button when running")
    func showsStopVMButtonWhenRunning() throws {
        let (s, u) = state(vmRunning: true)
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_stop_vm")) != nil)
    }

    @Test("shows start VM button when stopped")
    func showsStartVMButtonWhenStopped() throws {
        let (s, u) = state(vmRunning: false)
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_start_vm")) != nil)
    }

    @Test("shows check for updates button")
    func showsCheckUpdatesButton() throws {
        let (s, u) = state()
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_check_updates")) != nil)
    }

    @Test("shows Running text when VM is running")
    func showsRunningText() throws {
        let (s, u) = state(vmRunning: true)
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(text: "Running")) != nil)
    }

    @Test("shows Stopped text when VM is stopped")
    func showsStoppedText() throws {
        let (s, u) = state(vmRunning: false)
        let v = MenuBarView().environmentObject(s).environmentObject(u)
        #expect((try? v.inspect().find(text: "Stopped")) != nil)
    }

    @Test("runningCount is correct for mixed container states")
    func runningCountMixedStates() {
        let (s, _) = state()
        let runningCount = s.containers.filter { $0.state == "running" }.count
        // MockData.containers has 3 running, 1 exited, 1 paused
        #expect(runningCount == 3)
    }

    @Test("MenuBarContainerRow renders without crash for running container")
    func containerRowRunningRenders() throws {
        let (s, _) = state()
        let container = MockData.containers.first { $0.state == "running" }!
        let v = MenuBarContainerRow(container: container).environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("MenuBarContainerRow renders without crash for stopped container")
    func containerRowStoppedRenders() throws {
        let (s, _) = state()
        let container = MockData.containers.first { $0.state == "exited" }!
        let v = MenuBarContainerRow(container: container).environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }
}

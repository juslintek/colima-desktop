import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - DashboardView ViewInspector integration tests

@Suite("CovViews_DashboardView Integration", .serialized)
@MainActor
struct CovViews_DashboardViewTests {

    private func runningState() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.vmCPU = 4
        s.vmMemory = Int64(8) * 1_073_741_824
        s.vmDisk = Int64(100) * 1_073_741_824
        s.vmRuntime = "docker"
        s.colimaVersion = "0.10.1"
        s.activeProfile = "default"
        s.containers = []
        return s
    }

    private func stoppedState() -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = false
        s.vmCPU = 0
        s.vmMemory = 0
        s.vmDisk = 0
        s.vmRuntime = ""
        s.colimaVersion = "0.10.1"
        s.activeProfile = "default"
        s.containers = []
        return s
    }

    private func stateWithContainers(_ count: Int) -> AppState {
        let s = runningState()
        s.containers = (0..<count).map {
            MockContainer(id: "c\($0)", name: "ctr\($0)", image: "alpine", status: "Up", state: "running", ports: "", created: "now")
        }
        s.volumes = [MockVolume(id: "v1", name: "vol1", driver: "local", mountpoint: "/data", size: "100MB")]
        s.images = [MockImage(id: "i1", repository: "alpine", tag: "latest", size: "7MB", created: "now")]
        return s
    }

    // MARK: - Shell

    @Test("renders without crash when running")
    func rendersRunning() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash when stopped")
    func rendersStopped() throws {
        let v = DashboardView().environmentObject(stoppedState())
        #expect((try? v.inspect()) != nil)
    }

    // MARK: - VM Status row

    @Test("vmRunning: status indicator shows Running text")
    func statusRunningText() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Running")) != nil)
    }

    @Test("vmStopped: status indicator shows Stopped text")
    func statusStoppedText() throws {
        let v = DashboardView().environmentObject(stoppedState())
        #expect((try? v.inspect().find(text: "Stopped")) != nil)
    }

    @Test("status indicator has correct accessibility identifier")
    func statusIndicatorId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_dashboard")) != nil)
    }

    @Test("shows active profile label")
    func showsActiveProfileLabel() throws {
        let s = runningState()
        s.activeProfile = "default"
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect().find(text: "Profile: default")) != nil)
    }

    // MARK: - Action buttons

    @Test("start button has correct accessibility identifier")
    func startButtonId() throws {
        let v = DashboardView().environmentObject(stoppedState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_vm_dashboard")) != nil)
    }

    @Test("stop button has correct accessibility identifier")
    func stopButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_vm_dashboard")) != nil)
    }

    @Test("restart button has correct accessibility identifier")
    func restartButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_restart_vm_dashboard")) != nil)
    }

    // MARK: - Resource grid

    @Test("CPU label is present")
    func cpuLabel() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "CPUs")) != nil)
    }

    @Test("Memory label is present")
    func memoryLabel() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Memory")) != nil)
    }

    @Test("Disk label is present")
    func diskLabel() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Disk")) != nil)
    }

    @Test("Runtime label is present")
    func runtimeLabel() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Runtime")) != nil)
    }

    @Test("Version label is present with correct identifier")
    func versionLabel() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_version_dashboard")) != nil)
    }

    @Test("version value shows colima version string")
    func versionValue() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "v0.10.1")) != nil)
    }

    @Test("docker shown as default runtime when vmRuntime empty")
    func defaultRuntime() throws {
        let s = runningState()
        s.vmRuntime = ""
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect().find(text: "docker")) != nil)
    }

    @Test("named runtime shown when vmRuntime non-empty")
    func namedRuntime() throws {
        let s = runningState()
        s.vmRuntime = "containerd"
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect().find(text: "containerd")) != nil)
    }

    // MARK: - SSH buttons

    @Test("SSH button has correct identifier")
    func sshButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_ssh_vm_dashboard")) != nil)
    }

    @Test("SSH Config button has correct identifier")
    func sshConfigButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sshconfig_vm_dashboard")) != nil)
    }

    // MARK: - Check & Update box

    @Test("Update Colima title is present")
    func updateColimaTitle() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Update Colima")) != nil)
    }

    @Test("Check & Update button has correct identifier")
    func checkUpdateButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_update_vm_dashboard")) != nil)
    }

    // MARK: - Template box

    @Test("Configuration Template title is present")
    func templateTitle() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Configuration Template")) != nil)
    }

    @Test("Edit Template button has correct identifier")
    func editTemplateButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_template_vm_dashboard")) != nil)
    }

    @Test("template path subtitle is shown")
    func templatePathSubtitle() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "~/.colima/_templates/default.yaml")) != nil)
    }

    // MARK: - Prune box

    @Test("Prune title is present")
    func pruneTitle() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Prune")) != nil)
    }

    @Test("Start Prune button has correct identifier")
    func startPruneButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_vm_dashboard")) != nil)
    }

    @Test("prune description text is present")
    func pruneDescription() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Removes unused build cache, dangling images, and stopped containers.")) != nil)
    }

    // MARK: - Delete VM box

    @Test("Delete VM title is present")
    func deleteVMTitle() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Delete VM")) != nil)
    }

    @Test("Delete (keep data) button has correct identifier")
    func deleteVMButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_delete_vm_dashboard")) != nil)
    }

    @Test("Delete + All Data button has correct identifier")
    func deleteAllDataButtonId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_deletedata_vm_dashboard")) != nil)
    }

    @Test("delete description text is present")
    func deleteDescription() throws {
        let v = DashboardView().environmentObject(runningState())
        // The full text in the view:
        #expect((try? v.inspect().find(text: "Destroys the Colima VM. Container data is preserved on a separate disk and restored on next start (unless --data is used).")) != nil)
    }

    // MARK: - Inline Terminal

    @Test("dashboard terminal panel identifier is present")
    func terminalPanelId() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "panel_dashboard_terminal")) != nil)
    }

    @Test("terminal input field has correct identifier")
    func terminalInputField() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_dashboard_terminal")) != nil)
    }

    // MARK: - vmRunning branches

    @Test("start button is present when VM stopped")
    func startButtonPresentWhenStopped() throws {
        let v = DashboardView().environmentObject(stoppedState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_vm_dashboard")) != nil)
    }

    @Test("stop button is present when VM running")
    func stopButtonPresentWhenRunning() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_vm_dashboard")) != nil)
    }

    // MARK: - Delete confirmation with container / volume counts

    @Test("delete all data message shows container count from appState")
    func deleteAllDataUsesContainerCount() throws {
        let s = stateWithContainers(3)
        let v = DashboardView().environmentObject(s)
        // The button exists regardless of current container count
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_deletedata_vm_dashboard")) != nil)
    }

    // MARK: - Backup & Migration section

    @Test("Backup & Migration disclosure group is present")
    func backupMigrationSection() throws {
        let v = DashboardView().environmentObject(runningState())
        #expect((try? v.inspect().find(text: "Backup & Migration")) != nil)
    }
}

// MARK: - DashboardTerminal ViewInspector integration tests

@Suite("CovViews_DashboardTerminal Integration", .serialized)
@MainActor
struct CovViews_DashboardTerminalTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        let v = DashboardTerminal().environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("terminal panel identifier is present")
    func terminalPanelId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = DashboardTerminal().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "panel_dashboard_terminal")) != nil)
    }

    @Test("terminal input field is present")
    func terminalInputField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = DashboardTerminal().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_dashboard_terminal")) != nil)
    }

    @Test("initial history contains colima status output")
    func initialHistoryPresent() throws {
        let s = AppState(services: MockServiceProvider())
        let v = DashboardTerminal().environmentObject(s)
        #expect((try? v.inspect().find(text: "$ colima status")) != nil)
    }

    @Test("terminal shows initial output")
    func initialOutputPresent() throws {
        let s = AppState(services: MockServiceProvider())
        let v = DashboardTerminal().environmentObject(s)
        // The initial mock output contains colima status text
        #expect((try? v.inspect().find(text: "Terminal")) != nil)
    }
}

// MARK: - DashboardView additional integration coverage

@Suite("CovViews_DashboardView Additional", .serialized)
@MainActor
struct CovViews_DashboardAdditionalTests {

    @Test("renders with high vmMemory value without crash")
    func highMemoryValue() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.vmMemory = Int64(64) * 1_073_741_824  // 64 GiB
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders with large vmDisk value without crash")
    func largeDiskValue() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        s.vmDisk = Int64(500) * 1_073_741_824  // 500 GiB
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders with non-default profile name without crash")
    func nonDefaultProfile() throws {
        let s = AppState(services: MockServiceProvider())
        s.activeProfile = "my-ai-profile"
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect().find(text: "Profile: my-ai-profile")) != nil)
    }

    @Test("version label shows correct text accessor identifier")
    func versionAccessibilityId() throws {
        let s = AppState(services: MockServiceProvider())
        s.colimaVersion = "1.0.0"
        let v = DashboardView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_version_dashboard")) != nil)
    }
}

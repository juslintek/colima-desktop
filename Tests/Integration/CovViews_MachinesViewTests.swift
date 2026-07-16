import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - MockVM unit tests

@Suite("CovViews_MockVM")
struct CovViews_MockVMTests {

    @Test("linux OS has correct icon")
    func linuxIcon() {
        #expect(MockVM.VMOS.linux.icon == "server.rack")
    }

    @Test("macos OS has correct icon")
    func macosIcon() {
        #expect(MockVM.VMOS.macos.icon == "apple.logo")
    }

    @Test("windows OS has correct icon")
    func windowsIcon() {
        #expect(MockVM.VMOS.windows.icon == "pc")
    }

    @Test("linux OS has orange color")
    func linuxColor() {
        #expect(MockVM.VMOS.linux.color == .orange)
    }

    @Test("macos OS has blue color")
    func macosColor() {
        #expect(MockVM.VMOS.macos.color == .blue)
    }

    @Test("windows OS has cyan color")
    func windowsColor() {
        #expect(MockVM.VMOS.windows.color == .cyan)
    }

    @Test("MockVM stores all fields correctly")
    func mockVMFields() {
        let vm = MockVM(id: "vm1", name: "dev-ubuntu", os: .linux, status: "running", cpus: 4, memory: 8, disk: 50, arch: "aarch64")
        #expect(vm.id == "vm1")
        #expect(vm.name == "dev-ubuntu")
        #expect(vm.os == .linux)
        #expect(vm.status == "running")
        #expect(vm.cpus == 4)
        #expect(vm.memory == 8)
        #expect(vm.disk == 50)
        #expect(vm.arch == "aarch64")
    }
}

// MARK: - MachinesView ViewInspector integration tests

@Suite("CovViews_MachinesView Integration", .serialized)
@MainActor
struct CovViews_MachinesViewTests {

    private func makeMachine(_ name: String, os: MockVM.VMOS = .linux, status: String = "running") -> MockVM {
        MockVM(id: name, name: name, os: os, status: status, cpus: 4, memory: 8, disk: 50, arch: "aarch64")
    }

    private func stateWithMachines(_ machines: [MockVM]) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.machines = machines
        return s
    }

    private func stateEmpty() -> AppState {
        stateWithMachines([])
    }

    // MARK: - Shell

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = MachinesView().environmentObject(stateEmpty())
        #expect((try? v.inspect()) != nil)
    }

    @Test("create machine button is present")
    func createMachineButton() throws {
        let v = MachinesView().environmentObject(stateEmpty())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_machine")) != nil)
    }

    // MARK: - VM list rows

    @Test("machine row appears for running machine")
    func machineRowRunning() throws {
        let v = MachinesView().environmentObject(stateWithMachines([makeMachine("dev-ubuntu")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_dev-ubuntu")) != nil)
    }

    @Test("machine row appears for stopped machine")
    func machineRowStopped() throws {
        let v = MachinesView().environmentObject(stateWithMachines([makeMachine("build-fedora", status: "stopped")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_build-fedora")) != nil)
    }

    @Test("multiple machines are all shown")
    func multipleMachinesShown() throws {
        let machines = [makeMachine("alpha"), makeMachine("beta"), makeMachine("gamma", os: .windows, status: "stopped")]
        let v = MachinesView().environmentObject(stateWithMachines(machines))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_alpha")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_beta")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_gamma")) != nil)
    }

    @Test("machine name appears in list")
    func machineNameVisible() throws {
        let v = MachinesView().environmentObject(stateWithMachines([makeMachine("my-vm")]))
        #expect((try? v.inspect().find(text: "my-vm")) != nil)
    }

    // MARK: - OS types

    @Test("linux machine row is present")
    func linuxMachineRow() throws {
        let v = MachinesView().environmentObject(stateWithMachines([makeMachine("linux-box", os: .linux)]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_linux-box")) != nil)
    }

    @Test("macos machine row is present")
    func macosMachineRow() throws {
        let v = MachinesView().environmentObject(stateWithMachines([makeMachine("mac-ci", os: .macos)]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_mac-ci")) != nil)
    }

    @Test("windows machine row is present")
    func windowsMachineRow() throws {
        let v = MachinesView().environmentObject(stateWithMachines([makeMachine("win-test", os: .windows, status: "stopped")]))
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_win-test")) != nil)
    }

    // MARK: - Filter (empty vs non-empty search)

    @Test("empty machines list renders without crash")
    func emptyMachinesList() throws {
        let v = MachinesView().environmentObject(stateEmpty())
        #expect((try? v.inspect()) != nil)
    }

    @Test("all machines from MockServiceProvider appear when populated")
    func allMockMachinesAppear() throws {
        let s = AppState(services: MockServiceProvider())
        s.machines = [
            makeMachine("dev-ubuntu"),
            makeMachine("build-fedora", status: "stopped"),
            makeMachine("macos-ci", os: .macos),
            makeMachine("win11-test", os: .windows, status: "stopped"),
        ]
        let v = MachinesView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_dev-ubuntu")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_build-fedora")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_macos-ci")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_machine_win11-test")) != nil)
    }
}

// MARK: - MachineDetailView ViewInspector integration tests

@Suite("CovViews_MachineDetailView Integration", .serialized)
@MainActor
struct CovViews_MachineDetailViewTests {

    private let runningVM = MockVM(id: "vm1", name: "dev-ubuntu", os: .linux, status: "running", cpus: 4, memory: 8, disk: 50, arch: "aarch64")
    private let stoppedVM = MockVM(id: "vm2", name: "stopped-vm", os: .windows, status: "stopped", cpus: 2, memory: 4, disk: 30, arch: "x86_64")

    // MARK: - Shell

    @Test("renders without crash for running VM")
    func rendersRunningVM() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash for stopped VM")
    func rendersStoppedVM() throws {
        let v = MachineDetailView(vm: stoppedVM)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows VM name in header")
    func showsVMName() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "dev-ubuntu")) != nil)
    }

    // MARK: - Running VM controls

    @Test("running VM shows Stop button")
    func runningVMStopButton() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(button: "Stop")) != nil)
    }

    @Test("running VM shows Restart button")
    func runningVMRestartButton() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(button: "Restart")) != nil)
    }

    @Test("stopped VM shows Start button")
    func stoppedVMStartButton() throws {
        let v = MachineDetailView(vm: stoppedVM)
        #expect((try? v.inspect().find(button: "Start")) != nil)
    }

    // MARK: - Info tab (default)

    @Test("info tab shows OS label")
    func infoTabOSLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "OS")) != nil)
    }

    @Test("info tab shows Architecture label")
    func infoTabArchLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Architecture")) != nil)
    }

    @Test("info tab shows Status label")
    func infoTabStatusLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Status")) != nil)
    }

    @Test("info tab shows CPUs label")
    func infoTabCPUsLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "CPUs")) != nil)
    }

    @Test("info tab shows Memory label")
    func infoTabMemoryLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Memory")) != nil)
    }

    @Test("info tab shows Disk label")
    func infoTabDiskLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Disk")) != nil)
    }

    @Test("info tab shows Network section")
    func infoTabNetworkSection() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Network")) != nil)
    }

    @Test("info tab shows IP label")
    func infoTabIPLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "IP")) != nil)
    }

    @Test("info tab shows SSH label")
    func infoTabSSHLabel() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "SSH")) != nil)
    }

    @Test("info tab shows correct arch value")
    func infoTabArchValue() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "aarch64")) != nil)
    }

    @Test("info tab shows correct cpus value")
    func infoTabCPUsValue() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "4 cores")) != nil)
    }

    @Test("info tab shows correct memory value")
    func infoTabMemoryValue() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "8 GiB")) != nil)
    }

    @Test("info tab shows correct disk value")
    func infoTabDiskValue() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "50 GiB")) != nil)
    }

    // MARK: - Tab segmented picker

    @Test("Info tab picker item is present")
    func infoTabPickerItem() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Info")) != nil)
    }

    @Test("Stats tab picker item is present")
    func statsTabPickerItem() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Stats")) != nil)
    }

    @Test("Logs tab picker item is present")
    func logsTabPickerItem() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Logs")) != nil)
    }

    @Test("Terminal tab picker item is present")
    func terminalTabPickerItem() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Terminal")) != nil)
    }

    @Test("Files tab picker item is present")
    func filesTabPickerItem() throws {
        let v = MachineDetailView(vm: runningVM)
        #expect((try? v.inspect().find(text: "Files")) != nil)
    }
}

// MARK: - CreateMachineSheet ViewInspector integration tests

@Suite("CovViews_CreateMachineSheet Integration", .serialized)
@MainActor
struct CovViews_CreateMachineSheetTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows Create Machine title")
    func showsTitle() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "Create Machine")) != nil)
    }

    @Test("shows Cancel button")
    func cancelButton() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(button: "Cancel")) != nil)
    }

    @Test("shows Create button")
    func createButton() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(button: "Create")) != nil)
    }

    @Test("shows Operating System section")
    func osSectionPresent() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "Operating System")) != nil)
    }

    @Test("shows Name section")
    func nameSectionPresent() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "Name")) != nil)
    }

    @Test("shows Resources section")
    func resourcesSectionPresent() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "Resources")) != nil)
    }

    @Test("shows Linux picker option")
    func linuxOption() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "Linux")) != nil)
    }

    @Test("shows macOS picker option")
    func macosOption() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "macOS")) != nil)
    }

    @Test("shows Windows picker option")
    func windowsOption() throws {
        let v = CreateMachineSheet()
        #expect((try? v.inspect().find(text: "Windows")) != nil)
    }
}

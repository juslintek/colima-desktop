import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

/// Logic tests for the MenuBarExtra status menu. XCUITest can't drive the macOS
/// menu-bar extra, so we validate its bindings to AppState via ViewInspector.
@Suite("MenuBar Status Menu", .serialized)
@MainActor
struct MenuBarViewTests {

    private func state(vmRunning: Bool, containers: [MockContainer] = [], images: Int = 0, volumes: Int = 0) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = vmRunning
        s.containers = containers
        s.images = (0..<images).map { MockImage(id: "i\($0)", repository: "r\($0)", tag: "latest", size: "1MB", created: "now") }
        s.volumes = (0..<volumes).map { MockVolume(id: "v\($0)", name: "vol\($0)", driver: "local", mountpoint: "/m", size: "0B") }
        return s
    }

    /// Build the menu with both required environment objects (UpdaterManager stays
    /// dormant in tests: no SUPublicEDKey in the test bundle, so it never starts).
    @ViewBuilder private func menu(_ s: AppState) -> some View {
        MenuBarView().environmentObject(s).environmentObject(UpdaterManager())
    }

    private func running(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "alpine", status: "Up", state: "running", ports: "", created: "now")
    }
    private func stopped(_ name: String) -> MockContainer {
        MockContainer(id: name, name: name, image: "alpine", status: "Exited", state: "exited", ports: "", created: "now")
    }

    @Test("shows Running and a Stop button when the VM is up")
    func runningState() throws {
        let view = menu(state(vmRunning: true))
        let status = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_vm_status")
        #expect(try status.text().string() == "Running")
        #expect((try? view.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_stop_vm")) != nil)
    }

    @Test("shows Stopped and a Start button when the VM is down")
    func stoppedState() throws {
        let view = menu(state(vmRunning: false))
        let status = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_vm_status")
        #expect(try status.text().string() == "Stopped")
        #expect((try? view.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_start_vm")) != nil)
    }

    @Test("running-container metric counts only running containers")
    func runningCountMetric() throws {
        let s = state(vmRunning: true, containers: [running("a"), running("b"), stopped("c")])
        let view = menu(s)
        let pill = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_containers")
        // The pill combines icon + value + label; the running count (2) must appear.
        #expect(try pill.find(text: "2").string() == "2")
    }

    @Test("lists container names in the menu")
    func listsContainers() throws {
        let s = state(vmRunning: true, containers: [running("web"), stopped("db")])
        let view = menu(s)
        #expect((try? view.inspect().find(text: "web")) != nil)
        #expect((try? view.inspect().find(text: "db")) != nil)
    }

    @Test("Open Colima Desktop action is always present")
    func openButtonPresent() throws {
        let view = menu(state(vmRunning: true))
        #expect((try? view.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_open")) != nil)
    }

    @Test("zero state shows 0 running containers and the Start button")
    func zeroState() throws {
        let view = menu(state(vmRunning: false))
        let pill = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_containers")
        #expect(try pill.find(text: "0").string() == "0")
        #expect((try? view.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_start_vm")) != nil)
        // No Stop button while stopped.
        #expect((try? view.inspect().find(viewWithAccessibilityIdentifier: "btn_menubar_stop_vm")) == nil)
    }

    @Test("more than five containers shows an overflow summary line")
    func overflowSummary() throws {
        let many = (0..<8).map { running("ctr\($0)") }
        let view = menu(state(vmRunning: true, containers: many))
        // 8 containers → "3 more..." (shows first 5).
        #expect((try? view.inspect().find(text: "3 more...")) != nil)
    }

    @Test("image and volume counters reflect AppState")
    func counters() throws {
        let view = menu(state(vmRunning: true, images: 4, volumes: 2))
        let imgPill = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_images")
        #expect(try imgPill.find(text: "4").string() == "4")
        let volPill = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_metric_volumes")
        #expect(try volPill.find(text: "2").string() == "2")
    }

    // NOTE (documented gap, not invented): MenuBarView models VM state as a single
    // Bool (running/stopped). It has no distinct "installing / starting / stopping /
    // error / unknown" menu states today, and the install-prompt lives in ContentView,
    // not the menu. When Colima is missing, the menu simply shows "Stopped". Asserting
    // richer menu states would require implementing them first — tracked in
    // docs/e2e-real-mode-execution.md (coverage gaps).
    @Test("when Colima is not installed the menu shows Stopped (current behavior)")
    func notInstalledShowsStopped() throws {
        let s = state(vmRunning: false)
        s.colimaInstalled = false
        let view = menu(s)
        let status = try view.inspect().find(viewWithAccessibilityIdentifier: "menubar_vm_status")
        #expect(try status.text().string() == "Stopped")
    }
}

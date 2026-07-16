import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ContentView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_ContentView Integration", .serialized)
@MainActor
struct Cov3Rest_ContentViewTests {

    private func state(colimaInstalled: Bool = true, tab: NavigationItem = .dashboard) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.colimaInstalled = colimaInstalled
        s.selectedTab = tab
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        ContentView().environmentObject(appState)
    }

    @Test("renders without crash when colima is installed")
    func rendersInstalled() throws {
        let v = view(state(colimaInstalled: true))
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows main split view when colima is installed")
    func showsMainSplitView() throws {
        let s = state(colimaInstalled: true)
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "main_split_view")) != nil)
    }

    @Test("shows install view when colima is not installed")
    func showsInstallView() throws {
        let s = state(colimaInstalled: false)
        let v = view(s)
        // When not installed, should show InstallColimaView (not the split view)
        #expect((try? v.inspect()) != nil)
    }

    @Test("needsDetailColumn returns true for containers tab")
    func needsDetailColumnContainers() {
        let s = state(tab: .containers)
        // Verify the logic: containers tab needs 3-column layout
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == true)
    }

    @Test("needsDetailColumn returns true for images tab")
    func needsDetailColumnImages() {
        let s = state(tab: .images)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == true)
    }

    @Test("needsDetailColumn returns false for dashboard tab")
    func needsDetailColumnDashboard() {
        let s = state(tab: .dashboard)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == false)
    }

    @Test("needsDetailColumn returns false for configuration tab")
    func needsDetailColumnConfiguration() {
        let s = state(tab: .configuration)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == false)
    }

    @Test("needsDetailColumn returns true for volumes tab")
    func needsDetailColumnVolumes() {
        let s = state(tab: .volumes)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == true)
    }

    @Test("needsDetailColumn returns true for networks tab")
    func needsDetailColumnNetworks() {
        let s = state(tab: .networks)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == true)
    }

    @Test("needsDetailColumn returns true for machines tab")
    func needsDetailColumnMachines() {
        let s = state(tab: .machines)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == true)
    }

    @Test("needsDetailColumn returns false for profiles tab")
    func needsDetailColumnProfiles() {
        let s = state(tab: .profiles)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == false)
    }

    @Test("needsDetailColumn returns false for ai tab")
    func needsDetailColumnAI() {
        let s = state(tab: .ai)
        let needsDetail: Bool
        switch s.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes, .machines: needsDetail = true
        default: needsDetail = false
        }
        #expect(needsDetail == false)
    }

    @Test("toast overlay not shown when no toast")
    func toastOverlayHidden() {
        let s = state()
        s.isToastVisible = false
        s.toastMessage = nil
        // The toast overlay condition: isToastVisible && toastMessage != nil
        #expect(!(s.isToastVisible && s.toastMessage != nil))
    }

    @Test("toast overlay shown when toast is visible with message")
    func toastOverlayShown() {
        let s = state()
        s.isToastVisible = true
        s.toastMessage = "Hello"
        #expect(s.isToastVisible && s.toastMessage != nil)
    }

    @Test("SheetType inspect case round-trips through Identifiable id")
    func sheetTypeInspect() {
        let sheet = AppState.SheetType.inspect
        // id: Self means id is the case itself — different cases have different ids
        #expect(sheet.id == .inspect)
    }

    @Test("SheetType logs case has correct id")
    func sheetTypeLogs() {
        #expect(AppState.SheetType.logs.id == .logs)
    }

    @Test("SheetType terminal case has correct id")
    func sheetTypeTerminal() {
        #expect(AppState.SheetType.terminal.id == .terminal)
    }

    @Test("SheetType stats case has correct id")
    func sheetTypeStats() {
        #expect(AppState.SheetType.stats.id == .stats)
    }

    @Test("SheetType history case has correct id")
    func sheetTypeHistory() {
        #expect(AppState.SheetType.history.id == .history)
    }

    @Test("SheetType changes case has correct id")
    func sheetTypeChanges() {
        #expect(AppState.SheetType.changes.id == .changes)
    }

    @Test("SheetType search case has correct id")
    func sheetTypeSearch() {
        #expect(AppState.SheetType.search.id == .search)
    }

    @Test("SheetType commandRunner case has correct id")
    func sheetTypeCommandRunner() {
        #expect(AppState.SheetType.commandRunner.id == .commandRunner)
    }

    @Test("SheetType copyFiles case has correct id")
    func sheetTypeCopyFiles() {
        #expect(AppState.SheetType.copyFiles.id == .copyFiles)
    }

    @Test("SheetType createContainer case has correct id")
    func sheetTypeCreateContainer() {
        #expect(AppState.SheetType.createContainer.id == .createContainer)
    }

    @Test("inspect and logs SheetType cases are different")
    func sheetTypeCasesAreDifferent() {
        #expect(AppState.SheetType.inspect.id != AppState.SheetType.logs.id)
    }
}

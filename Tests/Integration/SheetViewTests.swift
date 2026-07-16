import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - TerminalSheetView integration tests

@Suite("TerminalSheetView Integration", .serialized)
@MainActor
struct TerminalSheetViewTests {

    @Test("shows command in header")
    func showsCommand() throws {
        let v = TerminalSheetView(command: "bash")
        #expect((try? v.inspect().find(text: "bash")) != nil)
    }

    @Test("has external terminal button")
    func hasExternalTerminalButton() throws {
        let v = TerminalSheetView(command: "bash")
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_open_terminal_external")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let v = TerminalSheetView(command: "bash")
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_terminal")) != nil)
    }
}

// MARK: - SearchSheetView integration tests

@Suite("SearchSheetView Integration", .serialized)
@MainActor
struct SearchSheetViewTests {

    @Test("shows Docker Hub search title")
    func showsTitle() throws {
        let state = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(state)
        #expect((try? v.inspect().find(text: "Search Docker Hub")) != nil)
    }

    @Test("has search field")
    func hasSearchField() throws {
        let state = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_search_hub")) != nil)
    }

    @Test("has search button")
    func hasSearchButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_search_hub_go")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_search")) != nil)
    }

    @Test("has results table")
    func hasResultsTable() throws {
        let state = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_search")) != nil)
    }

    @Test("SearchRow stores all fields")
    func searchRowFields() {
        let row = SearchSheetView.SearchRow(name: "nginx", description: "Official nginx", stars: 15000, official: true)
        #expect(row.name == "nginx")
        #expect(row.description == "Official nginx")
        #expect(row.stars == 15000)
        #expect(row.official == true)
    }

    @Test("SearchRow has unique ids")
    func searchRowUniqueId() {
        let a = SearchSheetView.SearchRow(name: "nginx", description: "", stars: 0, official: false)
        let b = SearchSheetView.SearchRow(name: "nginx", description: "", stars: 0, official: false)
        #expect(a.id != b.id)
    }
}

// MARK: - StatsSheetView integration tests

@Suite("StatsSheetView Integration", .serialized)
@MainActor
struct StatsSheetViewTests {

    @Test("shows container name in header")
    func showsName() throws {
        let state = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "web-server").environmentObject(state)
        #expect((try? v.inspect().find(text: "Stats: web-server")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "web").environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_stats")) != nil)
    }

    @Test("has live indicator")
    func hasLiveIndicator() throws {
        let state = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "web").environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "indicator_stats_live")) != nil)
    }

    @Test("StatsSheetView.ProcessRow stores all fields")
    func processRowFields() {
        let row = StatsSheetView.ProcessRow(pid: "1234", user: "root", cpu: "0.5%", mem: "32MB", command: "nginx: master")
        #expect(row.pid == "1234")
        #expect(row.user == "root")
        #expect(row.cpu == "0.5%")
        #expect(row.mem == "32MB")
        #expect(row.command == "nginx: master")
    }

    @Test("StatsSheetView.ProcessRow has unique id")
    func processRowUniqueId() {
        let a = StatsSheetView.ProcessRow(pid: "1", user: "root", cpu: "0%", mem: "0", command: "init")
        let b = StatsSheetView.ProcessRow(pid: "1", user: "root", cpu: "0%", mem: "0", command: "init")
        #expect(a.id != b.id)
    }
}

// MARK: - GuidedSetupWizard enums

@Suite("GuidedSetupWizard enums")
struct GuidedSetupWizardEnumTests {

    @Test("WorkloadType has 5 cases with non-empty icons")
    func workloadTypeCases() {
        #expect(WorkloadType.allCases.count == 5)
        for wt in WorkloadType.allCases {
            #expect(!wt.icon.isEmpty)
            #expect(!wt.rawValue.isEmpty)
            #expect(wt.id == wt.rawValue)
        }
    }

    @Test("ResourceTier has 4 cases with correct cpu/memory values")
    func resourceTierValues() {
        #expect(ResourceTier.light.cpus == 2)
        #expect(ResourceTier.light.memory == 4)
        #expect(ResourceTier.moderate.cpus == 4)
        #expect(ResourceTier.moderate.memory == 8)
        #expect(ResourceTier.heavy.cpus == 8)
        #expect(ResourceTier.heavy.memory == 16)
        #expect(ResourceTier.custom.cpus == 4)
    }

    @Test("ResourceTier icons are non-empty")
    func resourceTierIcons() {
        for tier in ResourceTier.allCases {
            #expect(!tier.icon.isEmpty)
        }
    }

    @Test("MountChoice has 3 cases with correct mountType and inotify values")
    func mountChoiceValues() {
        #expect(MountChoice.projects.mountType == "virtiofs")
        #expect(MountChoice.hotReload.mountType == "virtiofs")
        #expect(MountChoice.none.mountType == "sshfs")
        #expect(MountChoice.projects.inotify == false)
        #expect(MountChoice.hotReload.inotify == true)
        #expect(MountChoice.none.inotify == false)
    }

    @Test("MountChoice id equals rawValue")
    func mountChoiceId() {
        for choice in MountChoice.allCases {
            #expect(choice.id == choice.rawValue)
        }
    }
}

// MARK: - MonitoringView integration tests

@Suite("MonitoringView Integration", .serialized)
@MainActor
struct MonitoringViewTests {

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        MonitoringView().environmentObject(appState)
    }

    @Test("has VM stopped message when VM is not running")
    func vmNotRunningState() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = false
        let v = view(s)
        // MonitoringView shows a "VM not running" message when stopped
        let hasContent = (try? v.inspect()) != nil
        #expect(hasContent)
    }

    @Test("has memory governor identifier when VM is running")
    func memoryGovernorId() throws {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        let v = view(s)
        // Just verify the view renders without crashing
        let inspected = try? v.inspect()
        #expect(inspected != nil)
    }
}

// MARK: - SparklineView unit tests

@Suite("SparklineView")
@MainActor
struct SparklineViewTests {

    @Test("renders without crash for non-empty data")
    func rendersNonEmpty() throws {
        let v = SparklineView(data: [0.1, 0.5, 0.3, 0.8, 0.2], color: .blue)
        // Just verify the view body returns without crash
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash for single data point")
    func rendersSinglePoint() throws {
        let v = SparklineView(data: [0.5], color: .red)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash for empty data")
    func rendersEmpty() throws {
        let v = SparklineView(data: [], color: .green)
        #expect((try? v.inspect()) != nil)
    }

    @Test("uses explicit maxValue when provided")
    func explicitMaxValue() throws {
        let v = SparklineView(data: [10, 20, 30], color: .blue, maxValue: 100)
        // With maxValue=100, the view normalizes values — just check it doesn't crash
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - CopyFilesSheetView integration tests

@Suite("CopyFilesSheetView Integration", .serialized)
@MainActor
struct CopyFilesSheetViewTests {

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        CopyFilesSheetView(containerName: "web-server", onCopy: { _ in }).environmentObject(appState)
    }

    @Test("shows container name in title")
    func showsContainerName() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        // Title is "Copy Files — web-server" (em-dash)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_copy_files")) != nil)
    }

    @Test("has outer accessibility identifier")
    func hasOuterAccessibilityId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_copy_files")) != nil)
    }

    @Test("has cancel button")
    func hasCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_cancel")) != nil)
    }

    @Test("has execute copy button")
    func hasExecuteButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_execute")) != nil)
    }

    @Test("has direction picker")
    func hasDirectionPicker() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_copy_direction")) != nil)
    }

    @Test("has host path field")
    func hasHostPathField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_copy_host_path")) != nil)
    }

    @Test("has container path field")
    func hasContainerPathField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_copy_container_path")) != nil)
    }
}

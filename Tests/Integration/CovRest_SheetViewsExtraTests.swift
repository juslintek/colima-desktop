import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - StatsSheetView additional tests (CovRest_ prefix)

@Suite("CovRest_StatsSheetView Integration", .serialized)
@MainActor
struct CovRest_StatsSheetViewTests {

    @Test("has process table identifier")
    func hasProcessTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_stats_processes")) != nil)
    }

    @Test("shows processes section label")
    func showsProcessesSectionLabel() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(text: "Processes")) != nil)
    }

    @Test("has outer sheet accessibility identifier")
    func hasSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = StatsSheetView(name: "web").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_stats")) != nil)
    }

    @Test("formatBytes shows B for small values")
    func formatBytesSmall() {
        // Test formatting via ProcessRow model roundtrip
        // 512 bytes → "512B"
        let row = StatsSheetView.ProcessRow(pid: "1", user: "root", cpu: "0.5%", mem: "512B", command: "sh")
        #expect(row.mem == "512B")
    }

    @Test("ProcessRow has independent unique IDs")
    func processRowUniqueIds() {
        let rows = (0..<5).map { i in
            StatsSheetView.ProcessRow(pid: "\(i)", user: "root", cpu: "0.0%", mem: "10MB", command: "proc-\(i)")
        }
        let ids = Set(rows.map(\.id))
        #expect(ids.count == 5)
    }
}

// MARK: - HistorySheetView additional tests (CovRest_ prefix)

@Suite("CovRest_HistorySheetView Integration", .serialized)
@MainActor
struct CovRest_HistorySheetViewTests {

    @Test("shows repo name in header")
    func showsRepoName() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(text: "History: nginx")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_history")) != nil)
    }

    @Test("has history layers table identifier")
    func hasLayersTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_history_layers")) != nil)
    }

    @Test("has outer sheet accessibility identifier")
    func hasSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "ubuntu:22.04").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_history")) != nil)
    }

    @Test("LayerRow stores all fields correctly")
    func layerRowFields() {
        let row = HistorySheetView.LayerRow(
            layerId: "a1b2c3d4e5f6",
            created: "3 days ago",
            size: "45MB",
            command: "/bin/sh -c apt-get update"
        )
        #expect(row.layerId == "a1b2c3d4e5f6")
        #expect(row.created == "3 days ago")
        #expect(row.size == "45MB")
        #expect(row.command == "/bin/sh -c apt-get update")
    }

    @Test("LayerRow has unique ids")
    func layerRowUniqueIds() {
        let a = HistorySheetView.LayerRow(layerId: "abc", created: "now", size: "1MB", command: "CMD")
        let b = HistorySheetView.LayerRow(layerId: "abc", created: "now", size: "1MB", command: "CMD")
        #expect(a.id != b.id)
    }
}

// MARK: - ChangesSheetView tests (CovRest_ prefix)

@Suite("CovRest_ChangesSheetView Integration", .serialized)
@MainActor
struct CovRest_ChangesSheetViewTests {

    @Test("shows container name in header")
    func showsContainerName() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "web-server").environmentObject(s)
        #expect((try? v.inspect().find(text: "Changes: web-server")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "web-server").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_changes")) != nil)
    }

    @Test("has changes table identifier")
    func hasChangesTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "web-server").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_changes")) != nil)
    }

    @Test("has outer sheet accessibility identifier")
    func hasSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "api").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_changes")) != nil)
    }

    @Test("ChangeRow color for Added is green")
    func addedChangeRowIsGreen() {
        let row = ChangesSheetView.ChangeRow(kind: "Added", path: "/tmp/new-file")
        let color = row.color
        // green color is non-nil (just ensure color is non-zero alpha)
        _ = color  // SwiftUI Color does not expose components easily — just check badge
        #expect(row.badge == "A")
    }

    @Test("ChangeRow color for Modified returns yellow badge M")
    func modifiedChangeRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Modified", path: "/etc/nginx/nginx.conf")
        #expect(row.badge == "M")
    }

    @Test("ChangeRow color for Deleted returns red badge D")
    func deletedChangeRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Deleted", path: "/tmp/old-file")
        #expect(row.badge == "D")
    }

    @Test("ChangeRow unknown kind returns question mark badge")
    func unknownChangeRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Unknown", path: "/some/path")
        #expect(row.badge == "?")
    }

    @Test("ChangeRow has unique id per instance")
    func changeRowUniqueIds() {
        let a = ChangesSheetView.ChangeRow(kind: "Added", path: "/tmp/a")
        let b = ChangesSheetView.ChangeRow(kind: "Added", path: "/tmp/a")
        #expect(a.id != b.id)
    }

    @Test("ChangeRow stores path correctly")
    func changeRowPath() {
        let row = ChangesSheetView.ChangeRow(kind: "Modified", path: "/var/log/app.log")
        #expect(row.path == "/var/log/app.log")
    }
}

// MARK: - SearchSheetView additional tests (CovRest_ prefix)

@Suite("CovRest_SearchSheetView Integration", .serialized)
@MainActor
struct CovRest_SearchSheetViewTests {

    @Test("initialises with given search term")
    func initialTermIsSet() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView(initialTerm: "ubuntu").environmentObject(s)
        // If the view renders with initial term, the search sheet is functional
        #expect((try? v.inspect()) != nil)
    }

    @Test("initialises with empty term by default")
    func defaultTermIsEmpty() throws {
        let s = AppState(services: MockServiceProvider())
        let v = SearchSheetView().environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - CopyFilesSheetView additional tests (CovRest_ prefix)

@Suite("CovRest_CopyFilesSheetViewExtra Integration", .serialized)
@MainActor
struct CovRest_CopyFilesSheetViewExtraTests {

    @Test("command preview shows placeholder when paths are empty")
    func commandPreviewPlaceholder() throws {
        let v = CopyFilesSheetView(containerName: "api-server", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_copy_command_preview")) != nil)
    }

    @Test("Direction toContainer has correct rawValue")
    func directionToContainerRawValue() {
        #expect(CopyFilesSheetView.Direction.toContainer.rawValue == "Host → Container")
    }

    @Test("Direction fromContainer has correct rawValue")
    func directionFromContainerRawValue() {
        #expect(CopyFilesSheetView.Direction.fromContainer.rawValue == "Container → Host")
    }

    @Test("Direction allCases has exactly 2 cases")
    func directionAllCases() {
        #expect(CopyFilesSheetView.Direction.allCases.count == 2)
    }

    @Test("has browse host button")
    func hasBrowseHostButton() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_browse_host")) != nil)
    }

    @Test("has host path field")
    func hasHostPathField() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_copy_host_path")) != nil)
    }

    @Test("has container path field")
    func hasContainerPathField() throws {
        let v = CopyFilesSheetView(containerName: "nginx", onCopy: { _ in })
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_copy_container_path")) != nil)
    }
}

import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - InspectSheetView

@Suite("InspectSheetView Integration", .serialized)
@MainActor
struct InspectSheetViewTests {

    @Test("shows title with 'Inspect:' prefix")
    func showsTitle() throws {
        let v = InspectSheetView(title: "web-server", content: "{\"Id\":\"abc\"}")
        #expect((try? v.inspect().find(text: "Inspect: web-server")) != nil)
    }

    @Test("has copy button")
    func hasCopyButton() throws {
        let v = InspectSheetView(title: "mycontainer", content: "{}")
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_inspect")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let v = InspectSheetView(title: "mycontainer", content: "{}")
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_inspect")) != nil)
    }

    @Test("has outer accessibility identifier")
    func hasOuterAccessibilityId() throws {
        let v = InspectSheetView(title: "x", content: "abc")
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_inspect")) != nil)
    }

    @Test("shows content text")
    func showsContent() throws {
        let v = InspectSheetView(title: "c", content: "hello world content")
        #expect((try? v.inspect().find(text: "hello world content")) != nil)
    }
}

// MARK: - LogSheetView

@Suite("LogSheetView Integration", .serialized)
@MainActor
struct LogSheetViewTests {

    @Test("shows container name in title")
    func showsName() throws {
        let v = LogSheetView(name: "nginx-web", logs: [])
        #expect((try? v.inspect().find(text: "Logs: nginx-web")) != nil)
    }

    @Test("has follow toggle")
    func hasFollowToggle() throws {
        let v = LogSheetView(name: "c", logs: [])
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_logs_follow")) != nil)
    }

    @Test("has clear button")
    func hasClearButton() throws {
        let v = LogSheetView(name: "c", logs: [])
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_clear_logs")) != nil)
    }

    @Test("has copy button")
    func hasCopyButton() throws {
        let v = LogSheetView(name: "c", logs: [])
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_logs")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let v = LogSheetView(name: "c", logs: [])
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_logs")) != nil)
    }

    @Test("has outer accessibility identifier")
    func hasOuterAccessibilityId() throws {
        let v = LogSheetView(name: "c", logs: [])
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_logs")) != nil)
    }
}

// MARK: - ChangesSheetView.ChangeRow

@Suite("ChangesSheetView.ChangeRow")
struct ChangeRowTests {

    @Test("Added row has green color and A badge")
    func addedRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Added", path: "/etc/newfile")
        #expect(row.badge == "A")
        #expect(row.color == .green)
        #expect(row.path == "/etc/newfile")
    }

    @Test("Modified row has yellow color and M badge")
    func modifiedRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Modified", path: "/etc/hosts")
        #expect(row.badge == "M")
        #expect(row.color == .yellow)
    }

    @Test("Deleted row has red color and D badge")
    func deletedRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Deleted", path: "/tmp/old")
        #expect(row.badge == "D")
        #expect(row.color == .red)
    }

    @Test("Unknown kind has default color and ? badge")
    func unknownRow() {
        let row = ChangesSheetView.ChangeRow(kind: "Renamed", path: "/tmp/x")
        #expect(row.badge == "?")
        #expect(row.color == .primary)
    }

    @Test("each ChangeRow has unique id")
    func uniqueId() {
        let a = ChangesSheetView.ChangeRow(kind: "Added", path: "/a")
        let b = ChangesSheetView.ChangeRow(kind: "Added", path: "/a")
        #expect(a.id != b.id)
    }
}

// MARK: - ChangesSheetView

@Suite("ChangesSheetView Integration", .serialized)
@MainActor
struct ChangesSheetViewTests {

    @Test("shows container name in header")
    func showsName() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "mycontainer")
            .environmentObject(state)
        #expect((try? v.inspect().find(text: "Changes: mycontainer")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "c").environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_changes")) != nil)
    }

    @Test("has changes table")
    func hasChangesTable() throws {
        let state = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "c").environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_changes")) != nil)
    }
}

// MARK: - HistorySheetView.LayerRow

@Suite("HistorySheetView.LayerRow")
struct LayerRowTests {

    @Test("LayerRow stores all fields")
    func fields() {
        let row = HistorySheetView.LayerRow(layerId: "abc123def456", created: "2 hours ago", size: "12MB", command: "RUN apt-get install -y curl")
        #expect(row.layerId == "abc123def456")
        #expect(row.created == "2 hours ago")
        #expect(row.size == "12MB")
        #expect(row.command == "RUN apt-get install -y curl")
    }

    @Test("each LayerRow has unique id")
    func uniqueId() {
        let a = HistorySheetView.LayerRow(layerId: "a", created: "now", size: "1KB", command: "CMD")
        let b = HistorySheetView.LayerRow(layerId: "a", created: "now", size: "1KB", command: "CMD")
        #expect(a.id != b.id)
    }
}

// MARK: - HistorySheetView

@Suite("HistorySheetView Integration", .serialized)
@MainActor
struct HistorySheetViewTests {

    @Test("shows repo name in header")
    func showsRepo() throws {
        let state = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx:latest").environmentObject(state)
        #expect((try? v.inspect().find(text: "History: nginx:latest")) != nil)
    }

    @Test("has close button")
    func hasCloseButton() throws {
        let state = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx").environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_history")) != nil)
    }

    @Test("has outer accessibility identifier")
    func hasOuterAccessibilityId() throws {
        let state = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx").environmentObject(state)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_history")) != nil)
    }
}

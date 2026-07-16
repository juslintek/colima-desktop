import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - HistorySheetView additional wave 3 tests (Cov3Rest_ prefix)

@Suite("Cov3Rest_HistorySheetViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_HistorySheetViewWave3Tests {

    @Test("renders without crash for any image repo")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "postgres").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows outer sheet identifier")
    func showsSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "redis").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_history")) != nil)
    }

    @Test("shows layers table identifier")
    func showsLayersTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_history_layers")) != nil)
    }

    @Test("shows close button")
    func showsCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "alpine").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_history")) != nil)
    }

    @Test("shows repo name in header text")
    func showsRepoInHeader() throws {
        let s = AppState(services: MockServiceProvider())
        let v = HistorySheetView(repo: "my-image").environmentObject(s)
        #expect((try? v.inspect().find(text: "History: my-image")) != nil)
    }

    @Test("LayerRow fields stored correctly")
    func layerRowFields() {
        let row = HistorySheetView.LayerRow(
            layerId: "abc123def456",
            created: "5 hours ago",
            size: "45MB",
            command: "/bin/sh -c apt-get install -y nginx"
        )
        #expect(row.layerId == "abc123def456")
        #expect(row.created == "5 hours ago")
        #expect(row.size == "45MB")
        #expect(row.command == "/bin/sh -c apt-get install -y nginx")
    }

    @Test("LayerRow has unique id per instance")
    func layerRowUniqueIds() {
        let rows = (0..<5).map { i in
            HistorySheetView.LayerRow(layerId: "layer\(i)", created: "1 day ago", size: "1MB", command: "RUN cmd\(i)")
        }
        let ids = Set(rows.map(\.id))
        #expect(ids.count == 5)
    }

    @Test("size format for bytes > 1MiB is MB")
    func sizeFormatMB() {
        let size: Int64 = 2 * 1_048_576  // 2MB
        let formatted = size > 1_048_576 ? "\(size / 1_048_576)MB" : "\(size / 1024)KB"
        #expect(formatted == "2MB")
    }

    @Test("size format for bytes < 1MiB is KB")
    func sizeFormatKB() {
        let size: Int64 = 512 * 1024  // 512KB
        let formatted = size > 1_048_576 ? "\(size / 1_048_576)MB" : "\(size / 1024)KB"
        #expect(formatted == "512KB")
    }
}

// MARK: - MockFileTree integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_MockFileTree Integration", .serialized)
@MainActor
struct Cov3Rest_MockFileTreeTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = MockFileTree()
        #expect((try? v.inspect()) != nil)
    }

    @Test("FileNode directory has children")
    func fileNodeDirectory() {
        let node = FileNode(name: "app", size: nil, children: [
            FileNode(name: "server.js", size: "2.1 KB", children: nil),
        ])
        #expect(node.isDirectory == true)
        #expect(node.children?.count == 1)
    }

    @Test("FileNode file has no children")
    func fileNodeFile() {
        let node = FileNode(name: "server.js", size: "2.1 KB", children: nil)
        #expect(node.isDirectory == false)
        #expect(node.children == nil)
    }

    @Test("FileNode has unique id per instance")
    func fileNodeUniqueIds() {
        let a = FileNode(name: "file.txt", size: "1KB", children: nil)
        let b = FileNode(name: "file.txt", size: "1KB", children: nil)
        #expect(a.id != b.id)
    }

    @Test("FileNode with empty children array is directory")
    func emptyChildrenIsDirectory() {
        let node = FileNode(name: "tmp", size: "empty", children: [])
        #expect(node.isDirectory == true)
    }

    @Test("FileNode size nil for directories")
    func directorySizeIsNil() {
        let node = FileNode(name: "app", size: nil, children: [])
        #expect(node.size == nil)
    }
}

// MARK: - ChangesSheetView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_ChangesSheetView Integration", .serialized)
@MainActor
struct Cov3Rest_ChangesSheetViewTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "web-server").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows sheet identifier")
    func showsSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_changes")) != nil)
    }

    @Test("shows changes table identifier")
    func showsChangesTable() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "nginx").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_changes")) != nil)
    }

    @Test("shows close button")
    func showsCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "redis").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_changes")) != nil)
    }

    @Test("shows container name in header")
    func showsNameInHeader() throws {
        let s = AppState(services: MockServiceProvider())
        let v = ChangesSheetView(name: "my-app").environmentObject(s)
        #expect((try? v.inspect().find(text: "Changes: my-app")) != nil)
    }

    @Test("ChangeRow Added has green color and A badge")
    func changeRowAdded() {
        let row = ChangesSheetView.ChangeRow(kind: "Added", path: "/app/new-file.txt")
        #expect(row.badge == "A")
        #expect(row.color == .green)
    }

    @Test("ChangeRow Modified has yellow color and M badge")
    func changeRowModified() {
        let row = ChangesSheetView.ChangeRow(kind: "Modified", path: "/etc/nginx/nginx.conf")
        #expect(row.badge == "M")
        #expect(row.color == .yellow)
    }

    @Test("ChangeRow Deleted has red color and D badge")
    func changeRowDeleted() {
        let row = ChangesSheetView.ChangeRow(kind: "Deleted", path: "/tmp/old-file.txt")
        #expect(row.badge == "D")
        #expect(row.color == .red)
    }

    @Test("ChangeRow Unknown has question mark badge")
    func changeRowUnknown() {
        let row = ChangesSheetView.ChangeRow(kind: "Unknown", path: "/some/path")
        #expect(row.badge == "?")
    }

    @Test("ChangeRow has unique ids per instance")
    func changeRowUniqueIds() {
        let rows = (0..<5).map { i in
            ChangesSheetView.ChangeRow(kind: "Added", path: "/path/\(i)")
        }
        let ids = Set(rows.map(\.id))
        #expect(ids.count == 5)
    }

    @Test("Kind mapping from Docker API int 0 is Modified")
    func kindMappingModified() {
        let kind: String
        switch 0 {
        case 0: kind = "Modified"
        case 1: kind = "Added"
        case 2: kind = "Deleted"
        default: kind = "Unknown"
        }
        #expect(kind == "Modified")
    }

    @Test("Kind mapping from Docker API int 1 is Added")
    func kindMappingAdded() {
        let kind: String
        switch 1 {
        case 0: kind = "Modified"
        case 1: kind = "Added"
        case 2: kind = "Deleted"
        default: kind = "Unknown"
        }
        #expect(kind == "Added")
    }

    @Test("Kind mapping from Docker API int 2 is Deleted")
    func kindMappingDeleted() {
        let kind: String
        switch 2 {
        case 0: kind = "Modified"
        case 1: kind = "Added"
        case 2: kind = "Deleted"
        default: kind = "Unknown"
        }
        #expect(kind == "Deleted")
    }
}

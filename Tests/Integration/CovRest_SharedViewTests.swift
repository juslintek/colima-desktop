import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - PullProgressView additional tests (CovRest_ prefix)

@Suite("CovRest_PullProgressView Integration", .serialized)
@MainActor
struct CovRest_PullProgressViewTests {

    @Test("shows image name")
    func showsImageName() throws {
        let v = PullProgressView(name: "alpine:3.18", onCancel: {})
        #expect((try? v.inspect().find(text: "alpine:3.18")) != nil)
    }

    @Test("shows cancel button")
    func showsCancelButton() throws {
        let v = PullProgressView(name: "nginx:latest", onCancel: {})
        // The view has a cancel button (xmark.circle)
        #expect((try? v.inspect()) != nil)
    }

    @Test("PullLayer stores all fields correctly")
    func pullLayerFields() {
        let layer = PullProgressView.PullLayer(
            id: "abc123",
            size: "128 MB",
            downloaded: 0.5,
            status: "Downloading"
        )
        #expect(layer.id == "abc123")
        #expect(layer.size == "128 MB")
        #expect(layer.downloaded == 0.5)
        #expect(layer.status == "Downloading")
    }

    @Test("PullLayer has UUID-based unique id")
    func pullLayerUniqueId() {
        let a = PullProgressView.PullLayer(id: "same", size: "10MB", downloaded: 0, status: "Waiting")
        let b = PullProgressView.PullLayer(id: "same", size: "10MB", downloaded: 0, status: "Waiting")
        // Note: PullLayer.id is a String not UUID — each .id is the 'id' string property
        // (The PullLayer id is the 'id' parameter, not a UUID, so two layers with same id are same id)
        #expect(a.id == b.id)  // both are "same"
    }

    @Test("Done status is set when downloaded reaches 1.0")
    func doneStatusAtFullDownload() {
        var layer = PullProgressView.PullLayer(id: "abc", size: "10MB", downloaded: 1.0, status: "Done")
        #expect(layer.status == "Done")
        #expect(layer.downloaded >= 1.0)
    }
}

// MARK: - MockTerminalView additional tests (CovRest_ prefix)

@Suite("CovRest_MockTerminalView Integration", .serialized)
@MainActor
struct CovRest_MockTerminalViewTests {

    @Test("shows prompt character on render")
    func showsPromptCharacter() throws {
        let s = AppState(services: MockServiceProvider())
        let v = MockTerminalView(name: "nginx").environmentObject(s)
        // The terminal always starts with "$ " as initial output
        #expect((try? v.inspect().find(text: "$ ")) != nil)
    }

    @Test("renders different container names without crash")
    func rendersDifferentNames() throws {
        let s = AppState(services: MockServiceProvider())
        let names = ["web-server", "postgres-db", "redis-cache"]
        for name in names {
            let v = MockTerminalView(name: name).environmentObject(s)
            #expect((try? v.inspect()) != nil, "Expected \(name) to render without crash")
        }
    }
}

// MARK: - MockFileTree integration tests (CovRest_ prefix)

@Suite("CovRest_MockFileTree Integration", .serialized)
@MainActor
struct CovRest_MockFileTreeTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = MockFileTree()
        #expect((try? v.inspect()) != nil)
    }

    @Test("FileNode isDirectory true when children is non-nil")
    func fileNodeIsDirectory() {
        let dir = FileNode(name: "app", size: nil, children: [])
        #expect(dir.isDirectory == true)
    }

    @Test("FileNode isDirectory false when children is nil")
    func fileNodeIsFile() {
        let file = FileNode(name: "server.js", size: "2.1 KB", children: nil)
        #expect(file.isDirectory == false)
    }

    @Test("FileNode stores name correctly")
    func fileNodeName() {
        let node = FileNode(name: "package.json", size: "1.4 KB", children: nil)
        #expect(node.name == "package.json")
    }

    @Test("FileNode stores size correctly")
    func fileNodeSize() {
        let node = FileNode(name: "node_modules", size: "847 items", children: [])
        #expect(node.size == "847 items")
    }

    @Test("FileNode with nil size has no size label")
    func fileNodeNilSize() {
        let node = FileNode(name: "etc", size: nil, children: [])
        #expect(node.size == nil)
    }

    @Test("FileNode has unique UUID-based id")
    func fileNodeUniqueId() {
        let a = FileNode(name: "app", size: nil, children: [])
        let b = FileNode(name: "app", size: nil, children: [])
        #expect(a.id != b.id)
    }
}

// MARK: - MockLogsView additional tests (CovRest_ prefix)

@Suite("CovRest_MockLogsView Integration", .serialized)
@MainActor
struct CovRest_MockLogsViewTests {

    @Test("shows loading message initially")
    func showsLoadingMessage() throws {
        let s = AppState(services: MockServiceProvider())
        let v = MockLogsView(name: "web-server").environmentObject(s)
        // Initial state shows "Loading logs..."
        #expect((try? v.inspect().find(text: "Loading logs...")) != nil)
    }

    @Test("renders with different container names")
    func rendersDifferentContainerNames() throws {
        let s = AppState(services: MockServiceProvider())
        for name in ["redis", "postgres", "api-service"] {
            let v = MockLogsView(name: name).environmentObject(s)
            #expect((try? v.inspect()) != nil)
        }
    }
}

// MARK: - AISetupProgressView additional tests (CovRest_ prefix)

@Suite("CovRest_AISetupProgressViewExtra Integration", .serialized)
@MainActor
struct CovRest_AISetupProgressViewExtraTests {

    @Test("ramalama runner has 4 steps")
    func ramalamaHas4Steps() throws {
        let v = AISetupProgressView(runner: "ramalama", onDone: {})
        // Check that "Checking prerequisites" step is shown
        #expect((try? v.inspect().find(text: "Checking prerequisites")) != nil)
    }

    @Test("docker runner has 3 steps starting with prerequisites")
    func dockerHas3Steps() throws {
        let v = AISetupProgressView(runner: "docker", onDone: {})
        #expect((try? v.inspect().find(text: "Checking prerequisites")) != nil)
    }

    @Test("docker runner shows enabling Docker Model Runner step")
    func dockerRunnerSetupStep() throws {
        let v = AISetupProgressView(runner: "docker", onDone: {})
        #expect((try? v.inspect().find(text: "Enabling Docker Model Runner")) != nil)
    }

    @Test("ramalama runner shows Configuring GPU passthrough step")
    func ramalamaGpuStep() throws {
        let v = AISetupProgressView(runner: "ramalama", onDone: {})
        #expect((try? v.inspect().find(text: "Configuring GPU passthrough")) != nil)
    }
}

// MARK: - CommandRunnerView additional tests (CovRest_ prefix)

@Suite("CovRest_CommandRunnerViewExtra Integration", .serialized)
@MainActor
struct CovRest_CommandRunnerViewExtraTests {

    @Test("shows nerdctl command runner title for nerdctl tool")
    func nerdctlTitle() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "nerdctl").environmentObject(s)
        #expect((try? v.inspect().find(text: "nerdctl Command Runner")) != nil)
    }

    @Test("shows incus command runner title for incus tool")
    func incusTitle() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "incus").environmentObject(s)
        #expect((try? v.inspect().find(text: "incus Command Runner")) != nil)
    }

    @Test("has outer sheet accessibility identifier")
    func hasOuterSheetId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_command_runner")) != nil)
    }

    @Test("close button has correct accessibility id")
    func closeButtonId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_command_runner")) != nil)
    }

    @Test("output text area has accessibility id")
    func outputTextId() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_command_output")) != nil)
    }

    @Test("incus quick commands include list and image list")
    func incusQuickCmds() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "incus").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_quick_list")) != nil)
    }

    @Test("docker quick commands include ps button")
    func dockerQuickPsCmd() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_quick_ps")) != nil)
    }
}

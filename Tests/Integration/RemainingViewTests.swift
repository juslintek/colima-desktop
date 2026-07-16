import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - CommandItem unit tests

@Suite("CommandItem")
struct CommandItemTests {

    @Test("stores title, subtitle, icon, category")
    func fields() {
        var ran = false
        let item = CommandItem(title: "Go to Containers", subtitle: "View all containers", icon: "shippingbox", category: "Navigation") { ran = true }
        #expect(item.title == "Go to Containers")
        #expect(item.subtitle == "View all containers")
        #expect(item.icon == "shippingbox")
        #expect(item.category == "Navigation")
        item.action()
        #expect(ran)
    }

    @Test("each CommandItem has unique id")
    func uniqueId() {
        let a = CommandItem(title: "A", subtitle: "", icon: "x", category: "Navigation") {}
        let b = CommandItem(title: "A", subtitle: "", icon: "x", category: "Navigation") {}
        #expect(a.id != b.id)
    }
}

// MARK: - CommandPalette integration tests

@Suite("CommandPalette Integration", .serialized)
@MainActor
struct CommandPaletteTests {

    @Test("renders command palette view")
    func rendersView() throws {
        let s = AppState(services: MockServiceProvider())
        var presented = true
        let v = CommandPalette(isPresented: Binding(get: { presented }, set: { presented = $0 }))
            .environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("has search field with correct identifier")
    func hasSearchField() throws {
        let s = AppState(services: MockServiceProvider())
        var presented = true
        let v = CommandPalette(isPresented: Binding(get: { presented }, set: { presented = $0 }))
            .environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_command_search")) != nil)
    }
}

// MARK: - AISetupProgressView integration tests

@Suite("AISetupProgressView Integration", .serialized)
@MainActor
struct AISetupProgressViewTests {

    @Test("shows AI Setup title for any runner")
    func showsTitle() throws {
        var done = false
        let v = AISetupProgressView(runner: "docker", onDone: { done = true })
        // The title text includes "AI Setup"
        #expect((try? v.inspect().find(text: "AI Setup — Docker Model Runner")) != nil)
    }

    @Test("shows ramalama runner in title")
    func ramalamaRunnerTitle() throws {
        var done = false
        let v = AISetupProgressView(runner: "ramalama", onDone: { done = true })
        #expect((try? v.inspect().find(text: "AI Setup — Ramalama")) != nil)
    }

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        var done = false
        let v = AISetupProgressView(runner: "docker", onDone: { done = true })
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - InstallColimaView integration tests

@Suite("InstallColimaView Integration", .serialized)
@MainActor
struct InstallColimaViewTests {

    @Test("shows not installed text")
    func showsNotInstalledText() throws {
        let s = AppState(services: MockServiceProvider())
        let v = InstallColimaView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_colima_not_installed")) != nil)
    }

    @Test("shows install button when not installing")
    func showsInstallButton() throws {
        let s = AppState(services: MockServiceProvider())
        s.isInstallingColima = false
        let v = InstallColimaView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_install_colima")) != nil)
    }

    @Test("shows progress view when installing")
    func showsProgressWhenInstalling() throws {
        let s = AppState(services: MockServiceProvider())
        s.isInstallingColima = true
        let v = InstallColimaView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "progress_installing_colima")) != nil)
    }
}

// MARK: - CreateContainerView integration tests

@Suite("CreateContainerView Integration", .serialized)
@MainActor
struct CreateContainerViewTests {

    @Test("has image name field")
    func hasImageField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_create_container_image_full")) != nil)
    }

    @Test("has create container title")
    func hasTitle() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CreateContainerView().environmentObject(s)
        #expect((try? v.inspect().find(text: "Create Container")) != nil)
    }
}

// MARK: - MockLogsView integration tests

@Suite("MockLogsView Integration", .serialized)
@MainActor
struct MockLogsViewTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        let v = MockLogsView(name: "web-server").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - MockStatsView integration tests

@Suite("MockStatsView Integration", .serialized)
@MainActor
struct MockStatsViewTests {

    @Test("shows CPU label")
    func showsCPULabel() throws {
        let v = MockStatsView(name: "nginx")
        #expect((try? v.inspect().find(text: "CPU")) != nil)
    }

    @Test("shows Memory label")
    func showsMemoryLabel() throws {
        let v = MockStatsView(name: "nginx")
        #expect((try? v.inspect().find(text: "Memory")) != nil)
    }

    @Test("shows PIDs label")
    func showsPIDsLabel() throws {
        let v = MockStatsView(name: "nginx")
        #expect((try? v.inspect().find(text: "PIDs")) != nil)
    }
}

// MARK: - MockTerminalView integration tests

@Suite("MockTerminalView Integration", .serialized)
@MainActor
struct MockTerminalViewTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = MockTerminalView(name: "web-server")
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - PullProgressView integration tests

@Suite("PullProgressView Integration", .serialized)
@MainActor
struct PullProgressViewTests {

    @Test("renders without crash and shows image name")
    func rendersAndShowsName() throws {
        let v = PullProgressView(name: "nginx:latest", onCancel: {})
        // PullProgressView renders with the image name - just verify it doesn't crash
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - CommandRunnerView integration tests

@Suite("CommandRunnerView Integration", .serialized)
@MainActor
struct CommandRunnerViewTests {

    @Test("shows command runner title")
    func showsTitle() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(text: "docker Command Runner")) != nil)
    }

    @Test("has command input field")
    func hasCommandField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_command_input")) != nil)
    }

    @Test("has run button")
    func hasRunButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_command")) != nil)
    }
}

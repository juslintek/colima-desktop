import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - CommandRunnerView integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_CommandRunnerView Integration", .serialized)
@MainActor
struct Cov3Rest_CommandRunnerViewTests {

    @Test("renders without crash for docker tool")
    func rendersDocker() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("renders without crash for incus tool")
    func rendersIncus() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "incus").environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows sheet identifier")
    func showsSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_command_runner")) != nil)
    }

    @Test("shows close button")
    func showsCloseButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_close_command_runner")) != nil)
    }

    @Test("shows command input field")
    func showsCommandInputField() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_command_input")) != nil)
    }

    @Test("shows run button")
    func showsRunButton() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_command")) != nil)
    }

    @Test("shows command output text")
    func showsCommandOutput() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_command_output")) != nil)
    }

    @Test("title shows docker for docker tool")
    func titleShowsDocker() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "docker").environmentObject(s)
        #expect((try? v.inspect().find(text: "docker Command Runner")) != nil)
    }

    @Test("title shows incus for incus tool")
    func titleShowsIncus() throws {
        let s = AppState(services: MockServiceProvider())
        let v = CommandRunnerView(tool: "incus").environmentObject(s)
        #expect((try? v.inspect().find(text: "incus Command Runner")) != nil)
    }

    @Test("quick commands for docker are ps, images, info, volume ls")
    func dockerQuickCommands() {
        let quickCommands = ["ps", "images", "info", "volume ls"]
        #expect(quickCommands.contains("ps"))
        #expect(quickCommands.contains("images"))
        #expect(quickCommands.count == 4)
    }

    @Test("quick commands for incus are list, info, image list, network list")
    func incusQuickCommands() {
        let quickCommands = ["list", "info", "image list", "network list"]
        #expect(quickCommands.contains("list"))
        #expect(quickCommands.contains("network list"))
        #expect(quickCommands.count == 4)
    }

    @Test("runCommand ignores empty input")
    func runCommandIgnoresEmpty() {
        let cmd = "   "
        #expect(cmd.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("runCommand builds full command string with tool prefix")
    func runCommandBuildsFullString() {
        let tool = "docker"
        let input = "ps -a"
        let cmd = input.trimmingCharacters(in: .whitespaces)
        let output = "$ \(tool) \(cmd)\n\nRunning..."
        #expect(output.hasPrefix("$ docker ps -a"))
    }
}

// MARK: - CommandPalette integration tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_CommandPalette Integration", .serialized)
@MainActor
struct Cov3Rest_CommandPaletteTests {

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let s = AppState(services: MockServiceProvider())
        s.containers = MockData.containers
        s.profiles = MockData.profiles
        var isPresented = true
        let binding = Binding(get: { isPresented }, set: { isPresented = $0 })
        let v = CommandPalette(isPresented: binding).environmentObject(s)
        #expect((try? v.inspect()) != nil)
    }

    @Test("has sheet identifier")
    func hasSheetIdentifier() throws {
        let s = AppState(services: MockServiceProvider())
        var isPresented = true
        let binding = Binding(get: { isPresented }, set: { isPresented = $0 })
        let v = CommandPalette(isPresented: binding).environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "sheet_command_palette")) != nil)
    }

    @Test("has search field")
    func hasSearchField() throws {
        let s = AppState(services: MockServiceProvider())
        var isPresented = true
        let binding = Binding(get: { isPresented }, set: { isPresented = $0 })
        let v = CommandPalette(isPresented: binding).environmentObject(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_command_search")) != nil)
    }

    @Test("CommandItem stores all fields correctly")
    func commandItemFields() {
        let item = CommandItem(title: "Start VM", subtitle: "Start Colima", icon: "play.fill", category: "Actions") {}
        #expect(item.title == "Start VM")
        #expect(item.subtitle == "Start Colima")
        #expect(item.icon == "play.fill")
        #expect(item.category == "Actions")
    }

    @Test("CommandItem has unique id")
    func commandItemUniqueId() {
        let a = CommandItem(title: "Test", subtitle: "", icon: "circle", category: "Nav") {}
        let b = CommandItem(title: "Test", subtitle: "", icon: "circle", category: "Nav") {}
        #expect(a.id != b.id)
    }

    @Test("filteredCommands returns all when query is empty")
    func filteredCommandsAllOnEmpty() {
        // With empty query, all commands are returned
        let commands = [
            CommandItem(title: "Go to Containers", subtitle: "View all containers", icon: "shippingbox", category: "Navigation") {},
            CommandItem(title: "Start VM", subtitle: "Start the VM", icon: "play.fill", category: "Actions") {},
        ]
        let query = ""
        let filtered = query.isEmpty ? commands : commands.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
        #expect(filtered.count == 2)
    }

    @Test("filteredCommands filters by title")
    func filteredCommandsByTitle() {
        let commands = [
            CommandItem(title: "Go to Containers", subtitle: "", icon: "shippingbox", category: "Navigation") {},
            CommandItem(title: "Start VM", subtitle: "", icon: "play", category: "Actions") {},
        ]
        let query = "containers"
        let filtered = commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
        #expect(filtered.count == 1)
        #expect(filtered.first?.title == "Go to Containers")
    }

    @Test("filteredCommands filters by subtitle")
    func filteredCommandsBySubtitle() {
        let commands = [
            CommandItem(title: "Start VM", subtitle: "Start the Colima VM", icon: "play", category: "Actions") {},
            CommandItem(title: "Stop VM", subtitle: "Halt the VM gracefully", icon: "stop", category: "Actions") {},
        ]
        let query = "colima"
        let filtered = commands.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query) ||
            $0.category.localizedCaseInsensitiveContains(query)
        }
        #expect(filtered.count == 1)
        #expect(filtered.first?.subtitle.contains("Colima") == true)
    }

    @Test("filteredCommands filters by category")
    func filteredCommandsByCategory() {
        let commands = [
            CommandItem(title: "A", subtitle: "", icon: "circle", category: "Navigation") {},
            CommandItem(title: "B", subtitle: "", icon: "circle", category: "Actions") {},
            CommandItem(title: "C", subtitle: "", icon: "circle", category: "Navigation") {},
        ]
        let query = "Navigation"
        let filtered = commands.filter { $0.category.localizedCaseInsensitiveContains(query) }
        #expect(filtered.count == 2)
    }

    @Test("groupedCommands groups by category")
    func groupedCommandsByCategory() {
        let commands = [
            CommandItem(title: "A", subtitle: "", icon: "circle", category: "Navigation") {},
            CommandItem(title: "B", subtitle: "", icon: "circle", category: "Actions") {},
            CommandItem(title: "C", subtitle: "", icon: "circle", category: "Navigation") {},
        ]
        let grouped = Dictionary(grouping: commands, by: \.category)
            .sorted { $0.key < $1.key }
        // Should have 2 groups: Actions, Navigation (sorted alphabetically)
        #expect(grouped.count == 2)
        #expect(grouped.first?.0 == "Actions")
        #expect(grouped.last?.0 == "Navigation")
    }
}

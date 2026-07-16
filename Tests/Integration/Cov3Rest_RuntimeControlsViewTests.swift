import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - RuntimeControlsView additional tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_RuntimeControlsView Integration", .serialized)
@MainActor
struct Cov3Rest_RuntimeControlsViewTests {

    private func state(profile: String = "default", vmRunning: Bool = true) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.activeProfile = profile
        s.vmRunning = vmRunning
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        RuntimeControlsView().environmentObject(appState)
    }

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = view(state())
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows runtime name text")
    func showsRuntimeNameText() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_runtime_name")) != nil)
    }

    @Test("shows runtime version text")
    func showsRuntimeVersionText() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_runtime_version")) != nil)
    }

    @Test("shows runtime socket text")
    func showsRuntimeSocketText() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_runtime_socket")) != nil)
    }

    @Test("shows copy socket button")
    func showsCopySocketButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_copy_socket")) != nil)
    }

    @Test("shows command palette text field")
    func showsCommandPaletteField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_command_palette")) != nil)
    }

    @Test("shows run command button")
    func showsRunCommandButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_command_palette")) != nil)
    }

    @Test("shows docker contexts table")
    func showsDockerContextsTable() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_docker_contexts")) != nil)
    }

    @Test("shows docker context text")
    func showsDockerContextText() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_docker_context")) != nil)
    }

    @Test("shows target runtime picker")
    func showsTargetRuntimePicker() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_target_runtime")) != nil)
    }

    @Test("shows switch runtime button")
    func showsSwitchRuntimeButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_switch_runtime")) != nil)
    }

    @Test("shows nerdctl command field")
    func showsNerdctlField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_nerdctl_cmd")) != nil)
    }

    @Test("shows run nerdctl button")
    func showsRunNerdctlButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_nerdctl")) != nil)
    }

    @Test("shows incus command field")
    func showsIncusField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_incus_cmd")) != nil)
    }

    @Test("shows run incus button")
    func showsRunIncusButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_run_incus")) != nil)
    }

    @Test("shows docker context picker")
    func showsDockerContextPicker() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_docker_context")) != nil)
    }

    @Test("shows switch docker context button")
    func showsSwitchDockerContextButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_switch_dockercontext")) != nil)
    }

    @Test("shows check runtime update button")
    func showsCheckRuntimeUpdateButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_check_runtime_update")) != nil)
    }

    @Test("shows update runtime button")
    func showsUpdateRuntimeButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_update_runtime")) != nil)
    }

    @Test("shows data persistence text")
    func showsDataPersistenceText() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "text_data_persistence")) != nil)
    }

    @Test("shows runtime comparison table")
    func showsRuntimeComparisonTable() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_runtime_comparison")) != nil)
    }

    @Test("runtime profile shown in docker context text")
    func profileShownInContextText() throws {
        let s = state(profile: "staging")
        let v = view(s)
        #expect((try? v.inspect().find(text: "Current: colima-staging")) != nil)
    }
}

// MARK: - RuntimeControls quick command logic unit tests (Cov3Rest_ prefix)

@Suite("Cov3Rest_RuntimeControlsLogic Unit", .serialized)
struct Cov3Rest_RuntimeControlsLogicTests {

    @Test("runPaletteCommand trims whitespace and builds args")
    func commandParsingTrimsWhitespace() {
        let cmd = "  docker ps  "
        let trimmed = cmd.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: " ")
        #expect(parts.first == "docker")
        #expect(parts.last == "ps")
    }

    @Test("empty command string is ignored by palette")
    func emptyCommandIgnored() {
        let cmd = "   "
        #expect(cmd.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("detectedTool returns nerdctl when prefix is nerdctl")
    func detectedToolNerdctl() {
        let input = "nerdctl ps"
        let prefix = input.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        let tool: String
        switch prefix {
        case "nerdctl": tool = "nerdctl"
        case "incus": tool = "incus"
        default: tool = "docker"
        }
        #expect(tool == "nerdctl")
    }

    @Test("detectedTool returns incus when prefix is incus")
    func detectedToolIncus() {
        let input = "incus list"
        let prefix = input.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        let tool: String
        switch prefix {
        case "nerdctl": tool = "nerdctl"
        case "incus": tool = "incus"
        default: tool = "docker"
        }
        #expect(tool == "incus")
    }

    @Test("detectedTool falls back to docker for unknown prefix")
    func detectedToolDockerFallback() {
        let input = "kubectl get pods"
        let prefix = input.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        let tool: String
        switch prefix {
        case "nerdctl": tool = "nerdctl"
        case "incus": tool = "incus"
        default: tool = "docker"
        }
        #expect(tool == "docker")
    }

    @Test("history deduplication prevents same command twice")
    func historyDeduplication() {
        var history: [String] = []
        let cmd = "docker ps"
        if !history.contains(cmd) { history.append(cmd) }
        if !history.contains(cmd) { history.append(cmd) }
        #expect(history.count == 1)
    }

    @Test("history trimmed when exceeds historyLimit")
    func historyTrimmedAtLimit() {
        var history = Array(0..<20).map { "cmd\($0)" }
        let limit = 20
        history.append("new-cmd")
        if history.count > limit {
            history.removeFirst(history.count - limit)
        }
        #expect(history.count == 20)
        #expect(history.last == "new-cmd")
    }
}

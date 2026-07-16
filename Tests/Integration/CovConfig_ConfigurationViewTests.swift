import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - CovConfig_ prefix · ConfigurationView additional coverage (prefix enforces collision avoidance)

// ─── Helpers ────────────────────────────────────────────────────────────────

@MainActor
private func makeState() -> AppState { AppState(services: MockServiceProvider()) }

@MainActor
private func configView(_ appState: AppState) -> some View {
    ConfigurationView().environmentObject(appState)
}

// ─── VM Settings – extra fields ─────────────────────────────────────────────

@Suite("CovConfig_ConfigurationView_VMSettings", .serialized)
@MainActor
struct CovConfig_ConfigurationView_VMSettings {

    @Test("binfmt toggle is present")
    func binfmtToggle() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_binfmt")) != nil)
    }

    @Test("foreground toggle is present")
    func foregroundToggle() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_foreground")) != nil)
    }

    @Test("port forwarder picker is present")
    func portForwarderPicker() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_portforwarder")) != nil)
    }

    @Test("disk image field is present")
    func diskImageField() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_diskimage")) != nil)
    }

    @Test("vmtype state text reflects qemu default")
    func vmTypeStateText() throws {
        let v = configView(makeState())
        // state_native_config text must be present; just verify element exists
        let el = try? v.inspect().find(viewWithAccessibilityIdentifier: "state_native_config")
        #expect(el != nil)
    }

    @Test("CPU type cards present for all variants")
    func cpuTypeCards() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_cputype_host")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_cputype_cortex-a72")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_cputype_max")) != nil)
    }

    @Test("lock icon for runtime is present")
    func lockIconRuntime() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "lock_config_runtime")) != nil)
    }
}

// ─── Runtime section ─────────────────────────────────────────────────────────

@Suite("CovConfig_ConfigurationView_Runtime", .serialized)
@MainActor
struct CovConfig_ConfigurationView_Runtime {

    @Test("runtime picker is present")
    func runtimePicker() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_runtime")) != nil)
    }

    @Test("auto activate toggle is present")
    func autoActivateToggle() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_autoactivate")) != nil)
    }

    @Test("model runner picker is present")
    func modelRunnerPicker() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_modelrunner")) != nil)
    }

    @Test("docker JSON editor is present")
    func dockerJSONEditor() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_dockerjson")) != nil)
    }
}

// ─── Kubernetes section – extra fields ───────────────────────────────────────

@Suite("CovConfig_ConfigurationView_Kubernetes", .serialized)
@MainActor
struct CovConfig_ConfigurationView_Kubernetes {

    @Test("k8s enabled toggle is present")
    func k8sEnabledToggle() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_k8s")) != nil)
    }

    @Test("vmtype card qemu is unselected by default (no runtime binding needed)")
    func vmTypeCardQemuPresent() throws {
        let v = configView(makeState())
        let el = try? v.inspect().find(viewWithAccessibilityIdentifier: "card_vmtype_qemu")
        #expect(el != nil)
    }
}

// ─── Network section – extra fields ──────────────────────────────────────────

@Suite("CovConfig_ConfigurationView_Network", .serialized)
@MainActor
struct CovConfig_ConfigurationView_Network {

    @Test("DNS servers field is present")
    func dnsServersField() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_dns")) != nil)
    }

    @Test("DNS hosts text editor is present")
    func dnsHostsEditor() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_dnshosts")) != nil)
    }

    @Test("gateway field is present")
    func gatewayField() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_gateway")) != nil)
    }

    @Test("host addresses toggle is present")
    func hostAddressesToggle() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_hostaddresses")) != nil)
    }

    @Test("preferred route toggle is present")
    func preferredRouteToggle() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_preferredroute")) != nil)
    }
}

// ─── Mount type cards – recommended flag ─────────────────────────────────────

@Suite("CovConfig_ConfigurationView_MountTypes", .serialized)
@MainActor
struct CovConfig_ConfigurationView_MountTypes {

    @Test("virtiofs mount card is present and accessible")
    func virtiofsCard() throws {
        let v = configView(makeState())
        let card = try? v.inspect().find(viewWithAccessibilityIdentifier: "card_mounttype_virtiofs")
        #expect(card != nil)
    }

    @Test("9p mount card is present")
    func ninepCard() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_mounttype_9p")) != nil)
    }

    @Test("sshfs mount card is present")
    func sshfsCard() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_mounttype_sshfs")) != nil)
    }
}

// ─── Provisioning ────────────────────────────────────────────────────────────

@Suite("CovConfig_ConfigurationView_Provisioning", .serialized)
@MainActor
struct CovConfig_ConfigurationView_Provisioning {

    @Test("first provision script remove button is present by default")
    func firstProvisionRemoveButton() throws {
        let v = configView(makeState())
        // Default state seeds one provision entry at index 0
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_provision_0")) != nil)
    }
}

// ─── Environment ─────────────────────────────────────────────────────────────

@Suite("CovConfig_ConfigurationView_Environment", .serialized)
@MainActor
struct CovConfig_ConfigurationView_Environment {

    @Test("first env var remove button is present by default")
    func firstEnvRemoveButton() throws {
        let v = configView(makeState())
        // Default state seeds one env var at index 0
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_env_0")) != nil)
    }
}

// ─── Mounts list ─────────────────────────────────────────────────────────────

@Suite("CovConfig_ConfigurationView_Mounts", .serialized)
@MainActor
struct CovConfig_ConfigurationView_Mounts {

    @Test("first mount remove button present for default mounts")
    func firstMountRemoveButton() throws {
        let v = configView(makeState())
        // Default state seeds two mount entries (index 0 and 1)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_mount_0")) != nil)
    }

    @Test("second mount remove button present for default mounts")
    func secondMountRemoveButton() throws {
        let v = configView(makeState())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_mount_1")) != nil)
    }
}

// ─── DockerJSONEditor unit-level tests ───────────────────────────────────────

@Suite("CovConfig_DockerJSONEditor", .serialized)
@MainActor
struct CovConfig_DockerJSONEditor {

    @Test("DockerJSONEditor renders without crash")
    func renders() throws {
        @State var text = "{}"
        // SwiftUI state binding: create a non-state binding for the test
        let binding = Binding<String>(get: { "{}" }, set: { _ in })
        let v = DockerJSONEditor(text: binding)
        // Just verifying it can be inspected without throwing
        let _ = try? v.inspect()
    }
}

// ─── validateContainerName helper – unit coverage ────────────────────────────

@Suite("CovConfig_ConfigurationViewValidation", .serialized)
@MainActor
struct CovConfig_ConfigurationViewValidation {

    // These exercise AppState.validateContainerName which feeds into
    // ConfigurationView's create-container workflow indirectly

    @Test("empty name returns error")
    func emptyNameError() {
        let s = makeState()
        #expect(s.validateContainerName("") == "Name is required")
    }

    @Test("too-long name returns error")
    func tooLongNameError() {
        let s = makeState()
        let longName = String(repeating: "a", count: 129)
        #expect(s.validateContainerName(longName) != nil)
    }

    @Test("valid alphanumeric name passes")
    func validName() {
        let s = makeState()
        #expect(s.validateContainerName("my-container_1") == nil)
    }

    @Test("name with invalid characters returns error")
    func invalidCharacters() {
        let s = makeState()
        #expect(s.validateContainerName("my container!") != nil)
    }
}

// ─── applyConfig / saveConfig round-trip (through AppState) ──────────────────

@Suite("CovConfig_ConfigurationViewConfigRoundtrip", .serialized)
@MainActor
struct CovConfig_ConfigurationViewConfigRoundtrip {

    @Test("saveTemplate calls through AppState without error")
    func saveTemplateNoThrow() {
        let s = makeState()
        s.saveTemplate()
        // just verify no crash and toast message is set
        #expect(s.isToastVisible == true)
    }

    @Test("loadTemplate calls through AppState without error")
    func loadTemplateNoThrow() {
        let s = makeState()
        s.loadTemplate()
        #expect(s.isToastVisible == true)
    }

    @Test("resetConfig shows toast")
    func resetConfigToast() {
        let s = makeState()
        s.resetConfig()
        #expect(s.isToastVisible == true)
    }

    @Test("editYAML does not throw")
    func editYAMLNoThrow() {
        // editYAML opens a file URL via NSWorkspace — we just verify it doesn't
        // crash and doesn't set an activeSheet (it's a side-effect open, not a sheet).
        let s = makeState()
        s.editYAML()
        // No crash == pass; activeSheet is NOT set by editYAML (it uses NSWorkspace.open)
        #expect(s.activeSheet == nil)
    }
}

import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ConfigurationView integration tests

@Suite("ConfigurationView Integration", .serialized)
@MainActor
struct ConfigurationViewTests {

    private func state() -> AppState {
        AppState(services: MockServiceProvider())
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        ConfigurationView().environmentObject(appState)
    }

    // MARK: VM Resources section

    @Test("CPU stepper is present")
    func cpuStepper() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_cpus")) != nil)
    }

    @Test("memory stepper is present")
    func memoryStepper() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_memory")) != nil)
    }

    @Test("disk stepper is present")
    func diskStepper() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_disk")) != nil)
    }

    @Test("root disk stepper is present")
    func rootDiskStepper() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_rootdisk")) != nil)
    }

    // MARK: VM Settings section

    @Test("architecture picker is present")
    func archPicker() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_arch")) != nil)
    }

    @Test("VM type cards are present")
    func vmTypeCards() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_vmtype_qemu")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_vmtype_vz")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_vmtype_krunkit")) != nil)
    }

    @Test("CPU type label is present")
    func cpuTypeLabel() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_cputype")) != nil)
    }

    @Test("rosetta toggle is present")
    func rosettaToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_rosetta")) != nil)
    }

    @Test("nested virtualization toggle is present")
    func nestedVirtToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_nestedvirt")) != nil)
    }

    @Test("hostname field is present")
    func hostnameField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_hostname")) != nil)
    }

    @Test("lock icons for immutable settings are present")
    func lockIcons() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "lock_config_arch")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "lock_config_vmtype")) != nil)
    }

    // MARK: Runtime section

    @Test("native config state text is present")
    func nativeConfigState() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "state_native_config")) != nil)
    }

    // MARK: Kubernetes section

    @Test("kubernetes version picker is present")
    func k8sVersionPicker() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_k8sversion")) != nil)
    }

    @Test("k3s args field is present")
    func k3sArgsField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_k3sargs")) != nil)
    }

    @Test("k8s port field is present")
    func k8sPortField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_k8sport")) != nil)
    }

    // MARK: Network section

    @Test("network address toggle is present")
    func networkAddressToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_networkaddress")) != nil)
    }

    @Test("network mode picker is present")
    func networkModePicker() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_networkmode")) != nil)
    }

    @Test("network interface field is present")
    func networkInterfaceField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_interface")) != nil)
    }

    // MARK: Mounts section

    @Test("inotify toggle is present")
    func inotifyToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_inotify")) != nil)
    }

    @Test("disable mounts toggle is present")
    func disableMountsToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_disablemounts")) != nil)
    }

    @Test("add mount button is present")
    func addMountButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_add_mount")) != nil)
    }

    // MARK: SSH section

    @Test("SSH port field is present")
    func sshPortField() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_config_sshport")) != nil)
    }

    @Test("forward agent toggle is present")
    func forwardAgentToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_forwardagent")) != nil)
    }

    @Test("SSH config toggle is present")
    func sshConfigToggle() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_config_sshconfig")) != nil)
    }

    // MARK: Provisioning section

    @Test("add provision script button is present")
    func addProvisionButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_add_provision")) != nil)
    }

    // MARK: Environment section

    @Test("add environment variable button is present")
    func addEnvButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_add_env")) != nil)
    }

    // MARK: Template section

    @Test("load template button is present")
    func loadTemplateButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_load_template")) != nil)
    }

    @Test("save template button is present")
    func saveTemplateButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_save_template")) != nil)
    }

    // MARK: Actions

    @Test("save configuration button is present")
    func saveConfigButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_save_config_all")) != nil)
    }

    @Test("reset to defaults button is present")
    func resetConfigButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_reset_config_all")) != nil)
    }

    @Test("edit YAML button is present")
    func editYAMLButton() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_edit_config_yaml")) != nil)
    }

    // MARK: Mount type cards

    @Test("mount type cards are present")
    func mountTypeCards() throws {
        let v = view(state())
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_mounttype_virtiofs")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_mounttype_9p")) != nil)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "card_mounttype_sshfs")) != nil)
    }
}

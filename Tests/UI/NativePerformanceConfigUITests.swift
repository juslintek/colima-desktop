import XCTest

/// Exhaustive E2E coverage of macOS native-performance and other VM config options.
/// Verifies every selectable possibility: vmType (qemu/vz/krunkit), cpuType,
/// mountType (virtiofs/9p/sshfs), arch, runtime, portForwarder, networkMode,
/// modelRunner, plus rosetta / nestedVirt / binfmt / inotify / autoActivate toggles.
final class NativePerformanceConfigUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        E2ELaunch.configure(app)
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_configuration"].click()
        XCTAssertTrue(app.descendants(matching: .any)["state_native_config"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    /// Tap a selection card and confirm its accessibilityValue becomes "selected".
    private func selectCard(_ cardId: String, expect token: String) {
        let card = app.buttons[cardId].exists ? app.buttons[cardId] : app.descendants(matching: .any)[cardId]
        XCTAssertTrue(card.waitForExistence(timeout: 3), "Missing card \(cardId)")
        card.click()
        let predicate = NSPredicate(format: "value == %@", "selected")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: card)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 3), .completed,
                       "After tapping \(cardId), value='\(card.value as? String ?? "nil")' (expected selected)")
    }

    /// Toggle a checkbox and confirm its own value flips.
    private func toggleAndVerify(_ toggleId: String) {
        let toggle = app.checkBoxes[toggleId].exists
            ? app.checkBoxes[toggleId]
            : app.descendants(matching: .any)[toggleId]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Missing toggle \(toggleId)")
        let before = toggle.value as? String
        toggle.click()
        let predicate = NSPredicate(format: "value != %@", before ?? "")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 3), .completed,
                       "Toggle \(toggleId) value did not change (was '\(before ?? "nil")', now '\(toggle.value as? String ?? "nil")')")
    }

    private func assertPickerOptions(_ pickerId: String, _ options: [String]) {
        let picker = app.popUpButtons[pickerId].exists
            ? app.popUpButtons[pickerId]
            : app.descendants(matching: .any)[pickerId]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "Missing picker \(pickerId)")
        picker.click()
        for opt in options {
            XCTAssertTrue(app.menuItems[opt].waitForExistence(timeout: 2), "Missing option '\(opt)' in \(pickerId)")
        }
        app.menuItems[options[0]].click()
    }

    // MARK: - VM Type (native performance) — all possibilities

    func testSelectVMTypeQemu() { selectCard("card_vmtype_qemu", expect: "vmtype:qemu") }
    func testSelectVMTypeVZ() { selectCard("card_vmtype_vz", expect: "vmtype:vz") }
    func testSelectVMTypeKrunkit() { selectCard("card_vmtype_krunkit", expect: "vmtype:krunkit") }

    func testCycleAllVMTypes() {
        selectCard("card_vmtype_qemu", expect: "vmtype:qemu")
        selectCard("card_vmtype_vz", expect: "vmtype:vz")
        selectCard("card_vmtype_krunkit", expect: "vmtype:krunkit")
    }

    // MARK: - CPU Type — all possibilities

    func testSelectCPUTypeHost() { selectCard("card_cputype_host", expect: "cputype:host") }
    func testSelectCPUTypeCortexA72() { selectCard("card_cputype_cortex-a72", expect: "cputype:cortex-a72") }
    func testSelectCPUTypeMax() { selectCard("card_cputype_max", expect: "cputype:max") }

    func testCycleAllCPUTypes() {
        selectCard("card_cputype_cortex-a72", expect: "cputype:cortex-a72")
        selectCard("card_cputype_max", expect: "cputype:max")
        selectCard("card_cputype_host", expect: "cputype:host")
    }

    // MARK: - Mount Type (native performance) — all possibilities

    func testSelectMountTypeVirtiofs() { selectCard("card_mounttype_virtiofs", expect: "mounttype:virtiofs") }
    func testSelectMountType9p() { selectCard("card_mounttype_9p", expect: "mounttype:9p") }
    func testSelectMountTypeSshfs() { selectCard("card_mounttype_sshfs", expect: "mounttype:sshfs") }

    func testCycleAllMountTypes() {
        selectCard("card_mounttype_9p", expect: "mounttype:9p")
        selectCard("card_mounttype_sshfs", expect: "mounttype:sshfs")
        selectCard("card_mounttype_virtiofs", expect: "mounttype:virtiofs")
    }

    // MARK: - Native performance combo: vz + virtiofs

    func testNativePerformanceComboVZVirtiofs() {
        selectCard("card_vmtype_vz", expect: "vmtype:vz")
        selectCard("card_mounttype_virtiofs", expect: "mounttype:virtiofs")
    }

    // MARK: - Valid configuration combinations (reachability across the option matrix)

    func testComboQemu9p() {
        selectCard("card_vmtype_qemu", expect: "vmtype:qemu")
        selectCard("card_mounttype_9p", expect: "mounttype:9p")
    }

    func testComboQemuSshfs() {
        selectCard("card_vmtype_qemu", expect: "vmtype:qemu")
        selectCard("card_mounttype_sshfs", expect: "mounttype:sshfs")
    }

    func testComboVZVirtiofsRosetta() {
        selectCard("card_vmtype_vz", expect: "vmtype:vz")
        selectCard("card_mounttype_virtiofs", expect: "mounttype:virtiofs")
        toggleAndVerify("toggle_config_rosetta")
    }

    func testComboKrunkitRamalama() {
        selectCard("card_vmtype_krunkit", expect: "vmtype:krunkit")
        assertPickerOptions("field_config_modelrunner", ["docker", "ramalama"])
    }

    func testComboFullNativeAppleSilicon() {
        selectCard("card_vmtype_vz", expect: "vmtype:vz")
        selectCard("card_cputype_host", expect: "cputype:host")
        selectCard("card_mounttype_virtiofs", expect: "mounttype:virtiofs")
        toggleAndVerify("toggle_config_binfmt")
    }

    // MARK: - Pickers — all possibilities

    func testArchOptionsAllPresent() {
        assertPickerOptions("field_config_arch", ["host", "aarch64", "x86_64"])
    }

    func testRuntimeOptionsAllPresent() {
        assertPickerOptions("field_config_runtime", ["docker", "containerd", "incus"])
    }

    func testPortForwarderOptionsAllPresent() {
        assertPickerOptions("field_config_portforwarder", ["ssh", "grpc", "none"])
    }

    func testNetworkModeOptionsAllPresent() {
        assertPickerOptions("field_config_networkmode", ["shared", "bridged"])
    }

    func testModelRunnerOptionsAllPresent() {
        assertPickerOptions("field_config_modelrunner", ["docker", "ramalama"])
    }

    // MARK: - Performance toggles

    func testRosettaToggle() { toggleAndVerify("toggle_config_rosetta") }
    func testNestedVirtToggle() { toggleAndVerify("toggle_config_nestedvirt") }
    func testBinfmtToggle() { toggleAndVerify("toggle_config_binfmt") }
    func testInotifyToggle() { toggleAndVerify("toggle_config_inotify") }
    func testAutoActivateToggle() { toggleAndVerify("toggle_config_autoactivate") }
}

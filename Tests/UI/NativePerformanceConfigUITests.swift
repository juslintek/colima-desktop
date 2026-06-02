import XCTest

/// Exhaustive E2E coverage of macOS native-performance and other VM config options.
/// Verifies every selectable possibility: vmType (qemu/vz/krunkit), cpuType,
/// mountType (virtiofs/9p/sshfs), arch, runtime, portForwarder, networkMode,
/// modelRunner, plus rosetta / nestedVirt / binfmt / inotify / autoActivate toggles.
final class NativePerformanceConfigUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_configuration"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func selectCard(_ id: String) {
        let card = app.descendants(matching: .any)[id]
        XCTAssertTrue(card.waitForExistence(timeout: 3), "Missing card \(id)")
        card.click()
        let predicate = NSPredicate(format: "value == %@", "selected")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: card)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: 3), .completed,
                       "\(id) did not become selected (value=\(card.value as? String ?? "nil"))")
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

    private func toggleAndVerifyChanges(_ id: String) {
        let toggle = app.descendants(matching: .any)[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Missing toggle \(id)")
        let before = toggle.value as? String
        toggle.click()
        let after = toggle.value as? String
        XCTAssertNotEqual(before, after, "\(id) value did not change on click")
    }

    // MARK: - VM Type (native performance) — all possibilities

    func testSelectVMTypeQemu() { selectCard("card_vmtype_qemu") }
    func testSelectVMTypeVZ() { selectCard("card_vmtype_vz") }
    func testSelectVMTypeKrunkit() { selectCard("card_vmtype_krunkit") }

    func testCycleAllVMTypes() {
        for t in ["qemu", "vz", "krunkit"] { selectCard("card_vmtype_\(t)") }
    }

    // MARK: - CPU Type — all possibilities

    func testSelectCPUTypeHost() { selectCard("card_cputype_host") }
    func testSelectCPUTypeCortexA72() { selectCard("card_cputype_cortex-a72") }
    func testSelectCPUTypeMax() { selectCard("card_cputype_max") }

    func testCycleAllCPUTypes() {
        for t in ["host", "cortex-a72", "max"] { selectCard("card_cputype_\(t)") }
    }

    // MARK: - Mount Type (native performance) — all possibilities

    func testSelectMountTypeVirtiofs() { selectCard("card_mounttype_virtiofs") }
    func testSelectMountType9p() { selectCard("card_mounttype_9p") }
    func testSelectMountTypeSshfs() { selectCard("card_mounttype_sshfs") }

    func testCycleAllMountTypes() {
        for t in ["virtiofs", "9p", "sshfs"] { selectCard("card_mounttype_\(t)") }
    }

    // MARK: - Native performance combo: vz + virtiofs + rosetta + nestedVirt

    func testNativePerformanceComboVZVirtiofs() {
        selectCard("card_vmtype_vz")
        selectCard("card_mounttype_virtiofs")
        let rosetta = app.descendants(matching: .any)["toggle_config_rosetta"]
        XCTAssertTrue(rosetta.waitForExistence(timeout: 3))
    }

    // MARK: - Architecture — all possibilities

    func testArchOptionsAllPresent() {
        assertPickerOptions("field_config_arch", ["host", "aarch64", "x86_64"])
    }

    // MARK: - Runtime — all possibilities

    func testRuntimeOptionsAllPresent() {
        assertPickerOptions("field_config_runtime", ["docker", "containerd", "incus"])
    }

    // MARK: - Port Forwarder — all possibilities

    func testPortForwarderOptionsAllPresent() {
        assertPickerOptions("field_config_portforwarder", ["ssh", "grpc", "none"])
    }

    // MARK: - Network Mode — all possibilities

    func testNetworkModeOptionsAllPresent() {
        assertPickerOptions("field_config_networkmode", ["shared", "bridged"])
    }

    // MARK: - Model Runner — all possibilities

    func testModelRunnerOptionsAllPresent() {
        assertPickerOptions("field_config_modelrunner", ["docker", "ramalama"])
    }

    // MARK: - Performance toggles

    func testRosettaToggle() { toggleAndVerifyChanges("toggle_config_rosetta") }
    func testNestedVirtToggle() { toggleAndVerifyChanges("toggle_config_nestedvirt") }
    func testBinfmtToggle() { toggleAndVerifyChanges("toggle_config_binfmt") }
    func testInotifyToggle() { toggleAndVerifyChanges("toggle_config_inotify") }
    func testAutoActivateToggle() { toggleAndVerifyChanges("toggle_config_autoactivate") }
}

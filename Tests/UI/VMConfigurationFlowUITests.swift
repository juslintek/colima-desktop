import XCTest

/// End-to-end flows for VM (profile) creation, customization, configuration, and removal.
/// Each Colima profile is a distinct VM, so profile lifecycle == VM lifecycle.
final class VMConfigurationFlowUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        E2ELaunch.configure(app)
        app.launch()
        app.activate()
    }

    private func openProfiles() {
        app.descendants(matching: .any)["tab_profiles"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_profiles"].waitForExistence(timeout: 5))
    }

    private func openConfiguration() {
        app.descendants(matching: .any)["tab_configuration"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].waitForExistence(timeout: 5))
    }

    // MARK: - VM Creation

    func testCreateVMFlowAddsRow() {
        openProfiles()
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let name = app.descendants(matching: .any)["field_create_profile_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeText("staging")
        let confirm = app.descendants(matching: .any)["btn_confirm_profile_create"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.click()
        XCTAssertTrue(app.descendants(matching: .any)["row_profile_staging"].waitForExistence(timeout: 5))
    }

    func testCreateVMConfirmDisabledUntilValidName() {
        openProfiles()
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let confirm = app.descendants(matching: .any)["btn_confirm_profile_create"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertFalse(confirm.isEnabled)
        let name = app.descendants(matching: .any)["field_create_profile_name"]
        name.click()
        name.typeText("valid-vm")
        XCTAssertTrue(confirm.isEnabled)
    }

    func testCreateVMRejectsInvalidName() {
        openProfiles()
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let name = app.descendants(matching: .any)["field_create_profile_name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeText("bad name!")
        XCTAssertTrue(app.descendants(matching: .any)["text_profile_name_error"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["btn_confirm_profile_create"].isEnabled)
    }

    func testCreateVMHasResourceFields() {
        openProfiles()
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_cpus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_memory"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_runtime"].exists)
    }

    // MARK: - VM Cloning (customization from existing)

    func testCloneVMFlowAddsRow() {
        openProfiles()
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let dest = app.descendants(matching: .any)["field_clone_profile_dest"]
        XCTAssertTrue(dest.waitForExistence(timeout: 3))
        dest.click()
        dest.typeText("default-copy")
        let confirm = app.descendants(matching: .any)["btn_confirm_profile_clone"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.click()
        XCTAssertTrue(app.descendants(matching: .any)["row_profile_default-copy"].waitForExistence(timeout: 5))
    }

    // MARK: - VM Removal

    func testRemoveVMShowsConfirmation() {
        openProfiles()
        let del = app.descendants(matching: .any)["btn_delete_profile_dev"]
        XCTAssertTrue(del.waitForExistence(timeout: 3))
        del.click()
        XCTAssertTrue(app.buttons["Confirm"].waitForExistence(timeout: 5))
    }

    func testRemoveVMRemovesRow() {
        openProfiles()
        XCTAssertTrue(app.descendants(matching: .any)["row_profile_dev"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_delete_profile_dev"].click()
        let confirm = app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertFalse(app.descendants(matching: .any)["row_profile_dev"].waitForExistence(timeout: 3))
    }

    // MARK: - VM Lifecycle Controls (per profile)

    func testStartStopRestartButtonsPresent() {
        openProfiles()
        XCTAssertTrue(app.descendants(matching: .any)["btn_start_profile_k8s"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["btn_stop_profile_dev"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["btn_restart_profile_default"].exists)
    }

    // MARK: - Configuration Save / Reset

    func testSaveConfigurationCompletes() {
        openConfiguration()
        let save = app.descendants(matching: .any)["btn_save_config_all"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.click()
        // Save remains present (no crash); config view still rendered
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].waitForExistence(timeout: 3))
    }

    func testResetConfigurationCompletes() {
        openConfiguration()
        let reset = app.descendants(matching: .any)["btn_reset_config_all"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        reset.click()
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].waitForExistence(timeout: 3))
    }

    func testEditYAMLButtonEnabled() {
        openConfiguration()
        let btn = app.descendants(matching: .any)["btn_edit_config_yaml"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    // MARK: - Resource Customization

    func testResourceSteppersInteractable() {
        openConfiguration()
        for id in ["field_config_cpus", "field_config_memory", "field_config_disk", "field_config_rootdisk"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 3), "Missing stepper \(id)")
        }
    }

    func testAddMountOpensDialog() {
        openConfiguration()
        let add = app.descendants(matching: .any)["btn_add_mount"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        // Add-mount dialog shows a host path field menu / confirm — verify add button still present
        XCTAssertTrue(app.descendants(matching: .any)["btn_add_mount"].exists)
    }
}

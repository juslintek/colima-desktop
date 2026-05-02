import XCTest

final class ProfileManagementUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_profiles"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_profiles"].waitForExistence(timeout: 3))
    }

    // MARK: - Table & Rows

    func testProfilesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_profiles"].exists)
    }

    func testMockProfileRowsExist() {
        for name in ["default", "dev", "k8s"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_profile_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    // MARK: - Status indicators

    func testProfileStatusIndicatorExists() {
        let status = app.descendants(matching: .any)["status_indicator_profile_default"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
    }

    // MARK: - Per-row action buttons

    func testStartButtonExists() {
        let btn = app.descendants(matching: .any)["btn_start_profile_k8s"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testStopButtonExists() {
        let btn = app.descendants(matching: .any)["btn_stop_profile_dev"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testRestartButtonExists() {
        let btn = app.descendants(matching: .any)["btn_restart_profile_default"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testDeleteButtonExists() {
        let btn = app.descendants(matching: .any)["btn_delete_profile_k8s"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Delete confirmation

    func testDeleteProfileShowsConfirmation() {
        app.descendants(matching: .any)["btn_delete_profile_k8s"].click()
        let confirm = app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    }

    // MARK: - Create Profile Sheet

    func testCreateButtonExists() {
        let btn = app.descendants(matching: .any)["btn_create_profile_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testCreateSheetOpens() {
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let nameField = app.descendants(matching: .any)["field_create_profile_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    }

    func testCreateSheetHasFields() {
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_cpus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_memory"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_runtime"].waitForExistence(timeout: 3))
    }

    func testCreateConfirmDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let btn = app.descendants(matching: .any)["btn_confirm_profile_create"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled)
    }

    // MARK: - Clone Profile Sheet

    func testCloneButtonExists() {
        let btn = app.descendants(matching: .any)["btn_clone_profile_selected"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testCloneSheetOpens() {
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let source = app.descendants(matching: .any)["field_clone_profile_source"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
    }

    func testCloneSheetHasDestField() {
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let dest = app.descendants(matching: .any)["field_clone_profile_dest"]
        XCTAssertTrue(dest.waitForExistence(timeout: 3))
    }

    func testCloneConfirmDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let btn = app.descendants(matching: .any)["btn_confirm_profile_clone"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled)
    }

    // MARK: - Validation Errors

    func testProfileNameValidationError() {
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let nameField = app.descendants(matching: .any)["field_create_profile_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("invalid name with spaces!")
        let err = app.descendants(matching: .any)["text_profile_name_error"]
        XCTAssertTrue(err.waitForExistence(timeout: 3))
    }

    func testCloneNameValidationError() {
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let destField = app.descendants(matching: .any)["field_clone_profile_dest"]
        XCTAssertTrue(destField.waitForExistence(timeout: 3))
        destField.click()
        destField.typeText("invalid name with spaces!")
        let err = app.descendants(matching: .any)["text_clone_name_error"]
        XCTAssertTrue(err.waitForExistence(timeout: 3))
    }

    // MARK: - Info displays

    func testColimaHomeDisplay() {
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_home"].waitForExistence(timeout: 3))
    }

    func testColimaProfileDisplay() {
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_profile"].waitForExistence(timeout: 3))
    }

    // MARK: - Profile Switcher

    func testProfileSwitcherExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_sidebar_profile"].waitForExistence(timeout: 3))
    }
}

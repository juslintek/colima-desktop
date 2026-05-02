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

    func testProfilesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_profiles"].exists)
    }

    func testMockProfileRowsExist() {
        for name in ["default", "dev", "k8s"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_profile_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    func testStartStoppedProfile() {
        app.descendants(matching: .any)["btn_start_profile_k8s"].click()
        let status = app.descendants(matching: .any)["status_indicator_profile_k8s"]
        let pred = NSPredicate(format: "value == %@", "Running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("started"))
    }

    func testStopRunningProfile() {
        app.descendants(matching: .any)["btn_stop_profile_dev"].click()
        let status = app.descendants(matching: .any)["status_indicator_profile_dev"]
        let pred = NSPredicate(format: "value == %@", "Stopped")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("stopped"))
    }

    func testRestartProfile() {
        app.descendants(matching: .any)["btn_restart_profile_default"].click()
        let status = app.descendants(matching: .any)["status_indicator_profile_default"]
        let pred = NSPredicate(format: "value == %@", "Running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("restarted"))
    }

    func testDeleteProfileRemovesRow() {
        let row = app.descendants(matching: .any)["row_profile_k8s"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_delete_profile_k8s"].click()
        app.descendants(matching: .any)["Confirm"].click()
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: row)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("deleted"))
    }

    func testCreateProfileAddsRow() {
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        let nameField = app.descendants(matching: .any)["field_create_profile_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("test-prof")
        app.descendants(matching: .any)["btn_confirm_profile_create"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("created"))
        XCTAssertTrue(app.descendants(matching: .any)["row_profile_test-prof"].waitForExistence(timeout: 3))
    }

    func testCloneProfileAddsRow() {
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let destField = app.descendants(matching: .any)["field_clone_profile_dest"]
        XCTAssertTrue(destField.waitForExistence(timeout: 3))
        destField.click()
        destField.typeText("cloned-prof")
        app.descendants(matching: .any)["btn_confirm_profile_clone"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("cloned"))
        XCTAssertTrue(app.descendants(matching: .any)["row_profile_cloned-prof"].waitForExistence(timeout: 3))
    }

    func testColimaHomeDisplay() {
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_home"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_home"].label.contains("~/.colima"))
    }

    func testColimaProfileDisplay() {
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_profile"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_profile"].label.contains("default"))
    }

    func testProfileSwitcherExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_sidebar_profile"].waitForExistence(timeout: 3))
    }

    func testDockerContextButtonShowsToast() {
        // Navigate to runtime controls for docker context button
        app.descendants(matching: .any)["tab_runtimecontrols"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_switch_dockercontext"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_switch_dockercontext"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Docker context"))
    }

    func testCloneDialogFieldsExist() {
        app.descendants(matching: .any)["btn_clone_profile_selected"].click()
        let source = app.descendants(matching: .any)["field_clone_profile_source"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
    }

    func testCreateDialogFieldsExist() {
        app.descendants(matching: .any)["btn_create_profile_new"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_cpus"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_memory"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["field_create_profile_runtime"].waitForExistence(timeout: 3))
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
}

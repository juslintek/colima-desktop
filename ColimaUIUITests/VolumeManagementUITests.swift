import XCTest

final class VolumeManagementUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_volumes"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_volumes"].waitForExistence(timeout: 3))
    }

    func testVolumesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_volumes"].exists)
    }

    func testVolumesTitle() {
        XCTAssertTrue(app.navigationBars["Volumes"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["Volumes"].waitForExistence(timeout: 3))
    }

    func testMockVolumeRowsExist() {
        for name in ["postgres_data", "redis_data", "app_uploads"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_volume_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    func testCreateVolumeAddsRow() {
        app.descendants(matching: .any)["btn_create_volume_new"].click()
        let nameField = app.descendants(matching: .any)["field_volume_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("test_vol")
        app.descendants(matching: .any)["btn_confirm_volume_create"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("created"))
        XCTAssertTrue(app.descendants(matching: .any)["row_volume_test_vol"].waitForExistence(timeout: 3))
    }

    func testRemoveVolumeRemovesRow() {
        let row = app.descendants(matching: .any)["row_volume_redis_data"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_remove_volume_redis_data"].click()
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: row)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("removed"))
    }

    func testPruneVolumesShowsToast() {
        app.descendants(matching: .any)["btn_prune_volume_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("pruned"))
    }

    func testInspectVolumeShowsToast() {
        app.descendants(matching: .any)["btn_inspect_volume_postgres_data"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Inspecting"))
    }

    // MARK: - Validation

    func testVolumeValidationError() {
        app.descendants(matching: .any)["btn_create_volume_new"].click()
        let nameField = app.descendants(matching: .any)["field_volume_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("invalid name with spaces!")
        let err = app.descendants(matching: .any)["text_volume_validation_error"]
        XCTAssertTrue(err.waitForExistence(timeout: 3))
    }
}

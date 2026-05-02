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

    // MARK: - Table & Rows

    func testVolumesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_volumes"].exists)
    }

    func testMockVolumeRowsExist() {
        for name in ["postgres_data", "redis_data", "app_uploads"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_volume_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    // MARK: - Toolbar buttons

    func testCreateButtonExists() {
        let btn = app.descendants(matching: .any)["btn_create_volume_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testPruneButtonExists() {
        let btn = app.descendants(matching: .any)["btn_prune_volume_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testSortButtonExists() {
        let btn = app.descendants(matching: .any)["btn_sort_volumes"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Remove button per row

    func testRemoveButtonExistsForVolume() {
        let btn = app.descendants(matching: .any)["btn_remove_volume_postgres_data"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Create Sheet

    func testCreateSheetOpens() {
        app.descendants(matching: .any)["btn_create_volume_new"].click()
        let nameField = app.descendants(matching: .any)["field_volume_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    }

    func testCreateSheetHasConfirmButton() {
        app.descendants(matching: .any)["btn_create_volume_new"].click()
        let btn = app.descendants(matching: .any)["btn_confirm_volume_create"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testCreateConfirmDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_create_volume_new"].click()
        let btn = app.descendants(matching: .any)["btn_confirm_volume_create"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled)
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

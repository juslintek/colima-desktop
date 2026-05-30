import XCTest

final class NetworkManagementUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_networks"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_networks"].waitForExistence(timeout: 3))
    }

    // MARK: - Table & Rows

    func testNetworksTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_networks"].exists)
    }

    func testMockNetworkRowsExist() {
        for name in ["bridge", "host", "app-network"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_network_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    // MARK: - Toolbar buttons

    func testCreateButtonExists() {
        let btn = app.descendants(matching: .any)["btn_create_network_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testPruneButtonExists() {
        let btn = app.descendants(matching: .any)["btn_prune_network_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testSortButtonExists() {
        let btn = app.descendants(matching: .any)["btn_sort_networks"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Remove button per row

    func testRemoveButtonExistsForNetwork() {
        let btn = app.descendants(matching: .any)["btn_remove_network_app-network"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Create Sheet

    func testCreateSheetOpens() {
        app.descendants(matching: .any)["btn_create_network_new"].click()
        let nameField = app.descendants(matching: .any)["field_network_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    }

    func testCreateSheetHasConfirmButton() {
        app.descendants(matching: .any)["btn_create_network_new"].click()
        let btn = app.descendants(matching: .any)["btn_confirm_network_create"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testCreateConfirmDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_create_network_new"].click()
        let btn = app.descendants(matching: .any)["btn_confirm_network_create"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled)
    }

    // MARK: - Validation

    func testNetworkValidationError() {
        app.descendants(matching: .any)["btn_create_network_new"].click()
        let nameField = app.descendants(matching: .any)["field_network_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("invalid name with spaces!")
        let err = app.descendants(matching: .any)["text_network_validation_error"]
        XCTAssertTrue(err.waitForExistence(timeout: 3))
    }
}

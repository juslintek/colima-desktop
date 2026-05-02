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

    func testNetworksTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_networks"].exists)
    }

    func testMockNetworkRowsExist() {
        for name in ["bridge", "host", "app-network"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_network_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    func testCreateNetworkAddsRow() {
        app.descendants(matching: .any)["btn_create_network_new"].click()
        let nameField = app.descendants(matching: .any)["field_network_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("test-net")
        app.descendants(matching: .any)["btn_confirm_network_create"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("created"))
        XCTAssertTrue(app.descendants(matching: .any)["row_network_test-net"].waitForExistence(timeout: 3))
    }

    func testRemoveNetworkRemovesRow() {
        let row = app.descendants(matching: .any)["row_network_app-network"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_remove_network_app-network"].click()
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: row)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("removed"))
    }

    func testPruneNetworksShowsToast() {
        app.descendants(matching: .any)["btn_prune_network_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("pruned"))
    }

    func testInspectNetworkShowsToast() {
        app.descendants(matching: .any)["btn_inspect_network_bridge"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Inspecting"))
    }

    func testConnectNetworkShowsToast() {
        app.descendants(matching: .any)["btn_connect_network_bridge"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Connect"))
    }

    func testDisconnectNetworkShowsToast() {
        app.descendants(matching: .any)["btn_disconnect_network_bridge"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Disconnect"))
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

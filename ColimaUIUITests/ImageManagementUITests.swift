import XCTest

final class ImageManagementUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_images"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_images"].waitForExistence(timeout: 3))
    }

    func testImagesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_images"].exists)
    }

    func testMockImageRowsExist() {
        for repo in ["nginx", "postgres", "redis", "node", "python"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_image_\(repo)"].waitForExistence(timeout: 3), "Missing: \(repo)")
        }
    }

    func testPullImageAddsRow() {
        let pullField = app.descendants(matching: .any)["field_images_pull_name"]
        XCTAssertTrue(pullField.waitForExistence(timeout: 3))
        pullField.click()
        pullField.typeText("alpine")
        app.descendants(matching: .any)["btn_pull_image_new"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("pulled"))
        XCTAssertTrue(app.descendants(matching: .any)["row_image_alpine"].waitForExistence(timeout: 3))
    }

    func testRemoveImageRemovesRow() {
        let row = app.descendants(matching: .any)["row_image_redis"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_remove_image_redis"].click()
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: row)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("removed"))
    }

    func testPruneImagesShowsToast() {
        app.descendants(matching: .any)["btn_prune_image_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("pruned"))
    }

    func testHistoryButtonShowsToast() {
        app.descendants(matching: .any)["btn_history_image_nginx"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("History"))
    }

    func testTagButtonShowsToast() {
        app.descendants(matching: .any)["btn_tag_image_nginx"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Tagged"))
    }

    func testPushButtonShowsToast() {
        app.descendants(matching: .any)["btn_push_image_nginx"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Push"))
    }

    func testExportButtonShowsToast() {
        app.descendants(matching: .any)["btn_export_image_nginx"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Export"))
    }

    func testInspectButtonShowsToast() {
        app.descendants(matching: .any)["btn_inspect_image_nginx"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Inspect"))
    }

    func testSearchHubShowsToast() {
        let hubField = app.descendants(matching: .any)["field_images_hub_search"]
        XCTAssertTrue(hubField.waitForExistence(timeout: 3))
        hubField.click()
        hubField.typeText("ubuntu")
        app.descendants(matching: .any)["btn_search_image_hub"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Search Docker Hub"))
    }

    func testImportButtonShowsToast() {
        let importField = app.descendants(matching: .any)["field_images_import_path"]
        XCTAssertTrue(importField.waitForExistence(timeout: 3))
        importField.click()
        importField.typeText("/tmp/image.tar")
        app.descendants(matching: .any)["btn_import_image_new"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Import"))
    }

    func testSearchFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_images_search"].waitForExistence(timeout: 3))
    }

    // MARK: - Sheet: History

    func testHistorySheetOpens() {
        app.descendants(matching: .any)["btn_history_image_nginx"].click()
        let sheet = app.descendants(matching: .any)["sheet_history"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_history"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_history"].waitForExistence(timeout: 5))
    }

    func testHistorySheetCloseButton() {
        app.descendants(matching: .any)["btn_history_image_nginx"].click()
        let close = app.descendants(matching: .any)["btn_close_history"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testHistorySheetLayersTable() {
        app.descendants(matching: .any)["btn_history_image_nginx"].click()
        let table = app.descendants(matching: .any)["table_history_layers"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5) || app.descendants(matching: .any)["table_history_layers"].waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Search

    func testSearchSheetOpens() {
        let hubField = app.descendants(matching: .any)["field_images_hub_search"]
        XCTAssertTrue(hubField.waitForExistence(timeout: 3))
        hubField.click()
        hubField.typeText("ubuntu")
        app.descendants(matching: .any)["btn_search_image_hub"].click()
        let sheet = app.descendants(matching: .any)["sheet_search"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_search"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_search"].waitForExistence(timeout: 5))
    }

    func testSearchSheetCloseButton() {
        let hubField = app.descendants(matching: .any)["field_images_hub_search"]
        hubField.click()
        hubField.typeText("ubuntu")
        app.descendants(matching: .any)["btn_search_image_hub"].click()
        let close = app.descendants(matching: .any)["btn_close_search"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testSearchSheetSearchField() {
        let hubField = app.descendants(matching: .any)["field_images_hub_search"]
        hubField.click()
        hubField.typeText("ubuntu")
        app.descendants(matching: .any)["btn_search_image_hub"].click()
        let field = app.descendants(matching: .any)["field_search_hub"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testSearchSheetGoButton() {
        let hubField = app.descendants(matching: .any)["field_images_hub_search"]
        hubField.click()
        hubField.typeText("ubuntu")
        app.descendants(matching: .any)["btn_search_image_hub"].click()
        let btn = app.descendants(matching: .any)["btn_search_hub_go"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testSearchSheetResultsTable() {
        let hubField = app.descendants(matching: .any)["field_images_hub_search"]
        hubField.click()
        hubField.typeText("ubuntu")
        app.descendants(matching: .any)["btn_search_image_hub"].click()
        let table = app.descendants(matching: .any)["table_search_results"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5) || app.descendants(matching: .any)["table_search_results"].waitForExistence(timeout: 5))
    }
}

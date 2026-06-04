import XCTest

final class ImageManagementUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        E2ELaunch.configure(app)
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_images"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_images"].waitForExistence(timeout: 3))
    }

    // MARK: - Table & Rows

    func testImagesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_images"].exists)
    }

    func testMockImageRowsExist() {
        for repo in ["nginx", "postgres", "redis", "node", "python"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_image_\(repo)"].waitForExistence(timeout: 3), "Missing: \(repo)")
        }
    }

    // MARK: - Toolbar buttons

    func testSearchFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_images_search"].waitForExistence(timeout: 3))
    }

    func testPullSheetButtonExists() {
        let btn = app.descendants(matching: .any)["btn_pull_image_new_sheet"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testPruneButtonExists() {
        let btn = app.descendants(matching: .any)["btn_prune_image_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testSortButtonExists() {
        let btn = app.descendants(matching: .any)["btn_sort_images"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Remove button per row

    func testRemoveButtonExistsForImage() {
        let btn = app.descendants(matching: .any)["btn_remove_image_nginx"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Pull Sheet

    func testPullSheetOpens() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let field = app.descendants(matching: .any)["field_images_pull_name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testPullSheetHasHubSearchField() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let field = app.descendants(matching: .any)["field_images_hub_search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testPullSheetHasSearchHubButton() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let btn = app.descendants(matching: .any)["btn_search_image_hub"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testPullSheetHasImportField() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let field = app.descendants(matching: .any)["field_images_import_path"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testPullSheetHasImportButton() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let btn = app.descendants(matching: .any)["btn_import_image_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testPullSheetPullButtonDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let btn = app.descendants(matching: .any)["btn_pull_image_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled)
    }

    func testPullSheetPullButtonEnabledWithInput() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let field = app.descendants(matching: .any)["field_images_pull_name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("alpine")
        let btn = app.descendants(matching: .any)["btn_pull_image_new"]
        XCTAssertTrue(btn.isEnabled)
    }

    func testImportButtonDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_pull_image_new_sheet"].click()
        let btn = app.descendants(matching: .any)["btn_import_image_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled)
    }
}

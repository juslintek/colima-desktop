import XCTest

final class ContainerManagementUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_containers"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_containers"].waitForExistence(timeout: 3))
    }

    // MARK: - Row existence

    func testMockContainerRowsExist() {
        for name in ["web-server", "postgres-db", "redis-cache", "api-service", "worker"] {
            XCTAssertTrue(app.descendants(matching: .any)["row_container_\(name)"].waitForExistence(timeout: 3), "Missing: \(name)")
        }
    }

    // MARK: - Status indicators

    func testRunningContainerHasGreenIndicator() {
        let status = app.descendants(matching: .any)["status_indicator_web-server"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
    }

    func testStoppedContainerHasIndicator() {
        let status = app.descendants(matching: .any)["status_indicator_redis-cache"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
    }

    // MARK: - Action buttons existence

    func testStopButtonExistsForRunningContainer() {
        let btn = app.descendants(matching: .any)["btn_stop_container_web-server"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testStartButtonExistsForStoppedContainer() {
        let btn = app.descendants(matching: .any)["btn_start_container_redis-cache"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testRemoveButtonExists() {
        let btn = app.descendants(matching: .any)["btn_remove_container_web-server"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testPruneButtonExists() {
        let btn = app.descendants(matching: .any)["btn_prune_container_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    // MARK: - Search

    func testSearchFieldExists() {
        let search = app.descendants(matching: .any)["field_containers_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
    }

    func testSearchFiltersContainers() {
        let search = app.descendants(matching: .any)["field_containers_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("web")
        XCTAssertTrue(app.descendants(matching: .any)["row_container_web-server"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["row_container_postgres-db"].exists)
    }

    // MARK: - Sort

    func testSortButtonExists() {
        let btn = app.descendants(matching: .any)["btn_sort_containers"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Create Container Dialog

    func testCreateButtonExists() {
        let btn = app.descendants(matching: .any)["btn_create_container_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testCreateContainerDialogOpens() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let nameField = app.descendants(matching: .any)["field_create_container_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    }

    func testCreateContainerDialogHasImageField() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let imageField = app.descendants(matching: .any)["field_create_container_image"]
        XCTAssertTrue(imageField.waitForExistence(timeout: 3))
    }

    func testCreateContainerDialogHasBrowseButton() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let browseBtn = app.descendants(matching: .any)["btn_browse_images"]
        XCTAssertTrue(browseBtn.waitForExistence(timeout: 3))
    }

    func testCreateContainerDialogHasConfirmButton() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let confirmBtn = app.descendants(matching: .any)["btn_confirm_container_create"]
        XCTAssertTrue(confirmBtn.waitForExistence(timeout: 3))
    }

    func testCreateContainerDialogCancel() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let cancelBtn = app.descendants(matching: .any)["btn_cancel_container_create"]
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 3))
        cancelBtn.click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_create_container_new"].waitForExistence(timeout: 3))
    }

    func testCreateContainerConfirmDisabledWhenEmpty() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let confirmBtn = app.descendants(matching: .any)["btn_confirm_container_create"]
        XCTAssertTrue(confirmBtn.waitForExistence(timeout: 3))
        XCTAssertFalse(confirmBtn.isEnabled)
    }

    // MARK: - Validation Errors

    func testContainerNameValidationError() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let nameField = app.descendants(matching: .any)["field_create_container_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("invalid name with spaces")
        let err = app.descendants(matching: .any)["text_container_name_error"]
        XCTAssertTrue(err.waitForExistence(timeout: 3))
    }

    func testImageExistsLocalIndicator() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let imageField = app.descendants(matching: .any)["field_create_container_image"]
        XCTAssertTrue(imageField.waitForExistence(timeout: 3))
        imageField.click()
        imageField.typeText("nginx:latest")
        let indicator = app.descendants(matching: .any)["text_image_exists_local"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 3))
    }

    func testImageNotLocalIndicator() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let imageField = app.descendants(matching: .any)["field_create_container_image"]
        XCTAssertTrue(imageField.waitForExistence(timeout: 3))
        imageField.click()
        imageField.typeText("nonexistent-image-xyz:v99")
        let indicator = app.descendants(matching: .any)["text_image_not_local"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 3))
    }

    // MARK: - Image Browser Sheet

    func testImageBrowserSheetOpens() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let browseBtn = app.descendants(matching: .any)["btn_browse_images"]
        XCTAssertTrue(browseBtn.waitForExistence(timeout: 3))
        browseBtn.click()
        let sheet = app.descendants(matching: .any)["sheet_image_browser"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
    }

    func testImageBrowserSearchField() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let field = app.descendants(matching: .any)["field_image_browser_search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testImageBrowserLocalSection() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let section = app.descendants(matching: .any)["section_image_browser_local"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
    }

    func testImageBrowserHubSection() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let section = app.descendants(matching: .any)["section_image_browser_hub"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
    }

    func testImageBrowserTable() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let table = app.descendants(matching: .any)["table_image_browser"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
    }

    func testImageBrowserCancelButton() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let cancel = app.descendants(matching: .any)["btn_image_browser_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    }

    // MARK: - Detail Panel (inline tabs)

    func testSelectingContainerShowsDetailPanel() {
        let row = app.descendants(matching: .any)["row_container_web-server"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let detail = app.descendants(matching: .any)["container_detail_panel"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
    }

    func testDetailPanelHasTabPicker() {
        let row = app.descendants(matching: .any)["row_container_web-server"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.click()
        let picker = app.descendants(matching: .any)["picker_container_detail_tab"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
    }

    // MARK: - Confirmation dialog

    func testRemoveContainerShowsConfirmation() {
        app.descendants(matching: .any)["btn_remove_container_web-server"].click()
        let confirm = app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    }
}

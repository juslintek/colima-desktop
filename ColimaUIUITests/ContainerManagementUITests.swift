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

    // MARK: - State changes

    func testStartStoppedContainer() {
        app.descendants(matching: .any)["btn_start_container_redis-cache"].click()
        let status = app.descendants(matching: .any)["status_indicator_redis-cache"]
        let pred = NSPredicate(format: "value == %@", "running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("started"))
    }

    func testStopRunningContainer() {
        app.descendants(matching: .any)["btn_stop_container_web-server"].click()
        let status = app.descendants(matching: .any)["status_indicator_web-server"]
        let pred = NSPredicate(format: "value == %@", "exited")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("stopped"))
    }

    func testKillContainer() {
        app.descendants(matching: .any)["btn_kill_container_web-server"].click()
        let status = app.descendants(matching: .any)["status_indicator_web-server"]
        let pred = NSPredicate(format: "value == %@", "exited")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("killed"))
    }

    func testRestartContainer() {
        app.descendants(matching: .any)["btn_restart_container_web-server"].click()
        let status = app.descendants(matching: .any)["status_indicator_web-server"]
        let pred = NSPredicate(format: "value == %@", "running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("restarted"))
    }

    func testPauseContainer() {
        app.descendants(matching: .any)["btn_pause_container_web-server"].click()
        let status = app.descendants(matching: .any)["status_indicator_web-server"]
        let pred = NSPredicate(format: "value == %@", "paused")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("paused"))
    }

    func testUnpauseContainer() {
        app.descendants(matching: .any)["btn_unpause_container_worker"].click()
        let status = app.descendants(matching: .any)["status_indicator_worker"]
        let pred = NSPredicate(format: "value == %@", "running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("unpaused"))
    }

    func testRemoveContainerRemovesRow() {
        let row = app.descendants(matching: .any)["row_container_redis-cache"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_remove_container_redis-cache"].click()
        app.descendants(matching: .any)["Confirm"].click()
        let gone = NSPredicate(format: "exists == false")
        let exp = XCTNSPredicateExpectation(predicate: gone, object: row)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("removed"))
    }

    func testPruneContainersShowsToast() {
        app.descendants(matching: .any)["btn_prune_container_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("pruned"))
    }

    // MARK: - Search

    func testSearchFiltersContainers() {
        let search = app.descendants(matching: .any)["field_containers_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("web")
        XCTAssertTrue(app.descendants(matching: .any)["row_container_web-server"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["row_container_postgres-db"].exists)
    }

    // MARK: - Per-row action buttons

    func testLogsButtonShowsToast() {
        app.descendants(matching: .any)["btn_logs_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Logs"))
    }

    func testInspectButtonShowsToast() {
        app.descendants(matching: .any)["btn_inspect_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Inspect"))
    }

    func testExecButtonShowsToast() {
        app.descendants(matching: .any)["btn_exec_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Exec"))
    }

    func testTopButtonShowsToast() {
        app.descendants(matching: .any)["btn_top_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Top"))
    }

    func testStatsButtonShowsToast() {
        app.descendants(matching: .any)["btn_stats_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Stats"))
    }

    func testExportButtonShowsToast() {
        app.descendants(matching: .any)["btn_export_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Export"))
    }

    func testChangesButtonShowsToast() {
        app.descendants(matching: .any)["btn_changes_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Changes"))
    }

    func testWaitButtonShowsToast() {
        app.descendants(matching: .any)["btn_wait_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Wait"))
    }

    func testAttachButtonShowsToast() {
        app.descendants(matching: .any)["btn_attach_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Attach"))
    }

    func testUpdateResourcesButtonShowsToast() {
        app.descendants(matching: .any)["btn_update_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Resources updated"))
    }

    func testCopyButtonShowsToast() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Copy"))
    }

    func testCreateContainerShowsToast() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let nameField = app.descendants(matching: .any)["field_create_container_name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.click()
        nameField.typeText("test-ctr")
        let imageField = app.descendants(matching: .any)["field_create_container_image"]
        imageField.click()
        imageField.typeText("alpine:latest")
        app.descendants(matching: .any)["btn_confirm_container_create"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("created"))
    }

    func testCreateContainerDialogCancel() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let cancelBtn = app.descendants(matching: .any)["btn_cancel_container_create"]
        XCTAssertTrue(cancelBtn.waitForExistence(timeout: 3))
        cancelBtn.click()
        // Sheet should dismiss — create button should be visible again
        XCTAssertTrue(app.descendants(matching: .any)["btn_create_container_new"].waitForExistence(timeout: 3))
    }

    // MARK: - Sheet: Inspect

    func testInspectSheetOpens() {
        app.descendants(matching: .any)["btn_inspect_container_web-server"].click()
        let sheet = app.descendants(matching: .any)["sheet_inspect"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_inspect"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_inspect"].waitForExistence(timeout: 5))
    }

    func testInspectSheetCloseButton() {
        app.descendants(matching: .any)["btn_inspect_container_web-server"].click()
        let close = app.descendants(matching: .any)["btn_close_inspect"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testInspectSheetCopyButton() {
        app.descendants(matching: .any)["btn_inspect_container_web-server"].click()
        let copy = app.descendants(matching: .any)["btn_copy_inspect"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Logs

    func testLogsSheetOpens() {
        app.descendants(matching: .any)["btn_logs_container_web-server"].click()
        let sheet = app.descendants(matching: .any)["sheet_logs"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_logs"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_logs"].waitForExistence(timeout: 5))
    }

    func testLogsSheetCloseButton() {
        app.descendants(matching: .any)["btn_logs_container_web-server"].click()
        let close = app.descendants(matching: .any)["btn_close_logs"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testLogsSheetCopyButton() {
        app.descendants(matching: .any)["btn_logs_container_web-server"].click()
        let copy = app.descendants(matching: .any)["btn_copy_logs"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
    }

    func testLogsSheetClearButton() {
        app.descendants(matching: .any)["btn_logs_container_web-server"].click()
        let clear = app.descendants(matching: .any)["btn_clear_logs"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
    }

    func testLogsSheetFollowToggle() {
        app.descendants(matching: .any)["btn_logs_container_web-server"].click()
        let toggle = app.descendants(matching: .any)["toggle_logs_follow"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5) || app.descendants(matching: .any)["toggle_logs_follow"].waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Terminal

    func testTerminalSheetOpens() {
        app.descendants(matching: .any)["btn_exec_container_web-server"].click()
        let sheet = app.descendants(matching: .any)["sheet_terminal"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_terminal"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_terminal"].waitForExistence(timeout: 5))
    }

    func testTerminalSheetCloseButton() {
        app.descendants(matching: .any)["btn_exec_container_web-server"].click()
        let close = app.descendants(matching: .any)["btn_close_terminal"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testTerminalSheetInputField() {
        app.descendants(matching: .any)["btn_exec_container_web-server"].click()
        let field = app.descendants(matching: .any)["field_terminal_input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testTerminalSheetOpenExternal() {
        app.descendants(matching: .any)["btn_exec_container_web-server"].click()
        let btn = app.descendants(matching: .any)["btn_open_terminal_external"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Stats

    func testStatsSheetOpens() {
        app.descendants(matching: .any)["btn_stats_container_web-server"].click()
        let sheet = app.descendants(matching: .any)["sheet_stats"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_stats"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_stats"].waitForExistence(timeout: 5))
    }

    func testStatsSheetCloseButton() {
        app.descendants(matching: .any)["btn_stats_container_web-server"].click()
        let close = app.descendants(matching: .any)["btn_close_stats"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testStatsSheetLiveIndicator() {
        app.descendants(matching: .any)["btn_stats_container_web-server"].click()
        let indicator = app.descendants(matching: .any)["indicator_stats_live"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 5) || app.descendants(matching: .any)["indicator_stats_live"].waitForExistence(timeout: 5))
    }

    func testStatsSheetProcessesTable() {
        app.descendants(matching: .any)["btn_stats_container_web-server"].click()
        let table = app.descendants(matching: .any)["table_stats_processes"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5) || app.descendants(matching: .any)["table_stats_processes"].waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Changes

    func testChangesSheetOpens() {
        app.descendants(matching: .any)["btn_changes_container_web-server"].click()
        let sheet = app.descendants(matching: .any)["sheet_changes"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_changes"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_changes"].waitForExistence(timeout: 5))
    }

    func testChangesSheetCloseButton() {
        app.descendants(matching: .any)["btn_changes_container_web-server"].click()
        let close = app.descendants(matching: .any)["btn_close_changes"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }

    func testChangesSheetTable() {
        app.descendants(matching: .any)["btn_changes_container_web-server"].click()
        let table = app.descendants(matching: .any)["table_changes"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5) || app.descendants(matching: .any)["table_changes"].waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Copy Files

    func testCopyFilesSheetOpens() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let sheet = app.descendants(matching: .any)["sheet_copy_files"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_copy_files"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_copy_files"].waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetDirectionPicker() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let picker = app.descendants(matching: .any)["picker_copy_direction"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5) || app.segmentedControls["picker_copy_direction"].waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetHostPathField() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let field = app.descendants(matching: .any)["field_copy_host_path"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetContainerPathField() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let field = app.descendants(matching: .any)["field_copy_container_path"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetCommandPreview() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let preview = app.descendants(matching: .any)["text_copy_command_preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetExecuteButton() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let btn = app.descendants(matching: .any)["btn_copy_execute"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetCancelButton() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let btn = app.descendants(matching: .any)["btn_copy_cancel"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetBrowseHostButton() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        let btn = app.descendants(matching: .any)["btn_copy_browse_host"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testCopyFilesSheetErrorText() {
        app.descendants(matching: .any)["btn_copy_container_web-server"].click()
        // Enter invalid path to trigger error
        let hostField = app.descendants(matching: .any)["field_copy_host_path"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 5))
        hostField.click()
        hostField.typeText("")
        app.descendants(matching: .any)["btn_copy_execute"].click()
        let err = app.descendants(matching: .any)["text_copy_error"]
        XCTAssertTrue(err.waitForExistence(timeout: 5))
    }

    // MARK: - Sheet: Image Browser (from Create dialog)

    func testImageBrowserSheetOpens() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        let browseBtn = app.descendants(matching: .any)["btn_browse_images"]
        XCTAssertTrue(browseBtn.waitForExistence(timeout: 3))
        browseBtn.click()
        let sheet = app.descendants(matching: .any)["sheet_image_browser"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_image_browser"].waitForExistence(timeout: 5))
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
        let section = app.descendants(matching: .any)["section_image_browser_local"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5) || app.descendants(matching: .any)["section_image_browser_local"].waitForExistence(timeout: 5))
    }

    func testImageBrowserHubSection() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let section = app.descendants(matching: .any)["section_image_browser_hub"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5) || app.descendants(matching: .any)["section_image_browser_hub"].waitForExistence(timeout: 5))
    }

    func testImageBrowserTable() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let table = app.descendants(matching: .any)["table_image_browser"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5) || app.descendants(matching: .any)["table_image_browser"].waitForExistence(timeout: 5))
    }

    func testImageBrowserCancelButton() {
        app.descendants(matching: .any)["btn_create_container_new"].click()
        app.descendants(matching: .any)["btn_browse_images"].click()
        let cancel = app.descendants(matching: .any)["btn_image_browser_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
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
}

import XCTest

final class MonitoringUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_monitoring"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_vmresources"].waitForExistence(timeout: 3))
    }

    func testMonitoringTitle() {
        XCTAssertTrue(app.descendants(matching: .any)["Monitoring"].waitForExistence(timeout: 3))
    }

    func testVMResourcesSection() {
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_vmresources"].exists)
    }

    func testCPUUsageDisplayed() {
        XCTAssertTrue(app.descendants(matching: .any)["stat_cpu_usage"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["stat_cpu_usage"].label, "35%")
    }

    func testMemoryUsageDisplayed() {
        XCTAssertTrue(app.descendants(matching: .any)["stat_memory_usage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["stat_memory_usage"].label.contains("5.0"))
    }

    func testDiskUsageDisplayed() {
        XCTAssertTrue(app.descendants(matching: .any)["stat_disk_usage"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["stat_disk_usage"].label.contains("45.2"))
    }

    func testContainerStatsTableHasData() {
        XCTAssertTrue(app.descendants(matching: .any)["table_monitoring_stats"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["stat_row_web-server"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stat_row_postgres-db"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stat_row_api-service"].exists)
    }

    func testProcessListExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_monitoring_processes"].waitForExistence(timeout: 3))
    }

    func testProcessFilterFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_monitoring_process_filter"].waitForExistence(timeout: 3))
    }

    func testKillProcessShowsToast() {
        app.descendants(matching: .any)["btn_kill_monitoring_process"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("killed"))
    }

    func testRefreshShowsToast() {
        app.descendants(matching: .any)["btn_refresh_monitoring_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("refreshed"))
    }

    func testTopProcessesShowsToast() {
        app.descendants(matching: .any)["btn_top_monitoring_vm"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Top processes"))
    }

    func testMemoryGovernorIndicatorExists() {
        let indicator = app.descendants(matching: .any)["indicator_memory_governor"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 3))
        XCTAssertEqual(indicator.value as? String, "Normal")
    }

    func testAutoRefreshToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_monitoring_autorefresh"].waitForExistence(timeout: 3))
    }

    func testDiskBreakdownExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_disk_breakdown"].waitForExistence(timeout: 3))
    }

    // MARK: - New Monitoring Elements

    func testLastUpdatedTextExists() {
        let text = app.descendants(matching: .any)["text_monitoring_last_updated"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
    }

    func testAppMemoryTextExists() {
        let text = app.descendants(matching: .any)["text_monitoring_app_memory"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
    }

    func testGovernorExplanationExists() {
        let text = app.descendants(matching: .any)["text_governor_explanation"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
    }
}

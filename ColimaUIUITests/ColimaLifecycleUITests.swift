import XCTest

final class ColimaLifecycleUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_dashboard"].waitForExistence(timeout: 5))
    }

    // MARK: - Button Existence & State

    func testStartButtonExistsAndDisabledWhenRunning() {
        let btn = app.descendants(matching: .any)["btn_start_vm_dashboard"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertFalse(btn.isEnabled) // Disabled when VM is running
    }

    func testStopButtonExistsAndEnabled() {
        let btn = app.descendants(matching: .any)["btn_stop_vm_dashboard"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled) // Enabled when VM is running
    }

    func testRestartButtonExistsAndEnabled() {
        let btn = app.descendants(matching: .any)["btn_restart_vm_dashboard"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testDeleteVMSoftShowsConfirmation() {
        app.descendants(matching: .any)["btn_delete_vm_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Confirm"].waitForExistence(timeout: 3))
    }

    func testDeleteVMHardShowsConfirmation() {
        app.descendants(matching: .any)["btn_deletedata_vm_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Confirm"].waitForExistence(timeout: 3))
    }

    // MARK: - Dashboard Info

    func testSSHButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_ssh_vm_dashboard"].waitForExistence(timeout: 3))
    }

    func testSSHConfigButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_sshconfig_vm_dashboard"].waitForExistence(timeout: 3))
    }

    func testUpdateButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_update_vm_dashboard"].waitForExistence(timeout: 3))
    }

    func testPruneButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_prune_vm_dashboard"].waitForExistence(timeout: 3))
    }

    func testVersionDisplayExists() {
        let ver = app.descendants(matching: .any)["text_version_dashboard"]
        XCTAssertTrue(ver.waitForExistence(timeout: 3))
    }

    func testTemplateButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_template_vm_dashboard"].waitForExistence(timeout: 3))
    }

    // MARK: - Resource display

    func testResourceDisplayValues() {
        XCTAssertTrue(app.staticTexts["4 cores"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["8 GiB"].exists)
        XCTAssertTrue(app.staticTexts["100 GiB"].exists)
    }

    func testQuickStatsShowCounts() {
        XCTAssertTrue(app.descendants(matching: .any)["stat_containers_count"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["stat_images_count"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stat_volumes_count"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stat_networks_count"].exists)
    }

    // MARK: - VM Status

    func testVMStatusShowsRunning() {
        let status = app.descendants(matching: .any)["status_indicator_dashboard"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.value as? String, "running")
    }
}

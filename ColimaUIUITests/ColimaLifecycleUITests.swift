import XCTest

final class ColimaLifecycleUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_dashboard"].waitForExistence(timeout: 3))
    }

    // MARK: - VM Lifecycle

    func testStopVMChangesStatus() {
        app.descendants(matching: .any)["btn_stop_vm_dashboard"].click()
        let status = app.descendants(matching: .any)["status_indicator_dashboard"]
        let pred = NSPredicate(format: "value == %@", "stopped")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("stopped"))
    }

    func testStartVMAfterStop() {
        app.descendants(matching: .any)["btn_stop_vm_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["toast_notification_text"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_start_vm_dashboard"].click()
        let status = app.descendants(matching: .any)["status_indicator_dashboard"]
        let pred = NSPredicate(format: "value == %@", "running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("started"))
    }

    func testRestartVMShowsToast() {
        app.descendants(matching: .any)["btn_restart_vm_dashboard"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("restarted"))
    }

    func testDeleteVMSoftShowsConfirmation() {
        app.descendants(matching: .any)["btn_delete_vm_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Confirm"].waitForExistence(timeout: 3))
    }

    func testDeleteVMHardShowsConfirmation() {
        app.descendants(matching: .any)["btn_deletedata_vm_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["Confirm"].waitForExistence(timeout: 3))
    }

    // MARK: - Dashboard buttons

    func testSSHButtonShowsToast() {
        app.descendants(matching: .any)["btn_ssh_vm_dashboard"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("SSH"))
    }

    func testSSHConfigButtonShowsToast() {
        app.descendants(matching: .any)["btn_sshconfig_vm_dashboard"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("SSH config"))
    }

    func testUpdateButtonShowsToast() {
        app.descendants(matching: .any)["btn_update_vm_dashboard"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("updated"))
    }

    func testPruneButtonShowsToast() {
        app.descendants(matching: .any)["btn_prune_vm_dashboard"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("pruned"))
    }

    func testVersionDisplayExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_version_dashboard"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["text_version_dashboard"].label.contains("0.10.1"))
    }

    func testTemplateButtonShowsToast() {
        app.descendants(matching: .any)["btn_template_vm_dashboard"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("template"))
    }

    // MARK: - Resource display

    func testResourceDisplayValues() {
        XCTAssertTrue(app.descendants(matching: .any)["4 cores"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["8 GiB"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["100 GiB"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["docker"].exists)
    }

    func testQuickStatsShowCounts() {
        XCTAssertTrue(app.descendants(matching: .any)["stat_containers_count"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["stat_images_count"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stat_volumes_count"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["stat_networks_count"].exists)
    }
}

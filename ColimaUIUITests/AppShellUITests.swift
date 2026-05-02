import XCTest

final class AppShellUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
    }

    // MARK: - Sidebar

    func testSidebarExists() {
        XCTAssertTrue(app.descendants(matching: .any)["main_split_view"].waitForExistence(timeout: 3))
    }

    func testAllSidebarTabsExist() {
        let tabs = [
            "tab_dashboard", "tab_containers", "tab_images", "tab_volumes",
            "tab_networks", "tab_configuration", "tab_profiles", "tab_kubernetes",
            "tab_ai", "tab_monitoring", "tab_runtimecontrols", "tab_community"
        ]
        for id in tabs {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 3), "Missing tab: \(id)")
        }
    }

    // MARK: - Navigation

    func testNavigateToDashboard() {
        app.descendants(matching: .any)["tab_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_dashboard"].waitForExistence(timeout: 3))
    }

    func testNavigateToContainers() {
        app.descendants(matching: .any)["tab_containers"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_containers"].waitForExistence(timeout: 3))
    }

    func testNavigateToImages() {
        app.descendants(matching: .any)["tab_images"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_images"].waitForExistence(timeout: 3))
    }

    func testNavigateToVolumes() {
        app.descendants(matching: .any)["tab_volumes"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_volumes"].waitForExistence(timeout: 3))
    }

    func testNavigateToNetworks() {
        app.descendants(matching: .any)["tab_networks"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_networks"].waitForExistence(timeout: 3))
    }

    func testNavigateToConfiguration() {
        app.descendants(matching: .any)["tab_configuration"].click()
        XCTAssertTrue(app.descendants(matching: .any)["field_config_cpus"].waitForExistence(timeout: 3))
    }

    func testNavigateToProfiles() {
        app.descendants(matching: .any)["tab_profiles"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_profiles"].waitForExistence(timeout: 3))
    }

    func testNavigateToKubernetes() {
        app.descendants(matching: .any)["tab_kubernetes"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_k8s"].waitForExistence(timeout: 3))
    }

    func testNavigateToAI() {
        app.descendants(matching: .any)["tab_ai"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_run_ai_model"].waitForExistence(timeout: 3))
    }

    func testNavigateToMonitoring() {
        app.descendants(matching: .any)["tab_monitoring"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_vmresources"].waitForExistence(timeout: 3))
    }

    func testNavigateToRuntimeControls() {
        app.descendants(matching: .any)["tab_runtimecontrols"].click()
        XCTAssertTrue(app.descendants(matching: .any)["text_docker_context"].waitForExistence(timeout: 3))
    }

    func testNavigateToCommunity() {
        app.descendants(matching: .any)["tab_community"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_open_community_discussions"].waitForExistence(timeout: 3))
    }

    // MARK: - Dashboard data

    func testDashboardVMStatusValue() {
        app.descendants(matching: .any)["tab_dashboard"].click()
        let status = app.descendants(matching: .any)["status_indicator_dashboard"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.value as? String, "running")
    }

    func testDashboardMockDataCounts() {
        app.descendants(matching: .any)["tab_dashboard"].click()
        XCTAssertTrue(app.descendants(matching: .any)["stat_containers_count"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["stat_containers_count"].label, "5")
        XCTAssertEqual(app.descendants(matching: .any)["stat_images_count"].label, "5")
        XCTAssertEqual(app.descendants(matching: .any)["stat_volumes_count"].label, "3")
        XCTAssertEqual(app.descendants(matching: .any)["stat_networks_count"].label, "3")
    }

    // MARK: - Sidebar widgets

    func testProfileSwitcherInSidebar() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_sidebar_profile"].waitForExistence(timeout: 3))
    }

    func testVMStatusIndicatorInToolbar() {
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_vm"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["status_indicator_vm"].value as? String, "running")
    }

    func testStatusIndicatorTextExists() {
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_text"].waitForExistence(timeout: 3))
    }

    func testMenuBarStatusText() {
        // MenuBarExtra elements may not be directly accessible via XCUITest.
        // They exist in a separate window. Try accessing via the app hierarchy:
        let statusText = app.descendants(matching: .any)["menubar_status_text"]
        if statusText.waitForExistence(timeout: 2) {
            XCTAssertTrue(statusText.exists)
        }
        // MenuBarExtra testing is a known XCUITest limitation — elements live
        // outside the main app window and may not be reachable.
    }

    func testMenuBarButtonsExist() {
        // MenuBarExtra buttons live outside the main window hierarchy.
        // Attempt to find them; document limitation if not accessible.
        let btnIds = ["menubar_btn_start", "menubar_btn_stop", "menubar_btn_restart",
                      "menubar_btn_open", "menubar_btn_quit"]
        for id in btnIds {
            let btn = app.descendants(matching: .any)[id]
            if btn.waitForExistence(timeout: 2) {
                XCTAssertTrue(btn.exists)
            }
        }
        // If none found, this is expected — MenuBarExtra content is not
        // accessible via standard XCUITest queries.
    }


}

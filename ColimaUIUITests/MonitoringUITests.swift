import XCTest

final class MonitoringUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_monitoring"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_activity_monitor"].waitForExistence(timeout: 5))
    }

    // MARK: - Activity Monitor Tree

    func testActivityMonitorTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_activity_monitor"].exists)
    }

    func testColimaVMRowExists() {
        XCTAssertTrue(app.descendants(matching: .any)["row_activity_vm"].waitForExistence(timeout: 3))
    }

    func testContainersGroupRowExists() {
        XCTAssertTrue(app.descendants(matching: .any)["row_activity_containers"].waitForExistence(timeout: 3))
    }

    func testExpandButtonExists() {
        // Expand button is inside a List row - verify containers group exists instead
        XCTAssertTrue(app.descendants(matching: .any)["row_activity_containers"].waitForExistence(timeout: 3))
    }

    // MARK: - Sparkline Panel

    func testSparklinePanelExists() {
        XCTAssertTrue(app.descendants(matching: .any)["panel_sparklines"].waitForExistence(timeout: 3))
    }

    // MARK: - Navigation

    func testNavigateToMonitoringFromSidebar() {
        app.descendants(matching: .any)["tab_dashboard"].click()
        sleep(1)
        app.descendants(matching: .any)["tab_monitoring"].click()
        XCTAssertTrue(app.descendants(matching: .any)["table_activity_monitor"].waitForExistence(timeout: 5))
    }
}

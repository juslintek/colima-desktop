import XCTest

final class MachinesUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        E2ELaunch.configure(app)
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_machines"].click()
        XCTAssertTrue(app.descendants(matching: .any)["row_machine_dev-ubuntu"].waitForExistence(timeout: 5))
    }

    // MARK: - Machine Rows

    func testDevUbuntuRowExists() {
        XCTAssertTrue(app.descendants(matching: .any)["row_machine_dev-ubuntu"].exists)
    }

    func testBuildFedoraRowExists() {
        XCTAssertTrue(app.descendants(matching: .any)["row_machine_build-fedora"].exists)
    }

    func testMacosCIRowExists() {
        XCTAssertTrue(app.descendants(matching: .any)["row_machine_macos-ci"].exists)
    }

    func testWin11TestRowExists() {
        XCTAssertTrue(app.descendants(matching: .any)["row_machine_win11-test"].exists)
    }

    // MARK: - Create Button

    func testCreateMachineButtonExistsAndEnabled() {
        let btn = app.descendants(matching: .any)["btn_create_machine"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    // MARK: - Running Count

    func testRunningCountSubtitleVisible() {
        XCTAssertTrue(app.staticTexts["2 running"].waitForExistence(timeout: 3))
    }
}

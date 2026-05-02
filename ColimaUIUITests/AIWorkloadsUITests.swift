import XCTest

final class AIWorkloadsUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_ai"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_run_ai_model"].waitForExistence(timeout: 5))
    }

    func testAITitle() {
        XCTAssertTrue(app.navigationBars["AI Workloads"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["AI Workloads"].waitForExistence(timeout: 5))
    }

    func testKrunkitStatusVisible() {
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_krunkit"].waitForExistence(timeout: 5))
    }

    func testModelNameFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_ai_modelname"].waitForExistence(timeout: 5))
    }

    func testRunnerPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_ai_runner"].waitForExistence(timeout: 5))
    }

    func testRunModelButtonExists() {
        let btn = app.descendants(matching: .any)["btn_run_ai_model"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isEnabled)
    }

    func testServeModelButtonExists() {
        let btn = app.descendants(matching: .any)["btn_serve_ai_model"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isEnabled)
    }

    func testSetupButtonExists() {
        let btn = app.descendants(matching: .any)["btn_setup_ai_model"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isEnabled)
    }

    func testBrowseModelsButtonExists() {
        let btn = app.descendants(matching: .any)["btn_browse_ai_registry"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isEnabled)
    }

    func testInstallKrunkitButtonExists() {
        let btn = app.descendants(matching: .any)["btn_install_ai_krunkit"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isEnabled)
    }

    func testCreateAIProfileButtonExists() {
        let btn = app.descendants(matching: .any)["btn_createprofile_ai_new"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isEnabled)
    }

    // MARK: - Model Library Tabs & Elements

    func testDownloadedTabExists() {
        let tab = app.descendants(matching: .any)["tab_ai_downloaded"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5) || app.descendants(matching: .any)["tab_ai_downloaded"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["tab_ai_downloaded"].waitForExistence(timeout: 5))
    }

    func testModelsTableExists() {
        let table = app.descendants(matching: .any)["table_ai_models"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5) || app.descendants(matching: .any)["table_ai_models"].waitForExistence(timeout: 5))
    }

    func testOpenBrowserButtonExists() {
        let btn = app.descendants(matching: .any)["btn_ai_open_browser"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testServeURLExists() {
        let url = app.descendants(matching: .any)["text_ai_serve_url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
    }

    func testRAMWarningExists() {
        let warning = app.descendants(matching: .any)["text_ai_ram_warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
    }
}

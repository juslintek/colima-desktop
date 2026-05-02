import XCTest

final class AIWorkloadsUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_ai"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_run_ai_model"].waitForExistence(timeout: 3))
    }

    func testAITitle() {
        XCTAssertTrue(app.navigationBars["AI Workloads"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["AI Workloads"].waitForExistence(timeout: 3))
    }

    func testKrunkitStatusVisible() {
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_krunkit"].waitForExistence(timeout: 3))
    }

    func testModelNameFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_ai_modelname"].waitForExistence(timeout: 3))
    }

    func testRunnerPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_ai_runner"].waitForExistence(timeout: 3))
    }

    func testRunModelShowsToast() {
        app.descendants(matching: .any)["btn_run_ai_model"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("running"))
    }

    func testServeModelShowsToast() {
        app.descendants(matching: .any)["btn_serve_ai_model"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("serving"))
    }

    func testSetupShowsToast() {
        app.descendants(matching: .any)["btn_setup_ai_model"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("setup"))
    }

    func testBrowseModelsShowsToast() {
        app.descendants(matching: .any)["btn_browse_ai_registry"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("browser"))
    }

    func testInstallKrunkitShowsToast() {
        app.descendants(matching: .any)["btn_install_ai_krunkit"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("installed"))
    }

    func testCreateAIProfileShowsToast() {
        app.descendants(matching: .any)["btn_createprofile_ai_new"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("profile created"))
    }

    // MARK: - Model Library Tabs & Elements

    func testDownloadedTabExists() {
        let tab = app.descendants(matching: .any)["tab_ai_downloaded"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_ai_downloaded"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_ai_downloaded"].waitForExistence(timeout: 3))
    }

    func testModelsTableExists() {
        let table = app.descendants(matching: .any)["table_ai_models"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3) || app.descendants(matching: .any)["table_ai_models"].waitForExistence(timeout: 3))
    }

    func testOpenBrowserButtonExists() {
        let btn = app.descendants(matching: .any)["btn_ai_open_browser"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testServeURLExists() {
        let url = app.descendants(matching: .any)["text_ai_serve_url"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
    }

    func testRAMWarningExists() {
        let warning = app.descendants(matching: .any)["text_ai_ram_warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
    }
}

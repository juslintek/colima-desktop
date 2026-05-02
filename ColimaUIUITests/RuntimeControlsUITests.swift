import XCTest

final class RuntimeControlsUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_runtimecontrols"].click()
        XCTAssertTrue(app.descendants(matching: .any)["text_docker_context"].waitForExistence(timeout: 3))
    }

    func testRuntimeControlsTitle() {
        XCTAssertTrue(app.navigationBars["Runtime Controls"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["Runtime Controls"].waitForExistence(timeout: 3))
    }

    func testDockerContextSwitchShowsToast() {
        app.descendants(matching: .any)["btn_switch_dockercontext"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Docker context"))
    }

    func testNerdctlRunShowsToast() {
        let field = app.descendants(matching: .any)["field_nerdctl_cmd"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("ps")
        app.descendants(matching: .any)["btn_run_nerdctl"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("nerdctl"))
    }

    func testIncusRunShowsToast() {
        let field = app.descendants(matching: .any)["field_incus_cmd"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("list")
        app.descendants(matching: .any)["btn_run_incus"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("incus"))
    }

    func testRuntimeSwitchShowsToast() {
        app.descendants(matching: .any)["btn_switch_runtime"].click()
        // Confirmation dialog appears
        app.descendants(matching: .any)["Confirm"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("switching"))
    }

    func testRuntimeUpdateShowsToast() {
        app.descendants(matching: .any)["btn_update_runtime"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("updated"))
    }

    func testDataPersistenceIndicatorExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_data_persistence"].waitForExistence(timeout: 3))
    }

    func testCurrentRuntimeDisplay() {
        let ctx = app.descendants(matching: .any)["text_docker_context"]
        XCTAssertTrue(ctx.waitForExistence(timeout: 3))
        XCTAssertTrue(ctx.label.contains("colima-"))
    }

    func testRuntimePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_target_runtime"].waitForExistence(timeout: 3))
    }

    // MARK: - Command Palette

    func testCommandPaletteFieldExists() {
        let field = app.descendants(matching: .any)["field_command_palette"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testRunCommandPaletteButtonExists() {
        let btn = app.descendants(matching: .any)["btn_run_command_palette"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testCommandOutputExists() {
        // Run a command to populate output
        let field = app.descendants(matching: .any)["field_command_palette"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("docker ps")
        app.descendants(matching: .any)["btn_run_command_palette"].click()
        let output = app.descendants(matching: .any)["text_command_output"].firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 3) || app.descendants(matching: .any)["text_command_output"].waitForExistence(timeout: 3))
    }

    // MARK: - Runtime Status

    func testRuntimeNameExists() {
        let text = app.descendants(matching: .any)["text_runtime_name"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
    }

    func testRuntimeVersionExists() {
        let text = app.descendants(matching: .any)["text_runtime_version"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
    }

    func testRuntimeSocketExists() {
        let text = app.descendants(matching: .any)["text_runtime_socket"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
    }

    func testCopySocketButtonExists() {
        let btn = app.descendants(matching: .any)["btn_copy_socket"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Tables

    func testRuntimeComparisonTableExists() {
        let table = app.descendants(matching: .any)["table_runtime_comparison"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3) || app.descendants(matching: .any)["table_runtime_comparison"].waitForExistence(timeout: 3))
    }

    func testDockerContextsTableExists() {
        let table = app.descendants(matching: .any)["table_docker_contexts"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3) || app.descendants(matching: .any)["table_docker_contexts"].waitForExistence(timeout: 3))
    }

    // MARK: - Command Runner Sheet

    func testCommandRunnerSheetOpens() {
        let field = app.descendants(matching: .any)["field_nerdctl_cmd"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("ps")
        app.descendants(matching: .any)["btn_run_nerdctl"].click()
        let sheet = app.descendants(matching: .any)["sheet_command_runner"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_command_runner"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["sheet_command_runner"].waitForExistence(timeout: 5))
    }

    func testCommandRunnerSheetInputField() {
        let field = app.descendants(matching: .any)["field_nerdctl_cmd"]
        field.click()
        field.typeText("ps")
        app.descendants(matching: .any)["btn_run_nerdctl"].click()
        let input = app.descendants(matching: .any)["field_command_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
    }

    func testCommandRunnerSheetRunButton() {
        let field = app.descendants(matching: .any)["field_nerdctl_cmd"]
        field.click()
        field.typeText("ps")
        app.descendants(matching: .any)["btn_run_nerdctl"].click()
        let btn = app.descendants(matching: .any)["btn_run_command"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
    }

    func testCommandRunnerSheetCloseButton() {
        let field = app.descendants(matching: .any)["field_nerdctl_cmd"]
        field.click()
        field.typeText("ps")
        app.descendants(matching: .any)["btn_run_nerdctl"].click()
        let close = app.descendants(matching: .any)["btn_close_command_runner"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
    }
}

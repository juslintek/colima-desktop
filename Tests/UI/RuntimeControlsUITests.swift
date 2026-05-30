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

    // MARK: - Runtime Status

    func testRuntimeNameExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_runtime_name"].waitForExistence(timeout: 3))
    }

    func testRuntimeVersionExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_runtime_version"].waitForExistence(timeout: 3))
    }

    func testRuntimeSocketExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_runtime_socket"].waitForExistence(timeout: 3))
    }

    func testCopySocketButtonExists() {
        let btn = app.descendants(matching: .any)["btn_copy_socket"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Command Palette

    func testCommandPaletteFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_command_palette"].waitForExistence(timeout: 3))
    }

    func testRunCommandPaletteButtonExists() {
        let btn = app.descendants(matching: .any)["btn_run_command_palette"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testCommandOutputExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_command_output"].waitForExistence(timeout: 3))
    }

    // MARK: - Runtime Switching

    func testRuntimePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_target_runtime"].waitForExistence(timeout: 3))
    }

    func testSwitchRuntimeButtonExists() {
        let btn = app.descendants(matching: .any)["btn_switch_runtime"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testSwitchRuntimeShowsConfirmation() {
        app.descendants(matching: .any)["btn_switch_runtime"].click()
        let confirm = app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    }

    // MARK: - Docker Context

    func testDockerContextDisplay() {
        let ctx = app.descendants(matching: .any)["text_docker_context"]
        XCTAssertTrue(ctx.waitForExistence(timeout: 3))
    }

    func testSwitchDockerContextButtonExists() {
        let btn = app.descendants(matching: .any)["btn_switch_dockercontext"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testUpdateRuntimeButtonExists() {
        let btn = app.descendants(matching: .any)["btn_update_runtime"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    // MARK: - Legacy Controls

    func testNerdctlFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_nerdctl_cmd"].waitForExistence(timeout: 3))
    }

    func testNerdctlRunButtonExists() {
        let btn = app.descendants(matching: .any)["btn_run_nerdctl"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testIncusFieldExists() {
        XCTAssertTrue(app.descendants(matching: .any)["field_incus_cmd"].waitForExistence(timeout: 3))
    }

    func testIncusRunButtonExists() {
        let btn = app.descendants(matching: .any)["btn_run_incus"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Data Persistence

    func testDataPersistenceIndicatorExists() {
        XCTAssertTrue(app.descendants(matching: .any)["text_data_persistence"].waitForExistence(timeout: 3))
    }

    // MARK: - Tables

    func testRuntimeComparisonTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_runtime_comparison"].waitForExistence(timeout: 3))
    }

    func testDockerContextsTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_docker_contexts"].waitForExistence(timeout: 3))
    }
}

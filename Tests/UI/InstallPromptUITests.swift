import XCTest

/// E2E for the first-run onboarding: when Colima is not installed, the app must
/// detect it and prompt to install (instead of showing an empty/broken UI).
///
/// Uses mock mode with `--no-colima` so `MockServiceProvider` reports Colima as
/// absent; clicking Install flips it to installed and the main UI appears.
final class InstallPromptUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        // This onboarding test simulates a missing Colima, which only the mock backend
        // can model — so force mock + --no-colima directly (independent of E2E_BACKEND).
        app.launchArguments = ["--ui-testing", "--backend-mock", "--no-colima"]
        app.launch()
        app.activate()
    }

    func testPromptShownWhenColimaMissing() {
        XCTAssertTrue(app.descendants(matching: .any)["text_colima_not_installed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["btn_install_colima"].exists)
    }

    func testMainUIHiddenUntilInstalled() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_install_colima"].waitForExistence(timeout: 5))
        // Dashboard must not be reachable while Colima is missing.
        XCTAssertFalse(app.descendants(matching: .any)["status_indicator_dashboard"].exists)
    }

    func testInstallProceedsToMainUI() {
        let install = app.descendants(matching: .any)["btn_install_colima"]
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        install.click()
        // After the (mock) install completes, the prompt is replaced by the app shell.
        XCTAssertTrue(app.descendants(matching: .any)["tab_dashboard"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["btn_install_colima"].exists)
    }
}

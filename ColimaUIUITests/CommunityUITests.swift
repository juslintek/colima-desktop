import XCTest

final class CommunityUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_community"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_open_community_discussions"].waitForExistence(timeout: 3))
    }

    // MARK: - Link buttons

    func testLinkButtonsExist() {
        for id in ["discussions", "issues", "releases", "docs"] {
            XCTAssertTrue(app.descendants(matching: .any)["btn_open_community_\(id)"].waitForExistence(timeout: 3), "Missing: \(id)")
        }
    }

    func testLinkButtonsAreEnabled() {
        for id in ["discussions", "issues", "releases", "docs"] {
            let btn = app.descendants(matching: .any)["btn_open_community_\(id)"]
            XCTAssertTrue(btn.isEnabled, "Not enabled: \(id)")
        }
    }

    // MARK: - Issue Wizard

    func testIssueWizardRepoPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_issue_repo"].waitForExistence(timeout: 3))
    }

    func testIssueWizardNext1ButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_issue_wizard_next1"].waitForExistence(timeout: 3))
    }

    func testIssueWizardStep2Fields() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
    }

    func testIssueDescriptionFieldExists() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let desc = app.textViews["field_community_issue_description"]
        XCTAssertTrue(desc.waitForExistence(timeout: 3))
    }

    func testIssueWizardBack2Button() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let back2 = app.descendants(matching: .any)["btn_issue_wizard_back2"]
        XCTAssertTrue(back2.waitForExistence(timeout: 3))
        back2.click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_issue_wizard_next1"].waitForExistence(timeout: 3))
    }

    func testIssueWizardStep3Buttons() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.click()
        titleField.typeText("Test issue")
        app.descendants(matching: .any)["btn_issue_wizard_next2"].click()
        let submitBtn = app.descendants(matching: .any)["btn_submit_community_issue"]
        XCTAssertTrue(submitBtn.waitForExistence(timeout: 3))
    }

    func testIssueWizardBack3Button() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.click()
        titleField.typeText("Test")
        app.descendants(matching: .any)["btn_issue_wizard_next2"].click()
        let back3 = app.descendants(matching: .any)["btn_issue_wizard_back3"]
        XCTAssertTrue(back3.waitForExistence(timeout: 3))
        back3.click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_issue_wizard_back2"].waitForExistence(timeout: 3))
    }

    func testCopyIssueButtonExists() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.click()
        titleField.typeText("Test issue")
        app.descendants(matching: .any)["btn_issue_wizard_next2"].click()
        let btn = app.descendants(matching: .any)["btn_copy_issue"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Discussions Table

    func testDiscussionsTableExists() {
        let table = app.descendants(matching: .any)["table_discussions"]
        XCTAssertTrue(table.waitForExistence(timeout: 3))
    }

    // MARK: - FAQ

    func testFAQSearchFieldExists() {
        let field = app.descendants(matching: .any)["field_faq_search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    // MARK: - System Info

    func testSystemInfoExists() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let disclosure = app.disclosureTriangles.firstMatch
        if disclosure.waitForExistence(timeout: 3) { disclosure.click() }
        let info = app.descendants(matching: .any)["text_system_info"]
        XCTAssertTrue(info.waitForExistence(timeout: 3))
    }
}

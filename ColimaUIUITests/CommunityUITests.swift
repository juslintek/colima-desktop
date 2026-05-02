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

    func testCommunityTitle() {
        XCTAssertTrue(app.navigationBars["Community"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["Community"].waitForExistence(timeout: 3))
    }

    func testLinkButtonsExist() {
        for id in ["discussions", "issues", "releases", "docs"] {
            XCTAssertTrue(app.descendants(matching: .any)["btn_open_community_\(id)"].waitForExistence(timeout: 3), "Missing: \(id)")
        }
    }

    func testLinkButtonShowsToast() {
        app.descendants(matching: .any)["btn_open_community_discussions"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Opening"))
    }

    func testIssueWizardRepoPickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_issue_repo"].waitForExistence(timeout: 3))
    }

    func testSubmitIssueShowsToast() {
        // Step 1: Next
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        // Step 2: Fill title and Next
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.click()
        titleField.typeText("Test issue")
        app.descendants(matching: .any)["btn_issue_wizard_next2"].click()
        // Step 3: Submit
        let submitBtn = app.descendants(matching: .any)["btn_submit_community_issue"]
        XCTAssertTrue(submitBtn.waitForExistence(timeout: 3))
        submitBtn.click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("submitted"))
    }

    func testFAQSectionExists() {
        // FAQ tips use dynamic IDs based on question text prefix
        // Check that at least one FAQ item exists
        let faq = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'faq_'"))
        XCTAssertGreaterThan(faq.count, 0)
    }

    func testFAQContentExists() {
        // Verify specific FAQ question text is visible
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Cannot connect to Docker'")).firstMatch.waitForExistence(timeout: 3))
    }

    func testAllLinkButtonsShowToast() {
        for id in ["issues", "releases", "docs"] {
            app.descendants(matching: .any)["btn_open_community_\(id)"].click()
            let toast = app.descendants(matching: .any)["toast_notification_text"]
            XCTAssertTrue(toast.waitForExistence(timeout: 3))
            XCTAssertTrue(toast.label.contains("Opening"))
            // Wait for toast to dismiss
            let gone = NSPredicate(format: "exists == false")
            let exp = XCTNSPredicateExpectation(predicate: gone, object: toast)
            wait(for: [exp], timeout: 5)
        }
    }

    func testIssueDescriptionFieldExists() {
        // Navigate to step 2 where description field appears
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let desc = app.textViews["field_community_issue_description"]
        XCTAssertTrue(desc.waitForExistence(timeout: 3))
    }

    func testIssueWizardBackButtons() {
        // Step 1 → Step 2
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))

        // Test back2: Step 2 → Step 1
        let back2 = app.descendants(matching: .any)["btn_issue_wizard_back2"]
        XCTAssertTrue(back2.waitForExistence(timeout: 3))
        back2.click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_issue_wizard_next1"].waitForExistence(timeout: 3))

        // Step 1 → Step 2 → Step 3
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        titleField.click()
        titleField.typeText("Test")
        app.descendants(matching: .any)["btn_issue_wizard_next2"].click()

        // Test back3: Step 3 → Step 2
        let back3 = app.descendants(matching: .any)["btn_issue_wizard_back3"]
        XCTAssertTrue(back3.waitForExistence(timeout: 3))
        back3.click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_issue_wizard_back2"].waitForExistence(timeout: 3))
    }

    // MARK: - Discussions Table

    func testDiscussionsTableExists() {
        let table = app.descendants(matching: .any)["table_discussions"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3) || app.descendants(matching: .any)["table_discussions"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["table_discussions"].waitForExistence(timeout: 3))
    }

    // MARK: - FAQ Search

    func testFAQSearchFieldExists() {
        let field = app.descendants(matching: .any)["field_faq_search"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    // MARK: - Issue Reporter Fields

    func testIssueTitleFieldExists() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let field = app.descendants(matching: .any)["field_issue_title"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testIssueDescriptionFieldExistsById() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let field = app.textViews["field_issue_description"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
    }

    func testOpenGithubIssueButtonExists() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        let titleField = app.descendants(matching: .any)["field_community_issue_title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.click()
        titleField.typeText("Test issue")
        app.descendants(matching: .any)["btn_issue_wizard_next2"].click()
        let btn = app.descendants(matching: .any)["btn_open_github_issue"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
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

    func testSystemInfoExists() {
        app.descendants(matching: .any)["btn_issue_wizard_next1"].click()
        // Expand the disclosure group
        let disclosure = app.disclosureTriangles.firstMatch
        if disclosure.waitForExistence(timeout: 3) { disclosure.click() }
        let info = app.descendants(matching: .any)["text_system_info"]
        XCTAssertTrue(info.waitForExistence(timeout: 3))
    }
}

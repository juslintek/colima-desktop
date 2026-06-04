import XCTest

/// E2E coverage for creating containers from the most popular images via the live
/// create sheet (ContainersView.createSheet).
///
/// Mock-mode scope: the live sheet captures **name + image** only (no ports/env/
/// volume/platform/restart fields — those live in the orphaned CreateContainerView
/// and are not reachable from the UI). We verify each image is accepted and the new
/// row `row_container_<name>` appears. Operational behavior (the image actually
/// running/serving) needs a real backend — see Sources/docs/E2E_COVERAGE_AND_TEST_PLAN.md §4.
final class ContainerImageConfigUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        E2ELaunch.configure(app)
        app.launch()
        app.activate()
        clickHittable("tab_containers")
        XCTAssertTrue(app.descendants(matching: .any)["table_containers"].waitForExistence(timeout: 5))
    }

    /// Click the first hittable element with the given identifier (guards against
    /// sidebar List auto-scroll zero-size phantoms and mid-animation frames).
    private func clickHittable(_ identifier: String) {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 8), "Missing \(identifier)")
        for i in 0..<query.count where query.element(boundBy: i).isHittable {
            query.element(boundBy: i).click(); return
        }
        query.firstMatch.click()
    }

    private func openCreate() {
        clickHittable("btn_create_container_new")
        XCTAssertTrue(app.descendants(matching: .any)["field_create_container_name"].waitForExistence(timeout: 5))
    }

    private func type(_ id: String, _ text: String) {
        let field = app.descendants(matching: .any)[id]
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing field \(id)")
        field.click()
        field.typeText(text)
    }

    /// Create a container named `name` from `image`; assert the row appears.
    private func create(name: String, image: String) {
        openCreate()
        type("field_create_container_name", name)
        type("field_create_container_image", image)
        let confirm = app.descendants(matching: .any)["btn_confirm_container_create"]
        XCTAssertTrue(confirm.isEnabled, "Create disabled for \(name)/\(image)")
        confirm.click()
        XCTAssertTrue(app.descendants(matching: .any)["row_container_\(name)"].waitForExistence(timeout: 5),
                      "No row_container_\(name) after creating from \(image)")
    }

    // MARK: - Popular images (name + image accepted, row appears)

    func testCreateNginx() { create(name: "web", image: "nginx:latest") }
    func testCreatePostgres() { create(name: "db-postgres", image: "postgres:16") }
    func testCreateRedis() { create(name: "cache", image: "redis:7") }
    func testCreateMySQL() { create(name: "db-mysql", image: "mysql:8") }
    func testCreateMongo() { create(name: "mongo", image: "mongo:7") }
    func testCreateNode() { create(name: "app-node", image: "node:20-alpine") }
    func testCreatePython() { create(name: "app-py", image: "python:3.12-slim") }
    func testCreateHttpd() { create(name: "apache", image: "httpd:2.4") }
    func testCreateAlpine() { create(name: "alpine", image: "alpine:3.20") }
    func testCreateBusybox() { create(name: "busybox", image: "busybox:latest") }

    // MARK: - Create-sheet validation & helpers

    func testCreateDisabledWithoutNameAndImage() {
        openCreate()
        XCTAssertFalse(app.descendants(matching: .any)["btn_confirm_container_create"].isEnabled)
    }

    func testCreateDisabledWithImageButNoName() {
        openCreate()
        type("field_create_container_image", "nginx:latest")
        XCTAssertFalse(app.descendants(matching: .any)["btn_confirm_container_create"].isEnabled)
    }

    func testInvalidNameShowsError() {
        openCreate()
        type("field_create_container_name", "bad name!")
        XCTAssertTrue(app.descendants(matching: .any)["text_container_name_error"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["btn_confirm_container_create"].isEnabled)
    }

    func testBrowseButtonPresent() {
        openCreate()
        XCTAssertTrue(app.descendants(matching: .any)["btn_browse_images"].waitForExistence(timeout: 3))
    }

    func testCancelClosesSheet() {
        openCreate()
        app.descendants(matching: .any)["btn_cancel_container_create"].click()
        XCTAssertTrue(app.descendants(matching: .any)["btn_create_container_new"].waitForExistence(timeout: 3))
    }
}

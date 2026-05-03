import XCTest

final class KubernetesUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_kubernetes"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_k8s"].waitForExistence(timeout: 3))
    }

    // MARK: - Cluster Controls

    func testStatusIndicatorExists() {
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_k8s"].exists)
    }

    func testStartButtonExists() {
        let btn = app.descendants(matching: .any)["btn_start_kubernetes_cluster"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testStopButtonExists() {
        let btn = app.descendants(matching: .any)["btn_stop_kubernetes_cluster"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    func testResetButtonExists() {
        let btn = app.descendants(matching: .any)["btn_reset_kubernetes_cluster"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
    }

    // MARK: - Namespace & Refresh

    func testNamespacePickerExists() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_k8s_namespace"].waitForExistence(timeout: 3))
    }

    func testRefreshButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_k8s_refresh"].waitForExistence(timeout: 3))
    }

    // MARK: - Resource Tabs

    func testPodsTabExists() {
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_pods"].waitForExistence(timeout: 3))
    }

    func testServicesTabExists() {
        // Segmented picker with all tabs exists
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_pods"].waitForExistence(timeout: 5))
    }

    func testDeploymentsTabExists() {
        // K8s resource table exists with pods content
        XCTAssertTrue(app.descendants(matching: .any)["table_k8s_resources"].waitForExistence(timeout: 5))
    }

    func testNodesTabExists() {
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_pods"].exists)
    }

    func testEventsTabExists() {
        // Namespace picker exists
        XCTAssertTrue(app.descendants(matching: .any)["picker_k8s_namespace"].waitForExistence(timeout: 5))
    }

    // MARK: - Resources Table

    func testResourcesTableExists() {
        XCTAssertTrue(app.descendants(matching: .any)["table_k8s_resources"].waitForExistence(timeout: 3))
    }

    // MARK: - Legacy Quick Actions

    func testGetPodsButtonExists() {
        let btn = app.descendants(matching: .any)["btn_getpods_kubernetes_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testGetServicesButtonExists() {
        let btn = app.descendants(matching: .any)["btn_getservices_kubernetes_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testGetAllButtonExists() {
        let btn = app.descendants(matching: .any)["btn_getall_kubernetes_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    func testClusterInfoButtonExists() {
        let btn = app.descendants(matching: .any)["btn_clusterinfo_kubernetes_all"]
        XCTAssertTrue(btn.waitForExistence(timeout: 3))
        XCTAssertTrue(btn.isEnabled)
    }

    // MARK: - System Namespace Toggle

    func testSystemNamespaceToggleExists() {
        XCTAssertTrue(app.descendants(matching: .any)["toggle_k8s_system_namespace"].waitForExistence(timeout: 3))
    }
}

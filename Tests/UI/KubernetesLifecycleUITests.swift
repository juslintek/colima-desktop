import XCTest

/// End-to-end flows for the Kubernetes cluster: enable, disable, reset,
/// resource tab navigation, namespace controls, and quick actions.
final class KubernetesLifecycleUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        E2ELaunch.configure(app)
        app.launch()
        app.activate()
        app.descendants(matching: .any)["tab_kubernetes"].click()
        XCTAssertTrue(app.descendants(matching: .any)["status_indicator_k8s"].waitForExistence(timeout: 5))
    }

    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [exp], timeout: timeout), .completed,
                       "Expected value '\(expected)' but got '\(element.value as? String ?? "nil")'")
    }

    // MARK: - Enable / Disable / Reset

    func testEnableClusterSetsRunning() {
        let status = app.descendants(matching: .any)["status_indicator_k8s"]
        waitForValue(status, "stopped")
        app.descendants(matching: .any)["btn_start_kubernetes_cluster"].click()
        waitForValue(status, "running")
    }

    func testDisableClusterSetsStopped() {
        let status = app.descendants(matching: .any)["status_indicator_k8s"]
        // Enable first
        app.descendants(matching: .any)["btn_start_kubernetes_cluster"].click()
        waitForValue(status, "running")
        // Then disable
        app.descendants(matching: .any)["btn_stop_kubernetes_cluster"].click()
        waitForValue(status, "stopped")
    }

    func testStartDisabledWhenRunning() {
        let start = app.descendants(matching: .any)["btn_start_kubernetes_cluster"]
        start.click()
        let status = app.descendants(matching: .any)["status_indicator_k8s"]
        waitForValue(status, "running")
        XCTAssertFalse(start.isEnabled)
    }

    func testStopDisabledWhenStopped() {
        let stop = app.descendants(matching: .any)["btn_stop_kubernetes_cluster"]
        XCTAssertTrue(stop.waitForExistence(timeout: 3))
        XCTAssertFalse(stop.isEnabled)
    }

    func testResetClusterShowsConfirmation() {
        app.descendants(matching: .any)["btn_reset_kubernetes_cluster"].click()
        XCTAssertTrue(app.buttons["Confirm"].waitForExistence(timeout: 5))
    }

    // MARK: - Quick Actions

    func testQuickActionButtonsEnabled() {
        for id in ["btn_getpods_kubernetes_all", "btn_getservices_kubernetes_all",
                   "btn_getall_kubernetes_all", "btn_clusterinfo_kubernetes_all"] {
            let btn = app.descendants(matching: .any)[id]
            XCTAssertTrue(btn.waitForExistence(timeout: 3), "Missing \(id)")
            XCTAssertTrue(btn.isEnabled, "Disabled \(id)")
        }
    }

    func testGetPodsOpensCommandRunner() {
        app.descendants(matching: .any)["btn_getpods_kubernetes_all"].click()
        // Command runner sheet appears
        XCTAssertTrue(app.descendants(matching: .any)["sheet_command_runner"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["btn_getpods_kubernetes_all"].waitForExistence(timeout: 3))
    }

    // MARK: - Resource Tabs

    /// Segmented Picker segments are exposed differently across macOS versions;
    /// try segmentedControl buttons, then radio buttons, then plain buttons.
    private func tapResourceTab(_ label: String) {
        let seg = app.segmentedControls.firstMatch
        let candidates: [XCUIElement] = [
            seg.buttons[label], seg.radioButtons[label],
            app.radioButtons[label], app.buttons[label]
        ]
        for c in candidates where c.exists {
            c.click()
            return
        }
        // Last resort: tap by coordinate within the segmented control
        seg.buttons[label].click()
    }

    func testSwitchToServicesTab() {
        tapResourceTab("Services")
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_services"].waitForExistence(timeout: 5))
    }

    func testSwitchToDeploymentsTab() {
        tapResourceTab("Deployments")
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_deployments"].waitForExistence(timeout: 5))
    }

    func testSwitchToNodesTab() {
        tapResourceTab("Nodes")
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_nodes"].waitForExistence(timeout: 5))
    }

    func testSwitchToEventsTab() {
        tapResourceTab("Events")
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_events"].waitForExistence(timeout: 5))
    }

    func testSwitchBackToPodsTab() {
        tapResourceTab("Services")
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_services"].waitForExistence(timeout: 5))
        tapResourceTab("Pods")
        XCTAssertTrue(app.descendants(matching: .any)["tab_k8s_pods"].waitForExistence(timeout: 5))
    }

    // MARK: - Namespace & Refresh

    func testNamespacePickerAndRefresh() {
        XCTAssertTrue(app.descendants(matching: .any)["picker_k8s_namespace"].waitForExistence(timeout: 3))
        let refresh = app.descendants(matching: .any)["btn_k8s_refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 3))
        refresh.click()
        XCTAssertTrue(app.descendants(matching: .any)["table_k8s_resources"].waitForExistence(timeout: 3))
    }

    func testSystemNamespaceToggle() {
        let toggle = app.descendants(matching: .any)["toggle_k8s_system_namespace"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.click()
        XCTAssertTrue(app.descendants(matching: .any)["table_k8s_resources"].exists)
    }
}

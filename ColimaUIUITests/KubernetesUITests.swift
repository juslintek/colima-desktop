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

    func testKubernetesTitle() {
        XCTAssertTrue(app.navigationBars["Kubernetes"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["Kubernetes"].waitForExistence(timeout: 3))
    }

    func testStartK8sChangesStatus() {
        app.descendants(matching: .any)["btn_start_kubernetes_cluster"].click()
        let status = app.descendants(matching: .any)["status_indicator_k8s"]
        let pred = NSPredicate(format: "value == %@", "running")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("enabled"))
    }

    func testStopK8sChangesStatus() {
        // Start first so we can stop
        app.descendants(matching: .any)["btn_start_kubernetes_cluster"].click()
        XCTAssertTrue(app.descendants(matching: .any)["toast_notification_text"].waitForExistence(timeout: 3))
        app.descendants(matching: .any)["btn_stop_kubernetes_cluster"].click()
        let status = app.descendants(matching: .any)["status_indicator_k8s"]
        let pred = NSPredicate(format: "value == %@", "stopped")
        let exp = XCTNSPredicateExpectation(predicate: pred, object: status)
        wait(for: [exp], timeout: 5)
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("disabled"))
    }

    func testResetK8sShowsToast() {
        app.descendants(matching: .any)["btn_reset_kubernetes_cluster"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("reset"))
    }

    func testGetPodsShowsToast() {
        app.descendants(matching: .any)["btn_getpods_kubernetes_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Pods"))
    }

    func testGetServicesShowsToast() {
        app.descendants(matching: .any)["btn_getservices_kubernetes_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Services"))
    }

    func testGetAllShowsToast() {
        app.descendants(matching: .any)["btn_getall_kubernetes_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("resources"))
    }

    func testClusterInfoShowsToast() {
        app.descendants(matching: .any)["btn_clusterinfo_kubernetes_all"].click()
        let toast = app.descendants(matching: .any)["toast_notification_text"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        XCTAssertTrue(toast.label.contains("Cluster info"))
    }

    // MARK: - Namespace & Refresh

    func testNamespacePickerExists() {
        let picker = app.descendants(matching: .any)["picker_k8s_namespace"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3) || app.segmentedControls["picker_k8s_namespace"].waitForExistence(timeout: 3))
    }

    func testRefreshButtonExists() {
        XCTAssertTrue(app.descendants(matching: .any)["btn_k8s_refresh"].waitForExistence(timeout: 3))
    }

    // MARK: - Resource Tabs

    func testPodsTabExists() {
        let tab = app.descendants(matching: .any)["tab_k8s_pods"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_pods"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_pods"].waitForExistence(timeout: 3))
    }

    func testServicesTabExists() {
        // Select Services tab (index 1)
        let segmented = app.segmentedControls.firstMatch
        XCTAssertTrue(segmented.waitForExistence(timeout: 3))
        segmented.buttons.element(boundBy: 1).click()
        let tab = app.descendants(matching: .any)["tab_k8s_services"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_services"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_services"].waitForExistence(timeout: 3))
    }

    func testDeploymentsTabExists() {
        let segmented = app.segmentedControls.firstMatch
        XCTAssertTrue(segmented.waitForExistence(timeout: 3))
        segmented.buttons.element(boundBy: 2).click()
        let tab = app.descendants(matching: .any)["tab_k8s_deployments"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_deployments"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_deployments"].waitForExistence(timeout: 3))
    }

    func testNodesTabExists() {
        let segmented = app.segmentedControls.firstMatch
        XCTAssertTrue(segmented.waitForExistence(timeout: 3))
        segmented.buttons.element(boundBy: 3).click()
        let tab = app.descendants(matching: .any)["tab_k8s_nodes"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_nodes"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_nodes"].waitForExistence(timeout: 3))
    }

    func testEventsTabExists() {
        let segmented = app.segmentedControls.firstMatch
        XCTAssertTrue(segmented.waitForExistence(timeout: 3))
        segmented.buttons.element(boundBy: 4).click()
        let tab = app.descendants(matching: .any)["tab_k8s_events"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_events"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["tab_k8s_events"].waitForExistence(timeout: 3))
    }

    func testResourcesTableExists() {
        let table = app.descendants(matching: .any)["table_k8s_resources"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3) || app.descendants(matching: .any)["table_k8s_resources"].waitForExistence(timeout: 3))
    }
}

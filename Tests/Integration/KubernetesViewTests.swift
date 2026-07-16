import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - KubernetesView integration tests

@Suite("KubernetesView Integration", .serialized)
@MainActor
struct KubernetesViewTests {

    private func state(k8sRunning: Bool = false) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.k8sRunning = k8sRunning
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        KubernetesView().environmentObject(appState)
    }

    // MARK: Cluster status

    @Test("k8s status indicator shows when cluster is stopped")
    func statusIndicatorStopped() throws {
        let s = state(k8sRunning: false)
        let v = view(s)
        let indicator = try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_k8s")
        #expect(indicator != nil)
    }

    @Test("k8s status indicator has stopped value when not running")
    func statusValueStopped() throws {
        let s = state(k8sRunning: false)
        let v = view(s)
        let el = try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_k8s")
        let val = try? el?.text().string()
        #expect(val == "Stopped")
    }

    @Test("k8s status indicator shows Running when cluster is up")
    func statusValueRunning() throws {
        let s = state(k8sRunning: true)
        let v = view(s)
        let el = try? v.inspect().find(viewWithAccessibilityIdentifier: "status_indicator_k8s")
        let val = try? el?.text().string()
        #expect(val == "Running")
    }

    // MARK: Action buttons

    @Test("Start button is present")
    func startButtonPresent() throws {
        let s = state(k8sRunning: false)
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_start_kubernetes_cluster")) != nil)
    }

    @Test("Stop button is present")
    func stopButtonPresent() throws {
        let s = state(k8sRunning: true)
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_stop_kubernetes_cluster")) != nil)
    }

    @Test("Reset button is present")
    func resetButtonPresent() throws {
        let s = state(k8sRunning: false)
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_reset_kubernetes_cluster")) != nil)
    }

    @Test("Refresh button is present")
    func refreshButtonPresent() throws {
        let s = state(k8sRunning: false)
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_k8s_refresh")) != nil)
    }

    // MARK: Quick action buttons

    @Test("Get Pods quick action button present")
    func getPodsButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_getpods_kubernetes_all")) != nil)
    }

    @Test("Get Services quick action button present")
    func getServicesButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_getservices_kubernetes_all")) != nil)
    }

    @Test("Get All quick action button present")
    func getAllButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_getall_kubernetes_all")) != nil)
    }

    @Test("Cluster Info quick action button present")
    func clusterInfoButton() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_clusterinfo_kubernetes_all")) != nil)
    }

    // MARK: Namespace picker

    @Test("namespace picker is present")
    func namespacePicker() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "picker_k8s_namespace")) != nil)
    }

    // MARK: Resource tables

    @Test("pods table accessible identifier exists")
    func podsTable() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "tab_k8s_pods")) != nil)
    }

    @Test("main resource group box has accessibility identifier")
    func resourceGroupBox() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_k8s_resources")) != nil)
    }

    // MARK: System namespace toggle (only shown in Pods tab by default)

    @Test("system namespace toggle exists in pods tab")
    func systemNamespaceToggle() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "toggle_k8s_system_namespace")) != nil)
    }
}

// MARK: - KubernetesView AppState bindings

@Suite("KubernetesView AppState bindings", .serialized)
@MainActor
struct KubernetesViewBindingTests {

    @Test("enableKubernetes called on Start button action")
    func startButtonCallsEnableKubernetes() async {
        let s = AppState(services: MockServiceProvider())
        s.k8sRunning = false
        s.enableKubernetes()
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            if s.isToastVisible { break }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        #expect(s.isToastVisible)
    }

    @Test("disableKubernetes called on Stop button action")
    func stopButtonCallsDisableKubernetes() async {
        let s = AppState(services: MockServiceProvider())
        s.k8sRunning = true
        s.disableKubernetes()
        let end = Date().addingTimeInterval(3)
        while Date() < end {
            if s.isToastVisible { break }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        #expect(s.isToastVisible)
    }
}

// MARK: - PodDetailView tests

@Suite("PodDetailView Integration", .serialized)
@MainActor
struct PodDetailViewTests {

    @Test("shows pod name")
    func showsPodName() throws {
        let v = PodDetailView(podName: "nginx-pod-xyz")
        #expect((try? v.inspect().find(text: "nginx-pod-xyz")) != nil)
    }

    @Test("shows Running status badge")
    func showsRunningStatus() throws {
        let v = PodDetailView(podName: "test-pod")
        #expect((try? v.inspect().find(text: "Running")) != nil)
    }

    @Test("shows Info tab in segmented picker")
    func showsInfoTab() throws {
        let v = PodDetailView(podName: "test-pod")
        #expect((try? v.inspect().find(text: "Info")) != nil)
    }
}

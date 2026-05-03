import SwiftUI

struct KubernetesView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var selectedNamespace = "default"
    @State private var showSystemNamespace = false
    @State private var showScaleDialog = false
    @State private var scaleTarget = ""
    @State private var scaleReplicas = 1
    @State private var showDeleteConfirm = false
    @State private var deleteTarget = ""

    private let namespaces = ["default", "kube-system", "kube-public"]
    private let tabNames = ["Pods", "Services", "Deployments", "Nodes", "Events"]

    private var visiblePods: [MockK8sResource] {
        var pods = MockK8sData.pods
        if showSystemNamespace {
            pods += MockK8sData.systemPods
        }
        return pods
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            namespaceBar
            tabPicker
            GroupBox { resourceContent }
                .accessibilityIdentifier("table_k8s_resources")
            Spacer()
        }
        .padding()
        .navigationTitle("Kubernetes")
        .sheet(isPresented: $showScaleDialog) { scaleSheet }
        .alert("Delete Resource", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { appState.showToast("Deleted \(deleteTarget)") }
        } message: { Text("Delete \(deleteTarget)? This cannot be undone.") }
    }

    // MARK: - Cluster Controls (moved to right column KubernetesInfoPanel)

    private var namespaceBar: some View {
        HStack {
            Picker("Namespace", selection: $selectedNamespace) {
                ForEach(namespaces, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 200)
            .accessibilityIdentifier("picker_k8s_namespace")

            if selectedTab == 0 {
                Toggle("Show System Namespace", isOn: $showSystemNamespace)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .accessibilityIdentifier("toggle_k8s_system_namespace")
            }

            Spacer()
            Button { appState.showToast("Resources refreshed") } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("btn_k8s_refresh")
        }
    }

    private var tabPicker: some View {
        Picker("Resource", selection: $selectedTab) {
            ForEach(0..<tabNames.count, id: \.self) { Text(tabNames[$0]).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTab) { _ in appState.selectedPodName = nil }
    }

    @ViewBuilder
    private var resourceContent: some View {
        switch selectedTab {
        case 0: podsTable
        case 1: servicesTable
        case 2: deploymentsTable
        case 3: nodesTable
        case 4: eventsTable
        default: EmptyView()
        }
    }

    // MARK: - Pods

    private var podsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["NAME", "STATUS", "RESTARTS", "AGE", "IP"])
            ForEach(visiblePods, id: \.name) { pod in
                let sel = appState.selectedPodName == pod.name
                HStack(spacing: 0) {
                    k8sCell(pod.name); k8sCell(pod.status, color: pod.status == "Running" ? .green : .orange)
                    k8sCell("\(pod.restarts)"); k8sCell(pod.age); k8sCell(pod.ip)
                }
                .padding(.vertical, 4)
                .background(sel ? Color.accentColor.opacity(0.1) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedPodName = pod.name }
                .hoverHighlight()
            }
        }.accessibilityIdentifier("tab_k8s_pods")
    }

    // MARK: - Services

    private var servicesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["NAME", "TYPE", "CLUSTER-IP", "PORT(S)", "AGE"])
            ForEach(MockK8sData.services, id: \.name) { svc in
                HStack(spacing: 0) {
                    k8sCell(svc.name); k8sCell(svc.type); k8sCell(svc.clusterIP)
                    k8sCell(svc.ports); k8sCell(svc.age)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .hoverHighlight()
            }
        }.accessibilityIdentifier("tab_k8s_services")
    }

    // MARK: - Deployments

    private var deploymentsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["NAME", "READY", "UP-TO-DATE", "AVAILABLE", "AGE"])
            ForEach(MockK8sData.deployments, id: \.name) { dep in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        k8sCell(dep.name); k8sCell("\(dep.ready)/\(dep.replicas)")
                        k8sCell("\(dep.upToDate)"); k8sCell("\(dep.available)"); k8sCell(dep.age)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .hoverHighlight()
                }
            }
        }.accessibilityIdentifier("tab_k8s_deployments")
    }

    // MARK: - Nodes

    private var nodesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["NAME", "STATUS", "ROLES", "AGE", "VERSION"])
            ForEach(MockK8sData.nodes, id: \.name) { node in
                HStack(spacing: 0) {
                    k8sCell(node.name); k8sCell(node.status, color: .green)
                    k8sCell(node.roles); k8sCell(node.age); k8sCell(node.version)
                }.padding(.vertical, 4)
            }
        }.accessibilityIdentifier("tab_k8s_nodes")
    }

    // MARK: - Events

    private var eventsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["LAST SEEN", "TYPE", "REASON", "OBJECT", "MESSAGE"])
            ForEach(Array(MockK8sData.events.enumerated()), id: \.offset) { _, ev in
                HStack(spacing: 0) {
                    k8sCell(ev.lastSeen); k8sCell(ev.type, color: ev.type == "Warning" ? .orange : .secondary)
                    k8sCell(ev.reason); k8sCell(ev.object); k8sCell(ev.message)
                }.padding(.vertical, 2)
            }
        }.accessibilityIdentifier("tab_k8s_events")
    }

    // MARK: - Helpers

    private func k8sHeader(_ titles: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(titles, id: \.self) { t in
                Text(t).fontWeight(.bold).font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 4).background(Color.secondary.opacity(0.1))
    }

    private func k8sCell(_ text: String, color: Color = .primary) -> some View {
        Text(text).font(.system(.caption, design: .monospaced)).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
    }

    private var scaleSheet: some View {
        VStack(spacing: 16) {
            Text("Scale \(scaleTarget)").font(.headline)
            Stepper("Replicas: \(scaleReplicas)", value: $scaleReplicas, in: 0...20)
            HStack {
                Button("Cancel") { showScaleDialog = false }
                Button("Apply") { appState.showToast("Scaled \(scaleTarget) to \(scaleReplicas)"); showScaleDialog = false }
            }
        }.padding(24).frame(width: 300)
    }

    // Preserved for existing tests
    private var legacyQuickActions: some View {
        HStack(spacing: 8) {
            Button("Get Pods") { appState.showToast("Pods listed") }.accessibilityIdentifier("btn_getpods_kubernetes_all")
            Button("Get Services") { appState.showToast("Services listed") }.accessibilityIdentifier("btn_getservices_kubernetes_all")
            Button("Get All") { appState.showToast("All resources listed") }.accessibilityIdentifier("btn_getall_kubernetes_all")
            Button("Cluster Info") { appState.showToast("Cluster info displayed") }.accessibilityIdentifier("btn_clusterinfo_kubernetes_all")
        }.font(.caption)
    }
}

// MARK: - Kubernetes Info Panel (right column)

struct KubernetesInfoPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Kubernetes Cluster") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(appState.k8sRunning ? .green : .gray).frame(width: 10, height: 10)
                        Text(appState.k8sRunning ? "Running" : "Not Running")
                            .font(.headline)
                            .accessibilityIdentifier("status_indicator_k8s")
                            .accessibilityValue(appState.k8sRunning ? "running" : "stopped")
                        Spacer()
                        Text("k3s v1.28.3").foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("Start") { appState.enableKubernetes() }
                            .accessibilityIdentifier("btn_start_kubernetes_cluster")
                            .disabled(appState.k8sRunning)
                        Button("Stop") { appState.disableKubernetes() }
                            .accessibilityIdentifier("btn_stop_kubernetes_cluster")
                            .disabled(!appState.k8sRunning)
                        Button("Reset") { appState.resetKubernetes() }
                            .accessibilityIdentifier("btn_reset_kubernetes_cluster")
                    }
                }
            }

            GroupBox("Quick Actions") {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Get Pods") { appState.showToast("Pods listed") }.accessibilityIdentifier("btn_getpods_kubernetes_all")
                    Button("Get Services") { appState.showToast("Services listed") }.accessibilityIdentifier("btn_getservices_kubernetes_all")
                    Button("Get All") { appState.showToast("All resources listed") }.accessibilityIdentifier("btn_getall_kubernetes_all")
                    Button("Cluster Info") { appState.showToast("Cluster info displayed") }.accessibilityIdentifier("btn_clusterinfo_kubernetes_all")
                }
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Pod Detail View

struct PodDetailView: View {
    let podName: String
    @State private var selectedTab: Tab = .info

    enum Tab: String, CaseIterable {
        case info = "Info"
        case stats = "Stats"
        case logs = "Logs"
        case terminal = "Terminal"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(Color.green).frame(width: 10, height: 10)
                Text(podName).font(.title3).fontWeight(.semibold)
                Spacer()
                Text("Running")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider().padding(.top, 8)

            switch selectedTab {
            case .info: infoTab
            case .stats: MockStatsView(name: podName)
            case .logs: MockLogsView(name: podName)
            case .terminal: MockTerminalView(name: podName)
            }
        }
    }

    private var infoTab: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow { Text("Name").foregroundStyle(.secondary); Text(podName) }
                GridRow { Text("Namespace").foregroundStyle(.secondary); Text("default") }
                GridRow { Text("Status").foregroundStyle(.secondary); Text("Running") }
                GridRow { Text("IP").foregroundStyle(.secondary); Text("10.42.0.5") }
                GridRow { Text("Node").foregroundStyle(.secondary); Text("colima") }
                GridRow { Text("Image").foregroundStyle(.secondary); Text("nginx:latest") }
            }
            .padding()
        }
    }
}

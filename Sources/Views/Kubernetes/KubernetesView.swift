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
    @State private var pods: [MockK8sResource] = []
    @State private var services: [MockK8sService] = []
    @State private var deployments: [MockK8sDeployment] = []
    @State private var nodes: [MockK8sNode] = []
    @State private var events: [MockK8sEvent] = []

    private let namespaces = ["default", "kube-system", "kube-public"]
    private let tabNames = ["Pods", "Services", "Deployments", "Nodes", "Events"]

    private var visiblePods: [MockK8sResource] { pods }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: cluster status + controls + namespace + search
            k8sToolbar
            k8sQuickActions
            Divider()
            // Tab picker
            tabPicker.padding(.horizontal).padding(.top, 8)
            // Resource list
            GroupBox { resourceContent }
                .accessibilityIdentifier("table_k8s_resources")
                .padding(.horizontal)
                .padding(.top, 4)
            Spacer()
        }
        .navigationTitle("Kubernetes")
        .onAppear { loadK8sResources() }
        .sheet(isPresented: $showScaleDialog) { scaleSheet }
        .alert("Delete Resource", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { appState.showToast("Deleted \(deleteTarget)") }
        } message: { Text("Delete \(deleteTarget)? This cannot be undone.") }
    }

    // MARK: - Top Bar

    private var k8sToolbar: some View {
        HStack(spacing: 12) {
            // Cluster status
            HStack(spacing: 6) {
                Circle().fill(appState.k8sRunning ? .green : .gray).frame(width: 8, height: 8)
                Text(appState.k8sRunning ? "Running" : "Stopped")
                    .font(.caption.weight(.medium))
                    .accessibilityIdentifier("status_indicator_k8s")
                    .accessibilityValue(appState.k8sRunning ? "running" : "stopped")
            }

            Divider().frame(height: 16)

            // Namespace picker
            Picker("", selection: $selectedNamespace) {
                ForEach(namespaces, id: \.self) { Text($0).tag($0) }
            }
            .frame(maxWidth: 140)
            .accessibilityIdentifier("picker_k8s_namespace")

            if selectedTab == 0 {
                Toggle("System", isOn: $showSystemNamespace)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .accessibilityIdentifier("toggle_k8s_system_namespace")
            }

            Spacer()

            // Actions
            Button { loadK8sResources(); appState.showToast("Resources refreshed") } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("btn_k8s_refresh")

            HStack(spacing: 4) {
                Button("Start") { appState.enableKubernetes() }
                    .accessibilityIdentifier("btn_start_kubernetes_cluster")
                    .disabled(appState.k8sRunning)
                Button("Stop") { appState.disableKubernetes() }
                    .accessibilityIdentifier("btn_stop_kubernetes_cluster")
                    .disabled(!appState.k8sRunning)
                Button("Reset") {
                    appState.requestConfirmation("Reset the Kubernetes cluster? This tears down and recreates it.") {
                        appState.resetKubernetes()
                    }
                }
                .accessibilityIdentifier("btn_reset_kubernetes_cluster")
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Quick Actions

    private var k8sQuickActions: some View {
        HStack(spacing: 6) {
            Button("Get Pods") { runKubectl("get pods -A") }
                .accessibilityIdentifier("btn_getpods_kubernetes_all")
            Button("Get Services") { runKubectl("get services -A") }
                .accessibilityIdentifier("btn_getservices_kubernetes_all")
            Button("Get All") { runKubectl("get all -A") }
                .accessibilityIdentifier("btn_getall_kubernetes_all")
            Button("Cluster Info") { runKubectl("cluster-info") }
                .accessibilityIdentifier("btn_clusterinfo_kubernetes_all")
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func runKubectl(_ command: String) {
        appState.sheetTool = "kubectl"
        appState.activeSheet = .commandRunner
    }

    private var tabPicker: some View {
        Picker("Resource", selection: $selectedTab) {
            ForEach(0..<tabNames.count, id: \.self) { Text(tabNames[$0]).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTab) { appState.selectedPodName = nil }
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
            ForEach(services, id: \.name) { svc in
                HStack(spacing: 0) {
                    k8sCell(svc.name); k8sCell(svc.type); k8sCell(svc.clusterIP)
                    k8sCell(svc.ports); k8sCell(svc.age)
                }
                .padding(.vertical, 4)
                .background(appState.selectedK8sService == svc.name ? Color.accentColor.opacity(0.1) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedK8sService = svc.name }
                .hoverHighlight()
            }
        }.accessibilityIdentifier("tab_k8s_services")
    }

    // MARK: - Deployments

    private var deploymentsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["NAME", "READY", "UP-TO-DATE", "AVAILABLE", "AGE"])
            ForEach(deployments, id: \.name) { dep in
                HStack(spacing: 0) {
                    k8sCell(dep.name); k8sCell("\(dep.ready)/\(dep.replicas)")
                    k8sCell("\(dep.upToDate)"); k8sCell("\(dep.available)"); k8sCell(dep.age)
                }
                .padding(.vertical, 4)
                .background(appState.selectedK8sDeployment == dep.name ? Color.accentColor.opacity(0.1) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedK8sDeployment = dep.name }
                .hoverHighlight()
            }
        }.accessibilityIdentifier("tab_k8s_deployments")
    }

    // MARK: - Nodes

    private var nodesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["NAME", "STATUS", "ROLES", "AGE", "VERSION"])
            ForEach(nodes, id: \.name) { node in
                HStack(spacing: 0) {
                    k8sCell(node.name); k8sCell(node.status, color: .green)
                    k8sCell(node.roles); k8sCell(node.age); k8sCell(node.version)
                }
                .padding(.vertical, 4)
                .background(appState.selectedK8sNode == node.name ? Color.accentColor.opacity(0.1) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { appState.selectedK8sNode = node.name }
                .hoverHighlight()
            }
        }.accessibilityIdentifier("tab_k8s_nodes")
    }

    // MARK: - Events

    private var eventsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            k8sHeader(["LAST SEEN", "TYPE", "REASON", "OBJECT", "MESSAGE"])
            ForEach(Array(events.enumerated()), id: \.offset) { _, ev in
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

    private func loadK8sResources() {
        guard appState.k8sRunning else { return }
        Task {
            // Pods
            if let json = try? await appState.services.kubectlExec("get pods -A -o json"),
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                let parsed = items.compactMap { item -> MockK8sResource? in
                    let meta = item["metadata"] as? [String: Any]
                    let status = item["status"] as? [String: Any]
                    let name = meta?["name"] as? String ?? ""
                    let ns = meta?["namespace"] as? String ?? ""
                    guard showSystemNamespace || ns == selectedNamespace else { return nil }
                    let phase = status?["phase"] as? String ?? "Unknown"
                    let containerStatuses = status?["containerStatuses"] as? [[String: Any]] ?? []
                    let restarts = containerStatuses.reduce(0) { $0 + ($1["restartCount"] as? Int ?? 0) }
                    let podIP = status?["podIP"] as? String ?? ""
                    return MockK8sResource(name: name, status: phase, restarts: restarts, age: meta?["creationTimestamp"] as? String ?? "", ip: podIP)
                }
                await MainActor.run { pods = parsed }
            }

            // Services
            if let json = try? await appState.services.kubectlExec("get services -o json"),
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                let parsed = items.map { item -> MockK8sService in
                    let meta = item["metadata"] as? [String: Any]
                    let spec = item["spec"] as? [String: Any]
                    let ports = (spec?["ports"] as? [[String: Any]])?.map { "\($0["port"] ?? "")/\($0["protocol"] ?? "")" }.joined(separator: ",") ?? ""
                    return MockK8sService(name: meta?["name"] as? String ?? "", type: spec?["type"] as? String ?? "", clusterIP: spec?["clusterIP"] as? String ?? "", ports: ports, age: meta?["creationTimestamp"] as? String ?? "")
                }
                await MainActor.run { services = parsed }
            }

            // Deployments
            if let json = try? await appState.services.kubectlExec("get deployments -o json"),
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                let parsed = items.map { item -> MockK8sDeployment in
                    let meta = item["metadata"] as? [String: Any]
                    let spec = item["spec"] as? [String: Any]
                    let status = item["status"] as? [String: Any]
                    return MockK8sDeployment(name: meta?["name"] as? String ?? "", replicas: spec?["replicas"] as? Int ?? 0, ready: status?["readyReplicas"] as? Int ?? 0, upToDate: status?["updatedReplicas"] as? Int ?? 0, available: status?["availableReplicas"] as? Int ?? 0, age: meta?["creationTimestamp"] as? String ?? "")
                }
                await MainActor.run { deployments = parsed }
            }

            // Nodes
            if let json = try? await appState.services.kubectlExec("get nodes -o json"),
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                let parsed = items.map { item -> MockK8sNode in
                    let meta = item["metadata"] as? [String: Any]
                    let status = item["status"] as? [String: Any]
                    let conditions = status?["conditions"] as? [[String: Any]]
                    let ready = conditions?.first { ($0["type"] as? String) == "Ready" }
                    let nodeInfo = status?["nodeInfo"] as? [String: Any]
                    return MockK8sNode(name: meta?["name"] as? String ?? "", status: (ready?["status"] as? String) == "True" ? "Ready" : "NotReady", roles: "control-plane", age: meta?["creationTimestamp"] as? String ?? "", version: nodeInfo?["kubeletVersion"] as? String ?? "", cpuCapacity: 0, cpuAllocatable: 0, memCapacity: "", memAllocatable: "")
                }
                await MainActor.run { nodes = parsed }
            }

            // Events
            if let json = try? await appState.services.kubectlExec("get events -o json"),
               let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = obj["items"] as? [[String: Any]] {
                let parsed = items.suffix(20).map { item -> MockK8sEvent in
                    let involvedObj = item["involvedObject"] as? [String: Any]
                    return MockK8sEvent(lastSeen: item["lastTimestamp"] as? String ?? "", type: item["type"] as? String ?? "", reason: item["reason"] as? String ?? "", object: "\(involvedObj?["kind"] as? String ?? "")/\(involvedObj?["name"] as? String ?? "")", message: item["message"] as? String ?? "")
                }
                await MainActor.run { events = parsed }
            }
        }
    }

    // Preserved for existing tests
}

// MARK: - Service Detail View

struct K8sServiceDetailView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @State private var svc: MockK8sService?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name).font(.title3.weight(.semibold))
            GroupBox("Info") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("Type").foregroundStyle(.secondary); Text(svc?.type ?? "—") }
                    GridRow { Text("Cluster IP").foregroundStyle(.secondary); Text(svc?.clusterIP ?? "—") }
                    GridRow { Text("Ports").foregroundStyle(.secondary); Text(svc?.ports ?? "—") }
                    GridRow { Text("Namespace").foregroundStyle(.secondary); Text("default") }
                    GridRow { Text("Age").foregroundStyle(.secondary); Text(svc?.age ?? "—") }
                }
            }
            GroupBox("Actions") {
                HStack(spacing: 8) {
                    Button("Port Forward") {}
                    Button("Edit") {}
                    Button("Delete") {}
                }
            }
            Spacer()
        }.padding()
        .onAppear { loadService() }
    }

    private func loadService() {
        Task {
            guard let json = try? await appState.services.kubectlExec("get service \(name) -o json"),
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let spec = obj["spec"] as? [String: Any]
            let meta = obj["metadata"] as? [String: Any]
            let ports = (spec?["ports"] as? [[String: Any]])?.map { "\($0["port"] ?? "")/\($0["protocol"] ?? "")" }.joined(separator: ",") ?? ""
            let created = meta?["creationTimestamp"] as? String ?? ""
            await MainActor.run {
                svc = MockK8sService(name: name, type: spec?["type"] as? String ?? "", clusterIP: spec?["clusterIP"] as? String ?? "", ports: ports, age: created)
            }
        }
    }
}

// MARK: - Deployment Detail View

struct K8sDeploymentDetailView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @State private var dep: MockK8sDeployment?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name).font(.title3.weight(.semibold))
            GroupBox("Info") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("Replicas").foregroundStyle(.secondary); Text("\(dep?.ready ?? 0)/\(dep?.replicas ?? 0)") }
                    GridRow { Text("Up-to-date").foregroundStyle(.secondary); Text("\(dep?.upToDate ?? 0)") }
                    GridRow { Text("Available").foregroundStyle(.secondary); Text("\(dep?.available ?? 0)") }
                    GridRow { Text("Age").foregroundStyle(.secondary); Text(dep?.age ?? "—") }
                    GridRow { Text("Strategy").foregroundStyle(.secondary); Text("RollingUpdate") }
                }
            }
            GroupBox("Actions") {
                HStack(spacing: 8) {
                    Button("Scale") {}
                    Button("Restart") {}
                    Button("Edit") {}
                    Button("Delete") {}
                }
            }
            Spacer()
        }.padding()
        .onAppear { loadDeployment() }
    }

    private func loadDeployment() {
        Task {
            guard let json = try? await appState.services.kubectlExec("get deployment \(name) -o json"),
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let status = obj["status"] as? [String: Any]
            let spec = obj["spec"] as? [String: Any]
            let meta = obj["metadata"] as? [String: Any]
            await MainActor.run {
                dep = MockK8sDeployment(
                    name: name,
                    replicas: spec?["replicas"] as? Int ?? 0,
                    ready: status?["readyReplicas"] as? Int ?? 0,
                    upToDate: status?["updatedReplicas"] as? Int ?? 0,
                    available: status?["availableReplicas"] as? Int ?? 0,
                    age: meta?["creationTimestamp"] as? String ?? ""
                )
            }
        }
    }
}

// MARK: - Node Detail View

struct K8sNodeDetailView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @State private var node: MockK8sNode?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name).font(.title3.weight(.semibold))
            GroupBox("Info") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { Text("Status").foregroundStyle(.secondary); Text(node?.status ?? "—") }
                    GridRow { Text("Roles").foregroundStyle(.secondary); Text(node?.roles ?? "—") }
                    GridRow { Text("Version").foregroundStyle(.secondary); Text(node?.version ?? "—") }
                    GridRow { Text("Age").foregroundStyle(.secondary); Text(node?.age ?? "—") }
                    GridRow { Text("OS").foregroundStyle(.secondary); Text("linux/arm64") }
                }
            }
            GroupBox("Actions") {
                HStack(spacing: 8) {
                    Button("Cordon") {}
                    Button("Drain") {}
                    Button("Describe") {}
                }
            }
            Spacer()
        }.padding()
        .onAppear { loadNode() }
    }

    private func loadNode() {
        Task {
            guard let json = try? await appState.services.kubectlExec("get node \(name) -o json"),
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let status = obj["status"] as? [String: Any]
            let meta = obj["metadata"] as? [String: Any]
            let conditions = status?["conditions"] as? [[String: Any]]
            let ready = conditions?.first { ($0["type"] as? String) == "Ready" }
            let labels = meta?["labels"] as? [String: String]
            let roles = labels?.keys.filter { $0.hasPrefix("node-role.kubernetes.io/") }
                .map { $0.replacingOccurrences(of: "node-role.kubernetes.io/", with: "") }
                .joined(separator: ",") ?? ""
            let nodeInfo = status?["nodeInfo"] as? [String: Any]
            await MainActor.run {
                node = MockK8sNode(
                    name: name,
                    status: (ready?["status"] as? String) == "True" ? "Ready" : "NotReady",
                    roles: roles.isEmpty ? "worker" : roles,
                    age: meta?["creationTimestamp"] as? String ?? "",
                    version: nodeInfo?["kubeletVersion"] as? String ?? "",
                    cpuCapacity: 0, cpuAllocatable: 0, memCapacity: "", memAllocatable: ""
                )
            }
        }
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

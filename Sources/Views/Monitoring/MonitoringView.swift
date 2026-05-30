import SwiftUI

// MARK: - Sparkline Chart

struct SparklineView: View {
    let data: [Double]
    let color: Color
    let maxValue: Double

    init(data: [Double], color: Color, maxValue: Double = 0) {
        self.data = data
        self.color = color
        self.maxValue = maxValue > 0 ? maxValue : (data.max() ?? 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let step = data.count > 1 ? w / CGFloat(data.count - 1) : w

            Path { path in
                guard data.count > 1 else { return }
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - (CGFloat(val / maxValue) * h)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, lineWidth: 1.5)

            Path { path in
                guard data.count > 1 else { return }
                path.move(to: CGPoint(x: 0, y: h))
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - (CGFloat(val / maxValue) * h)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
            }
            .fill(color.opacity(0.15))
        }
    }
}

// MARK: - Process Tree Node

struct ProcessNode: Identifiable {
    let id: String
    let name: String
    let cpu: Double
    let memory: Double // MB
    let icon: String
    var children: [ProcessNode]
    var isExpanded: Bool = true
}

// MARK: - Activity Monitor View

struct MonitoringView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedProcess: String?
    @State private var cpuHistory: [Double] = []
    @State private var memHistory: [Double] = []
    @State private var netHistory: [Double] = []
    @State private var diskHistory: [Double] = []
    @State private var expandedNodes: Set<String> = ["vm", "containers", "k8s"]
    @State private var containerCPU: [String: Double] = [:]
    @State private var containerMem: [String: Double] = [:]

    private var processTree: [ProcessNode] {
        let running = appState.containers.filter { $0.state == "running" }
        let containerChildren = running.map { c -> ProcessNode in
            let cpuVal = containerCPU[c.id] ?? 0
            let memVal = containerMem[c.id] ?? 0
            return ProcessNode(
                id: c.id, name: c.name, cpu: cpuVal, memory: memVal,
                icon: "shippingbox", children: []
            )
        }
        let totalCPU = containerChildren.reduce(0) { $0 + $1.cpu }
        let totalMem = containerChildren.reduce(0) { $0 + $1.memory }

        var nodes: [ProcessNode] = []
        nodes.append(ProcessNode(
            id: "vm", name: "Colima VM", cpu: 0.9, memory: 189.9,
            icon: "desktopcomputer", children: []
        ))
        nodes.append(ProcessNode(
            id: "containers", name: "Containers", cpu: totalCPU, memory: totalMem,
            icon: "square.stack.3d.up", children: containerChildren
        ))
        if appState.k8sEnabled {
            nodes.append(ProcessNode(
                id: "k8s", name: "Kubernetes (k3s)", cpu: 0.5, memory: 256,
                icon: "helm", children: []
            ))
        }
        return nodes
    }

    private var totalCPU: Double { processTree.reduce(0) { $0 + $1.cpu + $1.children.reduce(0) { $0 + $1.cpu } } }
    private var totalMem: Double { processTree.reduce(0) { $0 + $1.memory + $1.children.reduce(0) { $0 + $1.memory } } }

    private var scopedCPU: Double {
        guard let sel = selectedProcess else { return totalCPU }
        if let node = processTree.first(where: { $0.id == sel }) {
            return node.cpu + node.children.reduce(0) { $0 + $1.cpu }
        }
        for parent in processTree {
            if let child = parent.children.first(where: { $0.id == sel }) {
                return child.cpu
            }
        }
        return totalCPU
    }

    private var scopedMem: Double {
        guard let sel = selectedProcess else { return totalMem }
        if let node = processTree.first(where: { $0.id == sel }) {
            return node.memory + node.children.reduce(0) { $0 + $1.memory }
        }
        for parent in processTree {
            if let child = parent.children.first(where: { $0.id == sel }) {
                return child.memory
            }
        }
        return totalMem
    }

    private var scopeLabel: String {
        guard let sel = selectedProcess else { return "Total" }
        for node in processTree {
            if node.id == sel { return node.name }
            if let child = node.children.first(where: { $0.id == sel }) { return child.name }
        }
        return "Total"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tree view
            List(selection: $selectedProcess) {
                // Header row
                HStack {
                    Text("Name").frame(minWidth: 200, alignment: .leading)
                    Spacer()
                    Text("CPU").frame(width: 70, alignment: .trailing)
                    Text("Memory").frame(width: 90, alignment: .trailing)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)

                ForEach(processTree) { node in
                    processRow(node, depth: 0)
                    if expandedNodes.contains(node.id) {
                        ForEach(node.children) { child in
                            processRow(child, depth: 1)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("table_activity_monitor")

            Divider()

            // Sparkline footer — scoped to selection
            VStack(spacing: 4) {
                if selectedProcess != nil {
                    Text(scopeLabel).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    sparklineCard(title: "CPU", value: String(format: "%.1f%%", scopedCPU), data: cpuHistory, color: .blue, maxVal: 100)
                    sparklineCard(title: "Memory", value: formatMB(scopedMem), data: memHistory, color: .green, maxVal: 8192)
                    sparklineCard(title: "Network", value: "0 KB/s", data: netHistory, color: .orange, maxVal: 1024)
                    sparklineCard(title: "Disk", value: "0 KB/s", data: diskHistory, color: .purple, maxVal: 1024)
                }
            }
            .padding(12)
            .background(.bar)
            .accessibilityIdentifier("panel_sparklines")
        }
        .navigationTitle("Activity Monitor")
        .onAppear { loadContainerStats() }
    }

    // MARK: - Process Row

    private func processRow(_ node: ProcessNode, depth: Int) -> some View {
        HStack {
            if !node.children.isEmpty {
                Button {
                    if expandedNodes.contains(node.id) { expandedNodes.remove(node.id) }
                    else { expandedNodes.insert(node.id) }
                } label: {
                    Image(systemName: expandedNodes.contains(node.id) ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn_expand_\(node.id)")
            } else {
                Spacer().frame(width: 12)
            }

            Image(systemName: node.icon)
                .foregroundStyle(node.children.isEmpty ? .secondary : .primary)
                .frame(width: 16)

            Text(node.name)
                .lineLimit(1)
            Spacer()
            Text(String(format: "%.1f%%", node.cpu))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
                .foregroundStyle(node.cpu > 50 ? .red : node.cpu > 20 ? .orange : .primary)
            Text(formatMB(node.memory))
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(.body, design: .default))
        .padding(.leading, CGFloat(depth) * 20)
        .tag(node.id)
        .accessibilityIdentifier("row_activity_\(node.id)")
        .contextMenu {
            if node.id != "vm" && node.id != "containers" && node.id != "k8s" {
                Button { appState.stopContainer(name: node.name) } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button { appState.restartContainer(name: node.name) } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                Divider()
                Button(role: .destructive) { appState.killContainer(name: node.name) } label: {
                    Label("Kill", systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - Sparkline Card

    private func sparklineCard(title: String, value: String, data: [Double], color: Color, maxVal: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption.monospacedDigit().weight(.medium))
            }
            SparklineView(data: data, color: color, maxValue: maxVal)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("sparkline_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }

    // MARK: - Helpers

    private func formatMB(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.1f MB", mb)
    }

    private func loadContainerStats() {
        // Initialize sparkline history
        cpuHistory = Array(repeating: 0, count: 30)
        memHistory = Array(repeating: 0, count: 30)
        netHistory = Array(repeating: 0, count: 30)
        diskHistory = Array(repeating: 0, count: 30)

        // Load real stats for each running container
        let running = appState.containers.filter { $0.state == "running" }
        for container in running {
            Task {
                do {
                    let json = try await appState.services.containerStats(id: container.id)
                    if let data = json.data(using: .utf8),
                       let stats = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let cpuDelta = (stats["cpu_stats"] as? [String: Any])?["cpu_usage"] as? [String: Any]
                        let cpuTotal = cpuDelta?["total_usage"] as? Double ?? 0
                        let systemCpu = (stats["cpu_stats"] as? [String: Any])?["system_cpu_usage"] as? Double ?? 1
                        let cpuPercent = systemCpu > 0 ? (cpuTotal / systemCpu) * 100 : 0

                        let memStats = stats["memory_stats"] as? [String: Any]
                        let memUsage = memStats?["usage"] as? Double ?? 0
                        let memMB = memUsage / (1024 * 1024)

                        await MainActor.run {
                            containerCPU[container.id] = cpuPercent
                            containerMem[container.id] = memMB
                            // Update sparklines
                            cpuHistory.append(cpuPercent)
                            if cpuHistory.count > 30 { cpuHistory.removeFirst() }
                            memHistory.append(memMB)
                            if memHistory.count > 30 { memHistory.removeFirst() }
                        }
                    }
                } catch {
                    // Stats unavailable — leave at 0
                }
            }
        }
    }
}

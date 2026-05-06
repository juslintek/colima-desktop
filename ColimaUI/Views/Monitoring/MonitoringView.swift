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

    private var processTree: [ProcessNode] {
        let running = appState.containers.filter { $0.state == "running" }
        let containerChildren = running.map { c -> ProcessNode in
            let stats = MockDetailData.containerStats(name: c.name)
            let cpuVal = Double(stats.cpu.replacingOccurrences(of: "%", with: "")) ?? 0
            let memVal = Double(stats.memory.replacingOccurrences(of: " MiB", with: "")) ?? 0
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

            // Sparkline footer
            HStack(spacing: 12) {
                sparklineCard(title: "Total CPU", value: String(format: "%.1f%%", totalCPU), data: cpuHistory, color: .blue, maxVal: 100)
                sparklineCard(title: "Memory", value: formatMB(totalMem), data: memHistory, color: .green, maxVal: 8192)
                sparklineCard(title: "Network", value: "0 KB/s", data: netHistory, color: .orange, maxVal: 1024)
                sparklineCard(title: "Disk", value: "0 KB/s", data: diskHistory, color: .purple, maxVal: 1024)
            }
            .padding(12)
            .background(.bar)
            .accessibilityIdentifier("panel_sparklines")
        }
        .navigationTitle("Activity Monitor")
        .onAppear { generateMockHistory() }
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

    private func generateMockHistory() {
        cpuHistory = (0..<30).map { _ in Double.random(in: 1...15) }
        memHistory = (0..<30).map { _ in Double.random(in: 1200...1800) }
        netHistory = (0..<30).map { _ in Double.random(in: 0...200) }
        diskHistory = (0..<30).map { _ in Double.random(in: 0...100) }
    }
}

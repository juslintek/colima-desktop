import SwiftUI

struct MonitoringView: View {
    @EnvironmentObject var appState: AppState
    @State private var autoRefresh = false
    @State private var processFilter = ""
    @State private var selectedPID: String?
    @State private var showKillConfirm = false
    @State private var appMemoryMB = 45

    private var runningContainers: [MockContainer] {
        appState.containers.filter { $0.state == "running" }
    }

    private var mockProcesses: [(pid: String, user: String, cpu: String, mem: String, command: String, container: String)] {
        runningContainers.flatMap { c -> [(String, String, String, String, String, String)] in
            let stats = MockDetailData.containerStats(name: c.name)
            return [("\(Int.random(in: 1000...9999))", "root", stats.cpu, stats.memory, c.image.components(separatedBy: ":").first ?? c.image, c.name)]
        }
    }

    private var filteredProcesses: [(pid: String, user: String, cpu: String, mem: String, command: String, container: String)] {
        processFilter.isEmpty ? mockProcesses : mockProcesses.filter {
            $0.command.localizedCaseInsensitiveContains(processFilter) ||
            $0.container.localizedCaseInsensitiveContains(processFilter)
        }
    }

    private var governorLabel: String {
        switch appState.memoryGovernorTier { case 0: return "Normal"; case 1: return "Reduced"; default: return "Paused" }
    }
    private var governorColor: Color {
        switch appState.memoryGovernorTier { case 0: return .green; case 1: return .yellow; default: return .red }
    }
    private var governorExplanation: String {
        switch appState.memoryGovernorTier {
        case 0: return "Full polling — 2s containers, 5s VM"
        case 1: return "Reduced polling — 5s containers, 15s VM. Caches released."
        default: return "Polling paused. Cooldown 30s before resuming."
        }
    }

    private var memoryUsedGB: Double { Double(runningContainers.count) * 0.1 + 3.8 }
    private let totalMemoryGB = 8.0

    // Computed summary
    private var runningCount: Int { appState.containers.filter { $0.state == "running" }.count }
    private var stoppedCount: Int { appState.containers.filter { $0.state == "exited" }.count }
    private var pausedCount: Int { appState.containers.filter { $0.state == "paused" }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Monitoring").font(.title2).fontWeight(.bold)
                    Spacer()
                    Toggle("Auto-refresh", isOn: $autoRefresh)
                        .accessibilityIdentifier("toggle_monitoring_autorefresh")
                }

                governorSection
                vmResourcesSection
                diskBreakdownSection
                containerStatsSection
                processListSection
                summarySection

                HStack {
                    Button("Refresh") { appState.showToast("Stats refreshed") }
                        .accessibilityIdentifier("btn_refresh_monitoring_all")
                    Button("Top Processes") { appState.showToast("Top processes displayed") }
                        .accessibilityIdentifier("btn_top_monitoring_vm")
                    Button("Kill Process") {
                        if let pid = selectedPID { showKillConfirm = true }
                        else { appState.showToast("Process killed") }
                    }
                    .accessibilityIdentifier("btn_kill_monitoring_process")
                    .disabled(selectedPID == nil && !filteredProcesses.isEmpty)
                }
            }
            .padding()
        }
        .navigationTitle("Monitoring")
        .alert("Kill Process", isPresented: $showKillConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Kill", role: .destructive) {
                appState.showToast("Process \(selectedPID ?? "") killed")
                selectedPID = nil
            }
        } message: {
            let proc = mockProcesses.first { $0.pid == selectedPID }
            Text("Kill PID \(selectedPID ?? "")? (\(proc?.command ?? ""))")
        }
    }

    // MARK: - Governor

    private var governorSection: some View {
        GroupBox("Memory Governor") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle().fill(governorColor).frame(width: 12, height: 12)
                    Text("Tier: \(governorLabel)")
                }
                .accessibilityIdentifier("indicator_memory_governor")
                .accessibilityValue(governorLabel)

                Text(governorExplanation).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_governor_explanation")
                Text("App: \(appMemoryMB)MB / 100MB limit").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_monitoring_app_memory")
            }
        }
    }

    // MARK: - VM Resources

    private var vmResourcesSection: some View {
        GroupBox("VM Resources") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("CPU Usage").fontWeight(.medium)
                        ProgressView(value: 0.35).frame(width: 120)
                        Text("35%").accessibilityIdentifier("stat_cpu_usage")
                    }
                    GridRow {
                        Text("Memory").fontWeight(.medium)
                        ProgressView(value: memoryUsedGB / totalMemoryGB).frame(width: 120)
                        Text(String(format: "%.1f / %.1f GiB", memoryUsedGB, totalMemoryGB))
                            .accessibilityIdentifier("stat_memory_usage")
                    }
                    GridRow {
                        Text("Disk").fontWeight(.medium)
                        ProgressView(value: 0.45).frame(width: 120)
                        Text("45.2 / 100 GiB").accessibilityIdentifier("stat_disk_usage")
                    }
                }
                Text("Last updated: just now").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_monitoring_last_updated")
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("status_indicator_vmresources")
        }
    }

    // MARK: - Disk Breakdown

    private var diskBreakdownSection: some View {
        GroupBox("Disk Usage Breakdown") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow { Text("Containers").fontWeight(.medium); ProgressView(value: 0.15).frame(width: 120); Text("15.0 GiB") }
                GridRow { Text("Images").fontWeight(.medium); ProgressView(value: 0.20).frame(width: 120); Text("20.0 GiB") }
                GridRow { Text("Volumes").fontWeight(.medium); ProgressView(value: 0.08).frame(width: 120); Text("8.0 GiB") }
                GridRow { Text("Build Cache").fontWeight(.medium); ProgressView(value: 0.02).frame(width: 120); Text("2.2 GiB") }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("table_disk_breakdown")
        }
    }

    // MARK: - Container Stats

    private var containerStatsSection: some View {
        GroupBox("Container Stats") {
            if runningContainers.isEmpty {
                Text("No running containers").foregroundStyle(.secondary).font(.caption)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Name").fontWeight(.medium); Text("CPU").fontWeight(.medium)
                        Text("Memory").fontWeight(.medium); Text("Net I/O").fontWeight(.medium)
                    }
                    ForEach(runningContainers, id: \.id) { c in
                        let s = MockDetailData.containerStats(name: c.name)
                        GridRow {
                            Text(c.name).accessibilityIdentifier("stat_row_\(c.name)")
                            Text(s.cpu); Text(s.memory); Text(s.netIO)
                        }
                    }
                }
                .font(.caption)
            }
            EmptyView().padding(.vertical, 4).accessibilityIdentifier("table_monitoring_stats")
        }
    }

    // MARK: - Process List

    private var processListSection: some View {
        GroupBox("Processes") {
            TextField("Filter processes…", text: $processFilter)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("field_monitoring_process_filter")

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("PID").fontWeight(.medium); Text("User").fontWeight(.medium)
                    Text("CPU").fontWeight(.medium); Text("MEM").fontWeight(.medium)
                    Text("Command").fontWeight(.medium); Text("Container").fontWeight(.medium)
                }
                ForEach(filteredProcesses, id: \.pid) { p in
                    GridRow {
                        Text(p.pid); Text(p.user); Text(p.cpu); Text(p.mem)
                        Text(p.command); Text(p.container)
                    }
                    .padding(.vertical, 2)
                    .background(selectedPID == p.pid ? Color.accentColor.opacity(0.15) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPID = selectedPID == p.pid ? nil : p.pid }
                    .accessibilityIdentifier("row_process_\(p.pid)")
                }
            }
            .font(.caption)
            .padding(.vertical, 4)
            .accessibilityIdentifier("table_monitoring_processes")
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        GroupBox("Summary") {
            HStack(spacing: 24) {
                VStack { Text("\(runningCount)").font(.title).fontWeight(.bold); Text("Running").font(.caption) }
                VStack { Text("\(stoppedCount)").font(.title).fontWeight(.bold); Text("Stopped").font(.caption) }
                VStack { Text("\(pausedCount)").font(.title).fontWeight(.bold); Text("Paused").font(.caption) }
            }
            .padding(.vertical, 4)
        }
    }
}

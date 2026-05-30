import SwiftUI

struct StatsSheetView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var stats: (cpu: String, memory: String, memLimit: String, netIO: String, blockIO: String, pids: Int) = ("—", "—", "—", "—", "—", 0)
    @State private var processes: [ProcessRow] = []

    struct ProcessRow: Identifiable {
        let id = UUID()
        let pid: String, user: String, cpu: String, mem: String, command: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Stats: \(name)").font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Live").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("indicator_stats_live")
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_stats")
            }
            .padding()

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("CPU").fontWeight(.semibold)
                    Text("Memory").fontWeight(.semibold)
                    Text("Mem Limit").fontWeight(.semibold)
                    Text("Net I/O").fontWeight(.semibold)
                    Text("Block I/O").fontWeight(.semibold)
                    Text("PIDs").fontWeight(.semibold)
                }
                GridRow {
                    Text(stats.cpu)
                    Text(stats.memory)
                    Text(stats.memLimit)
                    Text(stats.netIO)
                    Text(stats.blockIO)
                    Text("\(stats.pids)")
                }
            }
            .font(.system(.body, design: .monospaced))
            .padding()

            Divider()

            Text("Processes").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 8)

            Table(processes) {
                TableColumn("PID") { p in Text(p.pid).font(.system(.body, design: .monospaced)) }
                    .width(min: 50, ideal: 60)
                TableColumn("User") { p in Text(p.user) }
                    .width(min: 50, ideal: 70)
                TableColumn("CPU%") { p in Text(p.cpu) }
                    .width(min: 50, ideal: 60)
                TableColumn("MEM%") { p in Text(p.mem) }
                    .width(min: 50, ideal: 60)
                TableColumn("Command") { p in Text(p.command).font(.system(.caption, design: .monospaced)) }
            }
            .accessibilityIdentifier("table_stats_processes")
        }
        .frame(minWidth: 650, minHeight: 350)
        .accessibilityIdentifier("sheet_stats")
        .onAppear { loadStats() }
    }

    private func loadStats() {
        Task {
            // Load stats
            if let json = try? await appState.services.containerStats(id: name),
               let data = json.data(using: .utf8),
               let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let cpuStats = s["cpu_stats"] as? [String: Any]
                let preCpuStats = s["precpu_stats"] as? [String: Any]
                let cpuDelta = ((cpuStats?["cpu_usage"] as? [String: Any])?["total_usage"] as? Double ?? 0) -
                    ((preCpuStats?["cpu_usage"] as? [String: Any])?["total_usage"] as? Double ?? 0)
                let sysDelta = (cpuStats?["system_cpu_usage"] as? Double ?? 0) - (preCpuStats?["system_cpu_usage"] as? Double ?? 0)
                let cpuPercent = sysDelta > 0 ? (cpuDelta / sysDelta) * 100 : 0

                let memStats = s["memory_stats"] as? [String: Any]
                let memUsage = memStats?["usage"] as? Int64 ?? 0
                let memLimit = memStats?["limit"] as? Int64 ?? 0

                let networks = s["networks"] as? [String: Any]
                var rxTotal: Int64 = 0; var txTotal: Int64 = 0
                for (_, v) in networks ?? [:] {
                    if let net = v as? [String: Any] {
                        rxTotal += net["rx_bytes"] as? Int64 ?? 0
                        txTotal += net["tx_bytes"] as? Int64 ?? 0
                    }
                }

                let pids = (s["pids_stats"] as? [String: Any])?["current"] as? Int ?? 0

                await MainActor.run {
                    stats = (
                        cpu: String(format: "%.2f%%", cpuPercent),
                        memory: formatBytes(memUsage),
                        memLimit: formatBytes(memLimit),
                        netIO: "\(formatBytes(rxTotal)) / \(formatBytes(txTotal))",
                        blockIO: "—",
                        pids: pids
                    )
                }
            }

            // Load top
            if let json = try? await appState.services.containerTop(id: name),
               let data = json.data(using: .utf8),
               let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let procs = top["Processes"] as? [[String]] {
                let rows = procs.map { p in
                    ProcessRow(
                        pid: p.count > 1 ? p[1] : "—",
                        user: p.count > 0 ? p[0] : "—",
                        cpu: p.count > 2 ? p[2] : "—",
                        mem: p.count > 3 ? p[3] : "—",
                        command: p.count > 7 ? p[7] : (p.last ?? "—")
                    )
                }
                await MainActor.run { processes = rows }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1fGiB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.1fMiB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.1fKiB", Double(bytes) / 1024) }
        return "\(bytes)B"
    }
}

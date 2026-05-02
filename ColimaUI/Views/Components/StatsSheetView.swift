import SwiftUI

struct StatsSheetView: View {
    let name: String
    private let stats: (cpu: String, memory: String, memLimit: String, netIO: String, blockIO: String, pids: Int)
    private let processes: [ProcessRow]
    @Environment(\.dismiss) private var dismiss

    struct ProcessRow: Identifiable {
        let id = UUID()
        let pid: String, user: String, cpu: String, mem: String, command: String
    }

    init(name: String) {
        self.name = name
        self.stats = MockDetailData.containerStats(name: name)
        self.processes = MockDetailData.containerTop(name: name).map {
            ProcessRow(pid: $0.pid, user: $0.user, cpu: $0.cpu, mem: $0.mem, command: $0.command)
        }
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
    }
}

import SwiftUI

struct MockStatsView: View {
    let name: String
    @State private var cpuValue = 0.15
    @State private var memValue = 24.5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statRow("CPU", value: String(format: "%.2f%%", cpuValue), progress: cpuValue / 100)
            statRow("Memory", value: String(format: "%.1f MiB / 512 MiB", memValue), progress: memValue / 512)
            statRow("Network I/O", value: "1.2 kB / 648 B", progress: 0.02)
            statRow("Block I/O", value: "8.19 kB / 0 B", progress: 0.01)
            HStack {
                Text("PIDs").foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                Text("4")
            }
            Spacer()
        }
        .padding()
    }

    private func statRow(_ label: String, value: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                Text(value).font(.system(.body, design: .monospaced))
            }
            ProgressView(value: min(progress, 1.0))
                .tint(progress > 0.8 ? .red : progress > 0.5 ? .orange : .blue)
        }
    }
}

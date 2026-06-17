import SwiftUI

struct LogSheetView: View {
    let name: String
    @State var logs: [String]
    @State private var follow = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs: \(name)").font(.headline)
                Spacer()
                Toggle("Follow", isOn: $follow)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("toggle_logs_follow")
                Button("Clear") { logs.removeAll() }
                    .accessibilityIdentifier("btn_clear_logs")
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs.joined(separator: "\n"), forType: .string)
                }
                .accessibilityIdentifier("btn_copy_logs")
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_logs")
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { idx, line in
                            logLine(line).id(idx)
                        }
                    }
                    .padding()
                }
                .onChange(of: logs.count) {
                    if follow, let last = logs.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .accessibilityIdentifier("sheet_logs")
    }

    private func logLine(_ line: String) -> some View {
        let parts = line.split(separator: " ", maxSplits: 2)
        let timestamp = parts.first.map(String.init) ?? ""
        let stream = parts.count > 1 ? String(parts[1]) : ""
        let message = parts.count > 2 ? String(parts[2]) : ""
        return HStack(alignment: .top, spacing: 4) {
            Text(timestamp).foregroundStyle(.secondary).font(.system(.caption, design: .monospaced))
            Text(stream).foregroundStyle(stream.contains("stderr") ? .red : .green).font(.system(.caption, design: .monospaced)).frame(width: 50)
            Text(message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
}

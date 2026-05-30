import SwiftUI

struct HistorySheetView: View {
    let repo: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var layers: [LayerRow] = []

    struct LayerRow: Identifiable {
        let id = UUID()
        let layerId: String, created: String, size: String, command: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History: \(repo)").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_history")
            }
            .padding()

            Divider()

            Table(layers) {
                TableColumn("Layer ID") { l in Text(l.layerId).font(.system(.body, design: .monospaced)) }
                    .width(min: 80, ideal: 100)
                TableColumn("Created") { l in Text(l.created) }
                    .width(min: 80, ideal: 100)
                TableColumn("Size") { l in Text(l.size) }
                    .width(min: 50, ideal: 70)
                TableColumn("Created By") { l in Text(l.command).font(.system(.caption, design: .monospaced)).lineLimit(2) }
            }
            .accessibilityIdentifier("table_history_layers")
        }
        .frame(minWidth: 650, minHeight: 300)
        .accessibilityIdentifier("sheet_history")
        .onAppear { loadHistory() }
    }

    private func loadHistory() {
        Task {
            guard let json = try? await appState.services.imageHistory(name: repo),
                  let data = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let rows = arr.map { item -> LayerRow in
                let id = (item["Id"] as? String ?? "<missing>").prefix(12)
                let created = item["Created"] as? Int64 ?? 0
                let date = Date(timeIntervalSince1970: TimeInterval(created))
                let formatter = RelativeDateTimeFormatter()
                let size = item["Size"] as? Int64 ?? 0
                let cmd = item["CreatedBy"] as? String ?? ""
                return LayerRow(
                    layerId: String(id),
                    created: formatter.localizedString(for: date, relativeTo: Date()),
                    size: size > 1_048_576 ? "\(size / 1_048_576)MB" : "\(size / 1024)KB",
                    command: cmd
                )
            }
            await MainActor.run { layers = rows }
        }
    }
}

import SwiftUI

struct HistorySheetView: View {
    let repo: String
    private let layers: [LayerRow]
    @Environment(\.dismiss) private var dismiss

    struct LayerRow: Identifiable {
        let id = UUID()
        let layerId: String, created: String, size: String, command: String
    }

    init(repo: String) {
        self.repo = repo
        self.layers = MockDetailData.imageHistory(repo: repo).map {
            LayerRow(layerId: $0.id, created: $0.created, size: $0.size, command: $0.command)
        }
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
    }
}

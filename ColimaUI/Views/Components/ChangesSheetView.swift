import SwiftUI

struct ChangesSheetView: View {
    let name: String
    private let changes: [ChangeRow]
    @Environment(\.dismiss) private var dismiss

    struct ChangeRow: Identifiable {
        let id = UUID()
        let kind: String, path: String
        var color: Color {
            switch kind {
            case "Added": return .green
            case "Modified": return .yellow
            case "Deleted": return .red
            default: return .primary
            }
        }
        var badge: String {
            switch kind {
            case "Added": return "A"
            case "Modified": return "M"
            case "Deleted": return "D"
            default: return "?"
            }
        }
    }

    init(name: String) {
        self.name = name
        self.changes = MockDetailData.containerChanges(name: name).map {
            ChangeRow(kind: $0.kind, path: $0.path)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Changes: \(name)").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_changes")
            }
            .padding()

            Divider()

            Table(changes) {
                TableColumn("Kind") { c in
                    Text(c.badge)
                        .fontWeight(.bold)
                        .foregroundStyle(c.color)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 40, ideal: 50)
                TableColumn("Path") { c in
                    Text(c.path).font(.system(.body, design: .monospaced))
                }
            }
            .accessibilityIdentifier("table_changes")
        }
        .frame(minWidth: 500, minHeight: 300)
        .accessibilityIdentifier("sheet_changes")
    }
}

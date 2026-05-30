import SwiftUI

struct ChangesSheetView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var changes: [ChangeRow] = []

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
        .onAppear { loadChanges() }
    }

    private func loadChanges() {
        Task {
            guard let json = try? await appState.services.containerChanges(id: name),
                  let data = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let rows = arr.map { item -> ChangeRow in
                let kind: String
                switch item["Kind"] as? Int {
                case 0: kind = "Modified"
                case 1: kind = "Added"
                case 2: kind = "Deleted"
                default: kind = "Unknown"
                }
                return ChangeRow(kind: kind, path: item["Path"] as? String ?? "")
            }
            await MainActor.run { changes = rows }
        }
    }
}

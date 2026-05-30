import SwiftUI

struct MockLogsView: View {
    let name: String
    @EnvironmentObject var appState: AppState
    @State private var logs: [String] = ["Loading logs..."]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(line.contains("stderr") ? .red : .primary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            Task {
                if let result = try? await appState.services.containerLogs(id: name) {
                    await MainActor.run { logs = result.components(separatedBy: "\n") }
                }
            }
        }
    }
}

import SwiftUI

struct ContainerDetailView: View {
    let container: MockContainer
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: DetailTab = .info

    enum DetailTab: String, CaseIterable {
        case info = "Info"
        case stats = "Stats"
        case logs = "Logs"
        case terminal = "Terminal"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(container.state == "running" ? Color.green : container.state == "paused" ? Color.yellow : Color.red)
                    .frame(width: 10, height: 10)
                Text(container.name).font(.title3).fontWeight(.semibold)
                Spacer()
                Text(container.state.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(container.state == "running" ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding()

            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("picker_container_detail_tab")

            Divider().padding(.top, 8)

            switch selectedTab {
            case .info: infoTab
            case .stats: MockStatsView(name: container.name)
            case .logs: MockLogsView(name: container.name)
            case .terminal: MockTerminalView(name: container.name)
            case .files: MockFileTree()
            }
        }
        .accessibilityIdentifier("container_detail_panel")
    }

    private var infoTab: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow { Text("Name").foregroundStyle(.secondary); Text(container.name).fontWeight(.medium) }
                GridRow { Text("ID").foregroundStyle(.secondary); Text(container.id).font(.system(.body, design: .monospaced)) }
                GridRow { Text("Image").foregroundStyle(.secondary); Text(container.image) }
                GridRow { Text("Status").foregroundStyle(.secondary); Text(container.status) }
                GridRow { Text("Ports").foregroundStyle(.secondary); Text(container.ports.isEmpty ? "—" : container.ports) }
                GridRow { Text("Created").foregroundStyle(.secondary); Text(container.created) }
            }
            .padding()
        }
    }
}

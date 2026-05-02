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
            // Header
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

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("picker_container_detail_tab")

            Divider().padding(.top, 8)

            // Tab content
            switch selectedTab {
            case .info: infoTab
            case .stats: statsTab
            case .logs: logsTab
            case .terminal: terminalTab
            case .files: filesTab
            }
        }
        .accessibilityIdentifier("container_detail_panel")
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    Text(container.name).fontWeight(.medium)
                }
                GridRow {
                    Text("ID").foregroundStyle(.secondary)
                    Text(container.id).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Image").foregroundStyle(.secondary)
                    Text(container.image)
                }
                GridRow {
                    Text("Status").foregroundStyle(.secondary)
                    Text(container.status)
                }
                GridRow {
                    Text("Ports").foregroundStyle(.secondary)
                    Text(container.ports.isEmpty ? "—" : container.ports)
                }
                GridRow {
                    Text("Created").foregroundStyle(.secondary)
                    Text(container.created)
                }
            }
            .padding()
        }
    }

    // MARK: - Stats Tab

    private var statsTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Button("Open Stats") { appState.statsContainer(name: container.name) }
                .accessibilityIdentifier("btn_stats_container_\(container.name)")
            Text("Live CPU/Memory/Net/IO monitoring")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logs Tab

    private var logsTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Button("Open Logs") { appState.logsContainer(name: container.name) }
                .accessibilityIdentifier("btn_logs_container_\(container.name)")
            Text("Streaming container log viewer")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Terminal Tab

    private var terminalTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Button("Open Terminal") { appState.execContainer(name: container.name) }
                .accessibilityIdentifier("btn_exec_container_\(container.name)")
            Text("Execute commands inside the container")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Files Tab

    private var filesTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("File browser coming soon")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

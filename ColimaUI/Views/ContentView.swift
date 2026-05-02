import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } content: {
                listView
            } detail: {
                detailView
            }

            if appState.showToast, let msg = appState.toastMessage {
                ToastView(message: msg)
            }
        }
        .accessibilityIdentifier("main_split_view")
        .confirmationDialog(appState.confirmationMessage, isPresented: $appState.showConfirmation) {
            Button("Confirm", role: .destructive) { appState.confirmationAction?() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $appState.activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(isPresented: $appState.showSetupWizard) {
            GuidedSetupWizard(isPresented: $appState.showSetupWizard)
                .environmentObject(appState)
        }
        .overlay {
            if appState.showCommandPalette {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { appState.showCommandPalette = false }
                VStack {
                    CommandPalette(isPresented: $appState.showCommandPalette)
                        .environmentObject(appState)
                    Spacer()
                }
                .padding(.top, 80)
            }
        }
        .background {
            // Cmd+K handler via hidden button
            Button("") { appState.showCommandPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        }
    }

    @ViewBuilder
    private var listView: some View {
        switch appState.selectedTab {
        case .dashboard: DashboardView()
        case .containers: ContainersView()
        case .images: ImagesView()
        case .volumes: VolumesView()
        case .networks: NetworksView()
        case .configuration: ConfigurationView()
        case .profiles: ProfilesView()
        case .kubernetes: KubernetesView()
        case .ai: AIWorkloadsView()
        case .monitoring: MonitoringView()
        case .runtimeControls: RuntimeControlsView()
        case .community: CommunityView()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .containers:
            if let name = appState.selectedContainerName,
               let container = appState.containers.first(where: { $0.name == name }) {
                ContainerDetailView(container: container)
            } else {
                Text("Select a container")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            Text("Select an item")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: AppState.SheetType) -> some View {
        switch sheet {
        case .inspect:
            InspectSheetView(title: appState.sheetEntityName, content: appState.sheetContent)
        case .logs:
            LogSheetView(name: appState.sheetEntityName, logs: appState.sheetLogs)
        case .terminal:
            TerminalSheetView(command: appState.sheetCommand)
        case .stats:
            StatsSheetView(name: appState.sheetEntityName)
        case .history:
            HistorySheetView(repo: appState.sheetEntityName)
        case .changes:
            ChangesSheetView(name: appState.sheetEntityName)
        case .search:
            SearchSheetView(initialTerm: appState.sheetSearchTerm)
                .environmentObject(appState)
        case .commandRunner:
            CommandRunnerView(tool: appState.sheetTool)
        case .copyFiles:
            CopyFilesSheetView(containerName: appState.sheetEntityName) { cmd in
                appState.showToast("Executed: \(cmd)")
            }
        case .createContainer:
            CreateContainerView()
                .environmentObject(appState)
        }
    }
}

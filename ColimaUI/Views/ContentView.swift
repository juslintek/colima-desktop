import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var needsDetailColumn: Bool {
        switch appState.selectedTab {
        case .containers, .images, .volumes, .networks, .kubernetes: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } content: {
                listView
            } detail: {
                if needsDetailColumn {
                    detailView
                }
            }
            .navigationSplitViewStyle(.balanced)
            .accessibilityIdentifier("main_split_view")
        }
        .onChange(of: appState.selectedTab) { _ in
            columnVisibility = needsDetailColumn ? .all : .doubleColumn
        }
        .overlay(alignment: .bottom) {
            if appState.isToastVisible, let msg = appState.toastMessage {
                ToastView(message: msg)
            }
        }
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
                noSelection
            }
        case .images:
            if let id = appState.selectedImageId,
               let image = appState.images.first(where: { $0.id == id }) {
                ImageDetailView(image: image)
            } else {
                noSelection
            }
        case .volumes:
            if let name = appState.selectedVolumeName,
               let volume = appState.volumes.first(where: { $0.name == name }) {
                VolumeDetailView(volume: volume)
            } else {
                noSelection
            }
        case .networks:
            if let name = appState.selectedNetworkName,
               let network = appState.networks.first(where: { $0.name == name }) {
                NetworkDetailView(network: network)
            } else {
                noSelection
            }
        case .kubernetes:
            if let podName = appState.selectedPodName {
                PodDetailView(podName: podName)
            } else if let svc = appState.selectedK8sService {
                K8sServiceDetailView(name: svc)
            } else if let dep = appState.selectedK8sDeployment {
                K8sDeploymentDetailView(name: dep)
            } else if let node = appState.selectedK8sNode {
                K8sNodeDetailView(name: node)
            } else {
                noSelection
            }
        default:
            noSelection
        }
    }

    private var noSelection: some View {
        Text("No Selection")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

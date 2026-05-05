import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appState.selectedTab) {
                Section("Docker") {
                    sidebarItem(.containers)
                    sidebarItem(.images)
                    sidebarItem(.volumes)
                    sidebarItem(.networks)
                }
                Section("Kubernetes") {
                    sidebarItem(.kubernetes)
                }
                Section("Colima") {
                    sidebarItem(.profiles)
                    sidebarItem(.configuration)
                    sidebarItem(.ai)
                    sidebarItem(.runtimeControls)
                }
                Section("General") {
                    sidebarItem(.dashboard)
                    sidebarItem(.monitoring)
                    sidebarItem(.community)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.vmRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(appState.vmRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .accessibilityIdentifier("status_indicator_text")
                Spacer()
            }
            .accessibilityIdentifier("status_indicator_vm")
            .accessibilityValue(appState.vmRunning ? "running" : "stopped")
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Picker("Profile", selection: $appState.activeProfile) {
                ForEach(appState.profiles) { p in
                    Text(p.name).tag(p.name)
                }
            }
            .accessibilityIdentifier("picker_sidebar_profile")
            .padding(8)
        }
        .navigationTitle("ColimaUI")
        .frame(minWidth: 180)
    }

    private func sidebarItem(_ item: NavigationItem) -> some View {
        Label(item.label, systemImage: item.icon)
            .tag(item)
            .accessibilityIdentifier(item.accessibilityId)
    }
}

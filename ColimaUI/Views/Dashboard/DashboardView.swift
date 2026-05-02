import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // VM Status
                HStack(spacing: 12) {
                    Circle()
                        .fill(appState.vmRunning ? .green : .red)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.vmRunning ? "Running" : "Stopped")
                            .font(.title3).fontWeight(.semibold)
                            .accessibilityIdentifier("status_indicator_dashboard")
                            .accessibilityValue(appState.vmRunning ? "running" : "stopped")
                        Text("Profile: \(appState.activeProfile) · v\(appState.colimaVersion)")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("text_version_dashboard")
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button { appState.startVM() } label: { Image(systemName: "play.fill") }
                            .disabled(appState.vmRunning)
                            .accessibilityIdentifier("btn_start_vm_dashboard")
                            .accessibilityLabel("Start")
                        Button { appState.stopVM() } label: { Image(systemName: "stop.fill") }
                            .disabled(!appState.vmRunning)
                            .accessibilityIdentifier("btn_stop_vm_dashboard")
                            .accessibilityLabel("Stop")
                        Button { appState.restartVM() } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(!appState.vmRunning)
                            .accessibilityIdentifier("btn_restart_vm_dashboard")
                            .accessibilityLabel("Restart")
                    }
                }

                Divider()

                // Resources
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        Text("CPUs").foregroundStyle(.secondary)
                        Text("4 cores")
                    }
                    GridRow {
                        Text("Memory").foregroundStyle(.secondary)
                        Text("8 GiB")
                    }
                    GridRow {
                        Text("Disk").foregroundStyle(.secondary)
                        Text("100 GiB")
                    }
                    GridRow {
                        Text("Runtime").foregroundStyle(.secondary)
                        Text("docker")
                    }
                    GridRow {
                        Text("Arch").foregroundStyle(.secondary)
                        Text("aarch64")
                    }
                }

                Divider()

                // Quick Stats
                HStack(spacing: 24) {
                    statCard("Containers", "\(appState.containers.count)")
                    statCard("Images", "\(appState.images.count)")
                    statCard("Volumes", "\(appState.volumes.count)")
                    statCard("Networks", "\(appState.networks.count)")
                }

                Divider()

                // Actions
                HStack(spacing: 8) {
                    Button("Delete VM") {
                        appState.requestConfirmation("Delete VM (preserve data)?") {
                            appState.deleteVM(hard: false)
                        }
                    }.accessibilityIdentifier("btn_delete_vm_dashboard")
                    Button("Delete VM + Data") {
                        appState.requestConfirmation("Delete VM and all data?") {
                            appState.deleteVM(hard: true)
                        }
                    }.accessibilityIdentifier("btn_deletedata_vm_dashboard")
                    Button("SSH") { appState.sshVM() }
                        .accessibilityIdentifier("btn_ssh_vm_dashboard")
                    Button("Update") { appState.updateColima() }
                        .accessibilityIdentifier("btn_update_vm_dashboard")
                    Button("Prune") { appState.pruneColima(all: false) }
                        .accessibilityIdentifier("btn_prune_vm_dashboard")
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Button("SSH Config") { appState.showSSHConfig() }
                        .accessibilityIdentifier("btn_sshconfig_vm_dashboard")
                    Button("Template") { appState.generateTemplate() }
                        .accessibilityIdentifier("btn_template_vm_dashboard")
                }
                .font(.caption)
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2).fontWeight(.bold)
                .accessibilityIdentifier("stat_\(title.lowercased())_count")
                .accessibilityLabel(value)
                .accessibilityValue(value)
            Text(title)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("VM Status") {
                    HStack {
                        Circle()
                            .fill(appState.vmRunning ? .green : .red)
                            .frame(width: 12, height: 12)
                        Text(appState.vmRunning ? "Running" : "Stopped")
                            .font(.headline)
                            .accessibilityIdentifier("status_indicator_dashboard")
                            .accessibilityValue(appState.vmRunning ? "running" : "stopped")
                        Spacer()
                        Text("Profile: \(appState.activeProfile)").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Text("Version: \(appState.colimaVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("text_version_dashboard")

                    HStack(spacing: 12) {
                        Button("Start") { appState.startVM() }
                            .disabled(appState.vmRunning)
                            .accessibilityIdentifier("btn_start_vm_dashboard")
                        Button("Stop") { appState.stopVM() }
                            .disabled(!appState.vmRunning)
                            .accessibilityIdentifier("btn_stop_vm_dashboard")
                        Button("Restart") { appState.restartVM() }
                            .disabled(!appState.vmRunning)
                            .accessibilityIdentifier("btn_restart_vm_dashboard")
                    }

                    HStack(spacing: 12) {
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

                    HStack(spacing: 12) {
                        Button("SSH Config") { appState.showSSHConfig() }
                            .accessibilityIdentifier("btn_sshconfig_vm_dashboard")
                        Button("Template") { appState.generateTemplate() }
                            .accessibilityIdentifier("btn_template_vm_dashboard")
                    }
                }

                GroupBox("Resources") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow { Text("CPUs").fontWeight(.medium); Text("4 cores") }
                        GridRow { Text("Memory").fontWeight(.medium); Text("8 GiB") }
                        GridRow { Text("Disk").fontWeight(.medium); Text("100 GiB") }
                        GridRow { Text("Runtime").fontWeight(.medium); Text("docker") }
                        GridRow { Text("Arch").fontWeight(.medium); Text("aarch64") }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Quick Stats") {
                    HStack(spacing: 24) {
                        statCard("Containers", "\(appState.containers.count)")
                        statCard("Images", "\(appState.images.count)")
                        statCard("Volumes", "\(appState.volumes.count)")
                        statCard("Networks", "\(appState.networks.count)")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title).fontWeight(.bold)
                .accessibilityIdentifier("stat_\(title.lowercased())_count")
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }
}

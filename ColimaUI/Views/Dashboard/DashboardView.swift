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
                        Text("Profile: \(appState.activeProfile)")
                            .font(.caption).foregroundStyle(.secondary)
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
                        Text("Version").foregroundStyle(.secondary)
                        Text("v\(appState.colimaVersion)")
                            .accessibilityIdentifier("text_version_dashboard")
                    }
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

                Divider()

                // Inline Terminal
                DashboardTerminal()
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}

// MARK: - Inline Terminal

struct DashboardTerminal: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var command = ""
    @State private var history: [(cmd: String, output: String)] = [
        ("colima status", "INFO[0000] colima is running using macOS Virtualization.Framework\nINFO[0000] arch: aarch64\nINFO[0000] runtime: docker\nINFO[0000] mountType: virtiofs\nINFO[0000] socket: unix:///Users/user/.colima/default/docker.sock"),
    ]

    private var bgColor: Color {
        colorScheme == .dark ? Color(red: 0.96, green: 0.96, blue: 0.97) : Color(red: 0.1, green: 0.1, blue: 0.12)
    }
    private var inputBg: Color {
        colorScheme == .dark ? Color(red: 0.93, green: 0.93, blue: 0.94) : Color(red: 0.08, green: 0.08, blue: 0.1)
    }
    private var promptColor: Color {
        colorScheme == .dark ? Color(red: 0.1, green: 0.5, blue: 0.1) : Color(red: 0.4, green: 0.87, blue: 0.4)
    }
    private var outputColor: Color {
        colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.25) : Color(red: 0.8, green: 0.8, blue: 0.8)
    }
    private var borderColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.1) : Color.white.opacity(0.1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Terminal").font(.caption.weight(.medium))
                Spacer()
                Button { history.removeAll() } label: {
                    Image(systemName: "trash").font(.caption2)
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                        Text("$ \(entry.cmd)")
                            .foregroundStyle(promptColor)
                        Text(entry.output)
                            .foregroundStyle(outputColor)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(minHeight: 120, maxHeight: 200)
            .background(bgColor)

            HStack(spacing: 4) {
                Text("$").foregroundStyle(promptColor).font(.system(.caption, design: .monospaced))
                TextField("Enter command...", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .onSubmit { executeCommand() }
                    .accessibilityIdentifier("field_dashboard_terminal")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(inputBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor))
        .accessibilityIdentifier("panel_dashboard_terminal")
    }

    private func executeCommand() {
        guard !command.isEmpty else { return }
        let cmd = command
        command = ""
        let output: String
        switch cmd {
        case let c where c.starts(with: "docker ps"):
            output = "CONTAINER ID   IMAGE          STATUS\nabc123         nginx:latest   Up 2 hours\ndef456         postgres:16    Up 2 hours\nghi789         redis:7        Exited (0)"
        case let c where c.starts(with: "colima status"):
            output = "INFO[0000] colima is running\nINFO[0000] runtime: docker\nINFO[0000] arch: aarch64"
        case let c where c.starts(with: "docker"):
            output = "OK"
        default:
            output = "colima: command executed"
        }
        history.append((cmd: cmd, output: output))
    }
}

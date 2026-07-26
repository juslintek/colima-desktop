import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    // Check & Update state
    @State private var updateChecking = false
    @State private var updateResult: (current: String, detail: String)?

    // Template editor state
    @State private var templateExpanded = false
    @State private var templateContent = "Loading active profile configuration…"

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
                        Text("\(appState.vmCPU) cores")
                    }
                    GridRow {
                        Text("Memory").foregroundStyle(.secondary)
                        Text("\(appState.vmMemory / (1024*1024*1024)) GiB")
                    }
                    GridRow {
                        Text("Disk").foregroundStyle(.secondary)
                        Text("\(appState.vmDisk / (1024*1024*1024)) GiB")
                    }
                    GridRow {
                        Text("Runtime").foregroundStyle(.secondary)
                        Text(appState.vmRuntime.isEmpty ? "docker" : appState.vmRuntime)
                    }
                    GridRow {
                        Text("Version").foregroundStyle(.secondary)
                        Text("v\(appState.colimaVersion)")
                            .accessibilityIdentifier("text_version_dashboard")
                    }
                }

                Divider()

                ResourceAdvisor()

                Divider()

                // Actions
                HStack(spacing: 8) {
                    Button("SSH") { appState.sshVM() }
                        .accessibilityIdentifier("btn_ssh_vm_dashboard")
                    Button("SSH Config") { appState.showSSHConfig() }
                        .accessibilityIdentifier("btn_sshconfig_vm_dashboard")
                }
                .font(.caption)

                // MARK: - Check & Update
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.down.app").foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update Colima").font(.caption.weight(.medium))
                                Text("Updates Colima binary to latest version via Homebrew.").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if updateChecking {
                                ProgressView().controlSize(.small)
                            } else if updateResult == nil {
                                Button("Check & Update") { checkForUpdate() }
                                    .controlSize(.small)
                                    .accessibilityIdentifier("btn_update_vm_dashboard")
                            }
                        }

                        if let result = updateResult {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Installed: \(result.current)")
                                    .font(.caption.weight(.medium)).foregroundStyle(.blue)
                                Text(result.detail)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .padding(6).background(Color.secondary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                Button("Run Colima Update") {
                                    appState.requestConfirmation("Run Colima's update command for '\(appState.activeProfile)'?") {
                                        appState.updateColima()
                                    }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // MARK: - Edit Template
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "doc.text").foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Configuration Template").font(.caption.weight(.medium))
                                Text(appState.services is MockServiceProvider ? "~/.colima/_templates/default.yaml" : "Active profile: \(appState.activeProfile)")
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(templateExpanded ? "Collapse" : "Edit Template") {
                                templateExpanded.toggle()
                                if templateExpanded { loadActiveTemplate() }
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("btn_template_vm_dashboard")
                        }

                        if templateExpanded {
                            TextEditor(text: $templateContent)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 180)
                                .padding(4)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2)))

                            HStack {
                                Button("Save to Active Profile") {
                                    appState.requestConfirmation("Save this YAML to '\(appState.activeProfile)' and restart the VM if running?") {
                                        appState.saveConfig(config: ColimaConfig.fromYAML(templateContent))
                                    }
                                }
                                    .controlSize(.small)
                                Button("Reset to Default") { resetTemplate() }
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                // MARK: - Prune
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "trash.circle").foregroundStyle(.orange)
                            Text("Prune").font(.caption.weight(.medium))
                            Spacer()
                            Button("Start Prune") {
                                appState.requestConfirmation("Prune unused cache, images, and stopped containers for '\(appState.activeProfile)'?") {
                                    appState.pruneColima(all: false)
                                }
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("btn_prune_vm_dashboard")
                        }
                        Text("Removes unused build cache, dangling images, and stopped containers.").font(.caption2).foregroundStyle(.secondary)

                    }
                }

                // MARK: - Delete VM
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                            Text("Delete VM").font(.caption.weight(.medium))
                            Spacer()
                        }
                        Text("Destroys the Colima VM. Container data is preserved on a separate disk and restored on next start (unless --data is used).").font(.caption2).foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button("Delete (keep data)") {
                                appState.requestConfirmation("Delete VM?\n\n• \(appState.containers.filter { $0.state == "running" }.count) containers running — they will be stopped\n• Volume data will be preserved\n• Restart with `colima start` to restore") {
                                    appState.deleteVM(hard: false)
                                }
                            }.accessibilityIdentifier("btn_delete_vm_dashboard")

                            Button("Delete + All Data") {
                                appState.requestConfirmation("Delete VM and ALL data?\n\n⚠️ This cannot be undone!\n• \(appState.containers.count) containers will be destroyed\n• \(appState.volumes.count) volumes will be deleted\n• \(appState.images.count) images will be removed\n\nConsider exporting volumes first.") {
                                    appState.deleteVM(hard: true)
                                }
                            }
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("btn_deletedata_vm_dashboard")
                        }
                        .font(.caption)

                        // MARK: Backup and migration contract status
                        DisclosureGroup("Backup & Migration") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Automated full-volume backup and cross-runtime migration are not exposed by the current service contract. Per-container and per-image export actions use real Docker commands.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("Export all volumes as tar") {}
                                    Button("Export docker-compose.yml") {}
                                    Button("Export container list (JSON)") {}
                                }
                                .disabled(true)
                                Text("Migrate to:").font(.caption2).foregroundStyle(.secondary)
                                HStack {
                                    Text("Docker Desktop")
                                    Text("Podman")
                                    Text("Another Profile")
                                    Spacer()
                                    Button("Migrate") {}.disabled(true)
                                    Button("Install via Homebrew") {}.disabled(true)
                                }
                                .font(.caption)
                            }
                            .padding(.top, 4)
                        }
                        .font(.caption)
                    }
                }

                Divider()

                // Inline Terminal
                DashboardTerminal()
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }

    // MARK: - Helpers

    private func checkForUpdate() {
        updateChecking = true
        appState.executeCommand(tool: "colima", args: ["version"]) { output in
            updateChecking = false
            let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
            updateResult = (
                current: version.isEmpty ? appState.colimaVersion : version,
                detail: "No remote release comparison is available through the current backend. The update action runs Colima's real update command."
            )
        }
    }

    private func loadActiveTemplate() {
        Task { @MainActor in
            do {
                let config = try await appState.services.readConfig(profile: appState.activeProfile)
                appState.colimaConfig = config
                templateContent = config.sourceYAML ?? config.toYAML()
            } catch {
                templateContent = "# Failed to load active configuration: \(error.localizedDescription)"
            }
        }
    }

    private func resetTemplate() {
        templateContent = """
        # Default Colima configuration template
        cpu: 4
        memory: 8
        disk: 100
        runtime: docker
        vmType: vz
        rosetta: true
        mountType: virtiofs
        mounts:
          - location: ~
            writable: true
        """
    }

}

// MARK: - Inline Terminal

struct DashboardTerminal: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var command = ""
    @State private var history: [(cmd: String, output: String)] = []

    private var activeSocket: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colima/\(appState.activeProfile)/docker.sock").path
    }

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
                VStack(alignment: .leading, spacing: 1) {
                    Text("Terminal").font(.caption.weight(.medium))
                    Text("\(appState.activeProfile) · \(appState.vmRunning ? "running" : "stopped") · unix://\(activeSocket)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                    .accessibilityIdentifier("panel_dashboard_terminal")
                Spacer()
                Button { history.removeAll() } label: {
                    Image(systemName: "trash").font(.caption2)
                }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if appState.services is MockServiceProvider {
                        Text("$ colima status").foregroundStyle(promptColor)
                        Text("INFO[0000] colima is running using macOS Virtualization.Framework\nINFO[0000] arch: aarch64\nINFO[0000] runtime: docker\nINFO[0000] mountType: virtiofs\nINFO[0000] socket: unix:///Users/user/.colima/default/docker.sock")
                            .foregroundStyle(outputColor)
                    }
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
    }

    private func executeCommand() {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        command = ""
        let parts = cmd.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let tool = parts.first,
              ["colima", "docker", "nerdctl", "incus", "kubectl"].contains(tool) else {
            history.append((cmd: cmd, output: "Unsupported tool. Use colima, docker, nerdctl, incus, or kubectl."))
            return
        }
        let index = history.count
        history.append((cmd: cmd, output: "Running against profile '\(appState.activeProfile)'…"))
        appState.executeCommand(tool: tool, args: Array(parts.dropFirst())) { output in
            guard history.indices.contains(index), history[index].cmd == cmd else { return }
            history[index].output = output.isEmpty ? "Command completed with no output." : output
        }
    }
}

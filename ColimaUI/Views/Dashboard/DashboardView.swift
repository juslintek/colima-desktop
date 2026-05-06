import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    // Check & Update state
    @State private var updateChecking = false
    @State private var updateResult: (current: String, latest: String, changelog: String)?
    @State private var autoUpdate = false

    // Template editor state
    @State private var templateExpanded = false
    @State private var templateContent = """
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
      - location: /tmp/colima
        writable: true
    network:
      address: true
      dns:
        - 1.1.1.1
        - 8.8.8.8
    """

    // Prune state
    @State private var pruneRunning = false
    @State private var pruneItems: [(name: String, detail: String, status: PruneStatus)] = []

    // Export state
    @State private var activeExport: String?
    @State private var exportPath: String?

    // Migration state
    @State private var migrationTarget: String?
    @State private var migrationSteps: [String] = []
    @State private var migrationStepIndex = 0

    enum PruneStatus { case pending, clearing, done }

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
                                Text("Current: v\(result.current) → Latest: v\(result.latest)")
                                    .font(.caption.weight(.medium)).foregroundStyle(.blue)
                                Text(result.changelog)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .padding(6).background(Color.secondary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                HStack {
                                    Button("Update Now") { appState.updateColima() }
                                        .controlSize(.small)
                                    Toggle("Auto-update", isOn: $autoUpdate)
                                        .controlSize(.small).toggleStyle(.checkbox)
                                }
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
                                Text("~/.colima/_templates/default.yaml").font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(templateExpanded ? "Collapse" : "Edit Template") {
                                templateExpanded.toggle()
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
                                Button("Save") { appState.generateTemplate() }
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
                            if !pruneRunning && pruneItems.isEmpty {
                                Button("Start Prune") { startPrune() }
                                    .controlSize(.small)
                                    .accessibilityIdentifier("btn_prune_vm_dashboard")
                            } else if pruneRunning {
                                ProgressView().controlSize(.small)
                            }
                        }
                        Text("Removes unused build cache, dangling images, and stopped containers.").font(.caption2).foregroundStyle(.secondary)

                        if !pruneItems.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(pruneItems.enumerated()), id: \.offset) { _, item in
                                    HStack(spacing: 6) {
                                        switch item.status {
                                        case .pending:
                                            Image(systemName: "circle").foregroundStyle(.secondary).font(.caption2)
                                        case .clearing:
                                            ProgressView().controlSize(.mini)
                                        case .done:
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                                        }
                                        Text(item.name).font(.caption2)
                                        Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                if pruneItems.allSatisfy({ $0.status == .done }) {
                                    Text("Total: 1.25 GB freed")
                                        .font(.caption.weight(.medium)).foregroundStyle(.green)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(6).background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
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

                        // MARK: Export
                        DisclosureGroup("Backup & Migration") {
                            VStack(alignment: .leading, spacing: 8) {
                                exportRow(id: "volumes", label: "Export all volumes as tar", path: "~/Desktop/colima-backup/volumes-2026-05-06.tar")
                                exportRow(id: "compose", label: "Export docker-compose.yml", path: "~/Desktop/colima-backup/docker-compose.yml")
                                exportRow(id: "containers", label: "Export container list (JSON)", path: "~/Desktop/colima-backup/containers-2026-05-06.json")

                                Divider()

                                // MARK: Migration
                                Text("Migrate to:").font(.caption2).foregroundStyle(.secondary)
                                migrationRow(target: "Docker Desktop", installed: true)
                                migrationRow(target: "Podman", installed: false)
                                migrationRow(target: "Another Profile", installed: true)

                                if let target = migrationTarget, !migrationSteps.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Migrating to \(target)...").font(.caption2.weight(.medium))
                                        ForEach(0..<migrationSteps.count, id: \.self) { i in
                                            HStack(spacing: 4) {
                                                if i < migrationStepIndex {
                                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                                                } else if i == migrationStepIndex {
                                                    ProgressView().controlSize(.mini)
                                                } else {
                                                    Image(systemName: "circle").foregroundStyle(.secondary).font(.caption2)
                                                }
                                                Text(migrationSteps[i]).font(.caption2)
                                            }
                                        }
                                    }
                                    .padding(6).background(Color.secondary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            updateChecking = false
            updateResult = (current: "0.10.1", latest: "0.10.3", changelog: "Bug fixes, improved virtiofs performance")
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

    private func startPrune() {
        pruneRunning = true
        pruneItems = [
            (name: "Dangling images (3)", detail: "— freed 450 MB", status: .pending),
            (name: "Stopped containers (2)", detail: "— freed 120 MB", status: .pending),
            (name: "Unused networks (1)", detail: "— freed 0 MB", status: .pending),
            (name: "Build cache", detail: "— freed 680 MB", status: .pending),
        ]
        animatePruneItem(at: 0)
    }

    private func animatePruneItem(at index: Int) {
        guard index < pruneItems.count else {
            pruneRunning = false
            appState.pruneColima(all: false)
            return
        }
        pruneItems[index].status = .clearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            pruneItems[index].status = .done
            animatePruneItem(at: index + 1)
        }
    }

    @ViewBuilder
    private func exportRow(id: String, label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(label) {
                activeExport = id
                exportPath = path
            }.font(.caption)

            if activeExport == id, let p = exportPath {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                    Text("Saved to: \(p)").font(.caption2).foregroundStyle(.secondary)
                    Button("Show in Finder") { /* mock */ }
                        .font(.caption2).controlSize(.mini)
                }
            }
        }
    }

    @ViewBuilder
    private func migrationRow(target: String, installed: Bool) -> some View {
        HStack(spacing: 6) {
            if installed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                Text(target).font(.caption)
                Text("Installed").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Migrate") { startMigration(target: target) }.font(.caption).controlSize(.mini)
            } else {
                Image(systemName: "xmark.circle").foregroundStyle(.red).font(.caption2)
                Text(target).font(.caption)
                Text("Not installed").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Install via Homebrew") { appState.showToast("brew install \(target.lowercased())") }
                    .font(.caption).controlSize(.mini)
            }
        }
    }

    private func startMigration(target: String) {
        migrationTarget = target
        migrationSteps = [
            "Export volumes...",
            "Export container configs...",
            "Switch context...",
            "Stop Colima VM...",
            "Done! Suggest removal.",
        ]
        migrationStepIndex = 0
        animateMigrationStep()
    }

    private func animateMigrationStep() {
        guard migrationStepIndex < migrationSteps.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            migrationStepIndex += 1
            animateMigrationStep()
        }
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

import SwiftUI

struct RuntimeControlsView: View {
    @EnvironmentObject var appState: AppState
    @State private var nerdctlCmd = ""
    @State private var incusCmd = ""
    @State private var targetRuntime = "docker"
    @State private var commandInput = ""
    @State private var commandOutput = ""
    @State private var commandHistory: [String] = []
    @State private var historyExpanded = false
    @State private var historyLimit = 20

    private let dockerQuickCmds = ["ps", "images", "volume ls", "network ls", "system df", "info"]
    private let nerdctlQuickCmds = ["ps", "images", "compose ps"]
    private let incusQuickCmds = ["list", "image list", "profile list"]

    private var detectedTool: String {
        let prefix = commandInput.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        switch prefix {
        case "nerdctl": return "nerdctl"
        case "incus": return "incus"
        default: return "docker"
        }
    }

    private let runtimeComparison: [(label: String, docker: String, containerd: String, incus: String)] = [
        ("Runtime", "docker", "containerd", "incus"),
        ("Compose", "docker compose", "nerdctl compose", "—"),
        ("CLI", "docker", "nerdctl", "incus"),
    ]

    private let mockContexts = [
        (name: "colima-default", active: true),
        (name: "colima-dev", active: false),
        (name: "desktop-linux", active: false),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                runtimeStatusCard
                commandPaletteSection
                runtimeSwitchingSection
                dockerContextSection
                legacyControls
            }
            .padding()
        }
        .navigationTitle("Runtime Controls")
    }

    // MARK: - Runtime Status

    private var runtimeStatusCard: some View {
        GroupBox("Current Runtime Status") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Runtime").fontWeight(.medium)
                    Text("docker v24.0.7")
                        .accessibilityIdentifier("text_runtime_name")
                }
                GridRow {
                    Text("Version").fontWeight(.medium)
                    Text("24.0.7").accessibilityIdentifier("text_runtime_version")
                }
                GridRow {
                    Text("Socket").fontWeight(.medium)
                    HStack(spacing: 4) {
                        Text("~/.colima/default/docker.sock")
                            .font(.system(.caption, design: .monospaced))
                            .accessibilityIdentifier("text_runtime_socket")
                        Button { copyToClipboard("~/.colima/default/docker.sock") } label: {
                            Image(systemName: "doc.on.doc").font(.caption)
                        }.accessibilityIdentifier("btn_copy_socket")
                    }
                }
                GridRow {
                    Text("Profile").fontWeight(.medium)
                    Text(appState.activeProfile)
                }
                GridRow {
                    Text("Uptime").fontWeight(.medium)
                    Text("2h 15m")
                }
            }
        }
    }

    // MARK: - Command Palette

    private var commandPaletteSection: some View {
        GroupBox("Command Palette") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("docker ps, nerdctl images, incus list…", text: $commandInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("field_command_palette")
                        .onSubmit { runPaletteCommand() }
                    Button("Run") { runPaletteCommand() }
                        .accessibilityIdentifier("btn_run_command_palette")
                }

                Text("Docker").font(.caption).fontWeight(.bold)
                quickCmdRow(dockerQuickCmds, prefix: "docker")
                Text("nerdctl").font(.caption).fontWeight(.bold)
                quickCmdRow(nerdctlQuickCmds, prefix: "nerdctl")
                Text("incus").font(.caption).fontWeight(.bold)
                quickCmdRow(incusQuickCmds, prefix: "incus")

                ScrollView {
                    Text(commandOutput.isEmpty ? "Run a command to see output…" : commandOutput)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(commandOutput.isEmpty ? Color.secondary : Color.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 120)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
                .accessibilityIdentifier("text_command_output")

                if !commandHistory.isEmpty {
                    DisclosureGroup("History (\(commandHistory.suffix(historyLimit).count))", isExpanded: $historyExpanded) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(commandHistory.suffix(historyLimit).reversed().enumerated()), id: \.offset) { _, cmd in
                                Button {
                                    commandInput = cmd
                                    runPaletteCommand()
                                } label: {
                                    Text(cmd)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)

                        HStack {
                            Spacer()
                            Picker("Keep", selection: $historyLimit) {
                                Text("10").tag(10)
                                Text("20").tag(20)
                                Text("50").tag(50)
                            }
                            .frame(width: 120)
                            .font(.caption2)
                            Button("Clear") { commandHistory.removeAll() }
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func quickCmdRow(_ cmds: [String], prefix: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(cmds, id: \.self) { cmd in
                    Button(cmd) {
                        commandInput = "\(prefix) \(cmd)"
                        runPaletteCommand()
                    }
                    .font(.caption)
                    .accessibilityIdentifier("btn_quick_cmd_\(cmd.replacingOccurrences(of: " ", with: "_"))")
                }
            }
        }
    }

    private func runPaletteCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        let parts = cmd.components(separatedBy: " ")
        let tool = parts.first ?? "docker"
        let args = parts.dropFirst().joined(separator: " ")
        commandOutput = "$ \(cmd)\n\n\(MockDetailData.commandOutput(tool: tool, args: args))"
        if !commandHistory.contains(cmd) {
            commandHistory.append(cmd)
            if commandHistory.count > historyLimit {
                commandHistory.removeFirst(commandHistory.count - historyLimit)
            }
        }
        commandInput = ""
    }

    // MARK: - Runtime Switching

    private var runtimeSwitchingSection: some View {
        GroupBox("Runtime Switching") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow { Text("").frame(width: 80); Text("Current").fontWeight(.bold); Text("Target").fontWeight(.bold) }
                    ForEach(runtimeComparison, id: \.label) { row in
                        GridRow {
                            Text(row.label).fontWeight(.medium)
                            Text(targetRuntime == "docker" ? row.docker : (targetRuntime == "containerd" ? row.containerd : row.incus))
                            Text(targetRuntime == "docker" ? row.docker : (targetRuntime == "containerd" ? row.containerd : row.incus))
                        }
                    }
                }
                .font(.caption)
                .accessibilityIdentifier("table_runtime_comparison")

                HStack {
                    Picker("Target Runtime", selection: $targetRuntime) {
                        Text("docker").tag("docker"); Text("containerd").tag("containerd"); Text("incus").tag("incus")
                    }.accessibilityIdentifier("picker_target_runtime")
                    Button("Switch Runtime") {
                        appState.requestConfirmation("Switch runtime to \(targetRuntime)? This requires a VM restart.") {
                            appState.switchRuntime(to: targetRuntime)
                        }
                    }.accessibilityIdentifier("btn_switch_runtime")
                }

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Switching runtime requires VM restart. Container data will be preserved (soft delete).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Docker Context

    private var dockerContextSection: some View {
        GroupBox("Docker Contexts") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(mockContexts, id: \.name) { ctx in
                    HStack {
                        Image(systemName: ctx.active ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(ctx.active ? .green : .secondary)
                        Text(ctx.name).font(.system(.caption, design: .monospaced))
                        if ctx.active { Text("(active)").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        if !ctx.active {
                            Button("Switch") { appState.switchDockerContext(profile: ctx.name) }
                                .font(.caption)
                        }
                    }
                }
            }
            .accessibilityIdentifier("table_docker_contexts")

            // Preserved for test: shows current context
            Text("Current: colima-\(appState.activeProfile)")
                .accessibilityIdentifier("text_docker_context")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Legacy (preserved for tests)

    private var legacyControls: some View {
        GroupBox("Additional Controls") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("nerdctl command…", text: $nerdctlCmd).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_nerdctl_cmd")
                    Button("Run") { appState.nerdctlCommand(cmd: nerdctlCmd) }
                        .accessibilityIdentifier("btn_run_nerdctl")
                }
                HStack {
                    TextField("incus command…", text: $incusCmd).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_incus_cmd")
                    Button("Run") { appState.incusCommand(cmd: incusCmd) }
                        .accessibilityIdentifier("btn_run_incus")
                }
                HStack {
                    Button("Switch Context") { appState.switchDockerContext(profile: appState.activeProfile) }
                        .accessibilityIdentifier("btn_switch_dockercontext")
                    Button("Update Runtime") { appState.updateRuntime() }
                        .accessibilityIdentifier("btn_update_runtime")
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Circle().fill(.green).frame(width: 8, height: 8); Text("docker — soft delete").font(.caption) }
                    HStack { Circle().fill(.green).frame(width: 8, height: 8); Text("containerd — soft delete").font(.caption) }
                    HStack { Circle().fill(.orange).frame(width: 8, height: 8); Text("incus — hard delete only").font(.caption) }
                }.accessibilityIdentifier("text_data_persistence")
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.showToast("Copied to clipboard")
    }
}

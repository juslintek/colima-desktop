import SwiftUI

struct RuntimeControlsView: View {
    @EnvironmentObject var appState: AppState
    @State private var commandInput = ""
    @State private var commandOutput = ""
    @State private var commandHistory: [String] = []
    @State private var targetRuntime = "docker"
    @State private var nerdctlCmd = ""
    @State private var incusCmd = ""
    @State private var runtimeVersion = "Not queried"

    private var currentRuntime: String {
        if !appState.vmRuntime.isEmpty { return appState.vmRuntime }
        return appState.profiles.first(where: { $0.name == appState.activeProfile })?.runtime ?? "unavailable"
    }

    private var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colima/\(appState.activeProfile)/docker.sock").path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusSection
                commandSection
                runtimeSection
                contextSection
                additionalSection
            }
            .padding()
        }
        .navigationTitle("Runtime Controls")
        .accessibilityIdentifier("view_runtime")
        .onAppear {
            targetRuntime = currentRuntime == "unavailable" ? "docker" : currentRuntime
            queryRuntimeVersion()
        }
    }

    private var statusSection: some View {
        GroupBox("Current Runtime Status") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Runtime") {
                    Text(currentRuntime).accessibilityIdentifier("text_runtime_name")
                }
                LabeledContent("Version") {
                    Text(runtimeVersion).accessibilityIdentifier("text_runtime_version")
                }
                LabeledContent("Profile") { Text(appState.activeProfile) }
                LabeledContent("VM") { Text(appState.vmRunning ? "Running" : "Stopped") }
                LabeledContent("Socket") {
                    HStack(spacing: 5) {
                        Text("unix://\(socketPath)")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .accessibilityIdentifier("text_runtime_socket")
                        Button { copyToClipboard("unix://\(socketPath)") } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("btn_copy_socket")
                        .accessibilityLabel("Copy socket path")
                    }
                }
            }
        }
    }

    private var commandSection: some View {
        GroupBox("Profile-scoped Command Palette") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("docker ps, nerdctl images, incus list…", text: $commandInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(runCommand)
                        .accessibilityIdentifier("field_command_palette")
                    Button("Run", action: runCommand)
                        .disabled(commandInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("btn_run_command_palette")
                        .accessibilityLabel("Run command")
                }
                HStack(spacing: 6) {
                    ForEach(["docker ps", "docker images", "docker system df", "nerdctl ps", "incus list"], id: \.self) { command in
                        Button(command) {
                            commandInput = command
                            runCommand()
                        }
                        .font(.caption)
                        .accessibilityIdentifier("btn_quick_cmd_\(command.replacingOccurrences(of: " ", with: "_"))")
                    }
                }
                Text(commandOutput.isEmpty ? "Run a command to see real output from '\(appState.activeProfile)'." : commandOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(commandOutput.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityIdentifier("text_command_output")
                if !commandHistory.isEmpty {
                    Text("Recent: \(commandHistory.suffix(3).joined(separator: "  ·  "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var runtimeSection: some View {
        GroupBox("Runtime") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current: \(currentRuntime)")
                    Image(systemName: "arrow.right")
                    Picker("Target", selection: $targetRuntime) {
                        Text("docker").tag("docker")
                        Text("containerd").tag("containerd")
                        Text("incus").tag("incus")
                    }
                    .accessibilityIdentifier("picker_target_runtime")
                    Button("Switch Runtime") {
                        appState.requestConfirmation("Switch '\(appState.activeProfile)' from \(currentRuntime) to \(targetRuntime)? The VM will restart and may require recreation.") {
                            appState.switchRuntime(to: targetRuntime)
                        }
                    }
                    .disabled(targetRuntime == currentRuntime)
                    .accessibilityIdentifier("btn_switch_runtime")
                }
                Text("The saved configuration and the runtime reported by the VM are verified after restart. No migration is claimed until Colima reports the target runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_data_persistence")
                HStack {
                    Text("Runtime change: configuration + verified restart")
                    Spacer()
                    Button("Check Version", action: queryRuntimeVersion)
                        .accessibilityIdentifier("btn_check_runtime_update")
                    Button("Update Now") {
                        appState.requestConfirmation("Run Colima's update for profile '\(appState.activeProfile)'?") {
                            appState.updateRuntime()
                        }
                    }
                    .accessibilityIdentifier("btn_update_runtime")
                }
                .font(.caption)
            }
            .accessibilityIdentifier("table_runtime_comparison")
        }
    }

    private var contextSection: some View {
        GroupBox("App Profile Context") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(appState.profiles) { profile in
                    HStack {
                        Image(systemName: profile.name == appState.activeProfile ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(profile.name == appState.activeProfile ? .green : .secondary)
                        Text(profile.name).font(.system(.caption, design: .monospaced))
                        Text(profile.status).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        if profile.name != appState.activeProfile {
                            Button("Use in App") {
                                Task { await appState.switchProfile(name: profile.name) }
                            }
                            .font(.caption)
                            .accessibilityIdentifier("btn_use_profile_\(profile.name)")
                            .accessibilityLabel("Use profile \(profile.name) in app")
                        }
                    }
                }
                Text("Current: colima-\(appState.activeProfile)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_docker_context")
                Picker("Context", selection: Binding(
                    get: { appState.activeProfile },
                    set: { name in Task { await appState.switchProfile(name: name) } }
                )) {
                    ForEach(appState.profiles) { Text($0.name).tag($0.name) }
                }
                .accessibilityIdentifier("picker_docker_context")
                Button("Apply") { appState.switchDockerContext(profile: appState.activeProfile) }
                    .accessibilityIdentifier("btn_switch_dockercontext")
                Text("Changing this selection rebinds only Colima Desktop. Your shell's global Docker context is not mutated.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("table_docker_contexts")
        }
    }

    private var additionalSection: some View {
        GroupBox("Runtime-specific Commands") {
            VStack(spacing: 7) {
                HStack {
                    TextField("nerdctl command…", text: $nerdctlCmd)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_nerdctl_cmd")
                    Button("Run") {
                        commandInput = "nerdctl \(nerdctlCmd)"
                        runCommand()
                    }
                    .accessibilityIdentifier("btn_run_nerdctl")
                    .accessibilityLabel("Run nerdctl command")
                }
                HStack {
                    TextField("incus command…", text: $incusCmd)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_incus_cmd")
                    Button("Run") {
                        commandInput = "incus \(incusCmd)"
                        runCommand()
                    }
                    .accessibilityIdentifier("btn_run_incus")
                    .accessibilityLabel("Run incus command")
                }
            }
        }
    }

    private func runCommand() {
        let command = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let parts = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let tool = parts.first, ["docker", "nerdctl", "incus", "colima", "kubectl"].contains(tool) else {
            commandOutput = "Unsupported tool. Use docker, nerdctl, incus, colima, or kubectl."
            return
        }
        commandHistory.append(command)
        commandOutput = "Running against '\(appState.activeProfile)'…"
        commandInput = ""
        appState.executeCommand(tool: tool, args: Array(parts.dropFirst())) { output in
            commandOutput = output.isEmpty ? "Command completed with no output." : output
        }
    }

    private func queryRuntimeVersion() {
        guard appState.vmRunning else {
            runtimeVersion = "VM stopped"
            return
        }
        runtimeVersion = "Querying…"
        let tool = currentRuntime == "docker" ? "docker" : (currentRuntime == "containerd" ? "nerdctl" : "incus")
        let args = tool == "docker" ? ["version", "--format", "{{.Server.Version}}"] : ["version"]
        appState.executeCommand(tool: tool, args: args) { output in
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            runtimeVersion = trimmed.isEmpty ? "No version returned" : trimmed
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.showToast("Copied to clipboard")
    }
}

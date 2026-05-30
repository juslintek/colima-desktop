import SwiftUI

struct CommandRunnerView: View {
    let tool: String
    @EnvironmentObject var appState: AppState
    @State private var commandInput = ""
    @State private var output = ""
    @State private var commandHistory: [String] = []
    @Environment(\.dismiss) private var dismiss

    private var quickCommands: [String] {
        tool == "incus" ? ["list", "info", "image list", "network list"] : ["ps", "images", "info", "volume ls"]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(tool) Command Runner").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_command_runner")
            }
            .padding()

            Divider()

            HStack {
                Text("\(tool)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                TextField("command…", text: $commandInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("field_command_input")
                    .onSubmit { runCommand() }
                Button("Run") { runCommand() }
                    .accessibilityIdentifier("btn_run_command")
            }
            .padding()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickCommands, id: \.self) { cmd in
                        Button(cmd) {
                            commandInput = cmd
                            runCommand()
                        }
                        .font(.caption)
                        .accessibilityIdentifier("btn_quick_\(cmd.replacingOccurrences(of: " ", with: "_"))")
                    }
                }
                .padding(.horizontal)
            }

            Divider().padding(.top, 4)

            ScrollView {
                Text(output.isEmpty ? "Run a command to see output…" : output)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(output.isEmpty ? Color.secondary : Color.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityIdentifier("text_command_output")
            }
            .background(Color.black)

            if !commandHistory.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("History:").font(.caption).foregroundStyle(.secondary)
                        ForEach(commandHistory, id: \.self) { cmd in
                            Button(cmd) {
                                commandInput = cmd
                                runCommand()
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 350)
        .accessibilityIdentifier("sheet_command_runner")
    }

    private func runCommand() {
        let cmd = commandInput.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        let args = cmd.components(separatedBy: " ")
        output = "$ \(tool) \(cmd)\n\nRunning..."
        if !commandHistory.contains(cmd) { commandHistory.append(cmd) }
        commandInput = ""
        appState.executeCommand(tool: tool, args: args) { result in
            output = "$ \(tool) \(cmd)\n\n\(result)"
        }
    }
}

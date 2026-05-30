import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CopyFilesSheetView: View {
    let containerName: String
    let onCopy: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Direction: String, CaseIterable {
        case toContainer = "Host → Container"
        case fromContainer = "Container → Host"
    }

    @State private var direction: Direction = .toContainer
    @State private var hostPath = ""
    @State private var containerPath = ""
    @State private var error: String?

    private var command: String {
        switch direction {
        case .toContainer:
            return "docker cp \(hostPath) \(containerName):\(containerPath)"
        case .fromContainer:
            return "docker cp \(containerName):\(containerPath) \(hostPath)"
        }
    }

    private var isValid: Bool {
        !hostPath.isEmpty && !containerPath.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copy Files — \(containerName)").font(.headline)

            Picker("Direction", selection: $direction) {
                ForEach(Direction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("picker_copy_direction")

            GroupBox(direction == .toContainer ? "Source (Host)" : "Destination (Host)") {
                HStack {
                    TextField("/path/on/host", text: $hostPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_copy_host_path")
                    Button("Browse…") { browseHost() }
                        .accessibilityIdentifier("btn_copy_browse_host")
                }
            }

            GroupBox(direction == .toContainer ? "Destination (Container)" : "Source (Container)") {
                TextField("/path/in/container", text: $containerPath)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_copy_container_path")
                Text("e.g. /app/data, /etc/nginx/nginx.conf, /tmp/")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Command preview
            GroupBox("Command Preview") {
                Text(isValid ? command : "docker cp <source> <destination>")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isValid ? .primary : .secondary)
                    .accessibilityIdentifier("text_copy_command_preview")
                    .accessibilityValue(isValid ? command : "")
            }

            if let err = error {
                Text(err).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("text_copy_error")
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("btn_copy_cancel")
                Button("Copy") { executeCopy() }
                    .accessibilityIdentifier("btn_copy_execute")
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480)
        .accessibilityIdentifier("sheet_copy_files")
    }

    private func browseHost() {
        if direction == .toContainer {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK, let url = panel.url {
                hostPath = url.path
            }
        } else {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = containerPath.components(separatedBy: "/").last ?? "file"
            if panel.runModal() == .OK, let url = panel.url {
                hostPath = url.path
            }
        }
    }

    private func executeCopy() {
        onCopy(command)
        dismiss()
    }
}

import SwiftUI

struct CreateContainerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var imageName = ""
    @State private var platform = "auto"
    @State private var containerName = ""
    @State private var removeAfterStop = false
    @State private var restartPolicy = "no"
    @State private var command = ""
    @State private var entrypoint = ""
    @State private var workingDir = ""
    @State private var privileged = false
    @State private var readOnly = false
    @State private var useInit = false
    @State private var nameError: String?

    private let platforms = ["auto", "arm64", "amd64", "arm/v7", "riscv64", "ppc64le", "s390x"]
    private let restartPolicies = ["no", "always", "unless-stopped", "on-failure"]

    private var isValid: Bool {
        !imageName.isEmpty && nameError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Create Container").font(.headline).padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Image
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Image").font(.subheadline).fontWeight(.medium)
                        TextField("e.g. nginx:latest", text: $imageName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("field_create_container_image_full")
                    }

                    // Platform
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Platform").font(.subheadline).fontWeight(.medium)
                        Picker("", selection: $platform) {
                            ForEach(platforms, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("picker_create_container_platform")
                    }

                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.subheadline).fontWeight(.medium)
                        TextField("auto-generated if empty", text: $containerName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("field_create_container_name_full")
                            .onChange(of: containerName) {
                                nameError = containerName.isEmpty ? nil : appState.validateContainerName(containerName)
                            }
                        if let err = nameError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }

                    // Toggles
                    Toggle("Remove after stop (--rm)", isOn: $removeAfterStop)
                        .accessibilityIdentifier("toggle_create_container_rm")

                    // Restart policy
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Restart Policy").font(.subheadline).fontWeight(.medium)
                        Picker("", selection: $restartPolicy) {
                            ForEach(restartPolicies, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("picker_create_container_restart")
                    }

                    // Payload
                    DisclosureGroup("Payload") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Command", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("field_create_container_command")
                            TextField("Entrypoint", text: $entrypoint)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("field_create_container_entrypoint")
                            TextField("Working directory", text: $workingDir)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("field_create_container_workdir")
                        }
                    }

                    // Advanced
                    DisclosureGroup("Advanced") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Privileged", isOn: $privileged)
                                .accessibilityIdentifier("toggle_create_container_privileged")
                            Toggle("Read-only filesystem", isOn: $readOnly)
                                .accessibilityIdentifier("toggle_create_container_readonly")
                            Toggle("Use docker-init", isOn: $useInit)
                                .accessibilityIdentifier("toggle_create_container_init")
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("btn_create_container_cancel")
                Spacer()
                Button("Create") {
                    createContainer(start: false)
                }
                .accessibilityIdentifier("btn_create_container_confirm")
                .disabled(!isValid)
                Button("Create & Start") {
                    createContainer(start: true)
                }
                .accessibilityIdentifier("btn_create_container_start")
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 550)
    }

    private func createContainer(start: Bool) {
        let name = containerName.isEmpty ? imageName.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-") : containerName
        appState.createContainer(name: name, image: imageName)
        if start {
            appState.startContainer(name: name)
        }
        dismiss()
    }
}

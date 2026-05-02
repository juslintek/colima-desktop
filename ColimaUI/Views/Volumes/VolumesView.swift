import SwiftUI

struct VolumesView: View {
    @EnvironmentObject var appState: AppState
    @State private var newVolumeName = ""
    @State private var showCreate = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showCreate {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Volume name", text: $newVolumeName)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                            .accessibilityIdentifier("field_volume_name")
                            .onChange(of: newVolumeName) { _ in validationError = appState.validateVolumeName(newVolumeName) }
                        if let err = validationError {
                            Text(err).font(.caption).foregroundStyle(.red)
                                .accessibilityIdentifier("text_volume_validation_error")
                        }
                    }
                    Button("Confirm") {
                        guard appState.validateVolumeName(newVolumeName) == nil else { return }
                        appState.createVolume(name: newVolumeName)
                        newVolumeName = ""; showCreate = false; validationError = nil
                    }
                    .accessibilityIdentifier("btn_confirm_volume_create")
                    .disabled(newVolumeName.isEmpty || validationError != nil)
                }
                Spacer()
                Button("Create") { showCreate.toggle() }.accessibilityIdentifier("btn_create_volume_new")
                Button("Prune") { appState.pruneVolumes() }.accessibilityIdentifier("btn_prune_volume_all")
            }.padding()

            List(appState.volumes) { vol in
                HStack {
                    Text(vol.name).frame(minWidth: 120, alignment: .leading)
                        .accessibilityIdentifier("row_volume_\(vol.name)")
                    Text(vol.driver).foregroundStyle(.secondary).frame(minWidth: 60, alignment: .leading)
                    Text(vol.size).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { appState.removeVolume(name: vol.name) }
                        .accessibilityIdentifier("btn_remove_volume_\(vol.name)")
                    Button("Inspect") { appState.inspectVolume(name: vol.name) }
                        .accessibilityIdentifier("btn_inspect_volume_\(vol.name)")
                }
            }
            .accessibilityIdentifier("table_volumes")
        }
        .navigationTitle("Volumes")
    }
}

import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showCreateSheet = false
    @State private var showCloneSheet = false
    @State private var newName = ""
    @State private var newCpus = 4
    @State private var newMemory = "8GiB"
    @State private var newRuntime = "docker"
    @State private var cloneSource = "default"
    @State private var cloneDest = ""
    @State private var nameError: String?
    @State private var cloneError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("COLIMA_HOME: ~/.colima").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_colima_home")
                Spacer()
                Text("COLIMA_PROFILE: \(appState.activeProfile)").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("text_colima_profile")
            }.padding(.horizontal).padding(.top, 8)

            HStack {
                Spacer()
                Button("Create Profile") { showCreateSheet = true }
                    .accessibilityIdentifier("btn_create_profile_new")
                Button("Clone") { showCloneSheet = true }
                    .accessibilityIdentifier("btn_clone_profile_selected")
            }.padding()

            List(appState.profiles) { p in
                ProfileRowView(profile: p, appState: appState)
            }
            .accessibilityIdentifier("table_profiles")
        }
        .navigationTitle("Profiles")
        .sheet(isPresented: $showCreateSheet) {
            VStack(spacing: 12) {
                Text("Create Profile").font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Profile Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_create_profile_name")
                        .onChange(of: newName) { _ in nameError = appState.validateProfileName(newName) }
                    if let err = nameError {
                        Text(err).font(.caption).foregroundStyle(.red)
                            .accessibilityIdentifier("text_profile_name_error")
                    }
                }
                Stepper("CPUs: \(newCpus)", value: $newCpus, in: 1...16)
                    .accessibilityIdentifier("field_create_profile_cpus")
                TextField("Memory", text: $newMemory)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_create_profile_memory")
                Picker("Runtime", selection: $newRuntime) {
                    Text("docker").tag("docker")
                    Text("containerd").tag("containerd")
                    Text("incus").tag("incus")
                }.accessibilityIdentifier("field_create_profile_runtime")
                HStack {
                    Button("Cancel") { showCreateSheet = false }
                    Button("Create") {
                        appState.createProfile(name: newName, cpus: newCpus, memory: newMemory, runtime: newRuntime)
                        newName = ""; nameError = nil; showCreateSheet = false
                    }
                    .accessibilityIdentifier("btn_confirm_profile_create")
                    .disabled(newName.isEmpty || nameError != nil)
                }
            }
            .padding().frame(width: 350)
        }
        .sheet(isPresented: $showCloneSheet) {
            VStack(spacing: 12) {
                Text("Clone Profile").font(.headline)
                Picker("Source", selection: $cloneSource) {
                    ForEach(appState.profiles) { p in Text(p.name).tag(p.name) }
                }.accessibilityIdentifier("field_clone_profile_source")
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Destination Name", text: $cloneDest)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_clone_profile_dest")
                        .onChange(of: cloneDest) { _ in cloneError = appState.validateProfileName(cloneDest) }
                    if let err = cloneError {
                        Text(err).font(.caption).foregroundStyle(.red)
                            .accessibilityIdentifier("text_clone_name_error")
                    }
                }
                HStack {
                    Button("Cancel") { showCloneSheet = false }
                    Button("Clone") {
                        appState.cloneProfile(source: cloneSource, dest: cloneDest)
                        cloneDest = ""; cloneError = nil; showCloneSheet = false
                    }
                    .accessibilityIdentifier("btn_confirm_profile_clone")
                    .disabled(cloneDest.isEmpty || cloneError != nil)
                }
            }
            .padding().frame(width: 350)
        }
    }
}

struct ProfileRowView: View {
    let profile: MockProfile
    let appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(profile.status == "Running" ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityIdentifier("status_indicator_profile_\(profile.name)")
                .accessibilityValue(profile.status)
            Text(profile.name).frame(minWidth: 70, alignment: .leading)
                .accessibilityIdentifier("row_profile_\(profile.name)")
            Text(profile.runtime).foregroundStyle(.secondary)
            Spacer()
            Button("Start") { appState.startProfile(name: profile.name) }
                .accessibilityIdentifier("btn_start_profile_\(profile.name)")
                .disabled(profile.status == "Running")
            Button("Stop") { appState.stopProfile(name: profile.name) }
                .accessibilityIdentifier("btn_stop_profile_\(profile.name)")
                .disabled(profile.status == "Stopped")
            Button("Restart") { appState.restartProfile(name: profile.name) }
                .accessibilityIdentifier("btn_restart_profile_\(profile.name)")
            Button("Delete") {
                appState.requestConfirmation("Delete profile '\(profile.name)'?") {
                    appState.deleteProfile(name: profile.name)
                }
            }.accessibilityIdentifier("btn_delete_profile_\(profile.name)")
        }
    }
}

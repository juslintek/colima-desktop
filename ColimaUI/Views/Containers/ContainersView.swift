import SwiftUI

struct ContainersView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var newContainerName = ""
    @State private var newContainerImage = ""
    @State private var nameError: String?
    @State private var imageError: String?
    @State private var showImageBrowser = false

    private var runningContainers: [MockContainer] {
        filtered.filter { $0.state == "running" || $0.state == "paused" }
    }

    private var stoppedContainers: [MockContainer] {
        filtered.filter { $0.state != "running" && $0.state != "paused" }
    }

    var filtered: [MockContainer] {
        searchText.isEmpty ? appState.containers : appState.containers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var imageSuggestions: [MockImage] {
        guard !newContainerImage.isEmpty else { return appState.images }
        return appState.images.filter {
            "\($0.repository):\($0.tag)".localizedCaseInsensitiveContains(newContainerImage)
            || $0.repository.localizedCaseInsensitiveContains(newContainerImage)
        }
    }

    private var imageExistsLocally: Bool {
        let input = newContainerImage.lowercased()
        return appState.images.contains {
            "\($0.repository):\($0.tag)".lowercased() == input
            || ($0.tag == "latest" && $0.repository.lowercased() == input)
        }
    }

    private var createValid: Bool {
        !newContainerName.isEmpty && !newContainerImage.isEmpty && nameError == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            containerList
        }
        .navigationTitle("Containers")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Text("\(runningContainers.count) running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .accessibilityIdentifier("field_containers_search")
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("btn_create_container_new")
                    Button { appState.pruneContainers() } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityIdentifier("btn_prune_container_all")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) { createSheet }
    }

    // MARK: - Container List

    private var containerList: some View {
        List(selection: $appState.selectedContainerName) {
            if !runningContainers.isEmpty {
                Section("Running") {
                    ForEach(runningContainers) { c in
                        ContainerRowView(container: c, appState: appState)
                            .tag(c.name)
                    }
                }
            }
            if !stoppedContainers.isEmpty {
                Section("Stopped") {
                    ForEach(stoppedContainers) { c in
                        ContainerRowView(container: c, appState: appState)
                            .tag(c.name)
                    }
                }
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier("table_containers")
    }

    // MARK: - Create Sheet

    private var createSheet: some View {
        VStack(spacing: 12) {
            Text("Create Container").font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Container Name", text: $newContainerName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_create_container_name")
                    .onChange(of: newContainerName) { _ in
                        nameError = appState.validateContainerName(newContainerName)
                    }
                if let err = nameError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("text_container_name_error")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Image (e.g. nginx:latest)", text: $newContainerImage)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("field_create_container_image")
                    Button("Browse…") { showImageBrowser = true }
                        .accessibilityIdentifier("btn_browse_images")
                }

                if !newContainerImage.isEmpty {
                    if imageExistsLocally {
                        Label("Image available locally", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                            .accessibilityIdentifier("text_image_exists_local")
                    } else {
                        Label("Image not found locally — will pull on start", systemImage: "arrow.down.circle")
                            .font(.caption).foregroundStyle(.orange)
                            .accessibilityIdentifier("text_image_not_local")
                    }
                }

                if !newContainerImage.isEmpty && !imageSuggestions.isEmpty && !imageExistsLocally {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggestions:").font(.caption2).foregroundStyle(.secondary)
                        ForEach(imageSuggestions.prefix(5)) { img in
                            Button {
                                newContainerImage = "\(img.repository):\(img.tag)"
                            } label: {
                                Text("\(img.repository):\(img.tag)")
                                    .font(.caption).foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("btn_suggest_image_\(img.repository)")
                        }
                    }
                    .padding(.leading, 4)
                }
            }

            HStack {
                Button("Cancel") { resetAndClose() }
                    .accessibilityIdentifier("btn_cancel_container_create")
                Spacer()
                Button("Create") {
                    appState.createContainer(name: newContainerName, image: newContainerImage)
                    resetAndClose()
                }
                .accessibilityIdentifier("btn_confirm_container_create")
                .disabled(!createValid)
            }
        }
        .padding()
        .frame(width: 400)
        .sheet(isPresented: $showImageBrowser) { imageBrowserSheet }
    }

    // MARK: - Image Browser Sheet

    private var imageBrowserSheet: some View {
        ImageBrowserSheet(
            appState: appState,
            onSelect: { imageName in
                newContainerImage = imageName
                showImageBrowser = false
            },
            onCancel: { showImageBrowser = false }
        )
    }

    private func resetAndClose() {
        newContainerName = ""
        newContainerImage = ""
        nameError = nil
        imageError = nil
        showCreateSheet = false
    }
}

// MARK: - Image Browser

struct ImageBrowserSheet: View {
    let appState: AppState
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""
    @State private var isPulling = false

    private var filteredLocal: [MockImage] {
        guard !searchText.isEmpty else { return appState.images }
        return appState.images.filter {
            $0.repository.localizedCaseInsensitiveContains(searchText)
            || $0.tag.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredHub: [(name: String, description: String, stars: Int, official: Bool)] {
        let all = MockDetailData.searchResults(term: searchText.isEmpty ? "popular" : searchText)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search local images and Docker Hub…", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("field_image_browser_search")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.bar)

            Divider()

            List {
                if !filteredLocal.isEmpty {
                    Section("Local Images (\(filteredLocal.count))") {
                        ForEach(filteredLocal) { img in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(img.repository):\(img.tag)").fontWeight(.medium)
                                    Text("\(img.size) · \(img.created)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use") { onSelect("\(img.repository):\(img.tag)") }
                                    .accessibilityIdentifier("btn_select_image_\(img.repository)")
                            }
                        }
                    }
                    .accessibilityIdentifier("section_image_browser_local")
                }

                Section("Docker Hub\(searchText.isEmpty ? " — Popular" : " — \"\(searchText)\"")") {
                    ForEach(filteredHub, id: \.name) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(r.name).fontWeight(.medium)
                                    if r.official {
                                        Text("OFFICIAL").font(.caption2).padding(.horizontal, 4)
                                            .background(.blue.opacity(0.15)).cornerRadius(3)
                                    }
                                }
                                Text(r.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text("★ \(r.stars)").font(.caption).foregroundStyle(.secondary)
                            Button("Pull & Use") { pullAndSelect(r.name) }
                                .accessibilityIdentifier("btn_pull_select_hub_\(r.name)")
                        }
                    }
                }
                .accessibilityIdentifier("section_image_browser_hub")
            }
            .accessibilityIdentifier("table_image_browser")

            Divider()

            HStack {
                if isPulling {
                    ProgressView().controlSize(.small)
                    Text("Pulling image…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .accessibilityIdentifier("btn_image_browser_cancel")
            }
            .padding(10)
        }
        .frame(width: 550, height: 450)
        .accessibilityIdentifier("sheet_image_browser")
    }

    private func pullAndSelect(_ name: String) {
        isPulling = true
        appState.pullImage(name: name)
        isPulling = false
        onSelect("\(name):latest")
    }
}

// MARK: - Container Row

struct ContainerRowView: View {
    let container: MockContainer
    let appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(container.state == "running" ? Color.green : container.state == "paused" ? Color.yellow : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityIdentifier("status_indicator_\(container.name)")
                .accessibilityValue(container.state)

            VStack(alignment: .leading, spacing: 1) {
                Text(container.name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("row_container_\(container.name)")
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Inline icon-only actions
            if container.state == "running" {
                Button { appState.stopContainer(name: container.name) } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn_stop_container_\(container.name)")
            } else {
                Button { appState.startContainer(name: container.name) } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("btn_start_container_\(container.name)")
            }

            Button {
                appState.requestConfirmation("Remove container '\(container.name)'?") {
                    appState.removeContainer(name: container.name)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn_remove_container_\(container.name)")
        }
        .padding(.vertical, 2)
        .contextMenu { containerContextMenu }
    }

    @ViewBuilder
    private var containerContextMenu: some View {
        let c = container
        Button("Start") { appState.startContainer(name: c.name) }
            .accessibilityIdentifier("btn_start_container_\(c.name)")
            .disabled(c.state == "running")
        Button("Stop") { appState.stopContainer(name: c.name) }
            .disabled(c.state == "exited")
        Button("Kill") { appState.killContainer(name: c.name) }
            .accessibilityIdentifier("btn_kill_container_\(c.name)")
        Button("Pause") { appState.pauseContainer(name: c.name) }
            .accessibilityIdentifier("btn_pause_container_\(c.name)")
            .disabled(c.state != "running")
        Button("Unpause") { appState.unpauseContainer(name: c.name) }
            .accessibilityIdentifier("btn_unpause_container_\(c.name)")
            .disabled(c.state != "paused")
        Divider()
        Button("Restart") { appState.restartContainer(name: c.name) }
            .accessibilityIdentifier("btn_restart_container_\(c.name)")
        Button("Logs") { appState.logsContainer(name: c.name) }
            .accessibilityIdentifier("btn_logs_container_\(c.name)")
        Button("Inspect") { appState.inspectContainer(name: c.name) }
            .accessibilityIdentifier("btn_inspect_container_\(c.name)")
        Button("Exec") { appState.execContainer(name: c.name) }
            .accessibilityIdentifier("btn_exec_container_\(c.name)")
        Button("Top") { appState.topContainer(name: c.name) }
            .accessibilityIdentifier("btn_top_container_\(c.name)")
        Button("Stats") { appState.statsContainer(name: c.name) }
            .accessibilityIdentifier("btn_stats_container_\(c.name)")
        Button("Export") { appState.exportContainer(name: c.name) }
            .accessibilityIdentifier("btn_export_container_\(c.name)")
        Button("Changes") { appState.changesContainer(name: c.name) }
            .accessibilityIdentifier("btn_changes_container_\(c.name)")
        Button("Wait") { appState.waitContainer(name: c.name) }
            .accessibilityIdentifier("btn_wait_container_\(c.name)")
        Button("Attach") { appState.attachContainer(name: c.name) }
            .accessibilityIdentifier("btn_attach_container_\(c.name)")
        Button("Update") { appState.updateContainerResources(name: c.name) }
            .accessibilityIdentifier("btn_update_container_\(c.name)")
        Button("Copy") { appState.copyContainer(name: c.name) }
            .accessibilityIdentifier("btn_copy_container_\(c.name)")
        Divider()
        Button("Remove", role: .destructive) {
            appState.requestConfirmation("Remove container '\(c.name)'?") {
                appState.removeContainer(name: c.name)
            }
        }
    }
}

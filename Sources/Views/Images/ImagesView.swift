import SwiftUI

enum ImageSortOrder: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case created = "Created"
}

struct ImagesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var pullImageName = ""
    @State private var hubSearchTerm = ""
    @State private var importPath = ""
    @State private var showPullSheet = false
    @State private var activePull: String?
    @State private var sortOrder: ImageSortOrder = .name
    @State private var sortAscending = true

    private func sortedList(_ list: [MockImage]) -> [MockImage] {
        list.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .name: result = a.repository.localizedCaseInsensitiveCompare(b.repository) == .orderedAscending
            case .size: result = a.size < b.size
            case .created: result = a.created < b.created
            }
            return sortAscending ? result : !result
        }
    }

    var filtered: [MockImage] {
        let base = searchText.isEmpty ? appState.images : appState.images.filter { $0.repository.localizedCaseInsensitiveContains(searchText) }
        return sortedList(base)
    }

    private var inUseImages: [MockImage] {
        let usedRepos = Set(appState.containers.filter { $0.state == "running" }.map { $0.image })
        return filtered.filter { img in
            usedRepos.contains("\(img.repository):\(img.tag)") || usedRepos.contains(img.repository)
        }
    }

    private var unusedImages: [MockImage] {
        let inUseIds = Set(inUseImages.map(\.id))
        return filtered.filter { !inUseIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                emptyState
            } else {
                List(selection: $appState.selectedImageId) {
                    if !inUseImages.isEmpty {
                        Section("In Use") {
                            ForEach(inUseImages) { img in
                                imageRow(img).tag(img.id).hoverHighlight()
                            }
                        }
                    }
                    Section(unusedImages.isEmpty ? "All Images" : "Unused") {
                        ForEach(unusedImages) { img in
                            imageRow(img).tag(img.id).hoverHighlight()
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("table_images")
            }
        }
        .navigationTitle("Images")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(ImageSortOrder.allCases, id: \.self) { order in
                            Button {
                                if sortOrder == order { sortAscending.toggle() } else { sortOrder = order; sortAscending = true }
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if sortOrder == order {
                                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("btn_sort_images")
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .accessibilityIdentifier("field_images_search")
                    Button { showPullSheet = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("btn_pull_image_new_sheet")
                    Button { appState.pruneImages() } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityIdentifier("btn_prune_image_all")
                }
            }
        }
        .sheet(isPresented: $showPullSheet) { pullSheet }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No images")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Pull Image") { showPullSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imageRow(_ img: MockImage) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(inUseImages.contains(where: { $0.id == img.id }) ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(img.repository):\(img.tag)")
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("row_image_\(img.repository)")
                Text("\(img.size) · \(img.created)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { appState.removeImage(id: img.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn_remove_image_\(img.repository)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Inspect") { appState.inspectImage(repo: img.repository) }
                .accessibilityIdentifier("btn_inspect_image_\(img.repository)")
            Button("History") { appState.historyImage(repo: img.repository) }
                .accessibilityIdentifier("btn_history_image_\(img.repository)")
            Button("Tag") { appState.tagImage(repo: img.repository, newTag: "new-tag") }
                .accessibilityIdentifier("btn_tag_image_\(img.repository)")
            Button("Push") { appState.pushImage(repo: img.repository) }
                .accessibilityIdentifier("btn_push_image_\(img.repository)")
            Button("Export") { appState.exportImage(repo: img.repository) }
                .accessibilityIdentifier("btn_export_image_\(img.repository)")
            Divider()
            Button("Remove", role: .destructive) { appState.removeImage(id: img.id) }
        }
    }

    // MARK: - Pull Sheet

    private var pullSheet: some View {
        VStack(spacing: 12) {
            Text("Pull Image").font(.headline)

            TextField("Image name (e.g. nginx:latest)", text: $pullImageName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("field_images_pull_name")

            TextField("Search Docker Hub…", text: $hubSearchTerm)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("field_images_hub_search")

            HStack {
                Button("Search Hub") {
                    guard !hubSearchTerm.isEmpty else { return }
                    appState.searchImages(term: hubSearchTerm)
                }
                .accessibilityIdentifier("btn_search_image_hub")
                Spacer()
            }

            Divider()

            TextField("Import from file…", text: $importPath)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("field_images_import_path")

            HStack {
                Button("Import") {
                    guard !importPath.isEmpty else { return }
                    appState.importImage(path: importPath)
                    importPath = ""
                }
                .accessibilityIdentifier("btn_import_image_new")
                .disabled(importPath.isEmpty)
                Spacer()
            }

            Divider()

            HStack {
                Button("Cancel") { showPullSheet = false; activePull = nil }
                Spacer()
                Button("Pull") {
                    guard !pullImageName.isEmpty else { return }
                    activePull = pullImageName
                    appState.pullImage(name: pullImageName)
                }
                .accessibilityIdentifier("btn_pull_image_new")
                .disabled(pullImageName.isEmpty || activePull != nil)
            }

            if let pulling = activePull {
                PullProgressView(name: pulling) {
                    activePull = nil
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Image Detail View

struct ImageDetailView: View {
    let image: MockImage
    @State private var selectedTab: Tab = .info

    enum Tab: String, CaseIterable {
        case info = "Info"
        case terminal = "Terminal"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(image.repository):\(image.tag)").font(.title3).fontWeight(.semibold)
                Spacer()
                Text(image.size).font(.caption).foregroundStyle(.secondary)
            }
            .padding()

            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider().padding(.top, 8)

            switch selectedTab {
            case .info: infoTab
            case .terminal: MockTerminalView(name: image.repository)
            case .files: MockFileTree()
            }
        }
    }

    private var infoTab: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow { Text("Repository").foregroundStyle(.secondary); Text(image.repository) }
                GridRow { Text("Tag").foregroundStyle(.secondary); Text(image.tag) }
                GridRow { Text("ID").foregroundStyle(.secondary); Text(image.id).font(.system(.body, design: .monospaced)) }
                GridRow { Text("Size").foregroundStyle(.secondary); Text(image.size) }
                GridRow { Text("Created").foregroundStyle(.secondary); Text(image.created) }
                GridRow { Text("Layers").foregroundStyle(.secondary); Text("3 layers") }
            }
            .padding()
        }
    }
}

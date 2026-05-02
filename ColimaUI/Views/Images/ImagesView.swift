import SwiftUI

struct ImagesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var pullImageName = ""
    @State private var hubSearchTerm = ""
    @State private var importPath = ""
    @State private var showPullSheet = false

    var filtered: [MockImage] {
        searchText.isEmpty ? appState.images : appState.images.filter { $0.repository.localizedCaseInsensitiveContains(searchText) }
    }

    // Images used by running containers
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
            List {
                if !inUseImages.isEmpty {
                    Section("In Use") {
                        ForEach(inUseImages) { img in
                            imageRow(img)
                        }
                    }
                }
                Section(unusedImages.isEmpty ? "All Images" : "Unused") {
                    ForEach(unusedImages) { img in
                        imageRow(img)
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("table_images")
        }
        .navigationTitle("Images")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
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
                Button("Cancel") { showPullSheet = false }
                Spacer()
                Button("Pull") {
                    guard !pullImageName.isEmpty else { return }
                    appState.pullImage(name: pullImageName)
                    pullImageName = ""
                    showPullSheet = false
                }
                .accessibilityIdentifier("btn_pull_image_new")
                .disabled(pullImageName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

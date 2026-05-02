import SwiftUI

struct ImagesView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var pullImageName = ""
    @State private var hubSearchTerm = ""
    @State private var importPath = ""

    var filtered: [MockImage] {
        searchText.isEmpty ? appState.images : appState.images.filter { $0.repository.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search images…", text: $searchText)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .accessibilityIdentifier("field_images_search")
                Spacer()
                TextField("Image name to pull…", text: $pullImageName)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .accessibilityIdentifier("field_images_pull_name")
                Button("Pull") {
                    guard !pullImageName.isEmpty else { return }
                    appState.pullImage(name: pullImageName)
                    pullImageName = ""
                }.accessibilityIdentifier("btn_pull_image_new")
                Button("Prune") { appState.pruneImages() }.accessibilityIdentifier("btn_prune_image_all")
            }
            .padding()

            HStack {
                TextField("Search Docker Hub…", text: $hubSearchTerm)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .accessibilityIdentifier("field_images_hub_search")
                Button("Search Hub") {
                    guard !hubSearchTerm.isEmpty else { return }
                    appState.searchImages(term: hubSearchTerm)
                }.accessibilityIdentifier("btn_search_image_hub")
                Spacer()
                TextField("Import path…", text: $importPath)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    .accessibilityIdentifier("field_images_import_path")
                Button("Import") {
                    guard !importPath.isEmpty else { return }
                    appState.importImage(path: importPath)
                    importPath = ""
                }.accessibilityIdentifier("btn_import_image_new")
            }
            .padding(.horizontal)

            List(filtered) { img in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(img.repository).frame(minWidth: 100, alignment: .leading)
                            .accessibilityIdentifier("row_image_\(img.repository)")
                        Text(img.tag).foregroundStyle(.secondary).frame(minWidth: 60, alignment: .leading)
                        Text(img.size).foregroundStyle(.secondary).frame(minWidth: 60, alignment: .leading)
                        Text(img.created).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { appState.removeImage(id: img.id) }
                            .accessibilityIdentifier("btn_remove_image_\(img.repository)")
                        Button("Inspect") { appState.inspectImage(repo: img.repository) }
                            .accessibilityIdentifier("btn_inspect_image_\(img.repository)")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Button("History") { appState.historyImage(repo: img.repository) }
                                .accessibilityIdentifier("btn_history_image_\(img.repository)")
                            Button("Tag") { appState.tagImage(repo: img.repository, newTag: "new-tag") }
                                .accessibilityIdentifier("btn_tag_image_\(img.repository)")
                            Button("Push") { appState.pushImage(repo: img.repository) }
                                .accessibilityIdentifier("btn_push_image_\(img.repository)")
                            Button("Export") { appState.exportImage(repo: img.repository) }
                                .accessibilityIdentifier("btn_export_image_\(img.repository)")
                        }
                        .font(.caption)
                    }
                }
            }
            .accessibilityIdentifier("table_images")
        }
        .navigationTitle("Images")
    }
}

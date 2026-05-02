import SwiftUI

struct SearchSheetView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchTerm = ""
    @State private var results: [SearchRow] = []
    @Environment(\.dismiss) private var dismiss

    struct SearchRow: Identifiable {
        let id = UUID()
        let name: String, description: String, stars: Int, official: Bool
    }

    init(initialTerm: String = "") {
        _searchTerm = State(initialValue: initialTerm)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Search Docker Hub").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("btn_close_search")
            }
            .padding()

            HStack {
                TextField("Search images…", text: $searchTerm)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_search_hub")
                    .onSubmit { doSearch() }
                Button("Search") { doSearch() }
                    .accessibilityIdentifier("btn_search_hub_go")
            }
            .padding(.horizontal)

            Divider().padding(.top, 8)

            Table(results) {
                TableColumn("Name") { r in
                    HStack(spacing: 4) {
                        Text(r.name)
                        if r.official {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption)
                        }
                    }
                }
                .width(min: 120, ideal: 160)
                TableColumn("Description") { r in Text(r.description).lineLimit(1) }
                TableColumn("Stars") { r in Text("⭐ \(r.stars)") }
                    .width(min: 60, ideal: 80)
                TableColumn("") { r in
                    Button("Pull") {
                        appState.pullImage(name: r.name)
                        dismiss()
                    }
                    .accessibilityIdentifier("btn_pull_search_\(r.name)")
                }
                .width(50)
            }
            .accessibilityIdentifier("table_search_results")
        }
        .frame(minWidth: 650, minHeight: 350)
        .accessibilityIdentifier("sheet_search")
        .onAppear { if !searchTerm.isEmpty { doSearch() } }
    }

    private func doSearch() {
        guard !searchTerm.isEmpty else { return }
        results = MockDetailData.searchResults(term: searchTerm).map {
            SearchRow(name: $0.name, description: $0.description, stars: $0.stars, official: $0.official)
        }
    }
}

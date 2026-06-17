import SwiftUI

enum VolumeSortOrder: String, CaseIterable {
    case name = "Name"
    case driver = "Driver"
    case size = "Size"
}

struct VolumesView: View {
    @EnvironmentObject var appState: AppState
    @State private var newVolumeName = ""
    @State private var showCreate = false
    @State private var validationError: String?
    @State private var sortOrder: VolumeSortOrder = .name
    @State private var sortAscending = true

    private var sorted: [MockVolume] {
        appState.volumes.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .name: result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .driver: result = a.driver < b.driver
            case .size: result = a.size < b.size
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if sorted.isEmpty {
                emptyState
            } else {
                List(selection: $appState.selectedVolumeName) {
                    ForEach(sorted) { vol in
                        volumeRow(vol).tag(vol.name).hoverHighlight()
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("table_volumes")
            }
        }
        .navigationTitle("Volumes")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(VolumeSortOrder.allCases, id: \.self) { order in
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
                    .accessibilityIdentifier("btn_sort_volumes")
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("btn_create_volume_new")
                    Button { appState.pruneVolumes() } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityIdentifier("btn_prune_volume_all")
                }
            }
        }
        .sheet(isPresented: $showCreate) { createSheet }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No volumes")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Create Volume") { showCreate = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func volumeRow(_ vol: MockVolume) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(vol.name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("row_volume_\(vol.name)")
                Text("\(vol.driver) · \(vol.size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { appState.removeVolume(name: vol.name) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn_remove_volume_\(vol.name)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Inspect") { appState.inspectVolume(name: vol.name) }
                .accessibilityIdentifier("btn_inspect_volume_\(vol.name)")
            Divider()
            Button("Remove", role: .destructive) { appState.removeVolume(name: vol.name) }
        }
    }

    // MARK: - Create Sheet

    private var createSheet: some View {
        VStack(spacing: 12) {
            Text("Create Volume").font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Volume name", text: $newVolumeName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_volume_name")
                    .onChange(of: newVolumeName) { validationError = appState.validateVolumeName(newVolumeName) }
                if let err = validationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("text_volume_validation_error")
                }
            }

            HStack {
                Button("Cancel") {
                    newVolumeName = ""
                    validationError = nil
                    showCreate = false
                }
                Spacer()
                Button("Create") {
                    guard appState.validateVolumeName(newVolumeName) == nil else { return }
                    appState.createVolume(name: newVolumeName)
                    newVolumeName = ""
                    validationError = nil
                    showCreate = false
                }
                .accessibilityIdentifier("btn_confirm_volume_create")
                .disabled(newVolumeName.isEmpty || validationError != nil)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Volume Detail View

struct VolumeDetailView: View {
    let volume: MockVolume
    @State private var selectedTab: Tab = .info

    enum Tab: String, CaseIterable {
        case info = "Info"
        case files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(volume.name).font(.title3).fontWeight(.semibold)
                Spacer()
                Text(volume.size).font(.caption).foregroundStyle(.secondary)
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
            case .files: MockFileTree()
            }
        }
    }

    private var infoTab: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow { Text("Name").foregroundStyle(.secondary); Text(volume.name) }
                GridRow { Text("Driver").foregroundStyle(.secondary); Text(volume.driver) }
                GridRow { Text("Mountpoint").foregroundStyle(.secondary); Text(volume.mountpoint).font(.system(.body, design: .monospaced)) }
                GridRow { Text("Size").foregroundStyle(.secondary); Text(volume.size) }
                GridRow { Text("Created").foregroundStyle(.secondary); Text("2026-04-20 14:30:00") }
            }
            .padding()
        }
    }
}

import SwiftUI

enum NetworkSortOrder: String, CaseIterable {
    case name = "Name"
    case driver = "Driver"
    case scope = "Scope"
}

struct NetworksView: View {
    @EnvironmentObject var appState: AppState
    @State private var newNetworkName = ""
    @State private var showCreate = false
    @State private var validationError: String?
    @State private var sortOrder: NetworkSortOrder = .name
    @State private var sortAscending = true

    private var sorted: [MockNetwork] {
        appState.networks.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .name: result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .driver: result = a.driver < b.driver
            case .scope: result = a.scope < b.scope
            }
            return sortAscending ? result : !result
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if sorted.isEmpty {
                emptyState
            } else {
                List(selection: $appState.selectedNetworkName) {
                    ForEach(sorted) { net in
                        networkRow(net).tag(net.name).hoverHighlight()
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("table_networks")
            }
        }
        .navigationTitle("Networks")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(NetworkSortOrder.allCases, id: \.self) { order in
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
                    .accessibilityIdentifier("btn_sort_networks")
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("btn_create_network_new")
                    Button { appState.pruneNetworks() } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityIdentifier("btn_prune_network_all")
                }
            }
        }
        .sheet(isPresented: $showCreate) { createSheet }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No networks")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Create Network") { showCreate = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func networkRow(_ net: MockNetwork) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(net.name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("row_network_\(net.name)")
                Text("\(net.driver) · \(net.scope)\(net.subnet.isEmpty ? "" : " · \(net.subnet)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button { appState.removeNetwork(name: net.name) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("btn_remove_network_\(net.name)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Inspect") { appState.inspectNetwork(name: net.name) }
                .accessibilityIdentifier("btn_inspect_network_\(net.name)")
            Button("Connect") { appState.connectNetwork(network: net.name, container: "web-server") }
                .accessibilityIdentifier("btn_connect_network_\(net.name)")
            Button("Disconnect") { appState.disconnectNetwork(network: net.name, container: "web-server") }
                .accessibilityIdentifier("btn_disconnect_network_\(net.name)")
            Divider()
            Button("Remove", role: .destructive) { appState.removeNetwork(name: net.name) }
        }
    }

    // MARK: - Create Sheet

    private var createSheet: some View {
        VStack(spacing: 12) {
            Text("Create Network").font(.headline)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Network name", text: $newNetworkName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("field_network_name")
                    .onChange(of: newNetworkName) { _ in validationError = appState.validateNetworkName(newNetworkName) }
                if let err = validationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("text_network_validation_error")
                }
            }

            HStack {
                Button("Cancel") {
                    newNetworkName = ""
                    validationError = nil
                    showCreate = false
                }
                Spacer()
                Button("Create") {
                    guard appState.validateNetworkName(newNetworkName) == nil else { return }
                    appState.createNetwork(name: newNetworkName)
                    newNetworkName = ""
                    validationError = nil
                    showCreate = false
                }
                .accessibilityIdentifier("btn_confirm_network_create")
                .disabled(newNetworkName.isEmpty || validationError != nil)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

// MARK: - Network Detail View

struct NetworkDetailView: View {
    let network: MockNetwork

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(network.name).font(.title3).fontWeight(.semibold)
                Spacer()
                Text(network.driver).font(.caption).foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow { Text("Name").foregroundStyle(.secondary); Text(network.name) }
                    GridRow { Text("ID").foregroundStyle(.secondary); Text(network.id).font(.system(.body, design: .monospaced)) }
                    GridRow { Text("Driver").foregroundStyle(.secondary); Text(network.driver) }
                    GridRow { Text("Scope").foregroundStyle(.secondary); Text(network.scope) }
                    GridRow { Text("Subnet").foregroundStyle(.secondary); Text(network.subnet.isEmpty ? "—" : network.subnet) }
                    GridRow { Text("Gateway").foregroundStyle(.secondary); Text(network.subnet.isEmpty ? "—" : network.subnet.replacingOccurrences(of: "0/16", with: "1")) }
                    GridRow { Text("Containers").foregroundStyle(.secondary); Text("web-server, api-service") }
                }
                .padding()
            }
        }
    }
}

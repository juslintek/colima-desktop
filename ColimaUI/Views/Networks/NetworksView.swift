import SwiftUI

struct NetworksView: View {
    @EnvironmentObject var appState: AppState
    @State private var newNetworkName = ""
    @State private var showCreate = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(appState.networks) { net in
                    networkRow(net)
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("table_networks")
        }
        .navigationTitle("Networks")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
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

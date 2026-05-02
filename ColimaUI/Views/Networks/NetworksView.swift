import SwiftUI

struct NetworksView: View {
    @EnvironmentObject var appState: AppState
    @State private var newNetworkName = ""
    @State private var showCreate = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showCreate {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Network name", text: $newNetworkName)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                            .accessibilityIdentifier("field_network_name")
                            .onChange(of: newNetworkName) { _ in validationError = appState.validateNetworkName(newNetworkName) }
                        if let err = validationError {
                            Text(err).font(.caption).foregroundStyle(.red)
                                .accessibilityIdentifier("text_network_validation_error")
                        }
                    }
                    Button("Confirm") {
                        guard appState.validateNetworkName(newNetworkName) == nil else { return }
                        appState.createNetwork(name: newNetworkName)
                        newNetworkName = ""; showCreate = false; validationError = nil
                    }
                    .accessibilityIdentifier("btn_confirm_network_create")
                    .disabled(newNetworkName.isEmpty || validationError != nil)
                }
                Spacer()
                Button("Create") { showCreate.toggle() }.accessibilityIdentifier("btn_create_network_new")
                Button("Prune") { appState.pruneNetworks() }.accessibilityIdentifier("btn_prune_network_all")
            }.padding()

            List(appState.networks) { net in
                HStack {
                    Text(net.name).frame(minWidth: 100, alignment: .leading)
                        .accessibilityIdentifier("row_network_\(net.name)")
                    Text(net.driver).foregroundStyle(.secondary).frame(minWidth: 60, alignment: .leading)
                    Text(net.scope).foregroundStyle(.secondary).frame(minWidth: 60, alignment: .leading)
                    Text(net.subnet).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { appState.removeNetwork(name: net.name) }
                        .accessibilityIdentifier("btn_remove_network_\(net.name)")
                    Button("Inspect") { appState.inspectNetwork(name: net.name) }
                        .accessibilityIdentifier("btn_inspect_network_\(net.name)")
                    Button("Connect") { appState.connectNetwork(network: net.name, container: "web-server") }
                        .accessibilityIdentifier("btn_connect_network_\(net.name)")
                    Button("Disconnect") { appState.disconnectNetwork(network: net.name, container: "web-server") }
                        .accessibilityIdentifier("btn_disconnect_network_\(net.name)")
                }
            }
            .accessibilityIdentifier("table_networks")
        }
        .navigationTitle("Networks")
    }
}

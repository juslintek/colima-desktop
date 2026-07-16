import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - NetworksView additional tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_NetworksViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_NetworksViewWave3Tests {

    private func net(_ name: String, driver: String = "bridge", scope: String = "local", subnet: String = "172.17.0.0/16") -> MockNetwork {
        MockNetwork(id: name, name: name, driver: driver, scope: scope, subnet: subnet)
    }

    private func state(networks: [MockNetwork] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.networks = networks
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        NetworksView().environmentObject(appState)
    }

    @Test("renders without crash with empty networks")
    func rendersEmpty() throws {
        let v = view(state())
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows empty state when no networks")
    func showsEmptyState() throws {
        let v = view(state())
        #expect((try? v.inspect().find(text: "No networks")) != nil)
    }

    @Test("shows create network button in empty state")
    func showsCreateButtonInEmptyState() throws {
        let v = view(state())
        #expect((try? v.inspect().find(button: "Create Network")) != nil)
    }

    @Test("shows network table when networks present")
    func showsNetworkTable() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_networks")) != nil)
    }

    @Test("shows network row for each network")
    func showsNetworkRow() throws {
        let s = state(networks: [net("app-network")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_network_app-network")) != nil)
    }

    @Test("shows remove button for network row")
    func showsRemoveButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_network_bridge")) != nil)
    }

    @Test("shows sort menu button")
    func showsSortButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_networks")) != nil)
    }

    @Test("shows create network button in toolbar")
    func showsCreateButtonInToolbar() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_network_new")) != nil)
    }

    @Test("shows prune networks button in toolbar")
    func showsPruneButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_network_all")) != nil)
    }

    @Test("NetworkSortOrder allCases has 3 elements")
    func sortOrderCases() {
        #expect(NetworkSortOrder.allCases.count == 3)
    }

    @Test("NetworkSortOrder rawValues are correct")
    func sortOrderRawValues() {
        #expect(NetworkSortOrder.name.rawValue == "Name")
        #expect(NetworkSortOrder.driver.rawValue == "Driver")
        #expect(NetworkSortOrder.scope.rawValue == "Scope")
    }

    @Test("networks sorted by name ascending")
    func sortedByNameAscending() {
        let networks = [net("zeta"), net("alpha"), net("bridge")]
        let sorted = networks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #expect(sorted.first?.name == "alpha")
        #expect(sorted.last?.name == "zeta")
    }
}

// MARK: - NetworkDetailView tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_NetworkDetailView Integration", .serialized)
@MainActor
struct Cov3Rest_NetworkDetailViewTests {

    private func network() -> MockNetwork {
        MockNetwork(id: "net001", name: "app-network", driver: "bridge", scope: "local", subnet: "172.18.0.0/16")
    }

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = NetworkDetailView(network: network())
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows network name in header")
    func showsNetworkName() throws {
        let v = NetworkDetailView(network: network())
        #expect((try? v.inspect().find(text: "app-network")) != nil)
    }

    @Test("shows driver in header")
    func showsDriver() throws {
        let v = NetworkDetailView(network: network())
        #expect((try? v.inspect().find(text: "bridge")) != nil)
    }

    @Test("shows subnet label in detail")
    func showsSubnetLabel() throws {
        let v = NetworkDetailView(network: network())
        #expect((try? v.inspect().find(text: "Subnet")) != nil)
    }
}

// MARK: - Network validation unit tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_NetworkValidation Unit", .serialized)
@MainActor
struct Cov3Rest_NetworkValidationTests {

    @Test("validateNetworkName accepts valid name")
    func acceptsValidName() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateNetworkName("my-network")
        #expect(err == nil)
    }

    @Test("validateNetworkName rejects empty name")
    func rejectsEmptyName() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateNetworkName("")
        #expect(err != nil)
    }

    @Test("validateNetworkName rejects name with spaces")
    func rejectsNameWithSpaces() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateNetworkName("my network")
        #expect(err != nil)
    }
}

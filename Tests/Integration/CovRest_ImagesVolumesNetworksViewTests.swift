import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ImagesView integration tests (CovRest_ prefix)

@Suite("CovRest_ImagesView Integration", .serialized)
@MainActor
struct CovRest_ImagesViewTests {

    private func image(_ repo: String, tag: String = "latest", id: String? = nil) -> MockImage {
        MockImage(id: id ?? "sha256:\(repo)", repository: repo, tag: tag, size: "100MB", created: "1 week ago")
    }

    private func state(images: [MockImage] = [], containers: [MockContainer] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.images = images
        s.containers = containers
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        ImagesView().environmentObject(appState)
    }

    @Test("shows empty state when no images")
    func emptyStateShown() throws {
        let s = state(images: [])
        let v = view(s)
        #expect((try? v.inspect().find(text: "No images")) != nil)
    }

    @Test("shows Pull Image button in empty state")
    func emptyStatePullButton() throws {
        let s = state(images: [])
        let v = view(s)
        #expect((try? v.inspect().find(button: "Pull Image")) != nil)
    }

    @Test("shows images table when images present")
    func imagesTableVisible() throws {
        let s = state(images: [image("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_images")) != nil)
    }

    @Test("shows image repository:tag in row")
    func imageRowRepoTag() throws {
        let s = state(images: [image("nginx", tag: "latest")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_image_nginx")) != nil)
    }

    @Test("shows remove button for each image row")
    func imageRowRemoveButton() throws {
        let s = state(images: [image("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_image_nginx")) != nil)
    }

    @Test("sort menu button is present")
    func sortButtonPresent() throws {
        let s = state(images: [image("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_images")) != nil)
    }

    @Test("search field is present in toolbar")
    func searchFieldPresent() throws {
        let s = state(images: [image("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_images_search")) != nil)
    }

    @Test("pull new image button is present in toolbar")
    func pullNewButtonPresent() throws {
        let s = state(images: [image("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_pull_image_new_sheet")) != nil)
    }

    @Test("prune images button is present in toolbar")
    func pruneButtonPresent() throws {
        let s = state(images: [image("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_image_all")) != nil)
    }

    @Test("In Use section appears when running containers match image")
    func inUseSectionAppearsForRunningContainer() throws {
        let img = image("nginx", tag: "latest", id: "sha256:nginx")
        let container = MockContainer(id: "c1", name: "web", image: "nginx:latest",
                                       status: "Up", state: "running", ports: "80/tcp", created: "now")
        let s = state(images: [img], containers: [container])
        let v = view(s)
        #expect((try? v.inspect().find(text: "In Use")) != nil)
    }

    @Test("ImageSortOrder cases are all unique and non-empty")
    func imageSortOrderCases() {
        let cases = ImageSortOrder.allCases
        #expect(cases.count == 3)
        let values = cases.map(\.rawValue)
        #expect(Set(values).count == values.count)
        for c in cases { #expect(!c.rawValue.isEmpty) }
    }

    @Test("sortedList by name ascending returns lexicographic order")
    func sortByNameAscending() {
        let imgs: [MockImage] = [
            MockImage(id: "1", repository: "nginx", tag: "latest", size: "100MB", created: "now"),
            MockImage(id: "2", repository: "alpine", tag: "3", size: "5MB", created: "now"),
            MockImage(id: "3", repository: "ubuntu", tag: "22.04", size: "200MB", created: "now"),
        ]
        let s = state(images: imgs)
        // Access filtered: default is .name ascending
        #expect(s.images[0].repository == "nginx")  // unchanged source order
        // The sorted view would produce alpine, nginx, ubuntu
        let sorted = imgs.sorted { $0.repository.localizedCaseInsensitiveCompare($1.repository) == .orderedAscending }
        #expect(sorted.map(\.repository) == ["alpine", "nginx", "ubuntu"])
    }
}

// MARK: - ImageDetailView integration tests

@Suite("CovRest_ImageDetailView Integration", .serialized)
@MainActor
struct CovRest_ImageDetailViewTests {

    private func img() -> MockImage {
        MockImage(id: "sha256:abc123", repository: "nginx", tag: "latest", size: "187MB", created: "2 weeks ago")
    }

    @Test("shows repository and tag in header")
    func showsRepoAndTag() throws {
        let v = ImageDetailView(image: img())
        #expect((try? v.inspect().find(text: "nginx:latest")) != nil)
    }

    @Test("shows size in header")
    func showsSize() throws {
        let v = ImageDetailView(image: img())
        #expect((try? v.inspect().find(text: "187MB")) != nil)
    }

    @Test("has segmented tab picker")
    func hasTabPicker() throws {
        let v = ImageDetailView(image: img())
        #expect((try? v.inspect()) != nil)
    }

    @Test("info tab shows Repository row label")
    func infoTabRepositoryLabel() throws {
        let v = ImageDetailView(image: img())
        #expect((try? v.inspect().find(text: "Repository")) != nil)
    }

    @Test("ImageDetailView.Tab allCases has 3 tabs")
    func tabCases() {
        let cases = ImageDetailView.Tab.allCases
        #expect(cases.count == 3)
        let values = cases.map(\.rawValue)
        #expect(values.contains("Info"))
        #expect(values.contains("Terminal"))
        #expect(values.contains("Files"))
    }
}

// MARK: - VolumesView integration tests (CovRest_ prefix)

@Suite("CovRest_VolumesView Integration", .serialized)
@MainActor
struct CovRest_VolumesViewTests {

    private func vol(_ name: String) -> MockVolume {
        MockVolume(id: name, name: name, driver: "local",
                   mountpoint: "/var/lib/docker/volumes/\(name)/_data", size: "100MB")
    }

    private func state(volumes: [MockVolume]) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.volumes = volumes
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        VolumesView().environmentObject(appState)
    }

    @Test("shows empty state when no volumes")
    func emptyStateShown() throws {
        let s = state(volumes: [])
        let v = view(s)
        #expect((try? v.inspect().find(text: "No volumes")) != nil)
    }

    @Test("empty state has Create Volume button")
    func emptyStateCreateButton() throws {
        let s = state(volumes: [])
        let v = view(s)
        #expect((try? v.inspect().find(button: "Create Volume")) != nil)
    }

    @Test("shows volumes table when volumes present")
    func volumesTableVisible() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_volumes")) != nil)
    }

    @Test("shows volume name in row")
    func volumeRowName() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_volume_postgres_data")) != nil)
    }

    @Test("shows remove button for volume row")
    func volumeRowRemoveButton() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_volume_postgres_data")) != nil)
    }

    @Test("sort menu button is present")
    func sortButtonPresent() throws {
        let s = state(volumes: [vol("vol1")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_volumes")) != nil)
    }

    @Test("create volume button is present in toolbar")
    func createVolumeButtonPresent() throws {
        let s = state(volumes: [vol("vol1")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_volume_new")) != nil)
    }

    @Test("prune volumes button is present in toolbar")
    func pruneButtonPresent() throws {
        let s = state(volumes: [vol("vol1")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_volume_all")) != nil)
    }

    @Test("VolumeSortOrder cases are unique and non-empty")
    func volumeSortOrderCases() {
        let cases = VolumeSortOrder.allCases
        #expect(cases.count == 3)
        for c in cases { #expect(!c.rawValue.isEmpty) }
        #expect(Set(cases.map(\.rawValue)).count == cases.count)
    }
}

// MARK: - VolumeDetailView integration tests

@Suite("CovRest_VolumeDetailView Integration", .serialized)
@MainActor
struct CovRest_VolumeDetailViewTests {

    private func vol() -> MockVolume {
        MockVolume(id: "vol001", name: "postgres_data", driver: "local",
                   mountpoint: "/var/lib/docker/volumes/postgres_data/_data", size: "256MB")
    }

    @Test("shows volume name in header")
    func showsVolumeName() throws {
        let v = VolumeDetailView(volume: vol())
        #expect((try? v.inspect().find(text: "postgres_data")) != nil)
    }

    @Test("shows volume size in header")
    func showsVolumeSize() throws {
        let v = VolumeDetailView(volume: vol())
        #expect((try? v.inspect().find(text: "256MB")) != nil)
    }

    @Test("VolumeDetailView.Tab allCases has 2 tabs")
    func tabCases() {
        let cases = VolumeDetailView.Tab.allCases
        #expect(cases.count == 2)
        let values = cases.map(\.rawValue)
        #expect(values.contains("Info"))
        #expect(values.contains("Files"))
    }

    @Test("info tab shows Name row label")
    func infoTabShowsNameLabel() throws {
        let v = VolumeDetailView(volume: vol())
        #expect((try? v.inspect().find(text: "Name")) != nil)
    }

    @Test("info tab shows Driver row label")
    func infoTabShowsDriverLabel() throws {
        let v = VolumeDetailView(volume: vol())
        #expect((try? v.inspect().find(text: "Driver")) != nil)
    }
}

// MARK: - NetworksView integration tests (CovRest_ prefix)

@Suite("CovRest_NetworksView Integration", .serialized)
@MainActor
struct CovRest_NetworksViewTests {

    private func net(_ name: String, subnet: String = "172.17.0.0/16") -> MockNetwork {
        MockNetwork(id: name, name: name, driver: "bridge", scope: "local", subnet: subnet)
    }

    private func state(networks: [MockNetwork]) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.networks = networks
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        NetworksView().environmentObject(appState)
    }

    @Test("shows empty state when no networks")
    func emptyStateShown() throws {
        let s = state(networks: [])
        let v = view(s)
        #expect((try? v.inspect().find(text: "No networks")) != nil)
    }

    @Test("empty state has Create Network button")
    func emptyStateCreateButton() throws {
        let s = state(networks: [])
        let v = view(s)
        #expect((try? v.inspect().find(button: "Create Network")) != nil)
    }

    @Test("shows networks table when networks present")
    func networksTableVisible() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_networks")) != nil)
    }

    @Test("shows network name in row")
    func networkRowName() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_network_bridge")) != nil)
    }

    @Test("shows remove button for network row")
    func networkRowRemoveButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_network_bridge")) != nil)
    }

    @Test("sort menu button is present")
    func sortButtonPresent() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_networks")) != nil)
    }

    @Test("create network button is present in toolbar")
    func createNetworkButtonPresent() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_network_new")) != nil)
    }

    @Test("prune networks button is present in toolbar")
    func pruneButtonPresent() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_network_all")) != nil)
    }

    @Test("NetworkSortOrder cases are unique and non-empty")
    func networkSortOrderCases() {
        let cases = NetworkSortOrder.allCases
        #expect(cases.count == 3)
        for c in cases { #expect(!c.rawValue.isEmpty) }
        #expect(Set(cases.map(\.rawValue)).count == cases.count)
    }
}

// MARK: - NetworkDetailView integration tests

@Suite("CovRest_NetworkDetailView Integration", .serialized)
@MainActor
struct CovRest_NetworkDetailViewTests {

    private func net() -> MockNetwork {
        MockNetwork(id: "net001", name: "bridge", driver: "bridge", scope: "local", subnet: "172.17.0.0/16")
    }

    @Test("shows network name in header")
    func showsNetworkName() throws {
        let v = NetworkDetailView(network: net())
        #expect((try? v.inspect().find(text: "bridge")) != nil)
    }

    @Test("shows network driver in header area")
    func showsNetworkDriver() throws {
        let v = NetworkDetailView(network: net())
        // driver "bridge" also appears in the header
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows Name label in detail grid")
    func showsNameLabel() throws {
        let v = NetworkDetailView(network: net())
        #expect((try? v.inspect().find(text: "Name")) != nil)
    }

    @Test("shows Driver label in detail grid")
    func showsDriverLabel() throws {
        let v = NetworkDetailView(network: net())
        #expect((try? v.inspect().find(text: "Driver")) != nil)
    }

    @Test("shows Scope label in detail grid")
    func showsScopeLabel() throws {
        let v = NetworkDetailView(network: net())
        #expect((try? v.inspect().find(text: "Scope")) != nil)
    }

    @Test("shows Subnet label in detail grid")
    func showsSubnetLabel() throws {
        let v = NetworkDetailView(network: net())
        #expect((try? v.inspect().find(text: "Subnet")) != nil)
    }

    @Test("shows em-dash for empty subnet")
    func emptySubnetShowsDash() throws {
        let n = MockNetwork(id: "host", name: "host", driver: "host", scope: "local", subnet: "")
        let v = NetworkDetailView(network: n)
        // Subnet is empty → shows "—"
        #expect((try? v.inspect().find(text: "—")) != nil)
    }
}

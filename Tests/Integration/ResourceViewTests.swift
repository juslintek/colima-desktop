import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - ImagesView integration tests

@Suite("ImagesView Integration", .serialized)
@MainActor
struct ImagesViewTests {

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

    private func img(_ repo: String, tag: String = "latest") -> MockImage {
        MockImage(id: "sha256:\(repo)", repository: repo, tag: tag, size: "100MB", created: "1h ago")
    }

    @Test("shows empty state when no images")
    func emptyState() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(text: "No images")) != nil)
    }

    @Test("shows image list when images are present")
    func imageList() throws {
        let s = state(images: [img("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_images")) != nil)
    }

    @Test("shows image repo:tag in list via row identifier")
    func imageNames() throws {
        let s = state(images: [img("nginx", tag: "latest")])
        let v = view(s)
        // The image row uses `row_image_<repository>` identifier
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_image_nginx")) != nil)
    }

    @Test("toolbar has sort button")
    func sortButton() throws {
        let s = state(images: [img("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_images")) != nil)
    }

    @Test("toolbar has pull button")
    func pullButton() throws {
        let s = state(images: [img("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_pull_image_new_sheet")) != nil)
    }

    @Test("toolbar has prune button")
    func pruneButton() throws {
        let s = state(images: [img("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_image_all")) != nil)
    }

    @Test("toolbar has search field")
    func searchField() throws {
        let s = state(images: [img("nginx")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "field_images_search")) != nil)
    }

    @Test("ImageSortOrder has 3 cases")
    func sortOrderCases() {
        #expect(ImageSortOrder.allCases.count == 3)
        #expect(ImageSortOrder.allCases.contains(.name))
        #expect(ImageSortOrder.allCases.contains(.size))
        #expect(ImageSortOrder.allCases.contains(.created))
    }
}

// MARK: - VolumesView integration tests

@Suite("VolumesView Integration", .serialized)
@MainActor
struct VolumesViewTests {

    private func state(volumes: [MockVolume] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.volumes = volumes
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        VolumesView().environmentObject(appState)
    }

    private func vol(_ name: String) -> MockVolume {
        MockVolume(id: name, name: name, driver: "local", mountpoint: "/var/lib/docker/volumes/\(name)/_data", size: "100MB")
    }

    @Test("shows empty state when no volumes")
    func emptyState() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(text: "No volumes")) != nil)
    }

    @Test("shows volume list when volumes are present")
    func volumeList() throws {
        let s = state(volumes: [vol("mydata")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_volumes")) != nil)
    }

    @Test("shows volume name in list")
    func volumeName() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(text: "postgres_data")) != nil)
    }

    @Test("toolbar has sort button")
    func sortButton() throws {
        let s = state(volumes: [vol("v1")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_volumes")) != nil)
    }

    @Test("toolbar has create button")
    func createButton() throws {
        let s = state(volumes: [vol("v1")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_volume_new")) != nil)
    }

    @Test("toolbar has prune button")
    func pruneButton() throws {
        let s = state(volumes: [vol("v1")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_volume_all")) != nil)
    }

    @Test("VolumeSortOrder has 3 cases")
    func sortOrderCases() {
        #expect(VolumeSortOrder.allCases.count == 3)
        #expect(VolumeSortOrder.allCases.contains(.name))
        #expect(VolumeSortOrder.allCases.contains(.driver))
        #expect(VolumeSortOrder.allCases.contains(.size))
    }
}

// MARK: - NetworksView integration tests

@Suite("NetworksView Integration", .serialized)
@MainActor
struct NetworksViewTests {

    private func state(networks: [MockNetwork] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.networks = networks
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        NetworksView().environmentObject(appState)
    }

    private func net(_ name: String) -> MockNetwork {
        MockNetwork(id: name, name: name, driver: "bridge", scope: "local", subnet: "172.17.0.0/16")
    }

    @Test("shows empty state when no networks")
    func emptyState() throws {
        let s = state()
        let v = view(s)
        #expect((try? v.inspect().find(text: "No networks")) != nil)
    }

    @Test("shows network list when networks are present")
    func networkList() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_networks")) != nil)
    }

    @Test("shows network name in list")
    func networkName() throws {
        let s = state(networks: [net("app-network")])
        let v = view(s)
        #expect((try? v.inspect().find(text: "app-network")) != nil)
    }

    @Test("toolbar has sort button")
    func sortButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_networks")) != nil)
    }

    @Test("toolbar has create button")
    func createButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_network_new")) != nil)
    }

    @Test("toolbar has prune button")
    func pruneButton() throws {
        let s = state(networks: [net("bridge")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_network_all")) != nil)
    }

    @Test("NetworkSortOrder has 3 cases")
    func sortOrderCases() {
        #expect(NetworkSortOrder.allCases.count == 3)
        #expect(NetworkSortOrder.allCases.contains(.name))
        #expect(NetworkSortOrder.allCases.contains(.driver))
        #expect(NetworkSortOrder.allCases.contains(.scope))
    }
}

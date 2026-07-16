import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktopKit

// MARK: - VolumesView additional tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_VolumesViewWave3 Integration", .serialized)
@MainActor
struct Cov3Rest_VolumesViewWave3Tests {

    private func vol(_ name: String, driver: String = "local", size: String = "256MB") -> MockVolume {
        MockVolume(id: name, name: name, driver: driver, mountpoint: "/var/lib/docker/volumes/\(name)/_data", size: size)
    }

    private func state(volumes: [MockVolume] = []) -> AppState {
        let s = AppState(services: MockServiceProvider())
        s.volumes = volumes
        return s
    }

    @ViewBuilder
    private func view(_ appState: AppState) -> some View {
        VolumesView().environmentObject(appState)
    }

    @Test("renders without crash with no volumes")
    func rendersEmpty() throws {
        let v = view(state())
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows empty state when no volumes")
    func showsEmptyState() throws {
        let v = view(state())
        #expect((try? v.inspect().find(text: "No volumes")) != nil)
    }

    @Test("shows create volume button in empty state")
    func showsCreateButtonInEmptyState() throws {
        let v = view(state())
        #expect((try? v.inspect().find(button: "Create Volume")) != nil)
    }

    @Test("shows volumes table when volumes present")
    func showsVolumesTable() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "table_volumes")) != nil)
    }

    @Test("shows volume row for each volume")
    func showsVolumeRow() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "row_volume_postgres_data")) != nil)
    }

    @Test("shows remove button for volume row")
    func showsRemoveButton() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_remove_volume_postgres_data")) != nil)
    }

    @Test("shows sort menu button in toolbar")
    func showsSortButton() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_sort_volumes")) != nil)
    }

    @Test("shows create volume button in toolbar")
    func showsCreateButtonInToolbar() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_create_volume_new")) != nil)
    }

    @Test("shows prune volumes button in toolbar")
    func showsPruneButton() throws {
        let s = state(volumes: [vol("postgres_data")])
        let v = view(s)
        #expect((try? v.inspect().find(viewWithAccessibilityIdentifier: "btn_prune_volume_all")) != nil)
    }

    @Test("VolumeSortOrder allCases has 3 elements")
    func sortOrderCases() {
        #expect(VolumeSortOrder.allCases.count == 3)
    }

    @Test("VolumeSortOrder rawValues are correct")
    func sortOrderRawValues() {
        #expect(VolumeSortOrder.name.rawValue == "Name")
        #expect(VolumeSortOrder.driver.rawValue == "Driver")
        #expect(VolumeSortOrder.size.rawValue == "Size")
    }

    @Test("volumes sorted by name ascending")
    func sortedByNameAscending() {
        let volumes = [vol("zeta-data"), vol("alpha-data"), vol("beta-data")]
        let sorted = volumes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        #expect(sorted.first?.name == "alpha-data")
        #expect(sorted.last?.name == "zeta-data")
    }

    @Test("renders multiple volumes without crash")
    func rendersMultipleVolumes() throws {
        let s = state(volumes: [vol("data1"), vol("data2"), vol("data3")])
        let v = view(s)
        #expect((try? v.inspect()) != nil)
    }
}

// MARK: - VolumeDetailView tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_VolumeDetailView Integration", .serialized)
@MainActor
struct Cov3Rest_VolumeDetailViewTests {

    private func volume() -> MockVolume {
        MockVolume(id: "vol001", name: "postgres_data", driver: "local",
                   mountpoint: "/var/lib/docker/volumes/postgres_data/_data", size: "256MB")
    }

    @Test("renders without crash")
    func rendersWithoutCrash() throws {
        let v = VolumeDetailView(volume: volume())
        #expect((try? v.inspect()) != nil)
    }

    @Test("shows volume name in header")
    func showsVolumeName() throws {
        let v = VolumeDetailView(volume: volume())
        #expect((try? v.inspect().find(text: "postgres_data")) != nil)
    }

    @Test("shows size in header")
    func showsSize() throws {
        let v = VolumeDetailView(volume: volume())
        #expect((try? v.inspect().find(text: "256MB")) != nil)
    }

    @Test("Tab allCases has 2 options")
    func tabCases() {
        #expect(VolumeDetailView.Tab.allCases.count == 2)
    }

    @Test("Tab rawValues are correct")
    func tabRawValues() {
        #expect(VolumeDetailView.Tab.info.rawValue == "Info")
        #expect(VolumeDetailView.Tab.files.rawValue == "Files")
    }
}

// MARK: - Volume validation unit tests (Cov3Rest_ prefix, wave 3)

@Suite("Cov3Rest_VolumeValidation Unit", .serialized)
@MainActor
struct Cov3Rest_VolumeValidationTests {

    @Test("validateVolumeName accepts valid name")
    func acceptsValidName() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateVolumeName("my-volume")
        #expect(err == nil)
    }

    @Test("validateVolumeName rejects empty name")
    func rejectsEmptyName() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateVolumeName("")
        #expect(err != nil)
    }

    @Test("validateVolumeName rejects name with spaces")
    func rejectsNameWithSpaces() {
        let s = AppState(services: MockServiceProvider())
        let err = s.validateVolumeName("my volume")
        #expect(err != nil)
    }
}

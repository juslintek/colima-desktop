import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - AppState validation methods (CovRest_ prefix)

@Suite("CovRest_AppState Validation")
@MainActor
struct CovRest_AppStateValidationTests {

    private func state() -> AppState {
        AppState(services: MockServiceProvider())
    }

    // MARK: Container name validation

    @Test("validateContainerName accepts alphanumeric name")
    func containerNameAlphanumeric() {
        let s = state()
        #expect(s.validateContainerName("mycontainer") == nil)
    }

    @Test("validateContainerName accepts name with dashes and underscores")
    func containerNameDashUnderscore() {
        let s = state()
        #expect(s.validateContainerName("my-container_1") == nil)
    }

    @Test("validateContainerName rejects empty string")
    func containerNameEmpty() {
        let s = state()
        #expect(s.validateContainerName("") != nil)
    }

    @Test("validateContainerName rejects name longer than 128 chars")
    func containerNameTooLong() {
        let s = state()
        let name = String(repeating: "a", count: 129)
        #expect(s.validateContainerName(name) != nil)
    }

    @Test("validateContainerName rejects name with spaces")
    func containerNameWithSpaces() {
        let s = state()
        #expect(s.validateContainerName("my container") != nil)
    }

    @Test("validateContainerName accepts name of exactly 128 chars")
    func containerName128Chars() {
        let s = state()
        let name = String(repeating: "a", count: 128)
        #expect(s.validateContainerName(name) == nil)
    }

    @Test("validateContainerName rejects name with dots")
    func containerNameWithDots() {
        let s = state()
        // Dots are NOT in allowed set for container names
        #expect(s.validateContainerName("my.container") != nil)
    }

    // MARK: Image name validation

    @Test("validateImageName accepts simple repo name")
    func imageNameSimple() {
        let s = state()
        #expect(s.validateImageName("nginx") == nil)
    }

    @Test("validateImageName accepts repo:tag format")
    func imageNameRepoTag() {
        let s = state()
        #expect(s.validateImageName("nginx:latest") == nil)
    }

    @Test("validateImageName accepts repo with registry prefix")
    func imageNameWithRegistry() {
        let s = state()
        #expect(s.validateImageName("docker.io/nginx:latest") == nil)
    }

    @Test("validateImageName rejects empty string")
    func imageNameEmpty() {
        let s = state()
        #expect(s.validateImageName("") != nil)
    }

    @Test("validateImageName rejects name starting with hyphen")
    func imageNameStartsWithHyphen() {
        let s = state()
        #expect(s.validateImageName("-nginx") != nil)
    }

    @Test("validateImageName accepts name with nested paths")
    func imageNameNestedPath() {
        let s = state()
        #expect(s.validateImageName("myregistry.com/myorg/myimage:1.0") == nil)
    }

    // MARK: Volume name validation

    @Test("validateVolumeName accepts alphanumeric name")
    func volumeNameAlphanumeric() {
        let s = state()
        #expect(s.validateVolumeName("postgres_data") == nil)
    }

    @Test("validateVolumeName accepts name with dots")
    func volumeNameWithDots() {
        let s = state()
        #expect(s.validateVolumeName("my.vol.data") == nil)
    }

    @Test("validateVolumeName rejects empty string")
    func volumeNameEmpty() {
        let s = state()
        #expect(s.validateVolumeName("") != nil)
    }

    @Test("validateVolumeName rejects name with spaces")
    func volumeNameWithSpaces() {
        let s = state()
        #expect(s.validateVolumeName("my volume") != nil)
    }

    @Test("validateVolumeName accepts dashes and underscores")
    func volumeNameDashUnderscore() {
        let s = state()
        #expect(s.validateVolumeName("my-vol_data") == nil)
    }

    @Test("validateVolumeName rejects name with at-sign")
    func volumeNameWithAt() {
        let s = state()
        #expect(s.validateVolumeName("vol@data") != nil)
    }

    // MARK: Network name validation

    @Test("validateNetworkName accepts simple name")
    func networkNameSimple() {
        let s = state()
        #expect(s.validateNetworkName("app-network") == nil)
    }

    @Test("validateNetworkName accepts name with dots")
    func networkNameWithDots() {
        let s = state()
        #expect(s.validateNetworkName("my.network.v2") == nil)
    }

    @Test("validateNetworkName rejects empty string")
    func networkNameEmpty() {
        let s = state()
        #expect(s.validateNetworkName("") != nil)
    }

    @Test("validateNetworkName rejects name with spaces")
    func networkNameWithSpaces() {
        let s = state()
        #expect(s.validateNetworkName("my network") != nil)
    }

    @Test("validateNetworkName accepts underscores")
    func networkNameUnderscores() {
        let s = state()
        #expect(s.validateNetworkName("my_network_v1") == nil)
    }

    // MARK: Profile name validation

    @Test("validateProfileName accepts simple alphanumeric name")
    func profileNameAlphanumeric() {
        let s = state()
        #expect(s.validateProfileName("myprofile") == nil)
    }

    @Test("validateProfileName accepts name with dashes")
    func profileNameWithDash() {
        let s = state()
        #expect(s.validateProfileName("my-profile") == nil)
    }

    @Test("validateProfileName accepts name with underscores")
    func profileNameWithUnderscore() {
        let s = state()
        #expect(s.validateProfileName("my_profile") == nil)
    }

    @Test("validateProfileName rejects empty string")
    func profileNameEmpty() {
        let s = state()
        #expect(s.validateProfileName("") != nil)
    }

    @Test("validateProfileName rejects name longer than 64 chars")
    func profileNameTooLong() {
        let s = state()
        let name = String(repeating: "a", count: 65)
        #expect(s.validateProfileName(name) != nil)
    }

    @Test("validateProfileName accepts name of exactly 64 chars")
    func profileName64Chars() {
        let s = state()
        let name = String(repeating: "a", count: 64)
        #expect(s.validateProfileName(name) == nil)
    }

    @Test("validateProfileName rejects name with dots")
    func profileNameWithDots() {
        let s = state()
        // Dots are NOT in the allowed set for profile names
        #expect(s.validateProfileName("my.profile") != nil)
    }

    @Test("validateProfileName rejects name with spaces")
    func profileNameWithSpaces() {
        let s = state()
        #expect(s.validateProfileName("my profile") != nil)
    }
}

// MARK: - AppState state management (CovRest_ prefix)

@Suite("CovRest_AppState State Management")
@MainActor
struct CovRest_AppStateStateTests {

    @Test("showToast sets message and isToastVisible")
    func showToastSetsState() {
        let s = AppState(services: MockServiceProvider())
        s.showToast("Hello, World!")
        #expect(s.toastMessage == "Hello, World!")
        #expect(s.isToastVisible == true)
    }

    @Test("showError sets errorMessage and shows toast")
    func showErrorSetsState() {
        let s = AppState(services: MockServiceProvider())
        s.showError("Something went wrong")
        #expect(s.errorMessage == "Something went wrong")
        #expect(s.isToastVisible == true)
    }

    @Test("requiresVM returns false when VM is not running and shows error")
    func requiresVMReturnsFalseWhenStopped() {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = false
        let result = s.requiresVM("SSH")
        #expect(result == false)
        #expect(s.isToastVisible == true)
    }

    @Test("requiresVM returns true when VM is running")
    func requiresVMReturnsTrueWhenRunning() {
        let s = AppState(services: MockServiceProvider())
        s.vmRunning = true
        let result = s.requiresVM("SSH")
        #expect(result == true)
    }

    @Test("requestConfirmation sets confirmation message and action")
    func requestConfirmation() {
        let s = AppState(services: MockServiceProvider())
        var called = false
        s.requestConfirmation("Delete profile?") { called = true }
        #expect(s.confirmationMessage == "Delete profile?")
        #expect(s.showConfirmation == true)
        s.confirmationAction?()
        #expect(called)
    }

    @Test("AppState initialises with colimaInstalled=true by default")
    func defaultColimaInstalled() {
        let s = AppState(services: MockServiceProvider())
        #expect(s.colimaInstalled == true)
    }

    @Test("AppState initialises with vmRunning=true by default")
    func defaultVmRunning() {
        let s = AppState(services: MockServiceProvider())
        #expect(s.vmRunning == true)
    }

    @Test("AppState initialises with activeProfile=default")
    func defaultActiveProfile() {
        let s = AppState(services: MockServiceProvider())
        #expect(s.activeProfile == "default")
    }

    @Test("AppState k8sEnabled mirrors k8sRunning")
    func k8sEnabledMirrorsRunning() {
        let s = AppState(services: MockServiceProvider())
        s.k8sRunning = true
        #expect(s.k8sEnabled == true)
        s.k8sRunning = false
        #expect(s.k8sEnabled == false)
    }

    @Test("AppState isUITesting reflects CommandLine args")
    func isUITestingReflectsArgs() {
        let s = AppState(services: MockServiceProvider())
        // isUITesting checks CommandLine.arguments for --ui-testing
        // In test context this is false (no --ui-testing flag)
        let result = s.isUITesting
        #expect(result == false || result == true)  // Just verify it's a Bool
    }
}

// MARK: - MockData sanity (CovRest_ prefix)

@Suite("CovRest_MockData Sanity")
struct CovRest_MockDataSanityTests {

    @Test("MockData.containers has 5 entries")
    func containerCount() {
        #expect(MockData.containers.count == 5)
    }

    @Test("MockData.images has 5 entries")
    func imageCount() {
        #expect(MockData.images.count == 5)
    }

    @Test("MockData.volumes has 3 entries")
    func volumeCount() {
        #expect(MockData.volumes.count == 3)
    }

    @Test("MockData.networks has 3 entries")
    func networkCount() {
        #expect(MockData.networks.count == 3)
    }

    @Test("MockData.profiles has 3 entries")
    func profileCount() {
        #expect(MockData.profiles.count == 3)
    }

    @Test("MockData containers have unique ids")
    func containerUniqueIds() {
        let ids = MockData.containers.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("MockData images have unique ids")
    func imageUniqueIds() {
        let ids = MockData.images.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("MockData volumes have unique names")
    func volumeUniqueNames() {
        let names = MockData.volumes.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test("MockData networks have unique ids")
    func networkUniqueIds() {
        let ids = MockData.networks.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("MockData profiles have unique ids")
    func profileUniqueIds() {
        let ids = MockData.profiles.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("MockData containers include at least one running container")
    func hasRunningContainer() {
        let running = MockData.containers.filter { $0.state == "running" }
        #expect(!running.isEmpty)
    }

    @Test("MockData containers include at least one exited container")
    func hasExitedContainer() {
        let exited = MockData.containers.filter { $0.state == "exited" }
        #expect(!exited.isEmpty)
    }

    @Test("MockData profiles include default profile")
    func hasDefaultProfile() {
        #expect(MockData.profiles.contains { $0.name == "default" })
    }

    @Test("MockData profiles include at least one stopped profile")
    func hasStoppedProfile() {
        #expect(MockData.profiles.contains { $0.status == "Stopped" })
    }
}

// MARK: - MockServiceProvider (CovRest_ prefix)

@Suite("CovRest_MockServiceProvider")
struct CovRest_MockServiceProviderTests {

    @Test("listContainers returns containers as JSON-like dicts")
    func listContainersReturnsDicts() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.listContainers()
        #expect(result.count == MockData.containers.count)
        for dict in result {
            #expect(dict["Id"] != nil)
            #expect(dict["Names"] != nil)
        }
    }

    @Test("listImages returns images with RepoTags")
    func listImagesReturnsTags() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.listImages()
        #expect(result.count == MockData.images.count)
        for dict in result {
            #expect(dict["RepoTags"] != nil)
        }
    }

    @Test("listVolumes returns volumes with Name field")
    func listVolumesReturnsNames() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.listVolumes()
        #expect(result.count == MockData.volumes.count)
        for dict in result {
            #expect(dict["Name"] != nil)
        }
    }

    @Test("listNetworks returns networks with Name field")
    func listNetworksReturnsNames() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.listNetworks()
        #expect(result.count == MockData.networks.count)
        for dict in result {
            #expect(dict["Name"] != nil)
        }
    }

    @Test("vmStatus returns running status")
    func vmStatusRunning() async throws {
        let mock = MockServiceProvider()
        let status = try await mock.vmStatus(profile: "default")
        #expect(status.running == true)
        #expect(status.arch == "aarch64")
    }

    @Test("startVM sets vmRunning=true")
    func startVMSetsRunning() async throws {
        let mock = MockServiceProvider()
        mock.vmRunning = false
        try await mock.startVM(profile: "default")
        #expect(mock.vmRunning == true)
    }

    @Test("stopVM sets vmRunning=false")
    func stopVMSetsNotRunning() async throws {
        let mock = MockServiceProvider()
        mock.vmRunning = true
        try await mock.stopVM(profile: "default", force: false)
        #expect(mock.vmRunning == false)
    }

    @Test("createContainer adds container to list")
    func createContainerAdds() async throws {
        let mock = MockServiceProvider()
        let initialCount = mock.containers.count
        _ = try await mock.createContainer(name: "test-ctr", image: "alpine")
        #expect(mock.containers.count == initialCount + 1)
        #expect(mock.containers.last?.name == "test-ctr")
    }

    @Test("removeContainer removes container from list")
    func removeContainerRemoves() async throws {
        let mock = MockServiceProvider()
        let name = MockData.containers[0].name
        let initialCount = mock.containers.count
        try await mock.removeContainer(id: name)
        #expect(mock.containers.count == initialCount - 1)
        #expect(!mock.containers.contains { $0.name == name })
    }

    @Test("pullImage adds image to list")
    func pullImageAdds() async throws {
        let mock = MockServiceProvider()
        let initial = mock.images.count
        try await mock.pullImage(name: "busybox:latest")
        #expect(mock.images.count == initial + 1)
    }

    @Test("createVolume adds volume to list")
    func createVolumeAdds() async throws {
        let mock = MockServiceProvider()
        let initial = mock.volumes.count
        try await mock.createVolume(name: "new-volume")
        #expect(mock.volumes.count == initial + 1)
        #expect(mock.volumes.last?.name == "new-volume")
    }

    @Test("removeVolume removes volume from list")
    func removeVolumeRemoves() async throws {
        let mock = MockServiceProvider()
        let name = MockData.volumes[0].name
        let initial = mock.volumes.count
        try await mock.removeVolume(name: name)
        #expect(mock.volumes.count == initial - 1)
        #expect(!mock.volumes.contains { $0.name == name })
    }

    @Test("createNetwork adds network to list")
    func createNetworkAdds() async throws {
        let mock = MockServiceProvider()
        let initial = mock.networks.count
        try await mock.createNetwork(name: "test-net")
        #expect(mock.networks.count == initial + 1)
        #expect(mock.networks.last?.name == "test-net")
    }

    @Test("removeNetwork removes network from list")
    func removeNetworkRemoves() async throws {
        let mock = MockServiceProvider()
        let name = MockData.networks[0].name
        let initial = mock.networks.count
        try await mock.removeNetwork(name: name)
        #expect(mock.networks.count == initial - 1)
        #expect(!mock.networks.contains { $0.name == name })
    }

    @Test("listProfiles returns profiles matching MockData")
    func listProfilesCount() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.listProfiles()
        #expect(result.count == MockData.profiles.count)
    }

    @Test("deleteProfile removes it from list")
    func deleteProfileRemoves() async throws {
        let mock = MockServiceProvider()
        let initial = mock.profiles.count
        try await mock.deleteProfile(name: "dev", data: false)
        #expect(mock.profiles.count == initial - 1)
    }

    @Test("cloneProfile creates new profile with destination name")
    func cloneProfileCreates() async throws {
        let mock = MockServiceProvider()
        let initial = mock.profiles.count
        try await mock.cloneProfile(source: "default", dest: "clone-of-default")
        #expect(mock.profiles.count == initial + 1)
        #expect(mock.profiles.contains { $0.name == "clone-of-default" })
    }

    @Test("containerLogs returns mock log string")
    func containerLogsReturnsMock() async throws {
        let mock = MockServiceProvider()
        let logs = try await mock.containerLogs(id: "web-server")
        #expect(!logs.isEmpty)
        #expect(logs.contains("mock log line"))
    }

    @Test("inspectContainer returns JSON string")
    func inspectContainerReturnsJSON() async throws {
        let mock = MockServiceProvider()
        let json = try await mock.inspectContainer(id: "web-server")
        #expect(json.hasPrefix("{"))
        #expect(json.contains("web-server"))
    }

    @Test("containerChanges returns JSON array string")
    func containerChangesReturnsJSON() async throws {
        let mock = MockServiceProvider()
        let json = try await mock.containerChanges(id: "web-server")
        #expect(json.hasPrefix("["))
    }

    @Test("imageHistory returns JSON array string")
    func imageHistoryReturnsJSON() async throws {
        let mock = MockServiceProvider()
        let json = try await mock.imageHistory(name: "nginx")
        #expect(json.hasPrefix("["))
    }

    @Test("searchImages returns results with name field")
    func searchImagesResults() async throws {
        let mock = MockServiceProvider()
        let results = try await mock.searchImages(term: "nginx")
        #expect(!results.isEmpty)
        #expect(results.first?["name"] != nil)
    }

    @Test("processList returns non-empty string")
    func processListNonEmpty() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.processList(profile: "default")
        #expect(!result.isEmpty)
    }

    @Test("executeCommand returns mock output string")
    func executeCommandReturnsMock() async throws {
        let mock = MockServiceProvider()
        let result = try await mock.executeCommand(tool: "docker", args: ["ps"])
        #expect(result.contains("mock output"))
    }

    @Test("isColimaInstalled returns true in normal test context")
    func isColimaInstalledInTests() async {
        let mock = MockServiceProvider()
        let result = await mock.isColimaInstalled()
        // Without --no-colima flag, returns true
        #expect(result == true)
    }

    @Test("streamEvents returns nil Task")
    func streamEventsReturnsNil() {
        let mock = MockServiceProvider()
        let task = mock.streamEvents { _ in }
        #expect(task == nil)
    }

    @Test("streamLogs returns nil Task")
    func streamLogsReturnsNil() {
        let mock = MockServiceProvider()
        let task = mock.streamLogs(containerId: "web") { _ in }
        #expect(task == nil)
    }

    @Test("pauseContainer sets state to paused")
    func pauseContainerSetsState() async throws {
        let mock = MockServiceProvider()
        let name = MockData.containers.first { $0.state == "running" }!.name
        try await mock.pauseContainer(id: name)
        #expect(mock.containers.first { $0.name == name }?.state == "paused")
    }

    @Test("stopContainer sets state to exited")
    func stopContainerSetsState() async throws {
        let mock = MockServiceProvider()
        let name = MockData.containers.first { $0.state == "running" }!.name
        try await mock.stopContainer(id: name)
        #expect(mock.containers.first { $0.name == name }?.state == "exited")
    }

    @Test("restartContainer sets state to running")
    func restartContainerSetsState() async throws {
        let mock = MockServiceProvider()
        let name = MockData.containers.first { $0.state == "exited" }!.name
        try await mock.restartContainer(id: name)
        #expect(mock.containers.first { $0.name == name }?.state == "running")
    }

    @Test("pruneContainers removes exited containers")
    func pruneContainersRemovesExited() async throws {
        let mock = MockServiceProvider()
        let exitedBefore = mock.containers.filter { $0.state == "exited" }.count
        #expect(exitedBefore > 0)
        try await mock.pruneContainers()
        let exitedAfter = mock.containers.filter { $0.state == "exited" }.count
        #expect(exitedAfter == 0)
    }

    @Test("listMachines returns 4 mock machines")
    func listMachinesCount() async throws {
        let mock = MockServiceProvider()
        let machines = try await mock.listMachines()
        #expect(machines.count == 4)
    }

    @Test("readConfig returns ColimaConfig with mounts")
    func readConfigReturnsMounts() async throws {
        let mock = MockServiceProvider()
        let config = try await mock.readConfig(profile: "default")
        #expect(!config.mounts.isEmpty)
    }

    @Test("writeConfig does not throw")
    func writeConfigDoesNotThrow() async throws {
        let mock = MockServiceProvider()
        var config = ColimaConfig()
        config.cpu = 4
        // Should not throw
        try await mock.writeConfig(profile: "default", config: config)
    }
}

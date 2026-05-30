import Testing
@testable import ColimaDesktop

@Suite("AppState")
struct AppStateTests {

    @Test("initializes with mock service provider")
    func initMockMode() {
        let state = AppState(services: MockServiceProvider())
        #expect(state.selectedTab == .dashboard)
        #expect(state.isToastVisible == false)
    }

    @Test("validates container names")
    func containerNameValidation() {
        let state = AppState(services: MockServiceProvider())
        #expect(state.validateContainerName("valid-name") == nil)
        #expect(state.validateContainerName("also_valid123") == nil)
        #expect(state.validateContainerName("invalid name") != nil)
        #expect(state.validateContainerName("") != nil)
    }

    @Test("validates volume names")
    func volumeNameValidation() {
        let state = AppState(services: MockServiceProvider())
        #expect(state.validateVolumeName("my_volume") == nil)
        #expect(state.validateVolumeName("bad name!") != nil)
    }

    @Test("validates image names")
    func imageNameValidation() {
        let state = AppState(services: MockServiceProvider())
        #expect(state.validateImageName("nginx:latest") == nil)
        #expect(state.validateImageName("registry.io/org/img:v1") == nil)
        #expect(state.validateImageName("") != nil)
    }

    @Test("validates network names")
    func networkNameValidation() {
        let state = AppState(services: MockServiceProvider())
        #expect(state.validateNetworkName("app-network") == nil)
        #expect(state.validateNetworkName("bad network!") != nil)
    }

    @Test("validates profile names")
    func profileNameValidation() {
        let state = AppState(services: MockServiceProvider())
        #expect(state.validateProfileName("dev") == nil)
        #expect(state.validateProfileName("my-profile") == nil)
        #expect(state.validateProfileName("") != nil)
    }

    @Test("showToast sets message and visibility")
    func showToast() {
        let state = AppState(services: MockServiceProvider())
        state.showToast("Test message")
        #expect(state.toastMessage == "Test message")
        #expect(state.isToastVisible == true)
    }

    @Test("showError sets error toast")
    func showError() {
        let state = AppState(services: MockServiceProvider())
        state.showError("Something failed")
        #expect(state.toastMessage?.contains("Something failed") == true)
        #expect(state.isToastVisible == true)
    }
}

@Suite("MockData")
struct MockDataTests {

    @Test("containers not empty")
    func containers() {
        #expect(MockData.containers.isEmpty == false)
        #expect(MockData.containers.count == 5)
    }

    @Test("images not empty")
    func images() {
        #expect(MockData.images.isEmpty == false)
    }

    @Test("volumes not empty")
    func volumes() {
        #expect(MockData.volumes.isEmpty == false)
    }

    @Test("networks not empty")
    func networks() {
        #expect(MockData.networks.isEmpty == false)
    }

    @Test("profiles not empty")
    func profiles() {
        #expect(MockData.profiles.isEmpty == false)
    }
}

@Suite("NavigationItem")
struct NavigationItemTests {

    @Test("has expected case count")
    func caseCount() {
        #expect(NavigationItem.allCases.count == 13)
    }
}

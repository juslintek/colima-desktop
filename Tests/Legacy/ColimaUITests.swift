import XCTest
@testable import ColimaDesktop

final class ColimaUITests: XCTestCase {
    func testAppStateInitialValues() {
        let state = AppState(services: MockServiceProvider())
        XCTAssertTrue(state.vmRunning)
        XCTAssertEqual(state.selectedTab, .dashboard)
        XCTAssertFalse(state.isToastVisible)
    }

    func testAppStateRealModeInit() {
        let state = AppState(services: RealServiceProvider())
        // In real mode, vmRunning starts as true (optimistic) until refresh completes
        XCTAssertNotNil(state)
    }

    func testNavigationItemCases() {
        XCTAssertEqual(NavigationItem.allCases.count, 12) // 11 + runtimeControls
    }

    func testMockDataNotEmpty() {
        XCTAssertFalse(MockData.containers.isEmpty)
        XCTAssertFalse(MockData.images.isEmpty)
        XCTAssertFalse(MockData.volumes.isEmpty)
        XCTAssertFalse(MockData.networks.isEmpty)
        XCTAssertFalse(MockData.profiles.isEmpty)
    }

    func testValidation() {
        let state = AppState(services: MockServiceProvider())
        XCTAssertNil(state.validateContainerName("valid-name"))
        XCTAssertNotNil(state.validateContainerName("invalid name"))
        XCTAssertNotNil(state.validateContainerName(""))
        XCTAssertNil(state.validateVolumeName("my_volume"))
        XCTAssertNotNil(state.validateVolumeName("bad name!"))
    }

    func testDockerClientInit() {
        let client = DockerClient(profile: "default")
        XCTAssertNotNil(client)
    }

    func testServiceProviderInit() {
        let provider = RealServiceProvider()
        XCTAssertNotNil(provider)
    }
}

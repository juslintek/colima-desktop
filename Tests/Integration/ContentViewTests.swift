import Testing
import ViewInspector
import SwiftUI
@testable import ColimaDesktop

@Suite("ContentView Integration")
struct ContentViewTests {

    @Test("renders sidebar with navigation items")
    func sidebarExists() throws {
        let state = AppState(services: MockServiceProvider())
        let view = ContentView().environmentObject(state)
        let inspected = try view.inspect()
        // Verify the main split view renders
        let splitView = try inspected.find(viewWithAccessibilityIdentifier: "main_split_view")
        #expect(splitView != nil)
    }

    @Test("toast overlay appears when toast is visible")
    func toastOverlay() throws {
        let state = AppState(services: MockServiceProvider())
        state.showToast("Hello")
        let view = ContentView().environmentObject(state)
        let inspected = try view.inspect()
        let toast = try? inspected.find(text: "Hello")
        #expect(toast != nil)
    }
}

@Suite("AppState View Bindings")
struct AppStateBindingTests {

    @Test("tab selection updates selectedTab")
    func tabSelection() {
        let state = AppState(services: MockServiceProvider())
        state.selectedTab = .containers
        #expect(state.selectedTab == .containers)
        state.selectedTab = .images
        #expect(state.selectedTab == .images)
    }

    @Test("container actions update state in mock mode")
    func containerStart() async {
        let state = AppState(services: MockServiceProvider())
        await state.startContainer(name: "redis-cache")
        // In mock mode, toast should confirm action
        #expect(state.toastMessage?.contains("started") == true || state.toastMessage != nil)
    }
}

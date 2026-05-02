import SwiftUI

@main
struct ColimaUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        let useMocks = CommandLine.arguments.contains("--ui-testing")
        _appState = StateObject(wrappedValue: AppState(useMocks: useMocks))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

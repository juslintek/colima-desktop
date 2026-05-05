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

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label("\(appState.containers.filter { $0.state == "running" }.count)", systemImage: "cube")
        }
        .menuBarExtraStyle(.window)
    }
}

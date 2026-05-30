import SwiftUI

@main
struct ColimaDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState

    init() {
        let services: ServiceProvider = CommandLine.arguments.contains("--ui-testing")
            ? MockServiceProvider()
            : RealServiceProvider()
        _appState = StateObject(wrappedValue: AppState(services: services))
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

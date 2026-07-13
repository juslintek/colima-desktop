import SwiftUI

@main
struct ColimaDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var updater = UpdaterManager()

    init() {
        let services: ServiceProvider = CommandLine.arguments.contains("--backend-mock")
            ? MockServiceProvider()
            : RealServiceProvider()
        _appState = StateObject(wrappedValue: AppState(services: services))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(updater)
        } label: {
            Label("\(appState.containers.filter { $0.state == "running" }.count)", systemImage: "cube")
        }
        .menuBarExtraStyle(.window)
    }
}

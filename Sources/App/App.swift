import SwiftUI

@main
struct ColimaDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var updater = UpdaterManager()

    init() {
        // Backend is independent of UI-test affordances: `--ui-testing` only enables
        // test-friendly UI (window visibility, always-visible row actions). The real
        // ServiceProvider is the default (true end-to-end); `--backend-mock` opts into
        // mocks for CI / environments without a real Colima/Docker (e.g. the Tart VM,
        // which has no nested virtualization).
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

import SwiftUI
import Combine
import Sparkle

/// Wraps Sparkle for Developer ID auto-updates (NOT App Store — see DISTRIBUTION.md).
///
/// The updater stays dormant until a real EdDSA public key is set in Info.plist
/// (`SUPublicEDKey`), so development builds with the placeholder never show update
/// errors. It is also disabled under `--ui-testing` so XCUITest never triggers a
/// network check or an update prompt.
final class UpdaterManager: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false

    /// True when a real EdDSA public key is configured (not the shipped placeholder).
    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && !key.hasPrefix("REPLACE_")
    }

    init() {
        let uiTesting = CommandLine.arguments.contains("--ui-testing")
        let start = UpdaterManager.isConfigured && !uiTesting
        controller = SPUStandardUpdaterController(
            startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil
        )
        guard start else { return }
        // Background checks on by default for a notarized direct-download build.
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    /// User-initiated check (shows Sparkle UI: progress / "you're up to date" / release notes).
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

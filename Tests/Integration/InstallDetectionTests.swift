import Testing
import Foundation
@testable import ColimaDesktop

/// Real-backend integration tests for Colima install detection. These run on the
/// host (no GUI) and exercise the actual Process → colima path, unlike the mock UI tests.
@Suite("Colima Install Detection (real host)")
struct InstallDetectionTests {

    private var binaryPresent: Bool {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .contains { FileManager.default.fileExists(atPath: "\($0)/colima") }
    }

    @Test("isInstalled() matches actual binary presence")
    func detectionMatchesFilesystem() async {
        let detected = await DaemonClient.shared.isInstalled()
        #expect(detected == binaryPresent)
    }

    @Test("RealServiceProvider agrees with DaemonClient")
    func providerAgrees() async {
        let provider = await RealServiceProvider().isColimaInstalled()
        let daemon = await DaemonClient.shared.isInstalled()
        #expect(provider == daemon)
    }

    /// When Colima is actually installed, the real `colima version` round-trip must work
    /// (proves the Process exec + PATH wiring is correct end-to-end). Skipped otherwise.
    @Test("real colima version round-trip when installed")
    func versionRoundTrip() async throws {
        guard binaryPresent else { return }
        let version = try await DaemonClient.shared.version()
        #expect(!version.isEmpty)
    }
}

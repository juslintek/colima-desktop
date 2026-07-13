import Testing
import SnapshotTesting
import SwiftUI
@testable import ColimaDesktopKit

@Suite("Snapshot Tests")
struct SnapshotTests {

    @Test("placeholder compiles")
    func placeholder() {
        // Snapshot tests require a host app window context.
        // Full snapshot baseline will be generated in Phase 4.
        #expect(true)
    }
}

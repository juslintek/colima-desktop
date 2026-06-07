import Foundation
import Testing

/// Canonical real-mode E2E test support — shared by every test target.
///
/// Real, destructive backend tests run ONLY when both opt-in env vars are set AND
/// the resolved profile name is the dedicated, safety-prefixed test profile.
/// xcodebuild forwards environment to the test-runner process only when prefixed
/// with `TEST_RUNNER_`, so invoke real-mode runs with:
///
///   TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1 \
///   TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE=colima-desktop-e2e \
///   xcodebuild test ...
enum RealE2E {
    /// Safety prefix for every test-created Docker resource (Docker does not mangle these).
    static let prefix = "colima-desktop-e2e"

    /// NOTE: `colima` strips a leading `colima-` from profile names, so the requested
    /// profile `colima-desktop-e2e` is stored/served as `desktop-e2e`
    /// (socket at ~/.colima/desktop-e2e/docker.sock). The default below is the
    /// colima-resolved form.
    static let defaultProfile = "desktop-e2e"

    static func env(_ key: String) -> String? { ProcessInfo.processInfo.environment[key] }

    /// Resolved dedicated test profile as colima knows it.
    static var profile: String { env("COLIMA_DESKTOP_TEST_PROFILE") ?? defaultProfile }

    /// HARD SAFETY: only ever operate on a clearly-dedicated e2e profile, never `default`.
    static var profileIsSafe: Bool { profile != "default" && profile.contains("e2e") }

    /// Explicit opt-in: the real-e2e flag is set to "1".
    static var optedIn: Bool { env("COLIMA_DESKTOP_REAL_E2E") == "1" }

    static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.colima/\(profile)/docker.sock"
    }
    static var socketAvailable: Bool { FileManager.default.fileExists(atPath: socketPath) }

    /// Suite gate: opted in + safe profile + reachable socket.
    static var canRun: Bool { optedIn && profileIsSafe && socketAvailable }

    /// Deterministic, unique, safety-prefixed resource name (e.g. colima-desktop-e2e-ctr-1733...).
    static func resourceName(_ kind: String) -> String {
        "\(prefix)-\(kind)-\(UInt64(Date().timeIntervalSince1970 * 1000))"
    }

    static let skipMessage =
        "Real E2E disabled. Set TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1 and " +
        "TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE=desktop-e2e, then " +
        "`colima start colima-desktop-e2e --vm-type vz` (colima stores it as `desktop-e2e`)."
}

/// Poll an async condition until it holds or the deadline elapses.
/// Deterministic alternative to fixed sleeps; returns the final evaluation.
@discardableResult
func pollUntil(
    timeout: TimeInterval = 20,
    interval: TimeInterval = 0.25,
    _ condition: () async throws -> Bool
) async throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try await condition() { return true }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
    return try await condition()
}

/// Run an async operation with a hard deadline so a hung backend call fails fast
/// instead of stalling the whole suite.
func withTimeout<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw RealE2ETimeout.exceeded(seconds)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

enum RealE2ETimeout: Error, CustomStringConvertible {
    case exceeded(TimeInterval)
    var description: String {
        switch self { case .exceeded(let s): return "operation exceeded \(s)s timeout" }
    }
}

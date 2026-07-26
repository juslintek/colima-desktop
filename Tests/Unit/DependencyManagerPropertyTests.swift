import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - DependencyManager property + edge-case tests (Properties 20 & 21, R10.3/10.4/10.5)
//
// Feature: cross-platform-live-verification, Property 20 & 21
//
// Design Property 20 (Validates: Requirement 10.1):
//   "For any host state, the dependency check assigns each of the six tracked
//    tools (colima, lima, qemu, krunkit, docker-cli, kubectl) exactly one state
//    among installed, missing, and outdated."
//
// Design Property 21 (Validates: Requirement 10.2):
//   "For any dependency reported as missing, the DependencyManager offers an
//    install path through the platform package manager or a signed direct
//    download."
//
// Requirements 10.3/10.4/10.5 (install edge cases): a cancelled install returns
// to a safe state and reports the cancellation; an offline host reports the
// offline condition; a permission-denied install reports a permission error with
// remediation context.
//
// These exercise the task-10.4 `DependencyManager` (Sources/Services/DependencyManager.swift)
// entirely through its INJECTED seams — a `FakeProbe` (host detection) and a
// `RecordingInstaller` (the install action). NO real host detection, NO real
// install, NO live colima/docker/socket is touched: the production
// `DependencyManager()` default probe and `dockerDaemonResponds(socketPath:)` are
// never used. A seeded `P20RNG` makes every randomized iteration reproducible
// from the seed printed in its failure message.
//
// The six tools' bundled minimum-version floors (all non-nil) are:
//   colima 0.6.0 · lima 0.20.0 · qemu 8.0.0 · krunkit 0.1.0 · docker-cli 20.10.0 · kubectl 1.24.0

extension Tag {
    /// Per-property-unique tags so sibling property-test files (Properties 13/17/18/19/…)
    /// never collide on a shared identifier. The canonical tag strings
    /// "Feature: cross-platform-live-verification, Property {20,21}" are also carried
    /// in every suite/test display name below.
    @Tag static var property20DependencyStateTotality: Self
    @Tag static var property21InstallPathOffer: Self
}

// MARK: - Property 20 — DependencyManager state totality

@Suite(
    "Property 20 — DependencyManager state totality [Feature: cross-platform-live-verification, Property 20]",
    .tags(.property20DependencyStateTotality)
)
struct DependencyStateTotalityPropertyTests {

    /// Iterations per property. Comfortably exceeds the required minimum of 100.
    static let iterations = 200

    // MARK: 20.a — totality + determinism over ARBITRARY host observations

    @Test("classify is total, deterministic, and one-state-per-tool for any host observation — Feature: cross-platform-live-verification, Property 20")
    func totalityAndDeterminismOverArbitraryObservations() {
        for i in 0..<Self.iterations {
            let seed = 0x2000_0000_0000_0001 &+ UInt64(i)
            var rng = P20RNG(seed: seed)

            // A whole randomized host: one arbitrary observation per tool.
            var results: [DependencyTool: ToolProbeResult] = [:]
            for tool in DependencyTool.allCases {
                results[tool] = DepGen.arbitraryObservation(&rng)
            }
            let probe = FakeProbe(
                results: results,
                packageManagerAvailable: Bool.random(using: &rng),
                online: Bool.random(using: &rng)
            )
            let manager = DependencyManager(probe: probe)
            let ctx = "iter=\(i) seed=\(seed)"

            // checkAll() must yield EXACTLY one status per tracked tool.
            let all = manager.checkAll()
            #expect(all.count == DependencyTool.allCases.count,
                    "checkAll produced \(all.count) statuses, expected \(DependencyTool.allCases.count) — \(ctx)")
            #expect(Set(all.map(\.tool)) == Set(DependencyTool.allCases),
                    "checkAll did not cover exactly the six tools once each — \(ctx) got=\(all.map(\.tool))")

            for tool in DependencyTool.allCases {
                let obs = results[tool]!
                let status = manager.classify(tool)

                // Exactly one of the three states (the enum is total; assert membership explicitly).
                #expect([.installed, .missing, .outdated].contains(status.state),
                        "classify(\(tool.rawValue)) produced an out-of-domain state \(status.state) — \(ctx)")

                // Determinism: re-classifying the same fixed observation is identical.
                #expect(manager.classify(tool) == status,
                        "classify(\(tool.rawValue)) is non-deterministic — \(ctx)")

                // classify must compose probe + the pure state() decision faithfully.
                #expect(DependencyManager.state(for: tool, observation: obs) == status.state,
                        "classify(\(tool.rawValue)).state != state(for:observation:) — \(ctx) obs=\(DepGen.describe(obs))")

                // Comparator-independent partial correctness (holds for any version semantics):
                //   absent → missing; present & no version → installed; present & version → not missing.
                if !obs.present {
                    #expect(status.state == .missing,
                            "absent tool \(tool.rawValue) not classified missing — \(ctx)")
                } else if obs.version == nil {
                    #expect(status.state == .installed,
                            "present tool \(tool.rawValue) with no version not classified installed (floor comparison impossible) — \(ctx)")
                } else {
                    #expect(status.state == .installed || status.state == .outdated,
                            "present tool \(tool.rawValue) classified \(status.state); a present tool is never missing — \(ctx) obs=\(DepGen.describe(obs))")
                }
            }
        }
    }

    // MARK: 20.b — CORRECT state over categorized (unambiguous) versions

    @Test("classify assigns the correct state for absent/below/at/above-floor versions — Feature: cross-platform-live-verification, Property 20")
    func correctStateOverCategorizedVersions() {
        for i in 0..<Self.iterations {
            let seed = 0x2001_0000_0000_0001 &+ UInt64(i)
            var rng = P20RNG(seed: seed)

            for tool in DependencyTool.allCases {
                let (obs, expected) = DepGen.categorizedObservation(for: tool, &rng)
                let probe = FakeProbe(results: [tool: obs],
                                      packageManagerAvailable: Bool.random(using: &rng),
                                      online: true)
                let manager = DependencyManager(probe: probe)
                let status = manager.classify(tool)
                let ctx = "tool=\(tool.rawValue) iter=\(i) seed=\(seed) obs=\(DepGen.describe(obs)) floor=\(tool.minimumVersion ?? "nil")"

                #expect(status.state == expected,
                        "classify produced \(status.state), expected \(expected) — \(ctx)")

                // The observed version + resolved path thread through unchanged.
                #expect(status.detectedVersion == obs.version,
                        "detectedVersion not threaded through — \(ctx)")
                #expect(status.resolvedPath == obs.resolvedPath,
                        "resolvedPath not threaded through — \(ctx)")
            }
        }
    }

    // MARK: 20.c — deterministic mixed-host anchor (readable concrete example)

    @Test("a concrete mixed host classifies each tool correctly — Feature: cross-platform-live-verification, Property 20")
    func deterministicMixedHostAnchor() {
        // colima current, docker below floor, kubectl above floor, lima present w/o
        // version, qemu present with garbage version (unparseable → treated below
        // floor → outdated), krunkit absent.
        let results: [DependencyTool: ToolProbeResult] = [
            .colima: ToolProbeResult(present: true, resolvedPath: "/opt/homebrew/bin/colima", version: "0.10.1"),
            .dockerCLI: ToolProbeResult(present: true, resolvedPath: "/usr/local/bin/docker", version: "19.03.0"),
            .kubectl: ToolProbeResult(present: true, resolvedPath: "/opt/homebrew/bin/kubectl", version: "1.33.9"),
            .lima: ToolProbeResult(present: true, resolvedPath: "/opt/homebrew/bin/limactl", version: nil),
            .qemu: ToolProbeResult(present: true, resolvedPath: "/opt/homebrew/bin/qemu-img", version: "not-a-version"),
            .krunkit: .absent,
        ]
        let manager = DependencyManager(probe: FakeProbe(results: results, packageManagerAvailable: true, online: true))

        #expect(manager.classify(.colima).state == .installed)
        #expect(manager.classify(.dockerCLI).state == .outdated)      // 19.03.0 < 20.10.0
        #expect(manager.classify(.kubectl).state == .installed)       // 1.33.9 >= 1.24.0
        #expect(manager.classify(.lima).state == .installed)          // present, version unknown
        #expect(manager.classify(.qemu).state == .outdated)           // garbage parses as 0.0.0 < 8.0.0
        #expect(manager.classify(.krunkit).state == .missing)         // absent

        // Totality holds on the concrete host too.
        let all = manager.checkAll()
        #expect(all.count == 6)
        #expect(Set(all.map(\.tool)) == Set(DependencyTool.allCases))
    }
}

// MARK: - Property 21 — Missing-dependency install-path offer

@Suite(
    "Property 21 — missing-dependency install-path offer [Feature: cross-platform-live-verification, Property 21]",
    .tags(.property21InstallPathOffer)
)
struct DependencyInstallPathOfferPropertyTests {

    static let iterations = 200

    // MARK: 21.a — offeredInstallPath is ALWAYS concrete, kind follows availability

    @Test("offeredInstallPath returns a Homebrew command when a package manager is available, else a signed download — Feature: cross-platform-live-verification, Property 21")
    func offeredInstallPathIsAlwaysConcrete() {
        for i in 0..<Self.iterations {
            let seed = 0x2100_0000_0000_0001 &+ UInt64(i)
            var rng = P20RNG(seed: seed)

            for tool in DependencyTool.allCases {
                let available = Bool.random(using: &rng)
                let probe = FakeProbe(results: [:], packageManagerAvailable: available, online: true)
                let manager = DependencyManager(probe: probe)
                let path = manager.offeredInstallPath(for: tool)
                let ctx = "tool=\(tool.rawValue) available=\(available) iter=\(i) seed=\(seed)"

                switch path {
                case .packageManager(let command):
                    #expect(available,
                            "offered a package-manager path though no package manager is available — \(ctx)")
                    #expect(command.contains("brew install \(tool.brewFormula)"),
                            "package-manager command missing 'brew install \(tool.brewFormula)': '\(command)' — \(ctx)")
                    if let tap = tool.brewTap {
                        #expect(command.contains("brew tap \(tap)"),
                                "tapped formula missing 'brew tap \(tap)': '\(command)' — \(ctx)")
                    }
                case .signedDownload(let url):
                    #expect(!available,
                            "offered a signed-download path though a package manager is available — \(ctx)")
                    #expect(url == tool.signedDownloadURL,
                            "signed-download URL '\(url)' != tool.signedDownloadURL '\(tool.signedDownloadURL)' — \(ctx)")
                    #expect(url.hasPrefix("https://"),
                            "signed-download URL is not https: '\(url)' — \(ctx)")
                }

                // Always a concrete, user-facing path.
                #expect(!path.summary.isEmpty, "offered install path has an empty summary — \(ctx)")
            }
        }
    }

    // MARK: 21.b — missing/outdated offer a concrete path; installed offers none

    @Test("classify offers an install path for missing/outdated tools and none for installed — Feature: cross-platform-live-verification, Property 21")
    func classifyOffersPathForMissingOutdatedAndNoneForInstalled() {
        for i in 0..<Self.iterations {
            let seed = 0x2101_0000_0000_0001 &+ UInt64(i)
            var rng = P20RNG(seed: seed)

            for tool in DependencyTool.allCases {
                // Rotate through the three states across tools/iterations.
                let stateKind = Int.random(in: 0..<3, using: &rng)
                let obs: ToolProbeResult
                let expected: DependencyState
                switch stateKind {
                case 0:
                    obs = .absent
                    expected = .missing
                case 1:
                    obs = ToolProbeResult(present: true, resolvedPath: "/opt/homebrew/bin/\(tool.brewFormula)",
                                          version: DepGen.versionBelowFloor(for: tool, &rng))
                    expected = .outdated
                default:
                    obs = ToolProbeResult(present: true, resolvedPath: "/opt/homebrew/bin/\(tool.brewFormula)",
                                          version: "999.0.0")
                    expected = .installed
                }
                let available = Bool.random(using: &rng)
                let manager = DependencyManager(probe: FakeProbe(results: [tool: obs],
                                                                 packageManagerAvailable: available, online: true))
                let status = manager.classify(tool)
                let ctx = "tool=\(tool.rawValue) expected=\(expected) available=\(available) iter=\(i) seed=\(seed)"

                #expect(status.state == expected, "unexpected state \(status.state) — \(ctx)")
                #expect(!status.remediation.isEmpty, "empty remediation — \(ctx)")

                if expected == .installed {
                    #expect(status.installPath == nil,
                            "an installed tool must offer no install path, got \(String(describing: status.installPath)) — \(ctx)")
                } else {
                    // Missing or outdated: a concrete path is ALWAYS offered.
                    let offered = manager.offeredInstallPath(for: tool)
                    #expect(status.installPath != nil, "missing/outdated tool offered no install path — \(ctx)")
                    #expect(status.installPath == offered,
                            "classify install path \(String(describing: status.installPath)) != offeredInstallPath \(offered) — \(ctx)")
                    // Kind follows the injected availability.
                    switch offered {
                    case .packageManager: #expect(available, "package-manager path though unavailable — \(ctx)")
                    case .signedDownload: #expect(!available, "signed-download path though available — \(ctx)")
                    }
                    // Remediation references the offered path so the user can act on it.
                    #expect(status.remediation.contains(offered.summary),
                            "remediation does not reference the offered path '\(offered.summary)': '\(status.remediation)' — \(ctx)")
                }
            }
        }
    }
}

// MARK: - Install edge cases (Requirements 10.3 / 10.4 / 10.5)

@Suite(
    "DependencyManager install outcomes — cancel / offline / permission / failure / success (Requirements 10.3, 10.4, 10.5)"
)
struct DependencyInstallOutcomeTests {

    // MARK: 10.3 — cancelled BEFORE start returns a safe state with NO side effect

    @Test("install cancelled before it starts returns .cancelled and performs no install")
    func cancelledBeforeStartMakesNoChange() async {
        for tool in DependencyTool.allCases {
            let installer = RecordingInstaller(.succeed)
            // Online + package manager available so ONLY the pre-start cancel can short-circuit.
            let manager = DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))

            let outcome = await manager.install(tool, using: installer, isCancelled: { true })

            guard case .cancelled(let message) = outcome else {
                Issue.record("expected .cancelled for \(tool.rawValue), got \(outcome)")
                continue
            }
            #expect(!message.isEmpty, "cancellation message empty for \(tool.rawValue)")
            #expect(installer.runCount == 0,
                    "cancelled-before-start still invoked the installer \(installer.runCount) time(s) for \(tool.rawValue) — not a safe state")
        }
    }

    // MARK: 10.4 — offline reports the offline condition and attempts no download

    @Test("install while offline reports .offline and attempts no download")
    func offlineReportsAndAttemptsNoInstall() async {
        for tool in DependencyTool.allCases {
            let installer = RecordingInstaller(.succeed)
            let manager = DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: false))

            let outcome = await manager.install(tool, using: installer, isCancelled: { false })

            guard case .offline(let message) = outcome else {
                Issue.record("expected .offline for \(tool.rawValue), got \(outcome)")
                continue
            }
            #expect(!message.isEmpty, "offline message empty for \(tool.rawValue)")
            #expect(installer.runCount == 0,
                    "offline install still attempted the download \(installer.runCount) time(s) for \(tool.rawValue)")
        }
    }

    // MARK: 10.5 — permission-denied reports a permission error with remediation

    @Test("install denied permission reports .permissionDenied with remediation context")
    func permissionDeniedReportsRemediation() async {
        for tool in DependencyTool.allCases {
            let installer = RecordingInstaller(.throwError(.permissionDenied))
            let manager = DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))

            let outcome = await manager.install(tool, using: installer, isCancelled: { false })

            guard case .permissionDenied(let message) = outcome else {
                Issue.record("expected .permissionDenied for \(tool.rawValue), got \(outcome)")
                continue
            }
            #expect(installer.runCount == 1, "installer should have been attempted once for \(tool.rawValue)")
            #expect(message.contains(tool.displayName),
                    "permission remediation does not name the tool for \(tool.rawValue): '\(message)'")
            #expect(message.lowercased().contains("permission"),
                    "permission remediation lacks a permission cue for \(tool.rawValue): '\(message)'")
            #expect(!message.isEmpty)
        }
    }

    // MARK: installer failure → .failed with the underlying message

    @Test("install whose installer fails reports .failed with the message")
    func installerFailurePropagatesMessage() async {
        for tool in DependencyTool.allCases {
            let expectedMessage = "install-failed-\(tool.rawValue)"
            let installer = RecordingInstaller(.throwError(.failed(expectedMessage)))
            let manager = DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))

            let outcome = await manager.install(tool, using: installer, isCancelled: { false })

            guard case .failed(let message) = outcome else {
                Issue.record("expected .failed for \(tool.rawValue), got \(outcome)")
                continue
            }
            #expect(message == expectedMessage, "failure message not propagated for \(tool.rawValue): '\(message)'")
            #expect(installer.runCount == 1)
        }
    }

    // MARK: success re-observes as installed

    @Test("a successful install re-observes the tool as installed")
    func successReobservesAsInstalled() async {
        for tool in DependencyTool.allCases {
            let installer = RecordingInstaller(.succeed)
            // Post-install the probe reports the tool present at a current version.
            let installed = ToolProbeResult(present: true,
                                            resolvedPath: "/opt/homebrew/bin/\(tool.brewFormula)",
                                            version: "999.0.0")
            let manager = DependencyManager(probe: FakeProbe(results: [tool: installed],
                                                             packageManagerAvailable: true, online: true))

            let outcome = await manager.install(tool, using: installer, isCancelled: { false })

            #expect(outcome == .installed, "expected .installed for \(tool.rawValue), got \(outcome)")
            #expect(installer.runCount == 1, "installer should have run exactly once for \(tool.rawValue)")
        }
    }

    // MARK: remaining distinct outcome branches

    @Test("install maps every installer failure mode to the matching outcome")
    func installOutcomeMapsInstallerFailures() async {
        for tool in DependencyTool.allCases {
            // Installer itself reports a cancellation.
            let cancelledOutcome = await DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))
                .install(tool, using: RecordingInstaller(.throwError(.cancelled)), isCancelled: { false })
            if case .cancelled = cancelledOutcome {} else {
                Issue.record("installer-thrown .cancelled → \(cancelledOutcome) for \(tool.rawValue)")
            }

            // Connectivity lost mid-install.
            let offlineOutcome = await DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))
                .install(tool, using: RecordingInstaller(.throwError(.offline)), isCancelled: { false })
            if case .offline = offlineOutcome {} else {
                Issue.record("installer-thrown .offline → \(offlineOutcome) for \(tool.rawValue)")
            }

            // Non-typed error → .failed.
            let genericOutcome = await DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))
                .install(tool, using: RecordingInstaller(.throwOther), isCancelled: { false })
            if case .failed = genericOutcome {} else {
                Issue.record("generic installer error → \(genericOutcome) for \(tool.rawValue)")
            }

            // Installer "succeeds" but the tool is still not detected → .failed.
            let stillMissingOutcome = await DependencyManager(probe: FakeProbe(results: [:], packageManagerAvailable: true, online: true))
                .install(tool, using: RecordingInstaller(.succeed), isCancelled: { false })
            if case .failed = stillMissingOutcome {} else {
                Issue.record("succeeded-but-still-missing → \(stillMissingOutcome) for \(tool.rawValue)")
            }
        }
    }
}

// MARK: - Injected fakes (no real host detection / install)

/// Drives `DependencyManager`'s host-detection seam from fixed values so property
/// tests can express ANY host state without touching the real machine.
private struct FakeProbe: DependencyProbe {
    var results: [DependencyTool: ToolProbeResult]
    var packageManagerAvailable: Bool
    var online: Bool

    func probe(_ tool: DependencyTool) -> ToolProbeResult { results[tool] ?? .absent }
    func isPackageManagerAvailable() -> Bool { packageManagerAvailable }
    func isOnline() -> Bool { online }
}

/// Records how the install seam was driven and lets a test choose the outcome,
/// without ever running a real installer. Lock-protected because
/// `DependencyManager.install` awaits `run` off the calling context.
private final class RecordingInstaller: DependencyInstaller, @unchecked Sendable {
    enum Behavior {
        case succeed
        case throwError(DependencyInstallError)
        case throwOther
    }

    private let behavior: Behavior
    private let lock = NSLock()
    private var _runCount = 0
    private var _lastPath: InstallPath?

    init(_ behavior: Behavior) { self.behavior = behavior }

    func run(_ path: InstallPath) async throws {
        // Record synchronously (NSLock is unavailable from async contexts).
        record(path)
        switch behavior {
        case .succeed: return
        case .throwError(let error): throw error
        case .throwOther: throw GenericInstallError()
        }
    }

    private func record(_ path: InstallPath) {
        lock.lock()
        _runCount += 1
        _lastPath = path
        lock.unlock()
    }

    var runCount: Int { lock.lock(); defer { lock.unlock() }; return _runCount }
    var lastPath: InstallPath? { lock.lock(); defer { lock.unlock() }; return _lastPath }
}

private struct GenericInstallError: Error {}

// MARK: - Seeded RNG (reproducible counterexamples)

/// Deterministic SplitMix64 PRNG so every failing iteration is reproducible from
/// the seed printed in its failure message. File-private — does not collide with
/// the sibling property-test files' own RNGs.
private struct P20RNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Version parsing (independent of production DependencyVersion)

/// Minimal, independent dotted-version parsing used only to BUILD categorized
/// test versions (below/equal/above a floor) by integer component arithmetic —
/// so the expected classification is unambiguous by construction and does not
/// depend on the production comparator's internals.
private enum P20Version {
    static func parts(_ version: String) -> [Int] {
        let cleaned = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return cleaned.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }

    static func join(_ parts: [Int]) -> String { parts.map(String.init).joined(separator: ".") }
}

// MARK: - Randomized observation generators

private enum DepGen {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")

    /// Non-empty lowercase token (used for garbage version strings and paths).
    static func token(_ rng: inout P20RNG, minLen: Int = 3, maxLen: Int = 7) -> String {
        let len = Int.random(in: minLen...maxLen, using: &rng)
        var s = ""
        for _ in 0..<len { s.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]) }
        return s
    }

    /// An arbitrary version field spanning the whole input space the task calls
    /// out: nil / empty / garbage / whitespace / 1–3-component / v-prefixed /
    /// pre-release / mixed alnum.
    static func arbitraryVersionField(_ rng: inout P20RNG) -> String? {
        func n() -> Int { Int.random(in: 0...40, using: &rng) }
        switch Int.random(in: 0..<11, using: &rng) {
        case 0: return nil
        case 1: return ""
        case 2: return token(&rng)                                  // pure garbage
        case 3: return "   "                                        // whitespace
        case 4: return "\(n())"                                     // single number
        case 5: return "\(n()).\(n())"                              // two components
        case 6: return "\(n()).\(n()).\(n())"                       // three components
        case 7: return "v\(n()).\(n()).\(n())"                      // v-prefixed
        case 8: return "\(n()).\(n()).\(n())-beta.\(token(&rng))"   // pre-release suffix
        case 9: return "\(token(&rng))\(n())"                       // mixed garbage+number
        default: return "\(n()).\(n()).\(n()).\(n())"               // four components
        }
    }

    /// A fully arbitrary host observation for one tool.
    static func arbitraryObservation(_ rng: inout P20RNG) -> ToolProbeResult {
        let present = Bool.random(using: &rng)
        let path = Bool.random(using: &rng) ? "/opt/homebrew/bin/\(token(&rng))" : nil
        return ToolProbeResult(present: present, resolvedPath: path, version: arbitraryVersionField(&rng))
    }

    /// A version strictly BELOW the tool's floor, built by decrementing a
    /// positive floor component and keeping earlier components equal (so the
    /// result is strictly less regardless of trailing components).
    static func versionBelowFloor(for tool: DependencyTool, _ rng: inout P20RNG) -> String {
        guard let floor = tool.minimumVersion else { return "0.0.0" }
        let parts = P20Version.parts(floor)
        let candidates = parts.indices.filter { parts[$0] >= 1 }
        // Every one of the six floors has at least one positive component.
        let i = candidates.isEmpty ? 0 : candidates[Int.random(in: 0..<candidates.count, using: &rng)]
        var out = Array(parts.prefix(i))
        out.append(max(0, parts[i] - 1))
        for _ in 0..<(parts.count - i - 1) { out.append(Int.random(in: 0...999, using: &rng)) }
        return P20Version.join(out)
    }

    /// A version strictly ABOVE the tool's floor, built by incrementing one
    /// component and keeping earlier components equal.
    static func versionAboveFloor(for tool: DependencyTool, _ rng: inout P20RNG) -> String {
        guard let floor = tool.minimumVersion else { return "999.0.0" }
        let parts = P20Version.parts(floor)
        let i = Int.random(in: 0..<parts.count, using: &rng)
        var out = Array(parts.prefix(i))
        out.append(parts[i] + 1)
        for _ in 0..<(parts.count - i - 1) { out.append(Int.random(in: 0...999, using: &rng)) }
        return P20Version.join(out)
    }

    /// A version equal to the floor (identity, optionally v-prefixed — both parse equal).
    static func versionAtFloor(for tool: DependencyTool, _ rng: inout P20RNG) -> String {
        let floor = tool.minimumVersion ?? "0.0.0"
        return Bool.random(using: &rng) ? floor : "v\(floor)"
    }

    /// Build a categorized observation whose expected state is unambiguous.
    static func categorizedObservation(for tool: DependencyTool, _ rng: inout P20RNG) -> (ToolProbeResult, DependencyState) {
        let path = "/opt/homebrew/bin/\(tool.brewFormula)"
        // Weight toward the version-bearing categories; still cover absent + no-version.
        switch Int.random(in: 0..<5, using: &rng) {
        case 0:
            // Absent (version field randomized to prove it is ignored when absent).
            return (ToolProbeResult(present: false, resolvedPath: nil, version: arbitraryVersionField(&rng)), .missing)
        case 1:
            return (ToolProbeResult(present: true, resolvedPath: path, version: versionBelowFloor(for: tool, &rng)), .outdated)
        case 2:
            return (ToolProbeResult(present: true, resolvedPath: path, version: versionAtFloor(for: tool, &rng)), .installed)
        case 3:
            return (ToolProbeResult(present: true, resolvedPath: path, version: versionAboveFloor(for: tool, &rng)), .installed)
        default:
            // Present, version unknown → installed (no floor comparison possible).
            return (ToolProbeResult(present: true, resolvedPath: path, version: nil), .installed)
        }
    }

    static func describe(_ obs: ToolProbeResult) -> String {
        "ToolProbeResult(present=\(obs.present) version=\(obs.version.map { "\"\($0)\"" } ?? "nil") path=\(obs.resolvedPath ?? "nil"))"
    }
}

import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - Property 18 — Template read/save round-trip
//
// Feature: cross-platform-live-verification, Property 18
//
// Design Property 18 (Validates: Requirements 7.1):
//   "For any template content, saving it through SetTemplate and then reading
//    it through GetTemplate returns content equivalent to what was saved."
//
// This is a randomized property test (≥100 iterations per property). It exercises
// the exact serialization + path-resolution logic used by the live macOS
// template interface (`ColimaTemplate` + `DaemonClient.getTemplate/setTemplate`,
// landed by task 7.1) in three complementary ways:
//
//   1. The pure `ColimaTemplate.roundTrip` helper (no filesystem).
//   2. A file-based round-trip through an ISOLATED temp colima home that mirrors
//      `setTemplate` → `getTemplate` byte-for-byte (never touches real ~/.colima).
//   3. Unknown top-level key preservation across the encode/decode round-trip.
//
// No modal (NSSavePanel/NSOpenPanel/runModal) and no live backend are used — only
// pure helpers and a disposable temporary directory (headless-safe).

extension Tag {
    /// Unique per-property tag so sibling property-test files (Properties 13/17/19/…)
    /// never collide on a shared identifier. The canonical tag string
    /// "Feature: cross-platform-live-verification, Property 18" is also carried in
    /// every suite/test display name below.
    @Tag static var property18TemplateRoundTrip: Self
}

@Suite(
    "Property 18 — template read/save round-trip [Feature: cross-platform-live-verification, Property 18]",
    .tags(.property18TemplateRoundTrip)
)
struct TemplateRoundTripPropertyTests {

    /// Iterations per property. Comfortably exceeds the required minimum of 100.
    static let iterations = 200

    // MARK: Property 18.a — pure ColimaTemplate.roundTrip preserves content

    @Test("pure ColimaTemplate.roundTrip preserves template content — Feature: cross-platform-live-verification, Property 18")
    func pureRoundTripPreservesContent() {
        for i in 0..<Self.iterations {
            var rng = SplitMix64(seed: 0x9E37_7918_ABCD_0001 &+ UInt64(i))
            let original = P18Gen.makeConfig(&rng)

            let roundTripped = ColimaTemplate.roundTrip(original)

            P18Gen.expectEquivalent(
                original, roundTripped,
                "pure roundTrip iter=\(i) seed=\(0x9E37_7918_ABCD_0001 &+ UInt64(i)) \(P18Gen.describe(original))"
            )
        }
    }

    // MARK: Property 18.b — setTemplate → getTemplate through a temp colima home

    @Test("saving via setTemplate then reading via getTemplate returns equivalent content (temp colima home) — Feature: cross-platform-live-verification, Property 18")
    func fileRoundTripThroughTempColimaHome() throws {
        // Safety: the round-trip must NEVER touch the real ~/.colima directory.
        let realColimaHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".colima").path
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("p18-template-\(UUID().uuidString)")
        #expect(!tempRoot.path.hasPrefix(realColimaHome),
                "temp colima home must never live under the real ~/.colima")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Includes the profiles that all normalize to "default" ("", "colima",
        // "default") plus profile-scoped overrides.
        let profiles = ["default", "", "colima", "dev", "prod-1", "e2e", "staging2", "team_ci"]

        for i in 0..<Self.iterations {
            let seed = 0xC01D_CAFE_0000_0001 &+ UInt64(i)
            var rng = SplitMix64(seed: seed)
            let profile = profiles[Int.random(in: 0..<profiles.count, using: &rng)]
            // A fresh, isolated home per iteration so profiles that normalize to
            // the same file name never bleed across iterations.
            let colimaHome = tempRoot.appendingPathComponent("iter-\(i)").path
            let original = P18Gen.makeConfig(&rng)

            // Mirror DaemonClient.setTemplate exactly.
            try P18TemplateFile.save(original, profile: profile, colimaHome: colimaHome)

            // setTemplate must have written the profile-resolved template file.
            let path = ColimaTemplate.path(profile: profile, colimaHome: colimaHome)
            #expect(FileManager.default.fileExists(atPath: path),
                    "template file not written @iter \(i) profile='\(profile)' path=\(path)")

            // Mirror DaemonClient.getTemplate exactly.
            let readBack = try P18TemplateFile.load(profile: profile, colimaHome: colimaHome)

            P18Gen.expectEquivalent(
                original, readBack,
                "file roundTrip iter=\(i) profile='\(profile)' seed=\(seed) \(P18Gen.describe(original))"
            )
        }
    }

    // MARK: Property 18.c — unknown top-level keys survive the round-trip

    @Test("unknown top-level template keys survive the round-trip — Feature: cross-platform-live-verification, Property 18")
    func unknownKeysSurviveRoundTrip() {
        for i in 0..<Self.iterations {
            let seed = 0x00BA_DC0F_FEE0_0001 &+ UInt64(i)
            var rng = SplitMix64(seed: seed)
            let base = P18Gen.makeConfig(&rng)
            // Canonical YAML (sourceYAML is nil on a freshly-built config).
            let baseYAML = base.toYAML()

            // Inject 1–3 unique unknown top-level keys after the known content.
            let unknownCount = Int.random(in: 1...3, using: &rng)
            var unknowns: [(name: String, value: String)] = []
            var extra = ""
            for k in 0..<unknownCount {
                let name = "xUnknown\(k)_\(P18Gen.token(&rng))"
                let value = P18Gen.token(&rng)
                unknowns.append((name, value))
                extra += "\(name): \(value)\n"
            }
            let edited = baseYAML + extra

            // What setTemplate persists is encode(decode(edited)); getTemplate then
            // returns decode(persisted). Run the round-trip twice for idempotence.
            let persisted = ColimaTemplate.encode(ColimaTemplate.decode(edited))
            let readBack = ColimaTemplate.decode(persisted)
            let rePersisted = ColimaTemplate.encode(readBack)

            for unknown in unknowns {
                let line = "\(unknown.name): \(unknown.value)"
                #expect(persisted.contains(line),
                        "unknown key '\(line)' lost after first round-trip @iter \(i) seed=\(seed)")
                #expect(rePersisted.contains(line),
                        "unknown key '\(line)' lost after second round-trip @iter \(i) seed=\(seed)")
            }

            // Known content must survive alongside the preserved unknown keys.
            P18Gen.expectEquivalent(
                base, readBack,
                "unknown-keys iter=\(i) seed=\(seed) \(P18Gen.describe(base))"
            )
        }
    }
}

// MARK: - Seeded RNG (reproducible counterexamples)

/// Deterministic SplitMix64 PRNG so every failing iteration is reproducible from
/// the seed printed in its failure message.
private struct SplitMix64: RandomNumberGenerator {
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

// MARK: - Template file round-trip (mirror of DaemonClient.setTemplate/getTemplate)

/// Faithful reproduction of `DaemonClient.setTemplate`/`getTemplate` with an
/// injectable colima home, so the property test drives the real path-resolution
/// and file I/O without touching the private (hard-coded ~/.colima) home.
private enum P18TemplateFile {
    static func save(_ config: ColimaConfig, profile: String, colimaHome: String) throws {
        let path = ColimaTemplate.path(profile: profile, colimaHome: colimaHome)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try ColimaTemplate.encode(config).write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func load(profile: String, colimaHome: String) throws -> ColimaConfig {
        let path = ColimaTemplate.path(profile: profile, colimaHome: colimaHome)
        if FileManager.default.fileExists(atPath: path) {
            let yaml = try String(contentsOfFile: path, encoding: .utf8)
            return ColimaTemplate.decode(yaml)
        }
        let defaultPath = ColimaTemplate.defaultPath(colimaHome: colimaHome)
        if path != defaultPath, FileManager.default.fileExists(atPath: defaultPath) {
            let yaml = try String(contentsOfFile: defaultPath, encoding: .utf8)
            return ColimaTemplate.decode(yaml)
        }
        return ColimaConfig()
    }
}

// MARK: - Randomized ColimaConfig / template-content generators

private enum P18Gen {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    private static let paths = [
        "~", "/data", "~/projects", "/Volumes/Projects", "/tmp/work",
        "./local", "/mnt/store", "/Users/dev/src", "/var/lib/app",
    ]

    /// Non-empty lowercase-alphanumeric token (no colon, no whitespace, no newline),
    /// so it round-trips through the simple key/value YAML serializer cleanly.
    static func token(_ rng: inout SplitMix64, minLen: Int = 3, maxLen: Int = 8) -> String {
        let len = Int.random(in: minLen...maxLen, using: &rng)
        var s = ""
        for _ in 0..<len { s.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]) }
        return s
    }

    /// 70% a realistic enum value, 30% an arbitrary non-empty token — widening the
    /// input space while staying inside the string domain the serializer preserves.
    private static func choice(_ options: [String], _ rng: inout SplitMix64) -> String {
        if Int.random(in: 0..<10, using: &rng) < 7 {
            return options[Int.random(in: 0..<options.count, using: &rng)]
        }
        return token(&rng)
    }

    private static func path(_ rng: inout SplitMix64) -> String {
        if Bool.random(using: &rng) {
            return paths[Int.random(in: 0..<paths.count, using: &rng)]
        }
        return "/" + token(&rng) + "/" + token(&rng)
    }

    /// Build a randomized template config over the fields the task enumerates:
    /// cpu / memory / disk / arch / vmType / runtime / mountType / mounts / env.
    static func makeConfig(_ rng: inout SplitMix64) -> ColimaConfig {
        var c = ColimaConfig()
        c.cpu = Int.random(in: 1...64, using: &rng)
        // 1.0 ... 128.0 in 0.1 steps (Swift's Double<->String is round-trip exact).
        c.memory = Double(Int.random(in: 10...1280, using: &rng)) / 10.0
        c.disk = Int.random(in: 5...2000, using: &rng)
        c.arch = Bool.random(using: &rng) ? "aarch64" : "x86_64"
        c.vmType = choice(["vz", "qemu", "krunkit"], &rng)
        c.runtime = choice(["docker", "containerd", "incus"], &rng)
        c.mountType = choice(["virtiofs", "9p", "sshfs"], &rng)

        let mountCount = Int.random(in: 0...4, using: &rng)
        var mounts: [ColimaConfig.Mount] = []
        for _ in 0..<mountCount {
            mounts.append(.init(location: path(&rng), writable: Bool.random(using: &rng)))
        }
        c.mounts = mounts

        let envCount = Int.random(in: 0...4, using: &rng)
        var env: [String: String] = [:]
        for k in 0..<envCount {
            // Index prefix guarantees unique, non-empty, letter-leading keys.
            let key = "VAR\(k)_" + token(&rng, minLen: 1, maxLen: 4).uppercased()
            env[key] = token(&rng)
        }
        c.env = env
        return c
    }

    /// Field-by-field equivalence of the template content that round-trips.
    ///
    /// `ColimaConfig`'s custom `==` compares only cpu/memory/disk/arch/runtime/vmType,
    /// so mountType/mounts/env are asserted explicitly here to make "equivalent
    /// content" meaningful for Property 18.
    static func expectEquivalent(
        _ original: ColimaConfig,
        _ roundTripped: ColimaConfig,
        _ context: @autoclosure () -> String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let ctx = context()
        #expect(roundTripped.cpu == original.cpu, "cpu not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.memory == original.memory, "memory not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.disk == original.disk, "disk not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.arch == original.arch, "arch not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.vmType == original.vmType, "vmType not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.runtime == original.runtime, "runtime not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.mountType == original.mountType, "mountType not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.mounts == original.mounts, "mounts not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(roundTripped.env == original.env, "env not preserved — \(ctx)", sourceLocation: sourceLocation)
    }

    static func describe(_ c: ColimaConfig) -> String {
        "config(cpu=\(c.cpu) memory=\(c.memory) disk=\(c.disk) arch=\(c.arch) "
            + "vmType=\(c.vmType) runtime=\(c.runtime) mountType=\(c.mountType) "
            + "mounts=\(c.mounts) env=\(c.env))"
    }
}

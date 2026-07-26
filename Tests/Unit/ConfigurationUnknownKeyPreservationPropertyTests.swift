import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - Property 19 — Configuration unknown-key preservation
//
// Feature: cross-platform-live-verification, Property 19
//
// Design Property 19 (Validates: Requirements 7.4):
//   "For any profile configuration YAML, loading it into the macOS config model
//    and saving it back preserves every unknown key and every known value
//    present in the original."
//
// Requirement 7.4(4): WHEN the macOS_Frontend loads configuration, it SHALL
//   populate fields from the real profile YAML and SHALL preserve unknown keys on
//   save.
//
// This is a randomized property test (≥100 iterations per property). It exercises
// the PURE, side-effect-free helpers landed by task 7.4 in
// `Sources/Models/ColimaConfig.swift` — no `~/.colima` file I/O is performed:
//
//   • ColimaConfig.parse(_:) throws        — parse profile YAML (retains sourceYAML)
//   • ColimaConfig.roundTrip(_:)           — pure load→save (YAML → YAML)
//   • ColimaConfig.topLevelKeys(in:)       — declared top-level keys, in order
//   • ColimaConfig.unknownTopLevelKeys(in:)— keys the UI does not model
//   • ColimaConfig.knownTopLevelKeys       — the modelled top-level key set
//   • config.preservesUnknownKeys(from:)   — Property-19 predicate
//
// The generator mixes modelled ("known") keys with randomized UNKNOWN top-level
// keys (scalar / map / list shapes) AND unrecognized children of the known
// sections (network / kubernetes / docker / env), then asserts that a
// load→save (and a load→edit→save) preserves every unknown key verbatim while
// the known/edited values still serialize correctly.

extension Tag {
    /// Unique per-property tag so sibling property-test files (Properties 13/17/18/…)
    /// never collide on a shared identifier. The canonical tag string
    /// "Feature: cross-platform-live-verification, Property 19" is also carried in
    /// every suite/test display name below.
    @Tag static var property19ConfigUnknownKeys: Self
}

@Suite(
    "Property 19 — configuration unknown-key preservation [Feature: cross-platform-live-verification, Property 19]",
    .tags(.property19ConfigUnknownKeys)
)
struct ConfigurationUnknownKeyPreservationPropertyTests {

    /// Iterations per property. Comfortably exceeds the required minimum of 100.
    static let iterations = 200

    // MARK: Property 19.a — load→save preserves unknown keys AND known values

    @Test("loading profile YAML and saving it back preserves every unknown key + known value — Feature: cross-platform-live-verification, Property 19")
    func loadSavePreservesUnknownKeysAndKnownValues() throws {
        for i in 0..<Self.iterations {
            let seed = 0x1907_1907_0000_0001 &+ UInt64(i)
            var rng = P19RNG(seed: seed)
            let doc = P19Gen.makeDoc(&rng)
            let original = doc.yaml
            let ctx = "iter=\(i) seed=\(seed)"

            // The helper must identify EXACTLY the unknown top-level keys we injected,
            // and none of those may appear in the modelled key set.
            #expect(Set(ColimaConfig.unknownTopLevelKeys(in: original)) == Set(doc.unknownTopKeys),
                    "unknownTopLevelKeys mismatch — \(ctx)\ngot=\(ColimaConfig.unknownTopLevelKeys(in: original))\nwant=\(doc.unknownTopKeys)")
            for key in doc.unknownTopKeys {
                #expect(!ColimaConfig.knownTopLevelKeys.contains(key),
                        "generated unknown key '\(key)' collided with a known key — \(ctx)")
            }

            // Pure load→save (parse into the model, then serialize back out).
            let produced = ColimaConfig.roundTrip(original)

            // 1) Every unknown top-level key survives.
            let producedTop = Set(ColimaConfig.topLevelKeys(in: produced))
            for key in doc.unknownTopKeys {
                #expect(producedTop.contains(key),
                        "unknown top-level key '\(key)' lost after load→save — \(ctx)\n--- produced ---\n\(produced)")
            }
            // …confirmed independently by the Property-19 predicate.
            let parsed = try ColimaConfig.parse(original)
            #expect(parsed.preservesUnknownKeys(from: original),
                    "preservesUnknownKeys(from:) == false after load→save — \(ctx)\n--- produced ---\n\(produced)")

            // 2) Unknown top-level blocks (map/list shapes) survive verbatim.
            for block in doc.unknownTopBlocks {
                let verbatim = block.joined(separator: "\n")
                #expect(produced.contains(verbatim),
                        "unknown top-level block lost verbatim — \(ctx)\nwanted:\n\(verbatim)\n--- produced ---\n\(produced)")
            }
            // 3) Unrecognized children of known sections (network/kubernetes/docker/env) survive.
            for line in doc.unknownChildLines {
                #expect(produced.contains(line),
                        "unknown section child lost — \(ctx)\nwanted line: '\(line)'\n--- produced ---\n\(produced)")
            }

            // 4) Known values present in the original are preserved across load→save.
            let re = ColimaConfig.fromYAML(produced)
            P19Gen.expectKnownValues(re, doc, ctx: "load→save \(ctx)")
        }
    }

    // MARK: Property 19.b — load→EDIT→save keeps unknown keys AND applies edits

    @Test("editing known fields then saving preserves unknown keys and serializes the edits — Feature: cross-platform-live-verification, Property 19")
    func editThenSavePreservesUnknownKeysAndAppliesEdits() throws {
        for i in 0..<Self.iterations {
            let seed = 0x00ED_17ED_0000_0001 &+ UInt64(i)
            var rng = P19RNG(seed: seed)
            let doc = P19Gen.makeDoc(&rng)
            let original = doc.yaml
            let ctx = "iter=\(i) seed=\(seed)"

            var config = try ColimaConfig.parse(original)

            // Edit every modelled scalar field to a fresh random value (may coincide
            // with the original — still a valid edit).
            let newCPU = Int.random(in: 1...64, using: &rng)
            let newMemory = Double(Int.random(in: 10...1280, using: &rng)) / 10.0
            let newDisk = Int.random(in: 5...2000, using: &rng)
            let newArch = Bool.random(using: &rng) ? "aarch64" : "x86_64"
            let newRuntime = P19Gen.choice(["docker", "containerd", "incus"], &rng)
            let newVMType = P19Gen.choice(["vz", "qemu", "krunkit"], &rng)
            let newMountType = P19Gen.choice(["virtiofs", "9p", "sshfs"], &rng)
            config.cpu = newCPU
            config.memory = newMemory
            config.disk = newDisk
            config.arch = newArch
            config.runtime = newRuntime
            config.vmType = newVMType
            config.mountType = newMountType

            let produced = config.toYAML()

            // Unknown keys STILL survive after editing modelled fields.
            #expect(config.preservesUnknownKeys(from: original),
                    "preservesUnknownKeys(from:) == false after edit→save — \(ctx)\n--- produced ---\n\(produced)")
            let producedTop = Set(ColimaConfig.topLevelKeys(in: produced))
            for key in doc.unknownTopKeys {
                #expect(producedTop.contains(key),
                        "unknown top-level key '\(key)' lost after edit→save — \(ctx)\n--- produced ---\n\(produced)")
            }
            for block in doc.unknownTopBlocks {
                let verbatim = block.joined(separator: "\n")
                #expect(produced.contains(verbatim),
                        "unknown top-level block lost after edit→save — \(ctx)\nwanted:\n\(verbatim)\n--- produced ---\n\(produced)")
            }
            for line in doc.unknownChildLines {
                #expect(produced.contains(line),
                        "unknown section child lost after edit→save — \(ctx)\nwanted line: '\(line)'\n--- produced ---\n\(produced)")
            }

            // Edited known fields serialize correctly (survive a re-parse).
            let re = ColimaConfig.fromYAML(produced)
            #expect(re.cpu == newCPU, "edited cpu not serialized — \(ctx)")
            #expect(re.memory == newMemory, "edited memory not serialized — \(ctx)")
            #expect(re.disk == newDisk, "edited disk not serialized — \(ctx)")
            #expect(re.arch == newArch, "edited arch not serialized — \(ctx)")
            #expect(re.runtime == newRuntime, "edited runtime not serialized — \(ctx)")
            #expect(re.vmType == newVMType, "edited vmType not serialized — \(ctx)")
            #expect(re.mountType == newMountType, "edited mountType not serialized — \(ctx)")
        }
    }

    // MARK: Property 19.c — concrete regression fixtures (forward-compat verbatim survival)

    @Test("realistic colima.yaml with forward-compat keys survives verbatim — Feature: cross-platform-live-verification, Property 19")
    func regressionFixturesPreserveForwardCompatKeysVerbatim() throws {
        // Fixture 1: a realistic colima.yaml that carries forward-compat keys the
        // model does not know — a top-level scalar (`layer`, a real older Colima
        // option), an opaque top-level scalar (`sshInject`), a top-level map
        // (`telemetry`), a top-level list (`provisionV2`), plus unrecognized
        // children of the known `network` and `kubernetes` sections.
        let fixture1 = """
        cpu: 4
        memory: 8
        disk: 100
        arch: aarch64
        runtime: docker
        vmType: vz
        mountType: virtiofs
        autoActivate: true
        network:
          address: true
          mode: shared
          experimentalNAT: enabled
        kubernetes:
          enabled: false
          version: v1.30.0+k3s1
          ingressController: traefik-next
        layer: true
        sshInject: preserve-me
        telemetry:
          enabled: false
          endpoint: https-collector
        provisionV2:
          - mode: system
            script: echo-ready
        """
        let survivors1 = [
            "layer: true",
            "sshInject: preserve-me",
            "  experimentalNAT: enabled",            // unknown child of known `network`
            "  ingressController: traefik-next",     // unknown child of known `kubernetes`
            "telemetry:\n  enabled: false\n  endpoint: https-collector",  // unknown top-level map
            "provisionV2:\n  - mode: system\n    script: echo-ready",     // unknown top-level list
        ]
        let produced1 = ColimaConfig.roundTrip(fixture1)
        for survivor in survivors1 {
            #expect(produced1.contains(survivor),
                    "fixture1 lost forward-compat content:\n\(survivor)\n--- produced ---\n\(produced1)")
        }
        #expect(Set(ColimaConfig.unknownTopLevelKeys(in: fixture1)) == ["layer", "sshInject", "telemetry", "provisionV2"],
                "fixture1 unknownTopLevelKeys mismatch: \(ColimaConfig.unknownTopLevelKeys(in: fixture1))")
        let cfg1 = try ColimaConfig.parse(fixture1)
        #expect(cfg1.preservesUnknownKeys(from: fixture1), "fixture1 preservesUnknownKeys == false")
        #expect(ColimaConfig.fromYAML(produced1).cpu == 4, "fixture1 known cpu value not preserved")

        // Fixture 2: a near-empty config whose only non-modelled key is a single
        // forward-compat top-level scalar.
        let fixture2 = """
        cpu: 2
        futureOnlyKey: keepme
        """
        let produced2 = ColimaConfig.roundTrip(fixture2)
        #expect(produced2.contains("futureOnlyKey: keepme"),
                "fixture2 lost forward-compat key\n--- produced ---\n\(produced2)")
        #expect(Set(ColimaConfig.unknownTopLevelKeys(in: fixture2)) == ["futureOnlyKey"],
                "fixture2 unknownTopLevelKeys mismatch: \(ColimaConfig.unknownTopLevelKeys(in: fixture2))")
        let cfg2 = try ColimaConfig.parse(fixture2)
        #expect(cfg2.preservesUnknownKeys(from: fixture2), "fixture2 preservesUnknownKeys == false")
        #expect(ColimaConfig.fromYAML(produced2).cpu == 2, "fixture2 known cpu value not preserved")

        // Fixture 3: a nested/opaque forward-compat top-level block (map containing a
        // list and a scalar) alongside a modelled `env` passthrough child.
        let fixture3 = """
        cpu: 8
        network:
          address: false
        extraFeature:
          flags:
            - alpha
            - beta
          note: forward-compatible
        env:
          EXISTING_VAR: keep1
        """
        let produced3 = ColimaConfig.roundTrip(fixture3)
        let survivor3 = "extraFeature:\n  flags:\n    - alpha\n    - beta\n  note: forward-compatible"
        #expect(produced3.contains(survivor3),
                "fixture3 lost nested forward-compat block:\n\(survivor3)\n--- produced ---\n\(produced3)")
        #expect(produced3.contains("EXISTING_VAR: keep1"),
                "fixture3 lost env passthrough child\n--- produced ---\n\(produced3)")
        #expect(Set(ColimaConfig.unknownTopLevelKeys(in: fixture3)) == ["extraFeature"],
                "fixture3 unknownTopLevelKeys mismatch: \(ColimaConfig.unknownTopLevelKeys(in: fixture3))")
        let cfg3 = try ColimaConfig.parse(fixture3)
        #expect(cfg3.preservesUnknownKeys(from: fixture3), "fixture3 preservesUnknownKeys == false")
        #expect(ColimaConfig.fromYAML(produced3).cpu == 8, "fixture3 known cpu value not preserved")
    }
}

// MARK: - Seeded RNG (reproducible counterexamples)

/// Deterministic SplitMix64 PRNG so every failing iteration is reproducible from
/// the seed printed in its failure message.
private struct P19RNG: RandomNumberGenerator {
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

// MARK: - Randomized colima.yaml document generator

private enum P19Gen {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// Non-empty lowercase-alphanumeric token (no colon, no whitespace, no newline)
    /// so it round-trips through the simple key/value YAML serializer cleanly.
    static func token(_ rng: inout P19RNG, minLen: Int = 3, maxLen: Int = 7) -> String {
        let len = Int.random(in: minLen...maxLen, using: &rng)
        var s = ""
        for _ in 0..<len { s.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]) }
        return s
    }

    static func choice(_ options: [String], _ rng: inout P19RNG) -> String {
        options[Int.random(in: 0..<options.count, using: &rng)]
    }

    /// A generated colima.yaml plus the ground-truth needed to assert Property 19.
    struct Doc {
        var yaml: String
        var cpu: Int
        var memory: Double
        var disk: Int
        var arch: String
        var runtime: String
        var vmType: String
        var mountType: String
        var networkMode: String
        var kubernetesEnabled: Bool
        /// Names of the injected unknown top-level keys.
        var unknownTopKeys: [String]
        /// Verbatim line-blocks for the injected unknown top-level entries.
        var unknownTopBlocks: [[String]]
        /// Verbatim child lines injected under known sections (net/k8s/docker/env)
        /// that the save must preserve.
        var unknownChildLines: [String]
    }

    /// Build a randomized document mixing modelled keys, unknown top-level keys
    /// (scalar / map / list), and unrecognized children of known sections.
    static func makeDoc(_ rng: inout P19RNG) -> Doc {
        var uniq = 0
        func nextId() -> Int { uniq += 1; return uniq }

        let cpu = Int.random(in: 1...64, using: &rng)
        // 1.0 ... 128.0 in 0.1 steps (Swift's Double<->String is round-trip exact).
        let memory = Double(Int.random(in: 10...1280, using: &rng)) / 10.0
        let disk = Int.random(in: 5...2000, using: &rng)
        let arch = Bool.random(using: &rng) ? "aarch64" : "x86_64"
        let runtime = choice(["docker", "containerd", "incus"], &rng)
        let vmType = choice(["vz", "qemu", "krunkit"], &rng)
        let mountType = choice(["virtiofs", "9p", "sshfs"], &rng)
        let networkMode = choice(["shared", "bridged", "host"], &rng)
        let kubernetesEnabled = Bool.random(using: &rng)
        let k8sMinor = Int.random(in: 20...35, using: &rng)

        func memoryLiteral(_ m: Double) -> String { m == floor(m) ? "\(Int(m))" : "\(m)" }

        var unknownTopKeys: [String] = []
        var unknownTopBlocks: [[String]] = []
        var unknownChildLines: [String] = []

        // Each entry is a contiguous chunk of lines for one top-level key, so the
        // list can be safely order-shuffled without splitting a section.
        var entries: [[String]] = [
            ["cpu: \(cpu)"],
            ["memory: \(memoryLiteral(memory))"],
            ["disk: \(disk)"],
            ["arch: \(arch)"],
            ["runtime: \(runtime)"],
            ["vmType: \(vmType)"],
            ["mountType: \(mountType)"],
        ]

        // network — known section with 0–2 unrecognized children (handled by the
        // verbatim child-merge path in ColimaConfig.mergeTopLevelBlocks).
        var net = ["network:", "  address: true", "  mode: \(networkMode)"]
        for _ in 0..<Int.random(in: 0...2, using: &rng) {
            let line = "  net\(nextId())_\(token(&rng)): val_\(token(&rng))"
            net.append(line)
            unknownChildLines.append(line)
        }
        entries.append(net)

        // kubernetes — known section with 0–2 unrecognized children.
        var k8s = ["kubernetes:", "  enabled: \(kubernetesEnabled)", "  version: v1.\(k8sMinor).0+k3s1"]
        for _ in 0..<Int.random(in: 0...2, using: &rng) {
            let line = "  k8s\(nextId())_\(token(&rng)): val_\(token(&rng))"
            k8s.append(line)
            unknownChildLines.append(line)
        }
        entries.append(k8s)

        // docker — passthrough map: children are retained via canonical re-emission.
        let dockerChildren = Int.random(in: 0...2, using: &rng)
        if dockerChildren == 0 {
            entries.append(["docker: {}"])
        } else {
            var dk = ["docker:"]
            for _ in 0..<dockerChildren {
                let line = "  dkr\(nextId())_\(token(&rng)): val_\(token(&rng))"
                dk.append(line)
                unknownChildLines.append(line)
            }
            entries.append(dk)
        }

        // env — passthrough map: children are retained via canonical re-emission.
        let envChildren = Int.random(in: 0...2, using: &rng)
        if envChildren == 0 {
            entries.append(["env: {}"])
        } else {
            var ev = ["env:"]
            for _ in 0..<envChildren {
                let line = "  ENV\(nextId())_\(token(&rng).uppercased()): val_\(token(&rng))"
                ev.append(line)
                unknownChildLines.append(line)
            }
            entries.append(ev)
        }

        // 2–4 unknown top-level keys in scalar / map / list shapes.
        for _ in 0..<Int.random(in: 2...4, using: &rng) {
            let name = "xTop\(nextId())_\(token(&rng))"
            unknownTopKeys.append(name)
            let block: [String]
            switch Int.random(in: 0...2, using: &rng) {
            case 0:
                block = ["\(name): val_\(token(&rng))"]
            case 1:
                block = ["\(name):",
                         "  a_\(token(&rng)): val_\(token(&rng))",
                         "  b_\(token(&rng)): val_\(token(&rng))"]
            default:
                block = ["\(name):",
                         "  - val_\(token(&rng))",
                         "  - val_\(token(&rng))"]
            }
            entries.append(block)
            unknownTopBlocks.append(block)
        }

        // Deterministic Fisher–Yates shuffle so top-level ordering is randomized
        // (YAML is order-insensitive at the top level) while each section stays intact.
        for idx in stride(from: entries.count - 1, to: 0, by: -1) {
            let j = Int.random(in: 0...idx, using: &rng)
            entries.swapAt(idx, j)
        }

        let yaml = entries.map { $0.joined(separator: "\n") }.joined(separator: "\n") + "\n"

        return Doc(
            yaml: yaml, cpu: cpu, memory: memory, disk: disk, arch: arch,
            runtime: runtime, vmType: vmType, mountType: mountType,
            networkMode: networkMode, kubernetesEnabled: kubernetesEnabled,
            unknownTopKeys: unknownTopKeys, unknownTopBlocks: unknownTopBlocks,
            unknownChildLines: unknownChildLines
        )
    }

    /// Assert the modelled ("known") values that were present in the original doc
    /// survive a load→save unchanged.
    static func expectKnownValues(
        _ re: ColimaConfig,
        _ doc: Doc,
        ctx: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(re.cpu == doc.cpu, "known cpu not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.memory == doc.memory, "known memory not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.disk == doc.disk, "known disk not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.arch == doc.arch, "known arch not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.runtime == doc.runtime, "known runtime not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.vmType == doc.vmType, "known vmType not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.mountType == doc.mountType, "known mountType not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.network.mode == doc.networkMode, "known network.mode not preserved — \(ctx)", sourceLocation: sourceLocation)
        #expect(re.kubernetes.enabled == doc.kubernetesEnabled, "known kubernetes.enabled not preserved — \(ctx)", sourceLocation: sourceLocation)
    }
}

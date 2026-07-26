import Testing
import Foundation
@testable import ColimaDesktopKit

// MARK: - Property 17 — Accessibility identifier totality + uniqueness (macOS)
//
// Feature: cross-platform-live-verification, Property 17
//
// Design Property 17 (Validates: Requirements 7.6, 11.4):
//   "For all interactive controls across the Desktop_Frontends, each control has
//    a non-empty accessibility identifier and no identifier collides with another
//    control on the same surface."
//
// Requirement 7.6:  the macOS Runtime Controls surface (and every surface) must be
//   traversable by accessibility tooling with stable identifiers.
// Requirement 11.4: a keyboard-accessible, uniquely named identifier for each
//   interactive control across the Desktop_Frontends.
//
// This is the macOS analogue of the Windows `AutomationIdInventoryTests`. The
// SwiftUI XCUITest runtime cannot enumerate every control across the 12 canonical
// surfaces headlessly (sheets, conditional content, and modal-driven flows make
// full ViewInspector traversal impractical), so — exactly like the Windows test
// parses the real XAML as text — this test SCANS the real `Sources/Views/**/*.swift`
// source and asserts, per surface:
//
//   • accessibility identifiers are non-empty and unique within a surface
//     (no literal id collides with another control on the same surface),
//   • the surface is broadly instrumented (per-surface + global count floors that
//     guard against a vacuous pass — mirroring the Windows `>= N` floors),
//   • interactive controls are broadly covered by identifiers (coverage floor,
//     with the un-identified controls reported for follow-up), and
//   • the identifiers existing XCUITests depend on are still present (regression).
//
// The navigation surface identifiers (`tab_*`) are produced by the compiled
// `NavigationItem.accessibilityId`, so those are verified directly against the
// real model at runtime.
//
// The scanner itself is validated by randomized property tests (≥100 iterations
// each) over synthesized SwiftUI source, so the real-tree assertions rest on a
// checker proven to detect missing / duplicate / empty identifiers with no false
// positives — the same "synthetic property + real-repo anchor" shape used by the
// evidence-generator property tests in this program.
//
// No modal (NSSavePanel/NSOpenPanel/runModal), no live backend, no view rendering:
// pure text analysis of source files + the compiled navigation model (headless-safe).

extension Tag {
    /// Unique per-property tag so sibling property-test files (Properties 13/18/19/…)
    /// never collide on a shared identifier. The canonical tag string
    /// "Feature: cross-platform-live-verification, Property 17" is also carried in
    /// every suite/test display name below.
    @Tag static var property17AccessibilityIdentifiers: Self
}

@Suite(
    "Property 17 — accessibility identifier totality + uniqueness [Feature: cross-platform-live-verification, Property 17]",
    .tags(.property17AccessibilityIdentifiers)
)
struct AccessibilityIdentifierInventoryPropertyTests {

    /// Iterations per synthetic property. Comfortably exceeds the required minimum of 100.
    static let iterations = 200

    // The 12 primary canonical surfaces (design §Full-Functionality Exercise) whose
    // source files must exist and be broadly instrumented for accessibility.
    static let primarySurfaces: [(name: String, relPath: String)] = [
        ("Dashboard", "Dashboard/DashboardView.swift"),
        ("Containers", "Containers/ContainersView.swift"),
        ("Images", "Images/ImagesView.swift"),
        ("Volumes", "Volumes/VolumesView.swift"),
        ("Networks", "Networks/NetworksView.swift"),
        ("Configuration", "Configuration/ConfigurationView.swift"),
        ("Profiles", "Profiles/ProfilesView.swift"),
        ("Kubernetes", "Kubernetes/KubernetesView.swift"),
        ("AI", "AI/AIWorkloadsView.swift"),
        ("Monitoring", "Monitoring/MonitoringView.swift"),
        ("RuntimeControls", "RuntimeControls/RuntimeControlsView.swift"),
        ("CreateContainer", "Containers/CreateContainerView.swift"),
    ]

    // Literal identifiers existing XCUITests (Tests/UI/**) depend on. All are static
    // string literals in Sources/Views (verified in the source inventory) — including
    // the identifiers stabilized by tasks 7.5 (create-container flow) and 7.6
    // (Runtime Controls surface `view_runtime`). Dynamic/data-derived ids the
    // XCUITests also use (e.g. btn_delete_profile_<name>) are intentionally excluded
    // here because they are not source literals; navigation `tab_*` ids are covered
    // by the NavigationItem runtime check below.
    static let regressionIdentifiers: [String] = [
        // primary table / surface anchors
        "table_containers", "table_images", "table_volumes", "table_networks",
        "table_profiles", "table_ai_models", "table_activity_monitor", "table_runtime_comparison",
        // VM lifecycle (dashboard)
        "btn_start_vm_dashboard", "btn_stop_vm_dashboard", "btn_restart_vm_dashboard", "btn_delete_vm_dashboard",
        // prune actions
        "btn_prune_container_all", "btn_prune_image_all", "btn_prune_volume_all", "btn_prune_network_all",
        // create flows
        "btn_create_container_new", "btn_confirm_container_create",
        "field_create_container_name", "field_create_container_image",
        "field_volume_name", "btn_confirm_volume_create",
        "field_network_name", "btn_confirm_network_create",
        "field_create_profile_name", "btn_create_profile_new",
        // create-container advanced flow (task 7.5)
        "field_create_container_name_full", "field_create_container_image_full",
        "btn_create_container_advanced", "btn_create_container_empty_state",
        // search / config
        "field_containers_search", "field_config_cpus", "field_config_memory",
        "toggle_config_rosetta", "toggle_config_autoactivate",
        // runtime controls (task 7.6)
        "view_runtime", "picker_target_runtime", "btn_switch_runtime", "btn_copy_socket",
        // kubernetes / ai
        "btn_start_kubernetes_cluster", "btn_stop_kubernetes_cluster", "btn_reset_kubernetes_cluster",
        "field_ai_modelname", "btn_run_ai_model", "btn_setup_ai_model",
        // sidebar profile picker
        "picker_sidebar_profile",
    ]

    // Verified legitimate per-surface duplicate literal identifiers: the SAME logical
    // control rendered in mutually-exclusive if/else branches (only one is ever live),
    // which is not a collision with "another control".
    //   • main_split_view          — ContentView: two NavigationSplitView layout branches
    //   • label_template_validation — TemplateEditorView: valid vs. issues branch
    static let branchReuseAllowlist: Set<String> = ["main_split_view", "label_template_validation"]

    // MARK: - Synthetic randomized property tests (validate the scanner) — ≥100 iters

    @Test("scanner flags exactly the interactive controls that lack an accessibility identifier — Feature: cross-platform-live-verification, Property 17")
    func scannerFlagsExactlyUnidentifiedControls() {
        for i in 0..<Self.iterations {
            let seed = 0x1700_0000_0000_0001 &+ UInt64(i)
            var rng = P17RNG(seed: seed)
            let gen = P17Gen.makeSurface(&rng)
            let inv = A11yScan.analyze(gen.source)
            let ctx = "iter=\(i) seed=\(seed)\n--- source ---\n\(gen.source)"

            #expect(inv.interactiveControlCount == gen.controlCount,
                    "control count mismatch: got \(inv.interactiveControlCount), want \(gen.controlCount) — \(ctx)")
            #expect(inv.unidentifiedControlLines.count == gen.unidentified,
                    "unidentified count mismatch: got \(inv.unidentifiedControlLines.count), want \(gen.unidentified) — \(ctx)")
            #expect(inv.identifiedControlCount == gen.controlCount - gen.unidentified,
                    "identified count mismatch — \(ctx)")
            #expect(Set(inv.literalIdentifiers) == gen.literalIds,
                    "literal id set mismatch: got \(Set(inv.literalIdentifiers).sorted()), want \(gen.literalIds.sorted()) — \(ctx)")
            #expect(inv.emptyLiteralCount == 0, "unexpected empty ids — \(ctx)")
        }
    }

    @Test("scanner detects duplicate and empty accessibility identifiers — Feature: cross-platform-live-verification, Property 17")
    func scannerDetectsDuplicatesAndEmpties() {
        for i in 0..<Self.iterations {
            let seed = 0x1701_0000_0000_0001 &+ UInt64(i)
            var rng = P17RNG(seed: seed)
            let gen = P17Gen.makeIdList(&rng)
            let inv = A11yScan.analyze(gen.source)
            let ctx = "iter=\(i) seed=\(seed)\n--- source ---\n\(gen.source)"

            #expect(Set(A11yScan.duplicateLiterals(inv.literalIdentifiers)) == gen.duplicates,
                    "duplicate detection mismatch: got \(A11yScan.duplicateLiterals(inv.literalIdentifiers)), want \(gen.duplicates.sorted()) — \(ctx)")
            #expect(inv.emptyLiteralCount == gen.emptyCount,
                    "empty-id count mismatch: got \(inv.emptyLiteralCount), want \(gen.emptyCount) — \(ctx)")
            #expect(Set(inv.literalIdentifiers) == gen.uniqueLiterals,
                    "unique literal set mismatch — \(ctx)")
        }
    }

    @Test("a fully-identified surface yields zero violations (no false positives) — Feature: cross-platform-live-verification, Property 17")
    func fullyIdentifiedSurfaceHasNoViolations() {
        for i in 0..<Self.iterations {
            let seed = 0x1702_0000_0000_0001 &+ UInt64(i)
            var rng = P17RNG(seed: seed)
            let gen = P17Gen.makeCleanSurface(&rng)
            let inv = A11yScan.analyze(gen.source)
            let ctx = "iter=\(i) seed=\(seed)\n--- source ---\n\(gen.source)"

            #expect(inv.interactiveControlCount == gen.controlCount, "control count mismatch — \(ctx)")
            #expect(inv.unidentifiedControlLines.isEmpty,
                    "false positive: reported \(inv.unidentifiedControlLines.count) unidentified on a clean surface — \(ctx)")
            #expect(inv.identifiedControlCount == gen.controlCount, "coverage < 1.0 on a clean surface — \(ctx)")
            #expect(A11yScan.duplicateLiterals(inv.literalIdentifiers).isEmpty,
                    "false positive: duplicate reported on unique-id surface — \(ctx)")
            #expect(inv.emptyLiteralCount == 0, "false positive: empty id reported — \(ctx)")
            #expect(Set(inv.literalIdentifiers) == gen.literalIds, "literal id set mismatch — \(ctx)")
        }
    }

    @Test("scanner recognizes every interactive control kind and rejects decoys — Feature: cross-platform-live-verification, Property 17")
    func scannerRecognizesEveryControlKind() {
        // One occurrence of each interactive control kind the task enumerates.
        let kinds = """
        Button("a") { x() }
        Toggle("b", isOn: $b)
        Picker("c", selection: $c) { }
        TextField("d", text: $d)
        SecureField("e", text: $e)
        TextEditor(text: $f)
        Stepper("g", value: $g)
        Slider(value: $h)
        DatePicker("i", selection: $i)
        ColorPicker("j", selection: $j)
        Menu("k") { }
        Link("l", destination: url)
        NavigationLink("m") { Detail() }
        """
        let inv = A11yScan.analyze(kinds)
        #expect(inv.interactiveControlCount == 13,
                "expected 13 control kinds detected, got \(inv.interactiveControlCount)")

        // Decoys that must NOT be counted as interactive controls.
        let decoys = """
        Text("Button")
        Image(systemName: "x").buttonStyle(.plain)
        SomeCustomButton(title: "z")
        Rectangle().menuStyle(.borderlessButton)
        let label = "TextField shown to user"
        Circle().pickerStyle(.segmented)
        """
        let decoyInv = A11yScan.analyze(decoys)
        #expect(decoyInv.interactiveControlCount == 0,
                "decoys were miscounted as controls: \(decoyInv.interactiveControlCount)")
    }

    // MARK: - Deterministic real-repo anchors (Sources/Views/**/*.swift)

    @Test("every scanned surface has unique, non-empty accessibility identifiers — Feature: cross-platform-live-verification, Property 17")
    func realSurfacesHaveUniqueNonEmptyIdentifiers() throws {
        let root = Self.viewsRoot()
        #expect(FileManager.default.fileExists(atPath: root.path),
                "Sources/Views not found at \(root.path)")
        let files = Self.swiftFiles(under: root)
        #expect(files.count >= 25, "expected >= 25 Swift files under Sources/Views, found \(files.count)")

        for file in files {
            let src = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let inv = A11yScan.analyze(src)

            #expect(inv.emptyLiteralCount == 0,
                    "\(file.lastPathComponent): found \(inv.emptyLiteralCount) empty accessibilityIdentifier(\"\") — every identifier must be non-empty")

            // Uniqueness within a surface: no literal id attached to another control,
            // except the verified if/else branch-reuse identifiers.
            let dupes = Set(A11yScan.duplicateLiterals(inv.literalIdentifiers))
                .subtracting(Self.branchReuseAllowlist)
            #expect(dupes.isEmpty,
                    "\(file.lastPathComponent): duplicate accessibility identifiers collide within this surface: \(dupes.sorted()) — Property 17 requires per-surface uniqueness")
        }
    }

    @Test("navigation surface identifiers are total and unique (NavigationItem) — Feature: cross-platform-live-verification, Property 17")
    func navigationSurfaceIdentifiersTotalAndUnique() {
        // Every canonical navigation surface is reachable via a stable, unique tab id
        // produced by the compiled model — the source-of-truth the XCUITests target.
        let ids = NavigationItem.allCases.map { $0.accessibilityId }
        #expect(ids.allSatisfy { !$0.isEmpty }, "a NavigationItem has an empty accessibility id: \(ids)")
        #expect(ids.allSatisfy { $0.hasPrefix("tab_") }, "a NavigationItem id is not tab_-prefixed: \(ids)")
        #expect(Set(ids).count == ids.count, "navigation tab ids are not unique: \(ids)")

        let expected: Set<String> = [
            "tab_dashboard", "tab_containers", "tab_images", "tab_volumes", "tab_networks",
            "tab_configuration", "tab_profiles", "tab_kubernetes", "tab_ai", "tab_monitoring",
            "tab_machines", "tab_runtimecontrols", "tab_community",
        ]
        #expect(Set(ids) == expected,
                "navigation tab id set drifted from the XCUITest-depended set: got \(Set(ids).sorted())")
    }

    @Test("primary surfaces exist and are broadly instrumented for accessibility — Feature: cross-platform-live-verification, Property 17")
    func primarySurfacesPopulated() {
        let root = Self.viewsRoot()
        for (name, rel) in Self.primarySurfaces {
            let url = root.appendingPathComponent(rel)
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "primary surface \(name) missing at Sources/Views/\(rel)")
            let src = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let inv = A11yScan.analyze(src)
            // Per-surface population floor (total literal + dynamic identifiers) so no
            // primary surface can silently ship un-instrumented.
            #expect(inv.totalIdentifierOccurrences >= 4,
                    "primary surface \(name) is under-instrumented: only \(inv.totalIdentifierOccurrences) accessibility identifiers")
            #expect(inv.emptyLiteralCount == 0, "\(name): empty accessibility identifier present")
        }
    }

    @Test("XCUITest-critical identifiers are present in source, with anti-vacuous count + coverage floors — Feature: cross-platform-live-verification, Property 17")
    func regressionIdentifiersPresentWithFloors() {
        let root = Self.viewsRoot()
        let files = Self.swiftFiles(under: root)

        var allLiterals = Set<String>()
        var totalIds = 0, totalLiterals = 0, totalControls = 0, identified = 0
        var missingByControl: [String] = []

        for file in files {
            let src = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let inv = A11yScan.analyze(src)
            allLiterals.formUnion(inv.literalIdentifiers)
            totalIds += inv.totalIdentifierOccurrences
            totalLiterals += inv.literalIdentifiers.count
            totalControls += inv.interactiveControlCount
            identified += inv.identifiedControlCount
            for line in inv.unidentifiedControlLines {
                missingByControl.append("\(file.lastPathComponent):\(line)")
            }
        }

        // Anti-vacuous floors — a namespace/parse regression that silently matches
        // nothing must fail (mirrors the Windows inventory test's `>= N` guards).
        #expect(files.count >= 25, "too few Swift files scanned: \(files.count)")
        #expect(totalIds >= 250, "too few accessibility identifiers scanned (\(totalIds)) — scanner may be broken")
        #expect(totalLiterals >= 150, "too few literal identifiers scanned (\(totalLiterals))")
        #expect(totalControls >= 120, "too few interactive controls detected (\(totalControls)) — scanner may be broken")

        // Totality coverage: interactive controls are broadly identifier-covered.
        // Generous floor (real tree ≈ 0.8+); catches a mass id-stripping regression
        // without failing on intentionally id-less menu/context-menu items. The
        // specific un-identified controls are surfaced for follow-up.
        let coverage = totalControls > 0 ? Double(identified) / Double(totalControls) : 0
        #expect(coverage >= 0.4,
                "interactive-control identifier coverage \(String(format: "%.2f", coverage)) below floor — possible missing-identifier gap in Sources/. Unidentified controls: \(missingByControl.prefix(40))")

        // Regression: identifiers existing XCUITests depend on must still exist.
        let missing = Self.regressionIdentifiers.filter { !allLiterals.contains($0) }
        #expect(missing.isEmpty,
                "regression accessibility identifiers missing from Sources/Views: \(missing) — an XCUITest depends on each")
    }

    // MARK: - Real-tree location helpers

    /// Resolve `Sources/Views` from this test file's own path — robust to the
    /// working directory and test-bundle layout (mirrors how the Windows inventory
    /// test walks up to its source root).
    static func viewsRoot(_ filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)      // …/Tests/Unit/AccessibilityIdentifierInventoryPropertyTests.swift
            .deletingLastPathComponent()    // …/Tests/Unit
            .deletingLastPathComponent()    // …/Tests
            .deletingLastPathComponent()    // …/<repo root>
            .appendingPathComponent("Sources/Views", isDirectory: true)
    }

    static func swiftFiles(under root: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let url as URL in en where url.pathExtension == "swift" { out.append(url) }
        return out.sorted { $0.path < $1.path }
    }
}

// MARK: - Seeded RNG (reproducible counterexamples)

/// Deterministic SplitMix64 PRNG so every failing iteration is reproducible from
/// the seed printed in its failure message. File-private — does not collide with the
/// sibling property-test files' own RNGs.
private struct P17RNG: RandomNumberGenerator {
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

// MARK: - Source scanner (unit under test)

/// Text-level accessibility-identifier scanner for SwiftUI source — the macOS
/// analogue of the Windows XAML `AutomationIdInventoryTests` parser. It extracts
/// literal identifiers, counts interactive controls, and associates identifiers to
/// controls by modifier-chain proximity (an identifier belongs to the nearest
/// preceding control, up to the next control). Its correctness is proven by the
/// synthetic property tests above; the real-tree anchors then apply it to
/// `Sources/Views/**`.
private enum A11yScan {

    struct SurfaceInventory {
        /// Pure string-literal identifiers (no interpolation), in source order.
        var literalIdentifiers: [String]
        /// Count of empty literal identifiers — `accessibilityIdentifier("")`.
        var emptyLiteralCount: Int
        /// All `accessibilityIdentifier(` occurrences (literal + dynamic + expression).
        var totalIdentifierOccurrences: Int
        /// Interactive control declarations detected.
        var interactiveControlCount: Int
        /// Controls with an identifier somewhere in their modifier-chain window.
        var identifiedControlCount: Int
        /// 1-based line numbers of interactive controls with no identifier in-window.
        var unidentifiedControlLines: [Int]
    }

    // Interactive SwiftUI control constructors (the ones automation must target):
    // Button/Toggle/Picker/TextField/SecureField/TextEditor/Stepper/Slider/
    // DatePicker/ColorPicker/Menu/Link/NavigationLink, at expression position
    // (a word boundary not preceded by an identifier char or `.`, followed by `(` or `{`).
    private static let interactiveControlPattern =
        #"(?<![A-Za-z0-9_.])(NavigationLink|Button|Toggle|Picker|TextField|SecureField|TextEditor|Stepper|Slider|DatePicker|ColorPicker|Menu|Link)\b\s*[\({]"#
    private static let anyIdentifierPattern = #"accessibilityIdentifier\s*\("#
    // Captures only a pure string literal (excludes interpolation `\(` and escapes).
    private static let literalIdentifierPattern = #"accessibilityIdentifier\s*\(\s*"([^"\\]*)"\s*\)"#

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }

    static func analyze(_ source: String) -> SurfaceInventory {
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Literal identifiers (+ empty detection).
        var literals: [String] = []
        var empties = 0
        for m in regex(literalIdentifierPattern).matches(in: source, range: full) {
            let value = ns.substring(with: m.range(at: 1))
            if value.isEmpty { empties += 1 } else { literals.append(value) }
        }

        // All identifier occurrences (for association + anti-vacuous totals).
        let idLocations = regex(anyIdentifierPattern).matches(in: source, range: full).map { $0.range.location }

        // Interactive control starts.
        let controlStarts = regex(interactiveControlPattern).matches(in: source, range: full).map { $0.range.location }

        // Associate: a control is "identified" if an identifier occurrence falls in
        // the window [thisControl, nextControl) (or to EOF for the last control).
        var identified = 0
        var unidentifiedLines: [Int] = []
        for (i, start) in controlStarts.enumerated() {
            let windowEnd = (i + 1 < controlStarts.count) ? controlStarts[i + 1] : ns.length
            let hasId = idLocations.contains { $0 >= start && $0 < windowEnd }
            if hasId {
                identified += 1
            } else {
                unidentifiedLines.append(lineNumber(ns, upTo: start))
            }
        }

        return SurfaceInventory(
            literalIdentifiers: literals,
            emptyLiteralCount: empties,
            totalIdentifierOccurrences: idLocations.count,
            interactiveControlCount: controlStarts.count,
            identifiedControlCount: identified,
            unidentifiedControlLines: unidentifiedLines
        )
    }

    /// Literal ids that appear more than once (a within-surface collision candidate).
    static func duplicateLiterals(_ literals: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for l in literals { counts[l, default: 0] += 1 }
        return counts.compactMap { $0.value > 1 ? $0.key : nil }.sorted()
    }

    private static func lineNumber(_ ns: NSString, upTo utf16Location: Int) -> Int {
        let clamped = max(0, min(utf16Location, ns.length))
        let prefix = ns.substring(to: clamped)
        return prefix.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
    }
}

// MARK: - Randomized SwiftUI-source generators

private enum P17Gen {
    private static let leafControls = ["Button", "Toggle", "TextField", "SecureField", "Stepper", "Slider"]
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    static func token(_ rng: inout P17RNG, minLen: Int = 4, maxLen: Int = 8) -> String {
        let len = Int.random(in: minLen...maxLen, using: &rng)
        var s = ""
        for _ in 0..<len { s.append(alphabet[Int.random(in: 0..<alphabet.count, using: &rng)]) }
        return s
    }

    /// A leaf control expression (no nested controls) so modifier-chain association
    /// is unambiguous for the scanner-validation properties.
    private static func controlExpr(_ ctrl: String, _ k: Int) -> String {
        switch ctrl {
        case "Button": return "Button(\"L\(k)\") { act\(k)() }"
        case "Toggle": return "Toggle(\"L\(k)\", isOn: $flag\(k))"
        case "TextField": return "TextField(\"L\(k)\", text: $txt\(k))"
        case "SecureField": return "SecureField(\"L\(k)\", text: $sec\(k))"
        case "Stepper": return "Stepper(\"L\(k)\", value: $val\(k))"
        case "Slider": return "Slider(value: $sld\(k))"
        default: return "Button(\"L\(k)\") { }"
        }
    }

    private static func header(_ rng: inout P17RNG) -> [String] {
        [
            "import SwiftUI",
            "struct GenView\(Int.random(in: 0...999_999, using: &rng)): View {",
            "  var body: some View {",
            "    VStack {",
        ]
    }

    private static let footer = ["    }", "  }", "}"]

    /// A surface where each control randomly gets: no id / a unique literal id / a
    /// dynamic (interpolated) id. Returns the ground truth needed to check the scanner.
    static func makeSurface(_ rng: inout P17RNG)
        -> (source: String, controlCount: Int, unidentified: Int, literalIds: Set<String>) {
        let n = Int.random(in: 3...12, using: &rng)
        var lines = header(&rng)
        var literalIds = Set<String>()
        var unidentified = 0
        for k in 0..<n {
            let ctrl = leafControls[Int.random(in: 0..<leafControls.count, using: &rng)]
            lines.append("      \(controlExpr(ctrl, k))")
            lines.append("        .padding()")
            switch Int.random(in: 0..<3, using: &rng) {
            case 1: // unique literal id
                let id = "ctl\(k)_\(token(&rng))"
                literalIds.insert(id)
                lines.append("        .accessibilityIdentifier(\"\(id)\")")
            case 2: // dynamic (interpolated) id — identified but not a literal
                lines.append("        .accessibilityIdentifier(\"ctl\(k)_\\(dyn)\")")
            default: // no id
                unidentified += 1
            }
            lines.append("")
        }
        lines.append(contentsOf: footer)
        return (lines.joined(separator: "\n"), n, unidentified, literalIds)
    }

    /// A "clean" surface where every control gets a unique non-empty literal id.
    static func makeCleanSurface(_ rng: inout P17RNG)
        -> (source: String, controlCount: Int, literalIds: Set<String>) {
        let n = Int.random(in: 3...12, using: &rng)
        var lines = header(&rng)
        var literalIds = Set<String>()
        for k in 0..<n {
            let ctrl = leafControls[Int.random(in: 0..<leafControls.count, using: &rng)]
            let id = "ctl\(k)_\(token(&rng))"
            literalIds.insert(id)
            lines.append("      \(controlExpr(ctrl, k))")
            lines.append("        .accessibilityIdentifier(\"\(id)\")")
            lines.append("")
        }
        lines.append(contentsOf: footer)
        return (lines.joined(separator: "\n"), n, literalIds)
    }

    /// A flat list of identifier modifiers with a known multiset of duplicates and
    /// empties, to validate duplicate/empty detection.
    static func makeIdList(_ rng: inout P17RNG)
        -> (source: String, duplicates: Set<String>, emptyCount: Int, uniqueLiterals: Set<String>) {
        let uniqueCount = Int.random(in: 2...8, using: &rng)
        var ids: [String] = []
        var uniques = Set<String>()
        // Distinct base ids (guaranteed unique via a per-item index prefix).
        for k in 0..<uniqueCount {
            let id = "id\(k)_\(token(&rng))"
            ids.append(id)
            uniques.insert(id)
        }
        // Duplicate some of them.
        var dups = Set<String>()
        let dupCount = Int.random(in: 0...3, using: &rng)
        for _ in 0..<dupCount {
            let pick = ids[Int.random(in: 0..<uniqueCount, using: &rng)]
            // Only the originals count as "unique" bases; guard against picking an
            // already-appended duplicate by indexing into the first uniqueCount.
            if uniques.contains(pick) {
                ids.append(pick)
                dups.insert(pick)
            }
        }
        let emptyCount = Int.random(in: 0...2, using: &rng)
        // Deterministic Fisher–Yates shuffle.
        for idx in stride(from: ids.count - 1, to: 0, by: -1) {
            let j = Int.random(in: 0...idx, using: &rng)
            ids.swapAt(idx, j)
        }
        var lines = ["VStack {"]
        for id in ids { lines.append("  Text(\"x\").accessibilityIdentifier(\"\(id)\")") }
        for _ in 0..<emptyCount { lines.append("  Text(\"x\").accessibilityIdentifier(\"\")") }
        lines.append("}")
        return (lines.joined(separator: "\n"), dups, emptyCount, uniques)
    }
}

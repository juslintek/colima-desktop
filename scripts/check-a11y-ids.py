#!/usr/bin/env python3
"""
Cross-frontend accessibility-identifier hardening gate (R7, task 12.4).

Enforces design **Property 17 — accessibility identifier totality + uniqueness**
(Validates: Requirements 5.7, 11.4) across ALL four Desktop_Frontends at once, by
scanning each frontend's REAL source for its native accessibility-identifier scheme:

    macOS   Sources/**/*.swift            .accessibilityIdentifier("literal")
                                          + NavigationItem.accessibilityId  (tab_*)
    Windows windows/{MainWindow,Views}/*.xaml  AutomationProperties.AutomationId="..."
    Linux   linux/src/**/*.rs             .set_widget_name("literal")  (+ AT-SPI labels)
    TUI     tui/internal/ui/tabs.go       Tabs []string  (deterministic surface list)

Per-frontend Property-17 coverage already exists as native tests
(AccessibilityIdentifierInventoryPropertyTests / AutomationIdInventoryTests / the Rust
+ teatest suites). "Cross-frontend" is inherently polyglot — a Swift XCTest target can
only compile+scan Swift — so this standalone scanner (mirroring how
`scripts/gen-truth-table.py` scans every frontend) is the piece that enforces the
property ACROSS frontends and can be invoked by `verify.sh` / the release-candidate gate.
It only READS frontend source; it never modifies any frontend or test target.

────────────────────────────────────────────────────────────────────────────────────
What "cross-frontend accessibility-identifier uniqueness" MEANS here
────────────────────────────────────────────────────────────────────────────────────
Naming schemes are deliberately platform-idiomatic and DIFFER per frontend (macOS
`tab_*`/`view_*`, Windows `Nav*`, Linux `view_*`, TUI surface names). So the property is
about SEMANTIC consistency, never byte-identical id strings across frontends (requiring
the latter would be a false violation). The gate enforces, from design Property 17 +
Requirement 11.4:

  A. TOTALITY (per frontend, anti-vacuous) — every frontend exposes a non-empty
     identifier inventory, contains NO empty-string identifiers, and meets a per-frontend
     count floor so a parse/namespace regression that silently matches nothing FAILS.

  B. WITHIN-SURFACE UNIQUENESS (per frontend, per surface) — within any one surface
     (source file), no accessibility identifier is attached to two different controls.
     A small, documented branch-reuse allowlist covers the same logical control rendered
     in mutually-exclusive if/else branches (mirrors the macOS task-8.3 allowlist).

  C. CROSS-FRONTEND CANONICAL-SURFACE CONSISTENCY — each of the 12 CORE canonical
     surfaces carries a navigation/surface identifier on EVERY frontend, i.e. all four
     frontends cover the same shared surface set (so automation can target "the Networks
     surface" on every platform). Extra per-frontend surfaces (macOS `community`, Windows
     `settings`, Linux `onboarding`) are allowed — they don't break the shared core.

  D. SHARED-ID NON-COLLISION — any surface-key identifier literal that appears in more
     than one frontend must denote the SAME canonical surface everywhere. `view_runtime`
     is intentionally shared by macOS + Linux (both = the runtime surface; recorded in the
     task-7.6 ledger entry); a shared surface-key mapping to two different surfaces is a
     real cross-frontend collision and FAILS.

The CLI exits non-zero on ANY violation (A–D) or on a vacuous pass (a floor not met), so
`verify.sh` / the RC gate can treat it as a hard gate. A real cross-frontend collision is
reported precisely as a finding — never silently passed.

Pure functions (extractors + checkers) are importable by the task-12.4 property test
(`scripts/tests/test_check_a11y_ids.py`) via importlib (this file's name is hyphenated),
exactly like `scripts/gen-truth-table.py` / `test_gen_truth_table.py`.

Usage:
    python3 scripts/check-a11y-ids.py            # scan real trees; exit 0 GREEN / 1 on violation
    python3 scripts/check-a11y-ids.py --report   # + per-surface / per-violation detail
    python3 scripts/check-a11y-ids.py --json      # machine-readable summary to stdout
    python3 scripts/check-a11y-ids.py --root DIR  # scan an alternate repo root (tests)
"""

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field

# ─── Paths & constants ───────────────────────────────────────────────────────

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FRONTENDS: tuple[str, ...] = ("macos", "windows", "linux", "tui")

# The 12 CORE canonical surfaces present on EVERY frontend's navigation (design
# §"Full-Functionality Exercise" surface table, intersected with what every frontend
# actually navigates to; Template is folded into Configuration on the frontends).
CORE_CANONICAL_SURFACES: tuple[str, ...] = (
    "dashboard",
    "containers",
    "images",
    "volumes",
    "networks",
    "configuration",
    "profiles",
    "kubernetes",
    "ai",
    "monitoring",
    "machines",
    "runtime",
)

# Normalization aliases → a canonical surface key. Applied AFTER prefix-stripping and
# lowercasing/space-underscore removal, so each frontend's idiomatic token maps home:
#   macos  tab_runtimecontrols → runtimecontrols → runtime ;  tab_ai → ai
#   win    NavAIWorkloads      → aiworkloads     → ai       ;  NavRuntime → runtime
#   linux  view_ai_workloads   → aiworkloads     → ai       ;  view_runtime → runtime
#   tui    "AI Workloads"      → aiworkloads     → ai       ;  "Runtime" → runtime
SURFACE_ALIASES: dict[str, str] = {
    "runtimecontrols": "runtime",
    "runtime": "runtime",
    "aiworkloads": "ai",
    "aiworkload": "ai",
    "ai": "ai",
    "config": "configuration",
    "configuration": "configuration",
}

# Anti-vacuous per-frontend floors. Set well below the measured real counts (macOS 366
# ids / 41 view files, Windows 300 / 16 XAML, Linux 71 widget-names / 13 view-roots,
# TUI 12 tabs) but high enough that a parser/namespace regression matching nothing FAILS.
FLOORS: dict[str, dict[str, int]] = {
    "macos": {"ids": 250, "files": 25, "surface_keys": 12},
    "windows": {"ids": 200, "files": 13, "surface_keys": 12},
    "linux": {"ids": 55, "files": 11, "surface_keys": 12},
    "tui": {"ids": 12, "files": 1, "surface_keys": 12},
}
# Global anti-vacuous floor across all frontends.
GLOBAL_ID_FLOOR = 650

# Verified legitimate within-surface duplicate identifiers: the SAME logical control
# rendered in mutually-exclusive if/else branches (only one is ever live), which is not a
# collision with "another control". Mirrors the macOS task-8.3 allowlist. Keyed by
# frontend so an allowance on one platform can't mask a real collision on another.
BRANCH_REUSE_ALLOWLIST: dict[str, set[str]] = {
    "macos": {"main_split_view", "label_template_validation"},
    "windows": set(),
    "linux": set(),
    "tui": set(),
}


class CheckError(RuntimeError):
    """Raised when an input the scanner requires is missing/unreadable."""


# ─── Data models ─────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class SurfaceInventory:
    """One scanned surface (source file) and the literal identifiers it declares."""

    frontend: str
    surface: str  # file path (relative) or logical surface name
    identifiers: tuple[str, ...]  # non-empty literal ids, in source order
    empty_count: int  # count of empty-string identifiers ("")


@dataclass
class FrontendInventory:
    """Everything scanned for one frontend."""

    frontend: str
    surfaces: list[SurfaceInventory] = field(default_factory=list)
    # canonical surface keys this frontend navigates to (normalized)
    surface_keys: set[str] = field(default_factory=set)
    # surface-key literal ids (id -> canonical surface) for the shared-id check
    surface_key_ids: dict[str, str] = field(default_factory=dict)

    @property
    def total_ids(self) -> int:
        return sum(len(s.identifiers) for s in self.surfaces)

    @property
    def total_empty(self) -> int:
        return sum(s.empty_count for s in self.surfaces)

    @property
    def file_count(self) -> int:
        return len(self.surfaces)

    def all_ids(self) -> list[str]:
        out: list[str] = []
        for s in self.surfaces:
            out.extend(s.identifiers)
        return out


@dataclass(frozen=True)
class Violation:
    frontend: str
    kind: str  # totality | empty | duplicate | missing-surface | shared-collision | floor
    surface: str
    detail: str


# ─── Pure extractors ─────────────────────────────────────────────────────────

_SWIFT_LITERAL = re.compile(r'\.accessibilityIdentifier\(\s*"([^"\\]*)"\s*\)')
_XAML_AUTOMATION_ID = re.compile(r'AutomationProperties\.AutomationId\s*=\s*"([^"]*)"')
_RUST_WIDGET_NAME = re.compile(r'\.set_widget_name\(\s*"([^"\\]*)"\s*\)')


def _split_literals(matches: list[str]) -> tuple[list[str], int]:
    """Partition raw regex captures into (non-empty ids, empty-string count)."""
    ids = [m for m in matches if m != ""]
    empties = sum(1 for m in matches if m == "")
    return ids, empties


def extract_swift_ids(text: str) -> tuple[list[str], int]:
    """macOS: literal `.accessibilityIdentifier("id")`. Interpolated ids (containing
    `\\(`) are excluded by the backslash-free capture — they are dynamic, not literal,
    exactly as the macOS task-8.3 scanner treats them."""
    return _split_literals(_SWIFT_LITERAL.findall(text))


def extract_xaml_ids(text: str) -> tuple[list[str], int]:
    """Windows: `AutomationProperties.AutomationId="id"`."""
    return _split_literals(_XAML_AUTOMATION_ID.findall(text))


def extract_rust_widget_names(text: str) -> tuple[list[str], int]:
    """Linux: literal `.set_widget_name("id")`. `&format!(...)` / variable args carry no
    leading string literal and are correctly excluded (they are dynamic ids)."""
    return _split_literals(_RUST_WIDGET_NAME.findall(text))


_TUI_TABS_BLOCK = re.compile(r"var\s+Tabs\s*=\s*\[\]string\{(.*?)\}", re.DOTALL)
_GO_STRING = re.compile(r'"([^"\\]*)"')


def extract_tui_tabs(text: str) -> list[str]:
    """TUI: the ordered `var Tabs = []string{ ... }` surface list from tabs.go."""
    m = _TUI_TABS_BLOCK.search(text)
    if not m:
        return []
    return [s for s in _GO_STRING.findall(m.group(1)) if s]


_SWIFT_ENUM_CASE = re.compile(r"^\s*case\s+([A-Za-z][A-Za-z0-9_,\s]*)$")
_SWIFT_SWITCH_CASE = re.compile(r"case\s+\.([A-Za-z0-9_]+)\s*:\s*return\s+\"([^\"]*)\"")


def _property_body(text: str, name: str) -> str:
    """Return the brace-matched body of `var <name>: String { ... }`, or "" if absent.

    Used to isolate the `accessibilityId` computed property so its `case .x: return "…"`
    arms are not confused with the `label`/`icon` properties' arms (which also switch on
    the same enum cases and would otherwise pollute the reconstruction).
    """
    m = re.search(r"var\s+" + re.escape(name) + r"\s*:\s*String\s*\{", text)
    if not m:
        return ""
    open_idx = m.end() - 1  # points at the opening '{'
    depth = 0
    for j in range(open_idx, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[open_idx + 1:j]
    return text[open_idx + 1:]


def reconstruct_navigation_ids(text: str) -> list[str]:
    """Reconstruct macOS `NavigationItem.accessibilityId` values from the model source.

    macOS navigation ids are COMPUTED (`"tab_\\(rawValue)"` with a couple of special
    cases), so they are not string literals in `Sources`. This reproduces exactly what
    the Swift compiler yields — the same set the macOS task-8.3 test asserts at runtime:

        id(case) = <special-cased literal if present> else "tab_" + <case name>

    ONLY the `accessibilityId` property's switch arms are honored (parsed from its
    brace-matched body, never the `label`/`icon` properties); the `default` branch
    produces `tab_<case>` for every remaining enum case.
    """
    # Enum case declarations: lines like `case dashboard, containers, images` (no colon).
    cases: list[str] = []
    for line in text.splitlines():
        if ":" in line or "." in line:
            continue  # skip switch cases (`case .x: ...`) and anything qualified
        m = _SWIFT_ENUM_CASE.match(line)
        if m:
            for name in m.group(1).split(","):
                name = name.strip()
                if name:
                    cases.append(name)
    # Special-cased accessibilityId arms only (`case .runtimeControls: return "tab_..."`).
    body = _property_body(text, "accessibilityId")
    special = {m.group(1): m.group(2) for m in _SWIFT_SWITCH_CASE.finditer(body)}
    return [special.get(case, f"tab_{case}") for case in cases]


def normalize_surface_key(token: str) -> str:
    """Map a raw per-frontend nav/surface token to a canonical surface key."""
    t = token.strip()
    for prefix in ("tab_", "view_", "Nav", "nav_"):
        if t.startswith(prefix):
            t = t[len(prefix):]
            break
    t = re.sub(r"[\s_\-]+", "", t).lower()
    return SURFACE_ALIASES.get(t, t)


# ─── Pure checkers ───────────────────────────────────────────────────────────


def duplicates(seq) -> list[str]:
    """Values appearing more than once, sorted."""
    counts: dict[str, int] = {}
    for x in seq:
        counts[x] = counts.get(x, 0) + 1
    return sorted(k for k, v in counts.items() if v > 1)


def check_within_surface_uniqueness(inv: FrontendInventory) -> list[Violation]:
    """B — no identifier attached to two different controls on the SAME surface."""
    allow = BRANCH_REUSE_ALLOWLIST.get(inv.frontend, set())
    out: list[Violation] = []
    for s in inv.surfaces:
        dups = set(duplicates(s.identifiers)) - allow
        if dups:
            out.append(
                Violation(
                    inv.frontend,
                    "duplicate",
                    s.surface,
                    f"duplicate identifiers on one surface: {sorted(dups)}",
                )
            )
    return out


def check_no_empty(inv: FrontendInventory) -> list[Violation]:
    """A — no empty-string identifiers."""
    out: list[Violation] = []
    for s in inv.surfaces:
        if s.empty_count:
            out.append(
                Violation(
                    inv.frontend,
                    "empty",
                    s.surface,
                    f"{s.empty_count} empty-string identifier(s)",
                )
            )
    return out


def check_floors(inv: FrontendInventory) -> list[Violation]:
    """A — anti-vacuous per-frontend floors."""
    floor = FLOORS[inv.frontend]
    out: list[Violation] = []
    if inv.total_ids < floor["ids"]:
        out.append(Violation(inv.frontend, "floor", "-",
                             f"only {inv.total_ids} identifiers (< floor {floor['ids']})"))
    if inv.file_count < floor["files"]:
        out.append(Violation(inv.frontend, "floor", "-",
                             f"only {inv.file_count} surfaces scanned (< floor {floor['files']})"))
    if len(inv.surface_keys) < floor["surface_keys"]:
        out.append(Violation(inv.frontend, "floor", "-",
                             f"only {len(inv.surface_keys)} canonical surface keys "
                             f"(< floor {floor['surface_keys']})"))
    return out


def check_cross_frontend_consistency(
    inventories: dict[str, FrontendInventory],
) -> list[Violation]:
    """C — every CORE canonical surface has a nav/surface id on EVERY frontend."""
    out: list[Violation] = []
    for fe in FRONTENDS:
        inv = inventories[fe]
        for surface in CORE_CANONICAL_SURFACES:
            if surface not in inv.surface_keys:
                out.append(
                    Violation(
                        fe,
                        "missing-surface",
                        surface,
                        f"canonical surface '{surface}' has no navigation identifier "
                        f"on {fe} (covered: {sorted(inv.surface_keys)})",
                    )
                )
    return out


def check_shared_id_consistency(
    inventories: dict[str, FrontendInventory],
) -> list[Violation]:
    """D — a surface-key id literal shared by >1 frontend must mean the SAME surface."""
    # id -> {frontend: canonical_surface}
    seen: dict[str, dict[str, str]] = {}
    for fe in FRONTENDS:
        for ident, surface in inventories[fe].surface_key_ids.items():
            seen.setdefault(ident, {})[fe] = surface
    out: list[Violation] = []
    for ident, per_fe in seen.items():
        if len(per_fe) < 2:
            continue  # not shared
        targets = set(per_fe.values())
        if len(targets) > 1:
            out.append(
                Violation(
                    "+".join(sorted(per_fe)),
                    "shared-collision",
                    ident,
                    f"shared surface-key '{ident}' denotes different surfaces across "
                    f"frontends: {per_fe}",
                )
            )
    return out


def shared_surface_key_ids(
    inventories: dict[str, FrontendInventory],
) -> dict[str, dict[str, str]]:
    """Surface-key ids present in >1 frontend (for the report)."""
    seen: dict[str, dict[str, str]] = {}
    for fe in FRONTENDS:
        for ident, surface in inventories[fe].surface_key_ids.items():
            seen.setdefault(ident, {})[fe] = surface
    return {k: v for k, v in seen.items() if len(v) > 1}


# ─── Scanners (IO) ───────────────────────────────────────────────────────────

_SKIP_DIRS = {".build", "bin", "obj", "target", "DerivedData", "node_modules", ".git"}


def _walk(root: str, exts: tuple[str, ...]) -> list[str]:
    out: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in _SKIP_DIRS]
        for name in filenames:
            if name.endswith(exts):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def scan_macos(root: str) -> FrontendInventory:
    src = os.path.join(root, "Sources")
    if not os.path.isdir(src):
        raise CheckError(f"macOS source not found: {src}")
    inv = FrontendInventory("macos")
    for path in _walk(src, (".swift",)):
        ids, empty = extract_swift_ids(_read(path))
        rel = os.path.relpath(path, root)
        if ids or empty:
            inv.surfaces.append(SurfaceInventory("macos", rel, tuple(ids), empty))
        # Surface-ROOT anchor literals shared cross-frontend (e.g. `view_runtime`, which
        # macOS intentionally shares with Linux — task-7.6 ledger). Only `view_*` roots
        # are surface anchors; in-view `tab_*` sub-tab literals (e.g. tab_k8s_pods) are
        # NOT navigation surfaces and are excluded from the surface-key set.
        for ident in ids:
            if ident.startswith("view_"):
                inv.surface_key_ids[ident] = normalize_surface_key(ident)
    # The canonical navigation surface set comes from the compiled NavigationItem model:
    # its `tab_*` ids are COMPUTED, so reconstruct them (Property-C coverage source).
    nav_model = os.path.join(root, "Sources", "Models", "NavigationItem.swift")
    if not os.path.exists(nav_model):
        raise CheckError(f"macOS navigation model not found: {nav_model}")
    nav_ids = reconstruct_navigation_ids(_read(nav_model))
    for nav_id in nav_ids:
        inv.surface_key_ids[nav_id] = normalize_surface_key(nav_id)
    # Coverage (Property C) is judged against the navigation surfaces only.
    inv.surface_keys = {normalize_surface_key(i) for i in nav_ids}
    return inv


def scan_windows(root: str) -> FrontendInventory:
    wroot = os.path.join(root, "windows")
    if not os.path.isdir(wroot):
        raise CheckError(f"Windows source not found: {wroot}")
    inv = FrontendInventory("windows")
    files = []
    main = os.path.join(wroot, "MainWindow.xaml")
    if os.path.exists(main):
        files.append(main)
    files.extend(_walk(os.path.join(wroot, "Views"), (".xaml",)))
    for path in files:
        ids, empty = extract_xaml_ids(_read(path))
        rel = os.path.relpath(path, root)
        inv.surfaces.append(SurfaceInventory("windows", rel, tuple(ids), empty))
    # Navigation surface keys come from the Nav* AutomationIds in the shell window.
    if os.path.exists(main):
        nav_ids, _ = extract_xaml_ids(_read(main))
        for ident in nav_ids:
            if ident.startswith("Nav") and len(ident) > 3 and ident[3].isupper():
                inv.surface_key_ids[ident] = normalize_surface_key(ident)
    inv.surface_keys = {normalize_surface_key(i) for i in inv.surface_key_ids}
    return inv


def scan_linux(root: str) -> FrontendInventory:
    lroot = os.path.join(root, "linux", "src")
    if not os.path.isdir(lroot):
        raise CheckError(f"Linux source not found: {lroot}")
    inv = FrontendInventory("linux")
    for path in _walk(lroot, (".rs",)):
        ids, empty = extract_rust_widget_names(_read(path))
        rel = os.path.relpath(path, root)
        if ids or empty:
            inv.surfaces.append(SurfaceInventory("linux", rel, tuple(ids), empty))
        for ident in ids:
            if ident.startswith("view_"):
                inv.surface_key_ids[ident] = normalize_surface_key(ident)
    inv.surface_keys = {normalize_surface_key(i) for i in inv.surface_key_ids}
    return inv


def scan_tui(root: str) -> FrontendInventory:
    tabs_go = os.path.join(root, "tui", "internal", "ui", "tabs.go")
    if not os.path.exists(tabs_go):
        raise CheckError(f"TUI tabs source not found: {tabs_go}")
    inv = FrontendInventory("tui")
    tabs = extract_tui_tabs(_read(tabs_go))
    rel = os.path.relpath(tabs_go, root)
    inv.surfaces.append(SurfaceInventory("tui", rel, tuple(tabs), 0))
    for name in tabs:
        inv.surface_key_ids[name] = normalize_surface_key(name)
    inv.surface_keys = {normalize_surface_key(n) for n in tabs}
    return inv


SCANNERS = {
    "macos": scan_macos,
    "windows": scan_windows,
    "linux": scan_linux,
    "tui": scan_tui,
}


# ─── Orchestration ───────────────────────────────────────────────────────────


@dataclass
class Report:
    inventories: dict[str, FrontendInventory]
    violations: list[Violation]

    @property
    def ok(self) -> bool:
        return not self.violations


def check_all(inventories: dict[str, FrontendInventory]) -> list[Violation]:
    """Run every Property-17 sub-check (A–D) and return all violations."""
    violations: list[Violation] = []
    for fe in FRONTENDS:
        inv = inventories[fe]
        violations += check_no_empty(inv)
        violations += check_within_surface_uniqueness(inv)
        violations += check_floors(inv)
    violations += check_cross_frontend_consistency(inventories)
    violations += check_shared_id_consistency(inventories)
    # Global anti-vacuous floor.
    grand = sum(inv.total_ids for inv in inventories.values())
    if grand < GLOBAL_ID_FLOOR:
        violations.append(Violation("all", "floor", "-",
                                   f"only {grand} identifiers total (< global floor {GLOBAL_ID_FLOOR})"))
    return violations


def run(root: str) -> Report:
    inventories = {fe: SCANNERS[fe](root) for fe in FRONTENDS}
    return Report(inventories, check_all(inventories))


def _summary_dict(report: Report) -> dict:
    return {
        "result": "GREEN" if report.ok else "NOT GREEN",
        "core_surfaces": list(CORE_CANONICAL_SURFACES),
        "frontends": {
            fe: {
                "identifiers": inv.total_ids,
                "surfaces_scanned": inv.file_count,
                "empty_identifiers": inv.total_empty,
                "canonical_surface_keys": sorted(inv.surface_keys),
                "extra_surface_keys": sorted(inv.surface_keys - set(CORE_CANONICAL_SURFACES)),
            }
            for fe, inv in report.inventories.items()
        },
        "shared_surface_key_ids": shared_surface_key_ids(report.inventories),
        "violations": [
            {"frontend": v.frontend, "kind": v.kind, "surface": v.surface, "detail": v.detail}
            for v in report.violations
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Cross-frontend accessibility-identifier hardening gate (Property 17, task 12.4)."
    )
    parser.add_argument("--root", default=ROOT, help="repo root to scan (default: this repo)")
    parser.add_argument("--report", action="store_true", help="print per-surface / per-violation detail")
    parser.add_argument("--json", action="store_true", help="emit a machine-readable JSON summary")
    args = parser.parse_args(argv)

    try:
        report = run(args.root)
    except CheckError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(_summary_dict(report), indent=2, sort_keys=True))
        return 0 if report.ok else 1

    print("== Cross-frontend accessibility-identifier gate (Property 17 / task 12.4) ==")
    print(f"-- core canonical surfaces (must be on every frontend): {len(CORE_CANONICAL_SURFACES)} --")
    for fe in FRONTENDS:
        inv = report.inventories[fe]
        extra = sorted(inv.surface_keys - set(CORE_CANONICAL_SURFACES))
        core_ok = set(CORE_CANONICAL_SURFACES).issubset(inv.surface_keys)
        print(
            f"  {fe:8s} ids={inv.total_ids:4d}  surfaces={inv.file_count:2d}  "
            f"empty={inv.total_empty}  canonical={len(inv.surface_keys):2d} "
            f"(core={'OK' if core_ok else 'MISSING'}{', +' + ','.join(extra) if extra else ''})"
        )

    shared = shared_surface_key_ids(report.inventories)
    if shared:
        print("-- shared cross-frontend surface-key ids (must denote one surface) --")
        for ident, per_fe in sorted(shared.items()):
            print(f"  {ident} -> {per_fe}")

    if args.report:
        print("-- per-surface detail --")
        for fe in FRONTENDS:
            for s in report.inventories[fe].surfaces:
                print(f"  [{fe}] {s.surface}: {len(s.identifiers)} ids, {s.empty_count} empty")

    print("=" * 62)
    if report.ok:
        print("RESULT: GREEN — totality + within-surface uniqueness + cross-frontend "
              "consistency + shared-id non-collision all hold")
        return 0
    print(f"RESULT: NOT GREEN — {len(report.violations)} violation(s):")
    for v in report.violations:
        print(f"  [{v.frontend}] {v.kind} @ {v.surface}: {v.detail}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

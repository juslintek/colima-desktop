#!/usr/bin/env python3
"""Property tests for the cross-frontend a11y-id gate — scripts/check-a11y-ids.py (task 12.4).

Feature: cross-platform-live-verification, Property 17

Design Property 17 — accessibility identifier totality + uniqueness (Validates:
Requirements 5.7, 11.4):
  "For all interactive controls across the Desktop_Frontends, each control has a non-empty
   accessibility identifier and no identifier collides with another control on the same
   surface."

This task generalizes Property 17 to a CROSS-FRONTEND hardening gate. The unit under test
is `scripts/check-a11y-ids.py` (hyphenated → loaded via importlib, exactly like
`test_gen_truth_table.py` loads the evidence generator). Its pure extractor + checker
functions are exercised over >=100 randomized iterations each by synthesizing faithful
per-frontend source and checking the gate's own invariants:

  * P17-A Totality / empty detection — for any synthesized Swift/XAML/Rust surface, the
    extractor returns exactly the literal identifiers present and exactly the empty-string
    count, and interpolated/dynamic ids are never counted as literals.

  * P17-B Within-surface uniqueness — `duplicates()` + `check_within_surface_uniqueness`
    flag exactly the identifiers reused on one surface (minus the branch-reuse allowlist),
    and a surface of unique ids yields NO violation (no false positives).

  * P17-C Cross-frontend canonical-surface consistency — four inventories that each cover
    the 12 core canonical surfaces (+ random extras) yield no violation; dropping any one
    core surface from any one frontend yields exactly that missing-surface violation.

  * P17-D Shared-id non-collision — a surface-key id shared by >1 frontend that denotes the
    same canonical surface yields no violation; the same id mapped to two different
    surfaces yields exactly one shared-collision violation.

  * Navigation reconstruction — `reconstruct_navigation_ids` reproduces the compiled
    `tab_*` ids from a synthesized `NavigationItem` enum and NEVER leaks the label/icon
    switch arms; `normalize_surface_key` maps every frontend's idiomatic token home.

Plus deterministic edge cases and a REAL-repo anchor that runs the actual gate over the
live trees and asserts it is GREEN with non-vacuous per-frontend counts.

Runnable directly (writes a summary log + JSON to /tmp, exits nonzero on any failure):

    python3 scripts/tests/test_check_a11y_ids.py            # 150 iters/property
    python3 scripts/tests/test_check_a11y_ids.py --iters 250 --seed 42

and under pytest (each test asserts zero counterexamples over >=100 iterations). It NEVER
modifies the checker or any frontend source: a checker invariant that fails to hold is
surfaced as a counterexample (a candidate real bug), never silently patched.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import random
import sys
import time
import traceback
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locations & checker import (hyphenated filename -> importlib by path)
# --------------------------------------------------------------------------- #
REPO_ROOT = Path(__file__).resolve().parents[2]
CHK_PATH = REPO_ROOT / "scripts" / "check-a11y-ids.py"

LOG_PATH = Path(os.environ.get("A11Y_LOG", "/tmp/check_a11y_ids_pbt.log"))
SUMMARY_PATH = Path(os.environ.get("A11Y_SUMMARY", "/tmp/check_a11y_ids_pbt_summary.json"))

_LOG_FH = None


def log(msg: str) -> None:
    line = str(msg)
    print(line, flush=True)
    global _LOG_FH
    if _LOG_FH is not None:
        _LOG_FH.write(line + "\n")
        _LOG_FH.flush()


def load_checker():
    spec = importlib.util.spec_from_file_location("check_a11y_ids", str(CHK_PATH))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHK = load_checker()

FRONTENDS = tuple(CHK.FRONTENDS)
CORE = tuple(CHK.CORE_CANONICAL_SURFACES)

ALPHA = "abcdefghijklmnopqrstuvwxyz0123456789"


def token(rng, lo=4, hi=9) -> str:
    return "".join(rng.choice(ALPHA) for _ in range(rng.randint(lo, hi)))


# --------------------------------------------------------------------------- #
# Result accumulator
# --------------------------------------------------------------------------- #
class PropResult:
    def __init__(self, name):
        self.name = name
        self.ran = 0
        self.passed = 0
        self.failures = []

    @property
    def failed(self):
        return len(self.failures)

    def record_pass(self):
        self.ran += 1
        self.passed += 1

    def record_fail(self, detail):
        self.ran += 1
        self.failures.append(detail)
        if len(self.failures) <= 5:
            log("  [COUNTEREXAMPLE] %s" % json.dumps(detail)[:700])


def _short_tb():
    return traceback.format_exc().strip().splitlines()[-1]


# --------------------------------------------------------------------------- #
# Synthesizers
# --------------------------------------------------------------------------- #
def gen_swift_surface(rng):
    """Synthesize SwiftUI-ish source; return (text, literal_ids_multiset, empty_count).

    Each control gets one of: a fresh unique literal id / a reused (duplicate) literal id /
    an interpolated id (must be EXCLUDED from literals) / an empty id / no id.
    """
    n = rng.randint(1, 14)
    lines = ["import SwiftUI", "struct V: View { var body: some View {", "  VStack {"]
    literals: list[str] = []
    empties = 0
    pool: list[str] = []
    for k in range(n):
        lines.append('    Button("b%d") { act%d() }' % (k, k))
        choice = rng.randint(0, 5)
        if choice in (0, 1) or not pool:  # fresh unique literal
            ident = "ctl%d_%s" % (k, token(rng))
            literals.append(ident)
            pool.append(ident)
            lines.append('      .accessibilityIdentifier("%s")' % ident)
        elif choice == 2:  # reuse an earlier literal -> duplicate
            ident = rng.choice(pool)
            literals.append(ident)
            lines.append('      .accessibilityIdentifier("%s")' % ident)
        elif choice == 3:  # interpolated (dynamic) -> NOT a literal
            lines.append('      .accessibilityIdentifier("ctl%d_\\(dyn)")' % k)
        elif choice == 4:  # empty
            empties += 1
            lines.append('      .accessibilityIdentifier("")')
        # choice == 5: no identifier
    lines += ["  }", "} }"]
    return "\n".join(lines), literals, empties


def gen_xaml_surface(rng):
    n = rng.randint(1, 14)
    lines = ['<Page xmlns="x">', "  <StackPanel>"]
    literals: list[str] = []
    empties = 0
    pool: list[str] = []
    for k in range(n):
        choice = rng.randint(0, 3)
        if choice in (0, 1) or not pool:
            ident = "Ctl%d%s" % (k, token(rng))
            literals.append(ident)
            pool.append(ident)
            lines.append('    <Button AutomationProperties.AutomationId="%s" />' % ident)
        elif choice == 2:
            ident = rng.choice(pool)
            literals.append(ident)
            lines.append('    <TextBox AutomationProperties.AutomationId="%s" />' % ident)
        else:
            empties += 1
            lines.append('    <Button AutomationProperties.AutomationId="" />')
    lines += ["  </StackPanel>", "</Page>"]
    return "\n".join(lines), literals, empties


def gen_rust_surface(rng):
    n = rng.randint(1, 14)
    lines = ["pub fn build() {"]
    literals: list[str] = []
    empties = 0
    pool: list[str] = []
    for k in range(n):
        choice = rng.randint(0, 4)
        if choice in (0, 1) or not pool:
            ident = "w%d_%s" % (k, token(rng))
            literals.append(ident)
            pool.append(ident)
            lines.append('    b%d.set_widget_name("%s");' % (k, ident))
        elif choice == 2:
            ident = rng.choice(pool)
            literals.append(ident)
            lines.append('    b%d.set_widget_name("%s");' % (k, ident))
        elif choice == 3:  # format!/dynamic -> excluded
            lines.append('    b%d.set_widget_name(&format!("{prefix}_%d"));' % (k, k))
        else:  # empty
            empties += 1
            lines.append('    b%d.set_widget_name("");' % k)
    lines += ["}"]
    return "\n".join(lines), literals, empties


def gen_navigation_item(rng):
    """Synthesize a NavigationItem-shaped enum; return (text, expected_tab_ids).

    Includes label + icon + accessibilityId properties that ALL switch on the cases, to
    prove reconstruct_navigation_ids reads ONLY the accessibilityId arms.
    """
    base = ["dashboard", "containers", "images", "volumes", "networks",
            "configuration", "profiles", "kubernetes", "ai", "monitoring"]
    rng.shuffle(base)
    cases = base[: rng.randint(3, len(base))]
    # a couple of camelCase cases that get special-cased in accessibilityId
    specials = {}
    if rng.random() < 0.8:
        cases.append("runtimeControls")
        specials["runtimeControls"] = "tab_runtimecontrols"
    if rng.random() < 0.6:
        cases.append("machines")
        specials["machines"] = "tab_machines"
    expected = [specials.get(c, "tab_%s" % c) for c in cases]

    lines = ["import SwiftUI", "enum NavigationItem: String, CaseIterable {"]
    # split case declarations across 1-3 lines
    i = 0
    while i < len(cases):
        grp = cases[i:i + rng.randint(1, 4)]
        lines.append("    case " + ", ".join(grp))
        i += len(grp)
    lines.append("    var id: String { rawValue }")
    # label property (decoy switch arms)
    lines.append("    var label: String {")
    lines.append("        switch self {")
    for c in cases:
        lines.append('        case .%s: return "Label %s"' % (c, c))
    lines.append("        }")
    lines.append("    }")
    # icon property (decoy switch arms — SF Symbol-like names)
    lines.append("    var icon: String {")
    lines.append("        switch self {")
    for c in cases:
        lines.append('        case .%s: return "%s.icon"' % (c, token(rng)))
    lines.append("        }")
    lines.append("    }")
    # accessibilityId property (the ONLY arms reconstruct should read)
    lines.append("    var accessibilityId: String {")
    lines.append("        switch self {")
    for c, ident in specials.items():
        lines.append('        case .%s: return "%s"' % (c, ident))
    lines.append('        default: return "tab_\\(rawValue)"')
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines), expected


def make_inventory(frontend, surface_keys, surface_key_ids=None, surfaces=None):
    inv = CHK.FrontendInventory(frontend)
    inv.surface_keys = set(surface_keys)
    inv.surface_key_ids = dict(surface_key_ids or {})
    inv.surfaces = list(surfaces or [])
    return inv


# --------------------------------------------------------------------------- #
# P17-A — totality / empty detection / literal fidelity
# --------------------------------------------------------------------------- #
def run_property_17a(seed_rng, iters):
    r = PropResult("Property 17-A (totality + literal/empty extractor fidelity)")
    extractors = [
        (gen_swift_surface, CHK.extract_swift_ids),
        (gen_xaml_surface, CHK.extract_xaml_ids),
        (gen_rust_surface, CHK.extract_rust_widget_names),
    ]
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            gen, extract = rng.choice(extractors)
            text, expect_literals, expect_empty = gen(rng)
            ids, empty = extract(text)
            ctx = "iter_seed=%d gen=%s\n%s" % (iseed, gen.__name__, text)
            assert sorted(ids) == sorted(expect_literals), \
                "literal multiset mismatch: got %r want %r — %s" % (sorted(ids), sorted(expect_literals), ctx)
            assert empty == expect_empty, \
                "empty count mismatch: got %d want %d — %s" % (empty, expect_empty, ctx)
            # no literal may be empty (empties are counted separately, never in ids)
            assert all(i != "" for i in ids), "empty string leaked into literal ids — %s" % ctx
            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# P17-B — within-surface uniqueness (+ no false positives)
# --------------------------------------------------------------------------- #
def run_property_17b(seed_rng, iters):
    r = PropResult("Property 17-B (within-surface uniqueness)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            text, literals, _ = gen_swift_surface(rng)
            ids, _ = CHK.extract_swift_ids(text)
            # duplicates() must equal the true set of reused literals.
            true_dups = sorted({x for x in literals if literals.count(x) > 1})
            assert CHK.duplicates(ids) == true_dups, \
                "duplicates() mismatch: got %r want %r" % (CHK.duplicates(ids), true_dups)

            # check_within_surface_uniqueness on a one-surface inventory:
            surf = CHK.SurfaceInventory("macos", "S.swift", tuple(ids), 0)
            inv = make_inventory("macos", set(), surfaces=[surf])
            vio = CHK.check_within_surface_uniqueness(inv)
            if true_dups:
                assert len(vio) == 1 and vio[0].kind == "duplicate", \
                    "expected 1 duplicate violation, got %r" % vio
            else:
                assert vio == [], "false-positive duplicate on unique surface: %r" % vio

            # allowlist suppresses exactly the allowlisted id (branch-reuse).
            if true_dups:
                allow_id = true_dups[0]
                orig = CHK.BRANCH_REUSE_ALLOWLIST.get("macos", set())
                CHK.BRANCH_REUSE_ALLOWLIST["macos"] = set(orig) | {allow_id}
                try:
                    vio2 = CHK.check_within_surface_uniqueness(inv)
                    remaining = set(true_dups) - {allow_id}
                    if remaining:
                        assert vio2 and vio2[0].kind == "duplicate"
                    else:
                        assert vio2 == [], "allowlisted duplicate still flagged: %r" % vio2
                finally:
                    CHK.BRANCH_REUSE_ALLOWLIST["macos"] = orig
            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# P17-C — cross-frontend canonical-surface consistency
# --------------------------------------------------------------------------- #
def run_property_17c(seed_rng, iters):
    r = PropResult("Property 17-C (cross-frontend canonical-surface consistency)")
    extras_pool = ["community", "settings", "onboarding", "welcome", "about"]
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            invs = {}
            for fe in FRONTENDS:
                extras = set(rng.sample(extras_pool, rng.randint(0, len(extras_pool))))
                invs[fe] = make_inventory(fe, set(CORE) | extras)
            # Full coverage -> no consistency violation.
            assert CHK.check_cross_frontend_consistency(invs) == [], \
                "false positive: full core coverage flagged"

            # Drop one core surface from one frontend -> exactly that violation.
            victim_fe = rng.choice(FRONTENDS)
            victim_surface = rng.choice(CORE)
            invs[victim_fe].surface_keys.discard(victim_surface)
            vio = CHK.check_cross_frontend_consistency(invs)
            assert len(vio) == 1, "expected exactly 1 missing-surface violation, got %d: %r" % (len(vio), vio)
            v = vio[0]
            assert v.kind == "missing-surface" and v.frontend == victim_fe and v.surface == victim_surface, \
                "wrong violation: %r (want %s/%s)" % (v, victim_fe, victim_surface)
            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# P17-D — shared-id non-collision
# --------------------------------------------------------------------------- #
def run_property_17d(seed_rng, iters):
    r = PropResult("Property 17-D (shared surface-key non-collision)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            # Each frontend gets some private surface-key ids + a common shared id.
            shared_id = "view_%s" % token(rng)
            shared_surface = rng.choice(CORE)
            fes = rng.sample(list(FRONTENDS), rng.randint(2, 4))
            invs = {}
            for fe in FRONTENDS:
                skids = {("k_%s_%s" % (fe, token(rng))): rng.choice(CORE) for _ in range(rng.randint(0, 3))}
                invs[fe] = make_inventory(fe, set(CORE), surface_key_ids=skids)
            # consistent: same surface everywhere it's shared -> no violation
            for fe in fes:
                invs[fe].surface_key_ids[shared_id] = shared_surface
            assert CHK.check_shared_id_consistency(invs) == [], \
                "false positive: consistent shared id flagged"

            # collision: map the shared id to a DIFFERENT surface on one frontend
            other = rng.choice([s for s in CORE if s != shared_surface])
            invs[fes[0]].surface_key_ids[shared_id] = other
            vio = CHK.check_shared_id_consistency(invs)
            assert len(vio) == 1 and vio[0].kind == "shared-collision" and vio[0].surface == shared_id, \
                "expected 1 shared-collision for %s, got %r" % (shared_id, vio)
            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# P17-E — navigation reconstruction + normalization
# --------------------------------------------------------------------------- #
def run_property_17e(seed_rng, iters):
    r = PropResult("Property 17-E (navigation reconstruction ignores label/icon arms)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            text, expected = gen_navigation_item(rng)
            got = CHK.reconstruct_navigation_ids(text)
            ctx = "iter_seed=%d\n%s" % (iseed, text)
            assert got == expected, "nav id reconstruction mismatch: got %r want %r — %s" % (got, expected, ctx)
            # every reconstructed id is tab_-prefixed and normalizes into a surface key
            for ident in got:
                assert ident.startswith("tab_"), "nav id not tab_-prefixed: %s" % ident
                assert CHK.normalize_surface_key(ident), "empty normalization for %s" % ident
            # normalization aliases: the idiomatic tokens all map home
            assert CHK.normalize_surface_key("tab_runtimecontrols") == "runtime"
            assert CHK.normalize_surface_key("NavRuntime") == "runtime"
            assert CHK.normalize_surface_key("view_runtime") == "runtime"
            assert CHK.normalize_surface_key("Runtime") == "runtime"
            assert CHK.normalize_surface_key("NavAIWorkloads") == "ai"
            assert CHK.normalize_surface_key("view_ai_workloads") == "ai"
            assert CHK.normalize_surface_key("AI Workloads") == "ai"
            assert CHK.normalize_surface_key("tab_dashboard") == "dashboard"
            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Deterministic edge cases + REAL-repo anchor
# --------------------------------------------------------------------------- #
def run_deterministic_checks():
    results = []

    def check(name, fn):
        try:
            fn()
            results.append((name, True, "ok"))
        except Exception as e:
            results.append((name, False, "%r | %s" % (e, _short_tb())))

    def swift_excludes_interpolated():
        src = '.accessibilityIdentifier("btn_x")\n.accessibilityIdentifier("btn_\\(name)")\n.accessibilityIdentifier("")'
        ids, empty = CHK.extract_swift_ids(src)
        assert ids == ["btn_x"], ids
        assert empty == 1, empty

    check("swift extractor: literal only, excludes interpolated, counts empty", swift_excludes_interpolated)

    def rust_excludes_format():
        src = 'a.set_widget_name("view_x");\nb.set_widget_name(&format!("{p}_y"));\nc.set_widget_name(var);'
        ids, empty = CHK.extract_rust_widget_names(src)
        assert ids == ["view_x"], ids
        assert empty == 0, empty

    check("rust extractor: literal only, excludes format!/var", rust_excludes_format)

    def tui_tabs_parsed_in_order():
        src = 'var Tabs = []string{\n"Dashboard",\n"Containers",\n"Monitoring",\n}'
        assert CHK.extract_tui_tabs(src) == ["Dashboard", "Containers", "Monitoring"]

    check("tui extractor: Tabs slice parsed in order", tui_tabs_parsed_in_order)

    def nav_reconstruct_real_shape():
        text = (
            "enum NavigationItem: String, CaseIterable {\n"
            "    case dashboard, containers, ai\n"
            "    case machines, runtimeControls, community\n"
            "    var label: String { switch self {\n"
            '        case .dashboard: return "Dashboard"\n'
            '        case .runtimeControls: return "Runtime Controls"\n'
            "    } }\n"
            "    var icon: String { switch self {\n"
            '        case .dashboard: return "gauge"\n'
            '        case .runtimeControls: return "gearshape.2"\n'
            "    } }\n"
            "    var accessibilityId: String { switch self {\n"
            '        case .runtimeControls: return "tab_runtimecontrols"\n'
            '        case .machines: return "tab_machines"\n'
            '        default: return "tab_\\(rawValue)"\n'
            "    } }\n"
            "}\n"
        )
        got = CHK.reconstruct_navigation_ids(text)
        assert got == ["tab_dashboard", "tab_containers", "tab_ai",
                       "tab_machines", "tab_runtimecontrols", "tab_community"], got
        # must NOT contain any icon/label value
        assert "gauge" not in got and "Dashboard" not in got

    check("nav reconstruct: ignores label/icon arms, honors accessibilityId only", nav_reconstruct_real_shape)

    def real_repo_anchor():
        if not CHK_PATH.exists():
            raise AssertionError("SKIP: checker missing")
        report = CHK.run(str(REPO_ROOT))
        # Property 17 on real trees: GREEN, non-vacuous per-frontend counts, core covered.
        assert report.ok, "real-repo gate NOT GREEN: %r" % [
            (v.frontend, v.kind, v.surface, v.detail) for v in report.violations
        ]
        inv = report.inventories
        assert inv["macos"].total_ids >= 250, "macOS ids=%d" % inv["macos"].total_ids
        assert inv["windows"].total_ids >= 200, "windows ids=%d" % inv["windows"].total_ids
        assert inv["linux"].total_ids >= 55, "linux ids=%d" % inv["linux"].total_ids
        assert inv["tui"].total_ids >= 12, "tui ids=%d" % inv["tui"].total_ids
        for fe in FRONTENDS:
            assert set(CORE).issubset(inv[fe].surface_keys), \
                "%s missing core surfaces: %r" % (fe, set(CORE) - inv[fe].surface_keys)
            assert inv[fe].total_empty == 0, "%s has empty identifiers" % fe
        # the intentional shared surface-key (view_runtime on macOS + Linux) is consistent
        shared = CHK.shared_surface_key_ids(inv)
        assert "view_runtime" in shared, "expected view_runtime shared macOS/Linux, got %r" % shared
        assert set(shared["view_runtime"].values()) == {"runtime"}, shared["view_runtime"]

    check("real-repo anchor: gate GREEN + non-vacuous counts + core covered on every frontend", real_repo_anchor)

    return results


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run_all(iters, seed):
    global _LOG_FH
    _LOG_FH = open(LOG_PATH, "w")
    log("START check-a11y-ids PBT  seed=%d iters=%d  checker=%s" % (seed, iters, CHK_PATH))
    log("Feature: cross-platform-live-verification (Property 17 — cross-frontend a11y-id gate)")
    log("FRONTENDS=%r  CORE_SURFACES=%r" % (FRONTENDS, CORE))

    if not CHK_PATH.exists():
        log("FATAL: checker not found at %s" % CHK_PATH)
        return 1

    det = run_deterministic_checks()
    det_failed = [d for d in det if not d[1]]
    for name, ok, detail in det:
        log("  [det] %-62s %s%s" % (name, "OK" if ok else "FAIL", "" if ok else "  (%s)" % detail))
    log("Deterministic checks: %d/%d passed" % (len(det) - len(det_failed), len(det)))

    seed_rng = random.Random(seed)
    results = [
        run_property_17a(seed_rng, iters),
        run_property_17b(seed_rng, iters),
        run_property_17c(seed_rng, iters),
        run_property_17d(seed_rng, iters),
        run_property_17e(seed_rng, iters),
    ]
    for r in results:
        log("  %-58s ran=%d passed=%d failed=%d" % (r.name, r.ran, r.passed, r.failed))

    total_failed = len(det_failed) + sum(r.failed for r in results)
    summary = {
        "seed": seed,
        "iters_per_property": iters,
        "deterministic": {"total": len(det), "failed": len(det_failed),
                          "failures": [d[0] for d in det_failed]},
        "properties": [
            {"name": r.name, "ran": r.ran, "passed": r.passed, "failed": r.failed,
             "counterexamples": r.failures[:5]}
            for r in results
        ],
        "overall": "PASS" if total_failed == 0 else "FAIL",
    }
    with open(SUMMARY_PATH, "w") as fh:
        json.dump(summary, fh, indent=2)
    log("DONE overall=%s total_failures=%d  summary=%s" % (summary["overall"], total_failed, SUMMARY_PATH))
    _LOG_FH.close()
    return 0 if total_failed == 0 else 1


# --------------------------------------------------------------------------- #
# pytest entry points (min 100 iterations enforced)
# --------------------------------------------------------------------------- #
_PYTEST_ITERS = int(os.environ.get("A11Y_ITERS", "150"))
_PYTEST_SEED = int(os.environ.get("A11Y_SEED", "1704"))


def test_property_17a_totality_and_extractor_fidelity():
    """Feature: cross-platform-live-verification, Property 17."""
    r = run_property_17a(random.Random(_PYTEST_SEED), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "totality counterexamples: %r" % r.failures[:5]


def test_property_17b_within_surface_uniqueness():
    """Feature: cross-platform-live-verification, Property 17."""
    r = run_property_17b(random.Random(_PYTEST_SEED + 1), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "uniqueness counterexamples: %r" % r.failures[:5]


def test_property_17c_cross_frontend_consistency():
    """Feature: cross-platform-live-verification, Property 17."""
    r = run_property_17c(random.Random(_PYTEST_SEED + 2), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "consistency counterexamples: %r" % r.failures[:5]


def test_property_17d_shared_id_non_collision():
    """Feature: cross-platform-live-verification, Property 17."""
    r = run_property_17d(random.Random(_PYTEST_SEED + 3), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "shared-id counterexamples: %r" % r.failures[:5]


def test_property_17e_navigation_reconstruction():
    """Feature: cross-platform-live-verification, Property 17."""
    r = run_property_17e(random.Random(_PYTEST_SEED + 4), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "nav-reconstruction counterexamples: %r" % r.failures[:5]


def test_deterministic_edge_cases_and_real_repo_anchor():
    det = run_deterministic_checks()
    failed = [(d[0], d[2]) for d in det if not d[1]]
    assert not failed, "deterministic/real-repo failures: %r" % failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Property tests for scripts/check-a11y-ids.py (Property 17)")
    ap.add_argument("--iters", type=int, default=150, help="iterations per property (min 100 enforced)")
    ap.add_argument("--seed", type=int, default=int(os.environ.get("A11Y_SEED", str(int(time.time())))))
    args = ap.parse_args()
    sys.exit(run_all(max(100, args.iters), args.seed))


if __name__ == "__main__":
    main()

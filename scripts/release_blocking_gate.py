#!/usr/bin/env python3
"""
release_blocking_gate.py -- the P0/P1 RELEASE-BLOCKING gate (R8 / task 13.4, Requirement 12.5).

Requirement 12.5: "IF an open defect carries priority P0 or P1, THEN THE Release_Pipeline SHALL
block the v1.0.0 tag." Design Property 22: "For any set of open defects, the release gate blocks the
v1.0.0 tag IFF the set contains at least one defect with priority P0 or P1."

This gate is COMPLEMENTARY to the release-candidate gate (scripts/rc-gate.sh, task 12.5): the RC gate
enforces build/test/coverage/security/perf/a11y green; THIS gate enforces "no open P0/P1 defect".
BOTH must pass to ship (task 13.6).

DEFECT SOURCE (machine-readable):
  * Primary: a curated registry JSON (default docs/release-defects.json) -- a top-level list of
    defects, or an object with a "defects" list. Each defect carries at least {id, title, priority,
    status}. See that file's "_description"/"schema" for the format.
  * Auto: docs/sbom/vuln-summary.json (task 12.2) -- every CRITICAL finding is auto-treated as an
    open P0 defect and every HIGH as an open P1, so a future critical/high CVE auto-blocks even if
    nobody hand-adds it to the registry. Skippable with --no-vuln.

BLOCK RULE (derived, never trusts a hand-set boolean): a defect blocks IFF
  normalize_priority(priority) in {P0, P1}  AND  is_open(status).
Priority synonyms (case-insensitive): critical/blocker->P0, high->P1, medium/moderate->P2,
low/unspecified/none/trivial/info->P3. A defect is OPEN unless its status is a known closed status
(resolved|closed|fixed|done|wontfix|deferred|duplicate|invalid|not_applicable|verified);
unknown/missing status => OPEN (fail-closed, so a mis-typed status never hides a P0).

EXIT CODES:
  0  PASS  -- zero open P0/P1 defects; the release may proceed (defect-gate-wise).
  1  BLOCK -- at least one open P0/P1 defect; the release is blocked. Blocking defects are printed.
  2  ERROR -- usage error, or the defect source is missing/unreadable/malformed (FAIL-CLOSED: a
              broken defect source never counts as "pass").

USAGE
  scripts/release_blocking_gate.py                      # check docs/release-defects.json (+ vuln summary)
  scripts/release_blocking_gate.py --registry PATH      # check an explicit registry (used by tests)
  scripts/release_blocking_gate.py --no-vuln            # registry only (skip vuln-summary auto-ingest)
  scripts/release_blocking_gate.py --vuln-summary PATH  # explicit vuln summary
  scripts/release_blocking_gate.py --list               # print every defect + classification, exit 0
  scripts/release_blocking_gate.py --format json        # machine-readable verdict on stdout
  scripts/release_blocking_gate.py --selftest           # prove the block-iff-P0/P1 logic, exit 0/1
  scripts/release_blocking_gate.py -h | --help

Env fallbacks (flags win): RELEASE_DEFECTS_FILE, RELEASE_VULN_SUMMARY.

The pure functions (load_registry / normalize_priority / is_open / collect_defects /
blocking_defects / evaluate) are import-safe so the property test (task 13.5, Property 22) can drive
them directly. No network, no wall-clock in the verdict -> deterministic.
"""

import argparse
import json
import os
import sys

# ---- taxonomy -----------------------------------------------------------------------------------

BLOCKING_PRIORITIES = ("P0", "P1")
ALL_PRIORITIES = ("P0", "P1", "P2", "P3")

# priority synonyms -> canonical bucket (checked case-insensitively)
_PRIORITY_SYNONYMS = {
    "p0": "P0", "critical": "P0", "crit": "P0", "blocker": "P0", "sev0": "P0", "s0": "P0",
    "p1": "P1", "high": "P1", "sev1": "P1", "s1": "P1", "major": "P1",
    "p2": "P2", "medium": "P2", "moderate": "P2", "med": "P2", "sev2": "P2", "s2": "P2", "normal": "P2",
    "p3": "P3", "low": "P3", "minor": "P3", "unspecified": "P3", "none": "P3",
    "trivial": "P3", "info": "P3", "informational": "P3", "sev3": "P3", "s3": "P3",
}

# statuses that mean the defect is CLOSED (not block-eligible). Anything else => OPEN (fail-closed).
_CLOSED_STATUSES = {
    "resolved", "closed", "fixed", "done", "complete", "completed",
    "wontfix", "won't fix", "wont-fix", "deferred", "duplicate", "dup",
    "invalid", "not_applicable", "not-applicable", "na", "n/a", "verified", "released",
}


class GateError(Exception):
    """Raised when a defect source cannot be read/parsed (fail-closed -> exit 2)."""


def normalize_priority(raw):
    """Map an arbitrary priority label to P0..P3, or None if unrecognized.

    Unrecognized priorities return None (NOT block-eligible) -- the block rule only fires on an
    explicit P0/P1 (or a recognized synonym), so noise never fabricates a blocker.
    """
    if raw is None:
        return None
    key = str(raw).strip().lower()
    if not key:
        return None
    return _PRIORITY_SYNONYMS.get(key)


def is_open(status):
    """True if the defect is OPEN (block-eligible). Fail-closed: unknown/missing status => open."""
    if status is None:
        return True
    key = str(status).strip().lower()
    if not key:
        return True
    return key not in _CLOSED_STATUSES


def _blocks(defect):
    """A defect blocks IFF its normalized priority is P0/P1 AND it is open."""
    return normalize_priority(defect.get("priority")) in BLOCKING_PRIORITIES and is_open(
        defect.get("status")
    )


def load_registry(path):
    """Load the defect registry. Returns a list of defect dicts.

    Accepts either a top-level JSON list, or an object with a "defects" list. Raises GateError on a
    missing file, invalid JSON, or a wrong shape (fail-closed).
    """
    if not os.path.exists(path):
        raise GateError("defect registry not found: %s" % path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise GateError("defect registry unreadable (%s): %s" % (path, exc))
    if isinstance(data, list):
        defects = data
    elif isinstance(data, dict):
        defects = data.get("defects", [])
    else:
        raise GateError("defect registry must be a list or an object with 'defects': %s" % path)
    if not isinstance(defects, list):
        raise GateError("'defects' must be a list in %s" % path)
    out = []
    for i, d in enumerate(defects):
        if not isinstance(d, dict):
            raise GateError("defect #%d is not an object in %s" % (i, path))
        out.append(d)
    return out


def vuln_derived_defects(vuln_summary_path):
    """Auto-derive P0/P1 defects from the committed vulnerability summary (task 12.2).

    Each CRITICAL finding -> a synthetic open P0 defect; each HIGH -> a synthetic open P1. A missing
    summary yields [] (the vuln source is optional / may not have been generated yet). A present but
    malformed summary raises GateError (fail-closed) so a broken source is never silently ignored.
    """
    if not vuln_summary_path or not os.path.exists(vuln_summary_path):
        return []
    try:
        with open(vuln_summary_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise GateError("vuln summary unreadable (%s): %s" % (vuln_summary_path, exc))
    totals = (data or {}).get("severity_totals", {})
    try:
        crit = int(totals.get("critical", 0) or 0)
        high = int(totals.get("high", 0) or 0)
    except (TypeError, ValueError) as exc:
        raise GateError("vuln summary severity_totals malformed (%s): %s" % (vuln_summary_path, exc))
    out = []
    if crit > 0:
        out.append({
            "id": "VULN-AUTO-CRITICAL",
            "title": "%d known CRITICAL vulnerability(ies) (auto-derived from vuln-summary.json)" % crit,
            "priority": "P0", "severity": "critical", "status": "open",
            "source": vuln_summary_path, "component": "dependencies",
        })
    if high > 0:
        out.append({
            "id": "VULN-AUTO-HIGH",
            "title": "%d known HIGH vulnerability(ies) (auto-derived from vuln-summary.json)" % high,
            "priority": "P1", "severity": "high", "status": "open",
            "source": vuln_summary_path, "component": "dependencies",
        })
    return out


def collect_defects(registry_path, vuln_summary_path=None):
    """All defects the gate considers = registry defects (+ vuln-derived, unless disabled)."""
    defects = load_registry(registry_path)
    if vuln_summary_path is not None:
        defects = defects + vuln_derived_defects(vuln_summary_path)
    return defects


def blocking_defects(defects):
    """The subset that blocks the release (open AND priority P0/P1)."""
    return [d for d in defects if _blocks(d)]


def priority_counts(defects, open_only=True):
    """Count defects by canonical priority (P0..P3 + 'unclassified'). open_only counts open defects."""
    counts = {p: 0 for p in ALL_PRIORITIES}
    counts["unclassified"] = 0
    for d in defects:
        if open_only and not is_open(d.get("status")):
            continue
        pr = normalize_priority(d.get("priority"))
        counts[pr if pr in counts else "unclassified"] += 1
    return counts


def evaluate(defects):
    """Return the verdict dict for a list of defects (pure, deterministic)."""
    blockers = blocking_defects(defects)
    return {
        "blocked": bool(blockers),
        "verdict": "BLOCK" if blockers else "PASS",
        "blocking_count": len(blockers),
        "blocking_defects": blockers,
        "open_priority_counts": priority_counts(defects, open_only=True),
        "total_defects": len(defects),
    }


# ---- CLI ----------------------------------------------------------------------------------------

def _defect_line(d):
    return "  [%s] %s -- %s (%s)" % (
        normalize_priority(d.get("priority")) or (d.get("priority") or "?"),
        d.get("id", "?"),
        d.get("title", ""),
        d.get("status", "?"),
    )


def _print_report(defects, result, registry_path, vuln_note):
    print("== Colima Desktop release-blocking gate (task 13.4 / Requirement 12.5) ==")
    print("-- blocks the v1.0.0 tag IFF any OPEN defect is priority P0 or P1 --")
    print("defect source: %s%s" % (registry_path, vuln_note))
    oc = result["open_priority_counts"]
    print("open defects by priority: P0=%d P1=%d P2=%d P3=%d unclassified=%d (total records: %d)"
          % (oc["P0"], oc["P1"], oc["P2"], oc["P3"], oc["unclassified"], result["total_defects"]))
    print("-" * 78)
    if result["blocked"]:
        print("BLOCKING defects (open, P0/P1):")
        for d in result["blocking_defects"]:
            print(_defect_line(d))
        print("-" * 78)
        print("RESULT: RELEASE BLOCKED -- %d open P0/P1 defect(s). The v1.0.0 tag MUST NOT ship."
              % result["blocking_count"])
    else:
        print("RESULT: RELEASE-BLOCKING GATE GREEN -- 0 open P0/P1 defects. "
              "(Ship still also requires the RC gate, task 12.5.)")


def _print_list(defects, registry_path):
    print("== release-blocking defect registry: %s ==" % registry_path)
    if not defects:
        print("  (no defects recorded)")
    for d in defects:
        flag = "BLOCKS" if _blocks(d) else "ok"
        print("%-7s %s" % (flag, _defect_line(d).strip()))
    print("-" * 78)
    print("legend: BLOCKS = open AND priority P0/P1 (would block v1.0.0); ok = does not block")


def _selftest():
    """Prove the block-iff-open-P0/P1 logic flips correctly. Exit 0 on success, 1 on failure."""
    cases = [
        ([], False, "empty set does not block"),
        ([{"id": "a", "priority": "P2", "status": "open"}], False, "open P2 does not block"),
        ([{"id": "a", "priority": "P3", "status": "open"}], False, "open P3 does not block"),
        ([{"id": "a", "priority": "P0", "status": "resolved"}], False, "resolved P0 does not block"),
        ([{"id": "a", "priority": "P1", "status": "closed"}], False, "closed P1 does not block"),
        ([{"id": "a", "priority": "P0", "status": "open"}], True, "open P0 blocks"),
        ([{"id": "a", "priority": "P1", "status": "open"}], True, "open P1 blocks"),
        ([{"id": "a", "priority": "critical", "status": "open"}], True, "synonym critical->P0 blocks"),
        ([{"id": "a", "priority": "high", "status": "new"}], True, "synonym high->P1, unknown status open"),
        ([{"id": "a", "priority": "P0"}], True, "missing status => open (fail-closed) blocks"),
        ([{"id": "a", "priority": "P2", "status": "open"},
          {"id": "b", "priority": "P1", "status": "open"}], True, "any one open P1 blocks the set"),
    ]
    ok = True
    print("== release-blocking-gate --selftest (block IFF open P0/P1) ==")
    for defects, expect_block, label in cases:
        got = evaluate(defects)["blocked"]
        status = "PASS" if got == expect_block else "FAIL"
        if got != expect_block:
            ok = False
        print("  %-4s %s (expected block=%s, got=%s)" % (status, label, expect_block, got))
    print("RESULT: selftest %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--registry", default=os.environ.get(
        "RELEASE_DEFECTS_FILE", os.path.join(root, "docs", "release-defects.json")))
    ap.add_argument("--vuln-summary", default=os.environ.get(
        "RELEASE_VULN_SUMMARY", os.path.join(root, "docs", "sbom", "vuln-summary.json")))
    ap.add_argument("--no-vuln", action="store_true", help="skip vuln-summary.json auto-ingest")
    ap.add_argument("--list", action="store_true", help="print every defect + classification, exit 0")
    ap.add_argument("--format", choices=("text", "json"), default="text")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("-h", "--help", action="store_true")
    try:
        args = ap.parse_args(argv)
    except SystemExit:
        return 2

    if args.help:
        print(__doc__.strip())
        return 0
    if args.selftest:
        return _selftest()

    vuln_path = None if args.no_vuln else args.vuln_summary
    try:
        defects = collect_defects(args.registry, vuln_path)
    except GateError as exc:
        print("release-blocking-gate: ERROR: %s" % exc, file=sys.stderr)
        print("RESULT: RELEASE BLOCKED (defect source unreadable -- fail-closed)")
        return 2

    if args.list:
        _print_list(defects, args.registry)
        return 0

    result = evaluate(defects)

    if args.format == "json":
        print(json.dumps({
            "verdict": result["verdict"],
            "blocked": result["blocked"],
            "blocking_count": result["blocking_count"],
            "open_priority_counts": result["open_priority_counts"],
            "total_defects": result["total_defects"],
            "blocking_defects": [
                {"id": d.get("id"), "priority": normalize_priority(d.get("priority")),
                 "status": d.get("status"), "title": d.get("title")}
                for d in result["blocking_defects"]
            ],
        }, indent=2))
    else:
        vuln_note = ""
        if vuln_path and os.path.exists(vuln_path):
            vuln_note = " (+ auto-ingest %s)" % os.path.relpath(vuln_path, root)
        elif not args.no_vuln:
            vuln_note = " (vuln summary absent -- skipped)"
        _print_report(defects, result, os.path.relpath(args.registry, root), vuln_note)

    return 1 if result["blocked"] else 0


if __name__ == "__main__":
    raise SystemExit(main())

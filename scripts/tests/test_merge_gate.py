#!/usr/bin/env python3
"""Property tests for the conflict-free merge gate — scripts/ci/merge-gate.sh (task 1.9).

Feature: cross-platform-live-verification

These tests treat merge-gate.sh as a black box and assert three design correctness
properties by generating randomized inputs (>=100 iterations each), computing the
expected exit code with a faithful in-Python re-implementation of the gate's own
decision logic, invoking the real subcommand, and comparing exit codes:

  * Property 3 — Merge-gate ownership rejection      (check-ownership: 0 accept / 2 reject)
      For any changeset + owned prefix(es), the gate rejects iff any changed path is
      outside every owned prefix, and accepts iff every path is under some prefix.
      Validates Requirements 2.7.

  * Property 4 — Merge-gate green / no-regression     (check-green: 0 accept / 4 reject)
      check-green accepts only when verify is GREEN AND no OTHER-platform STATUS.md
      scoreboard cell regresses; the touched platform may change freely.
      Validates Requirements 2.8.

  * Property 5 — Path-ownership disjointness          (disjoint: 0 disjoint / 5 overlap)
      For any set of owned prefixes, `disjoint` returns 0 iff they are pairwise
      non-overlapping, else exit 5.
      Validates Requirements 2.2, 2.3.

Design intent: this harness deliberately shells out with `bash --noprofile --norc`
so the interactive repo-scan startup hook is never sourced and each gate call is
fast + isolated (per-call timeout). It is runnable directly:

    python3 scripts/tests/test_merge_gate.py            # 150 iters/property
    python3 scripts/tests/test_merge_gate.py --iters 250 --seed 42

and also under pytest (the test_* functions assert zero property failures).

It NEVER modifies merge-gate.sh. A disagreement between the gate and the oracle is
surfaced as a counterexample (a candidate real bug), never silently patched.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locations
# --------------------------------------------------------------------------- #
REPO_ROOT = Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "scripts" / "ci" / "merge-gate.sh"

# Stable exit codes documented by merge-gate.sh --help
EX_OK = 0
EX_USAGE = 1
EX_OWNERSHIP = 2
EX_RESERVED = 3
EX_GREEN = 4
EX_DISJOINT = 5

LOG_PATH = Path(os.environ.get("MERGE_GATE_LOG", "/tmp/merge_gate_pbt.log"))
SUMMARY_PATH = Path(os.environ.get("MERGE_GATE_SUMMARY", "/tmp/merge_gate_pbt_summary.json"))

_LOG_FH = None


def log(msg: str) -> None:
    """Write a line to stdout and to the /tmp log (flushed) so a background run
    can be observed by reading the file back."""
    line = str(msg)
    print(line, flush=True)
    global _LOG_FH
    if _LOG_FH is not None:
        _LOG_FH.write(line + "\n")
        _LOG_FH.flush()


# --------------------------------------------------------------------------- #
# Subprocess driver — bash --noprofile --norc, per-call timeout
# --------------------------------------------------------------------------- #
def run_gate(args, timeout=20):
    """Invoke merge-gate.sh <args...> in an isolated non-interactive bash.

    Returns the integer exit code. Raises on timeout / launch failure so the
    caller records it as a harness error (not a silent pass)."""
    cmd = ["bash", "--noprofile", "--norc", str(GATE)] + [str(a) for a in args]
    proc = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env={"PATH": os.environ.get("PATH", "/usr/bin:/bin:/usr/sbin:/sbin"),
             "HOME": os.environ.get("HOME", "/tmp"),
             "TMPDIR": os.environ.get("TMPDIR", "/tmp")},
    )
    return proc.returncode


def _write_tmp(text, suffix):
    fd, path = tempfile.mkstemp(suffix=suffix, prefix="mg_pbt_")
    with os.fdopen(fd, "w") as fh:
        fh.write(text)
    return path


# --------------------------------------------------------------------------- #
# ORACLE — faithful re-implementation of merge-gate.sh decision logic
# --------------------------------------------------------------------------- #
def normalize_prefix(x: str) -> str:
    """Mirror of merge-gate.sh normalize_prefix(): strip a trailing /**, /* or /
    in sequence."""
    if x.endswith("/**"):
        x = x[:-3]
    if x.endswith("/*"):
        x = x[:-2]
    if x.endswith("/"):
        x = x[:-1]
    return x


def path_under_prefix(p: str, prefix: str) -> bool:
    """Mirror of merge-gate.sh path_under_prefix(): a normalized prefix that still
    contains a glob metachar (* or ?) matches as a shell `case` glob (where * and ?
    span '/'); otherwise it is an exact/directory prefix."""
    norm = normalize_prefix(prefix)
    if not norm:
        return False
    if "*" in norm or "?" in norm:
        # shell case-glob semantics == fnmatch (which lets * and ? cross '/')
        return fnmatch.fnmatchcase(p, norm)
    return p == norm or p.startswith(norm + "/")


def changeset_ownership_ok(paths, prefixes) -> bool:
    """True iff every path is under at least one owned prefix (=> accept, exit 0)."""
    for p in paths:
        if not any(path_under_prefix(p, pre) for pre in prefixes):
            return False
    return True


def prefixes_overlap(a: str, b: str) -> bool:
    """Mirror of merge-gate.sh prefixes_overlap(): literal (non-glob) containment —
    equal, or one normalized prefix is a directory ancestor of the other."""
    na, nb = normalize_prefix(a), normalize_prefix(b)
    if not na or not nb:
        return False
    if na == nb:
        return True
    if nb.startswith(na + "/"):
        return True
    if na.startswith(nb + "/"):
        return True
    return False


def any_overlap(prefixes) -> bool:
    for i in range(len(prefixes)):
        for j in range(i + 1, len(prefixes)):
            if prefixes_overlap(prefixes[i], prefixes[j]):
                return True
    return False


def rank(tok: str) -> int:
    """Mirror of merge-gate.sh rank(): higher is better."""
    if tok == "PASS":
        return 4
    if tok in ("present", "scaffold"):
        return 3
    if tok in ("n/a", "N/A"):
        return 2
    if tok in ("WARN", "warn"):
        return 1
    if tok in ("?", ""):
        return 1
    if tok == "FAIL":
        return 0
    return 1


_SEP_RE = re.compile(r"^[-:]*$")


def emit_status_triples(md_text: str):
    """Mirror of merge-gate.sh emit_status_triples() awk: parse a scoreboard
    markdown table into (criterion, platform, token) triples. token = first
    whitespace word of the cell."""
    triples = []
    plat = {}          # column index (python) -> platform name
    hdr = False
    for line in md_text.splitlines():
        if not line.startswith("|"):
            continue
        fields = [f.strip() for f in line.split("|")]
        nf = len(fields)
        # separator? every field in [1 .. nf-2] (awk $2..$(NF-1)) is only -/:
        issep = True
        for i in range(1, nf - 1):
            if not _SEP_RE.match(fields[i]):
                issep = False
                break
        if issep:
            continue
        if not hdr:
            for i in range(2, nf - 1):     # awk $3..$(NF-1)
                plat[i] = fields[i]
            hdr = True
            continue
        crit = fields[1] if nf > 1 else ""  # awk $2
        if crit == "":
            continue
        for i in range(2, nf - 1):
            if i in plat and plat[i] != "":
                parts = fields[i].split()
                tok = parts[0] if parts else "?"
                triples.append((crit, plat[i], tok))
    return triples


def status_regressions(before_text: str, after_text: str, touched: str):
    """Mirror of merge-gate.sh status_regressions(): a regression is any cell on a
    platform OTHER than `touched` whose rank drops from before -> after. Cells with
    no baseline (absent in before) are not regressions."""
    touched_lc = (touched or "").lower()
    before_map = {}
    for (c, p, t) in emit_status_triples(before_text):
        before_map.setdefault((c, p), t)      # first match wins (awk exits early)
    regs = []
    for (c, p, t_after) in emit_status_triples(after_text):
        if p.lower() == touched_lc:
            continue
        t_before = before_map.get((c, p))
        if t_before is None or t_before == "":
            continue
        if rank(t_after) < rank(t_before):
            regs.append((p, c, t_before, t_after))
    return regs


def oracle_check_green(verify_green: bool, before_text, after_text, platform: str) -> int:
    """Expected check-green exit code."""
    if not platform:
        return EX_GREEN
    if not verify_green:
        return EX_GREEN
    if before_text is not None and after_text is not None:
        if status_regressions(before_text, after_text, platform):
            return EX_GREEN
    return EX_OK


# --------------------------------------------------------------------------- #
# Generators
# --------------------------------------------------------------------------- #
PREFIX_POOL = [
    "scripts/**", "daemon/**", "Sources/**", "tui/**", "windows/**",
    "linux/**", "Tests/**", "docs/**", ".github/**", "exploration/**",
    ".kiro/board/STATUS.md", "README*",
]

# A diverse path pool: clearly-inside candidates, sibling look-alikes, deep nests,
# exact reserved files, README variants, and clearly-unowned paths.
PATH_POOL = [
    "scripts/ci/merge-gate.sh", "scripts/verify.sh", "scripts", "scripts/tests/test_merge_gate.py",
    "scriptsX/y.txt", "scripts.bak/z",
    "daemon/internal/server/server.go", "daemon/cmd/main.go", "daemon",
    "Sources/App/AppState.swift", "Sources/Views/Shared/Foo.swift",
    "tui/main.go", "windows/App.xaml.cs", "linux/src/main.rs",
    "Tests/UnitTests/FooTests.swift", "docs/gap-report.md", "docs/parity-matrix.md",
    ".github/workflows/frontends.yml", "exploration/action-inventory.json",
    ".kiro/board/STATUS.md", ".kiro/board/PLAN.md",
    "README", "README.md", "READMEs/extra.txt",
    "unowned/file.txt", "other/thing", "proto/colima_ui.proto", "toplevel.txt",
]

PLATFORMS = ["macOS", "Windows", "Linux", "TUI", "Daemon"]
CRIT_POOL = ["Build", "Unit", "Integration", "Coverage", "DaemonBuild",
             "DaemonTests", "Snapshot", "Lint", "Race"]
# Tokens whose first whitespace-word has a well-defined rank, plus compound cells
# and an unknown token (rank default 1) to exercise first-word extraction.
TOKEN_POOL = ["PASS", "present", "scaffold", "n/a", "N/A", "WARN", "warn",
              "?", "FAIL", "PASS (0 warnings)", "scaffold (CI)", "unknown"]

DISJOINT_POOL = [
    "scripts/**", "daemon/**", "daemon/internal/**", "Sources/**",
    "Sources/Views/**", "tui/**", "windows/**", "linux/**", "Tests/**",
    "docs/**", "docs/parity-matrix.md", ".github/**",
]


def gen_ownership_case(rng):
    prefixes = rng.sample(PREFIX_POOL, rng.randint(1, 3))
    k = rng.randint(0, 6)                       # 0 => empty changeset (accept)
    paths = [rng.choice(PATH_POOL) for _ in range(k)]
    return prefixes, paths


def _render_status_table(criteria, platforms, cell_map):
    """cell_map: dict[(crit, plat)] -> token. Emits a valid markdown scoreboard."""
    header = "| Criterion | " + " | ".join(platforms) + " |"
    sep = "|" + "|".join(["---"] * (len(platforms) + 1)) + "|"
    rows = [header, sep]
    for c in criteria:
        cells = [cell_map[(c, p)] for p in platforms]
        rows.append("| " + c + " | " + " | ".join(cells) + " |")
    return "\n".join(rows) + "\n"


def gen_green_case(rng):
    n_plat = rng.randint(2, len(PLATFORMS))
    platforms = rng.sample(PLATFORMS, n_plat)
    n_crit = rng.randint(1, 6)
    criteria = rng.sample(CRIT_POOL, n_crit)

    before = {}
    for c in criteria:
        for p in platforms:
            before[(c, p)] = rng.choice(TOKEN_POOL)

    # touched platform: usually one of the columns; sometimes absent-from-table;
    # sometimes a different letter-case to exercise case-insensitive comparison.
    roll = rng.random()
    if roll < 0.7:
        touched = rng.choice(platforms)
    elif roll < 0.85:
        touched = rng.choice(platforms).lower()
    else:
        touched = "Nonexistent"

    after = {}
    for c in criteria:
        for p in platforms:
            b = before[(c, p)]
            if p.lower() == touched.lower():
                after[(c, p)] = rng.choice(TOKEN_POOL)          # free change
            else:
                # sometimes deliberately regress, sometimes hold/improve
                if rng.random() < 0.4:
                    after[(c, p)] = rng.choice(TOKEN_POOL)      # may regress
                else:
                    # pick a token whose rank >= current (no regression)
                    rb = rank(b)
                    candidates = [t for t in TOKEN_POOL if rank(t) >= rb]
                    after[(c, p)] = rng.choice(candidates)

    verify_green = rng.random() < 0.65
    before_text = _render_status_table(criteria, platforms, before)
    after_text = _render_status_table(criteria, platforms, after)
    # --platform passed to the gate is the touched platform
    return verify_green, before_text, after_text, touched


def gen_disjoint_case(rng):
    n = rng.randint(2, 5)
    prefixes = rng.sample(DISJOINT_POOL, n)
    return prefixes


# --------------------------------------------------------------------------- #
# Property runners
# --------------------------------------------------------------------------- #
class PropResult:
    def __init__(self, name):
        self.name = name
        self.ran = 0
        self.passed = 0
        self.failures = []      # list of dicts (counterexamples)

    @property
    def failed(self):
        return len(self.failures)


def run_property_3(rng, iters):
    r = PropResult("Property 3 (merge-gate ownership rejection)")
    for _ in range(iters):
        prefixes, paths = gen_ownership_case(rng)
        expected = EX_OK if changeset_ownership_ok(paths, prefixes) else EX_OWNERSHIP
        paths_file = _write_tmp("\n".join(paths) + ("\n" if paths else ""), ".txt")
        try:
            args = ["check-ownership"]
            # randomly split prefixes across repeated flags and CSV to exercise both
            if rng.random() < 0.5 and len(prefixes) > 1:
                args += ["--owned-prefix", ",".join(prefixes)]
            else:
                for pre in prefixes:
                    args += ["--owned-prefix", pre]
            args += ["--files", paths_file]
            actual = run_gate(args)
        finally:
            os.unlink(paths_file)
        r.ran += 1
        if actual == expected:
            r.passed += 1
        else:
            r.failures.append({
                "prefixes": prefixes, "paths": paths,
                "expected": expected, "actual": actual,
            })
            if len(r.failures) <= 5:
                log("  [P3 COUNTEREXAMPLE] prefixes=%r paths=%r expected=%d actual=%d"
                    % (prefixes, paths, expected, actual))
    return r


def run_property_4(rng, iters):
    r = PropResult("Property 4 (merge-gate green / no-regression)")
    for _ in range(iters):
        verify_green, before_text, after_text, touched = gen_green_case(rng)
        expected = oracle_check_green(verify_green, before_text, after_text, touched)
        bpath = _write_tmp(before_text, ".md")
        apath = _write_tmp(after_text, ".md")
        try:
            args = ["check-green", "--platform", touched,
                    "--verify", "green" if verify_green else "not-green",
                    "--status-before", bpath, "--status-after", apath]
            actual = run_gate(args)
        finally:
            os.unlink(bpath)
            os.unlink(apath)
        r.ran += 1
        if actual == expected:
            r.passed += 1
        else:
            r.failures.append({
                "verify_green": verify_green, "touched": touched,
                "before": before_text, "after": after_text,
                "expected": expected, "actual": actual,
            })
            if len(r.failures) <= 5:
                log("  [P4 COUNTEREXAMPLE] verify_green=%s touched=%s expected=%d actual=%d"
                    % (verify_green, touched, expected, actual))
                log("    before:\n%s" % before_text)
                log("    after:\n%s" % after_text)
    return r


def run_property_5(rng, iters):
    r = PropResult("Property 5 (path-ownership disjointness)")
    for _ in range(iters):
        prefixes = gen_disjoint_case(rng)
        expected = EX_DISJOINT if any_overlap(prefixes) else EX_OK
        actual = run_gate(["disjoint"] + prefixes)
        r.ran += 1
        if actual == expected:
            r.passed += 1
        else:
            r.failures.append({
                "prefixes": prefixes, "expected": expected, "actual": actual,
            })
            if len(r.failures) <= 5:
                log("  [P5 COUNTEREXAMPLE] prefixes=%r expected=%d actual=%d"
                    % (prefixes, expected, actual))
    return r


# --------------------------------------------------------------------------- #
# Deterministic edge cases (unit-style sanity, run before the randomized loop)
# --------------------------------------------------------------------------- #
def run_deterministic_checks():
    """Fixed, hand-verified cases. Returns list of (name, ok, detail)."""
    results = []

    def check(name, args, expected, files_text=None):
        fpath = None
        a = list(args)
        if files_text is not None:
            fpath = _write_tmp(files_text, ".txt")
            a += ["--files", fpath]
        try:
            actual = run_gate(a)
        finally:
            if fpath:
                os.unlink(fpath)
        ok = actual == expected
        results.append((name, ok, "expected=%d actual=%d" % (expected, actual)))

    def check_green(name, platform, verify, before, after, expected):
        b = _write_tmp(before, ".md")
        af = _write_tmp(after, ".md")
        try:
            actual = run_gate(["check-green", "--platform", platform, "--verify", verify,
                               "--status-before", b, "--status-after", af])
        finally:
            os.unlink(b)
            os.unlink(af)
        ok = actual == expected
        results.append((name, ok, "expected=%d actual=%d" % (expected, actual)))

    # ---- Property 3 edges ----
    check("P3 empty changeset accepts",
          ["check-ownership", "--owned-prefix", "scripts/**"], EX_OK, files_text="")
    check("P3 in-lane accepts",
          ["check-ownership", "--owned-prefix", "scripts/**"], EX_OK,
          files_text="scripts/ci/merge-gate.sh\nscripts/verify.sh\n")
    check("P3 out-of-lane rejects",
          ["check-ownership", "--owned-prefix", "scripts/**"], EX_OWNERSHIP,
          files_text="scripts/verify.sh\ndaemon/x.go\n")
    check("P3 sibling look-alike rejects",
          ["check-ownership", "--owned-prefix", "scripts/**"], EX_OWNERSHIP,
          files_text="scriptsX/y.txt\n")
    check("P3 exact-file prefix accepts",
          ["check-ownership", "--owned-prefix", ".kiro/board/STATUS.md"], EX_OK,
          files_text=".kiro/board/STATUS.md\n")
    check("P3 exact-file prefix rejects sibling",
          ["check-ownership", "--owned-prefix", ".kiro/board/STATUS.md"], EX_OWNERSHIP,
          files_text=".kiro/board/PLAN.md\n")
    check("P3 README glob accepts",
          ["check-ownership", "--owned-prefix", "README*"], EX_OK,
          files_text="README.md\nREADME\n")
    check("P3 multi-prefix CSV accepts",
          ["check-ownership", "--owned-prefix", "scripts/**,docs/**"], EX_OK,
          files_text="scripts/a.sh\ndocs/b.md\n")

    # ---- Property 4 edges ----
    tbl = "| Criterion | macOS | Windows |\n|---|---|---|\n| Build | PASS | PASS |\n"
    check_green("P4 green + no snapshot regression accepts", "macOS", "green", tbl, tbl, EX_OK)
    check_green("P4 not-green rejects", "macOS", "not-green", tbl, tbl, EX_GREEN)
    before = "| Criterion | macOS | Windows |\n|---|---|---|\n| Build | PASS | PASS |\n"
    after_reg = "| Criterion | macOS | Windows |\n|---|---|---|\n| Build | PASS | FAIL |\n"
    check_green("P4 other-platform regression rejects", "macOS", "green", before, after_reg, EX_GREEN)
    after_touched = "| Criterion | macOS | Windows |\n|---|---|---|\n| Build | FAIL | PASS |\n"
    check_green("P4 touched-platform may regress freely", "macOS", "green", before, after_touched, EX_OK)
    after_improve = "| Criterion | macOS | Windows |\n|---|---|---|\n| Build | PASS | PASS |\n"
    before_worse = "| Criterion | macOS | Windows |\n|---|---|---|\n| Build | PASS | FAIL |\n"
    check_green("P4 other-platform improvement accepts", "macOS", "green", before_worse, after_improve, EX_OK)

    # ---- Property 5 edges ----
    check("P5 two distinct disjoint", ["disjoint", "daemon/**", "tui/**"], EX_OK)
    check("P5 nested overlaps", ["disjoint", "daemon/**", "daemon/internal/**"], EX_DISJOINT)
    check("P5 identical overlaps", ["disjoint", "scripts/**", "scripts/**"], EX_DISJOINT)
    check("P5 three all-distinct disjoint",
          ["disjoint", "daemon/**", "tui/**", "Sources/**"], EX_OK)
    check("P5 exact-file under dir overlaps",
          ["disjoint", "docs/**", "docs/parity-matrix.md"], EX_DISJOINT)

    return results


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run_all(iters, seed):
    global _LOG_FH
    _LOG_FH = open(LOG_PATH, "w")
    rng = random.Random(seed)
    log("START merge-gate PBT  seed=%d iters=%d  gate=%s" % (seed, iters, GATE))
    log("Feature: cross-platform-live-verification (Properties 3, 4, 5)")

    if not GATE.exists():
        log("FATAL: gate script not found at %s" % GATE)
        return 1

    # 1) deterministic sanity
    det = run_deterministic_checks()
    det_failed = [d for d in det if not d[1]]
    for name, ok, detail in det:
        log("  [det] %-45s %s (%s)" % (name, "OK" if ok else "FAIL", detail))
    log("Deterministic edge cases: %d/%d passed" % (len(det) - len(det_failed), len(det)))

    # 2) randomized properties (>=100 iterations each)
    results = [
        run_property_3(rng, iters),
        run_property_4(rng, iters),
        run_property_5(rng, iters),
    ]
    for r in results:
        log("  %-55s ran=%d passed=%d failed=%d" % (r.name, r.ran, r.passed, r.failed))

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
    log("DONE overall=%s total_failures=%d  summary=%s"
        % (summary["overall"], total_failed, SUMMARY_PATH))
    _LOG_FH.close()
    return 0 if total_failed == 0 else 1


# --------------------------------------------------------------------------- #
# pytest entry points
# --------------------------------------------------------------------------- #
_PYTEST_ITERS = int(os.environ.get("MERGE_GATE_ITERS", "150"))
_PYTEST_SEED = int(os.environ.get("MERGE_GATE_SEED", "1310"))


def test_property_3_merge_gate_ownership_rejection():
    """Feature: cross-platform-live-verification, Property 3."""
    rng = random.Random(_PYTEST_SEED)
    r = run_property_3(rng, _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "ownership counterexamples: %r" % r.failures[:5]


def test_property_4_merge_gate_green_no_regression():
    """Feature: cross-platform-live-verification, Property 4."""
    rng = random.Random(_PYTEST_SEED + 1)
    r = run_property_4(rng, _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "green/no-regression counterexamples: %r" % r.failures[:5]


def test_property_5_path_ownership_disjointness():
    """Feature: cross-platform-live-verification, Property 5."""
    rng = random.Random(_PYTEST_SEED + 2)
    r = run_property_5(rng, _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "disjointness counterexamples: %r" % r.failures[:5]


def test_deterministic_edge_cases():
    det = run_deterministic_checks()
    failed = [d[0] for d in det if not d[1]]
    assert not failed, "deterministic edge case failures: %r" % failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Property tests for scripts/ci/merge-gate.sh")
    ap.add_argument("--iters", type=int, default=150,
                    help="randomized iterations per property (min 100 enforced)")
    ap.add_argument("--seed", type=int,
                    default=int(os.environ.get("MERGE_GATE_SEED", str(int(time.time())))))
    args = ap.parse_args()
    iters = max(100, args.iters)
    rc = run_all(iters, args.seed)
    sys.exit(rc)


if __name__ == "__main__":
    main()

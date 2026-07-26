#!/usr/bin/env python3
"""Property tests for the P0/P1 RELEASE-BLOCKING gate — scripts/release_blocking_gate.py (task 13.5).

Feature: cross-platform-live-verification

These tests treat the task-13.4 release-blocking gate as the unit under test. Its filename is
underscored (not hyphenated), but — mirroring scripts/tests/test_vuln_report.py and
test_gen_truth_table.py — it is loaded via importlib.util.spec_from_file_location and its pure,
import-safe functions are exercised in-process (fast, no subprocess, immune to the interactive
repo-scan startup hook + ~30s output cap that make the shell flaky here):

    load_registry / normalize_priority / is_open / vuln_derived_defects /
    collect_defects / blocking_defects / evaluate

design Property 22 (Release P0/P1 blocking, Requirement 12.5): *For any* set of open defects, the
release gate blocks the v1.0.0 tag IFF the set contains at least one defect with priority P0 or P1.
The gate DERIVES the block decision from each defect's priority + status (block IFF
normalize_priority(priority) in {P0,P1} AND is_open(status)); it never trusts a hand-set boolean.

Properties asserted over >=100 randomized, seeded (deterministic) iterations each — all tagged
`Feature: cross-platform-live-verification, Property 22`:

  * Property 22 — block-iff-open-P0/P1 (the core)
      For any randomly generated defect set (priorities incl. synonyms critical/high/medium/low/
      unspecified + blank/garbage/missing; statuses incl. open/new/resolved/closed/fixed/wontfix/
      blank/unknown/missing), evaluate(defects).blocked is TRUE iff at least one defect normalizes to
      P0/P1 AND is open — cross-checked against an INDEPENDENT golden oracle (the test declares each
      token's expected bucket/openness itself, never re-using the gate's private dicts). Also asserts
      the exact blocking-defect set, blocking_count, verdict, and open_priority_counts, and — crucially
      — that injecting a bogus `"blocking": True|False` field NEVER changes the verdict (the design's
      "derived, never trusts a hand-set boolean" guarantee).

  * Property 22 — normalize_priority totality
      Every input maps to exactly one of P0..P3 or None, deterministically, and is invariant to
      case + surrounding whitespace.

  * Property 22 — is_open fail-closed
      A defect is OPEN unless its status is a known closed status; unknown/missing/blank status => OPEN
      (so a mis-typed status can never hide a P0).

  * Property 22 — vuln-summary auto-ingest
      A committed vuln summary with critical>0 auto-derives an OPEN P0 (and high>0 an OPEN P1) that
      blocks the release even with an otherwise non-blocking registry; critical==0 AND high==0 adds no
      blocker. moderate/low/unspecified counts never fabricate a blocker.

Deterministic edge-case assertions (hand-verified) + a regression ANCHOR against the real committed
docs/release-defects.json (currently expected: 0 open P0/P1 => not blocked) round it out.

Runnable directly (writes a summary log + JSON to /tmp and exits nonzero on any failure):

    python3 scripts/tests/test_release_blocking_gate.py               # 200 iters/property
    python3 scripts/tests/test_release_blocking_gate.py --iters 500 --seed 42

and also under pytest (the test_* functions assert zero property failures, >=100 iters).

It NEVER modifies release_blocking_gate.py. A gate invariant that does not hold is surfaced as a
counterexample (a candidate real bug), never silently patched.
"""

import argparse
import contextlib
import importlib.util
import io
import json
import os
import random
import sys
import tempfile
import time
import traceback
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locations & gate import (loaded by file path via importlib, like the siblings)
# --------------------------------------------------------------------------- #
REPO_ROOT = Path(__file__).resolve().parents[2]
GATE_PATH = REPO_ROOT / "scripts" / "release_blocking_gate.py"
REAL_REGISTRY = REPO_ROOT / "docs" / "release-defects.json"
REAL_VULN_SUMMARY = REPO_ROOT / "docs" / "sbom" / "vuln-summary.json"

LOG_PATH = Path(os.environ.get("RBG_LOG", "/tmp/release_blocking_gate_pbt.log"))
SUMMARY_PATH = Path(os.environ.get("RBG_SUMMARY", "/tmp/release_blocking_gate_pbt_summary.json"))

_LOG_FH = None


def log(msg):
    """Print to stdout and (if open) to the /tmp log, flushed, so a backgrounded run can be
    observed by reading the file back."""
    line = str(msg)
    print(line, flush=True)
    global _LOG_FH
    if _LOG_FH is not None:
        _LOG_FH.write(line + "\n")
        _LOG_FH.flush()


def load_gate():
    """Load scripts/release_blocking_gate.py as a module via importlib (import-safe pure funcs)."""
    spec = importlib.util.spec_from_file_location("release_blocking_gate", str(GATE_PATH))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GATE = load_gate()
GateError = GATE.GateError

# --------------------------------------------------------------------------- #
# INDEPENDENT golden token tables.
#
# These are declared by the TEST (not imported from the gate's private dicts) so the "block iff
# open P0/P1" oracle is a genuine regression guard, not a tautology. Each priority base token is
# paired with the bucket it MUST normalize to; each status base token with whether it MUST be open.
# (The gate strips()+lower()s both, so case/whitespace variants must classify identically — the
# `decorate()` helper exercises that invariance.)
# --------------------------------------------------------------------------- #
PRIORITY_TOKENS = {
    "P0": ["p0", "critical", "crit", "blocker", "sev0", "s0"],
    "P1": ["p1", "high", "sev1", "s1", "major"],
    "P2": ["p2", "medium", "moderate", "med", "sev2", "s2", "normal"],
    "P3": ["p3", "low", "minor", "unspecified", "none", "trivial", "info",
           "informational", "sev3", "s3"],
}
# Priority strings that are NOT synonyms => normalize to None (not block-eligible). Verified below
# that none of these lowercases to a key in the gate's synonym table.
UNRECOGNIZED_PRIORITY = ["", "   ", "garbage", "xyzzy", "urgent", "p4", "p5", "sev4", "s4",
                         "0", "9001", "!!!", "highish", "criticalish", "todo", "priority", "unknown"]

CLOSED_STATUSES = ["resolved", "closed", "fixed", "done", "complete", "completed", "wontfix",
                   "won't fix", "wont-fix", "deferred", "duplicate", "dup", "invalid",
                   "not_applicable", "not-applicable", "na", "n/a", "verified", "released"]
# Statuses that are NOT closed => OPEN (block-eligible). Blank/whitespace => open (fail-closed).
OPEN_STATUSES = ["open", "new", "in_progress", "in progress", "reopened", "investigating",
                 "triage", "wip", "pending", "blocked", "active", "confirmed", "acknowledged",
                 "unknown", "todo", "garbage", "", "   "]

ALL_BUCKETS = (None, "P0", "P1", "P2", "P3")


def _self_consistency_guard():
    """Fail loudly if a curated 'unrecognized'/'open' token secretly collides with a real synonym/
    closed status — that would make the golden oracle wrong. Keeps the tables honest over time."""
    syn = set()
    for toks in PRIORITY_TOKENS.values():
        syn.update(toks)
    bad_pri = [t for t in UNRECOGNIZED_PRIORITY if t.strip().lower() and t.strip().lower() in syn]
    assert not bad_pri, "UNRECOGNIZED_PRIORITY collides with a real synonym: %r" % bad_pri
    closed = set(CLOSED_STATUSES)
    bad_st = [t for t in OPEN_STATUSES if t.strip().lower() and t.strip().lower() in closed]
    assert not bad_st, "OPEN_STATUSES collides with a closed status: %r" % bad_st


_self_consistency_guard()


# --------------------------------------------------------------------------- #
# Generators (constrain to the input space intelligently; expected outcome is known)
# --------------------------------------------------------------------------- #
def decorate(token, rng):
    """Randomly re-case + pad a string token; the gate strips()+lower()s, so this MUST preserve
    the token's classification (exercises case/whitespace invariance). None passes through."""
    if token is None:
        return None
    form = rng.choice([token, token.upper(), token.lower(), token.title(), token.swapcase()])
    pads = ["", " ", "  ", "\t", " \t ", "\n"]
    return rng.choice(pads) + form + rng.choice(pads)


def gen_priority(rng):
    """Return (token_value, expected_bucket, omit_key)."""
    kind = rng.choice(["P0", "P1", "P2", "P3", "unrecognized", "nonevalue", "missing"])
    if kind == "missing":
        return None, None, True                    # key absent -> get() None -> None bucket
    if kind == "nonevalue":
        return None, None, False                   # explicit JSON null -> None bucket
    if kind == "unrecognized":
        return decorate(rng.choice(UNRECOGNIZED_PRIORITY), rng), None, False
    return decorate(rng.choice(PRIORITY_TOKENS[kind]), rng), kind, False


def gen_status(rng):
    """Return (token_value, expected_open, omit_key)."""
    kind = rng.choice(["open", "closed", "nonevalue", "missing"])
    if kind == "missing":
        return None, True, True                    # key absent -> get() None -> open (fail-closed)
    if kind == "nonevalue":
        return None, True, False                   # explicit JSON null -> open (fail-closed)
    if kind == "closed":
        return decorate(rng.choice(CLOSED_STATUSES), rng), False, False
    return decorate(rng.choice(OPEN_STATUSES), rng), True, False


def gen_defect(rng, idx):
    """Build one defect dict + its independently-known (expected_blocks, bucket, is_open).

    Randomly injects extra fields (severity/source/note) and — importantly — a bogus `blocking`
    boolean UNRELATED to the true verdict, to prove the gate ignores it (derives from priority+
    status only)."""
    ptok, bucket, p_missing = gen_priority(rng)
    stok, is_open, s_missing = gen_status(rng)
    d = {"id": "D%d" % idx, "title": "synthetic defect %d" % idx}
    if not p_missing:
        d["priority"] = ptok
    if not s_missing:
        d["status"] = stok
    if rng.random() < 0.4:                          # decoy hand-set boolean (must be ignored)
        d["blocking"] = rng.choice([True, False])
    if rng.random() < 0.3:
        d["severity"] = rng.choice(["critical", "high", "low", "", "n/a"])
    if rng.random() < 0.3:
        d["note"] = "irrelevant note %d" % idx
    expected_blocks = (bucket in ("P0", "P1")) and is_open
    return d, expected_blocks, bucket, is_open


def gen_nonblocking_defect(rng, idx):
    """A defect guaranteed NOT to block: either an open P2/P3, or a closed anything. Used to build
    a neutral base registry so the vuln auto-ingest contribution can be isolated."""
    if rng.random() < 0.5:
        bucket = rng.choice(["P2", "P3"])
        return {"id": "R%d" % idx, "priority": decorate(rng.choice(PRIORITY_TOKENS[bucket]), rng),
                "status": decorate(rng.choice(OPEN_STATUSES), rng)}
    bucket = rng.choice(["P0", "P1", "P2", "P3"])
    return {"id": "R%d" % idx, "priority": decorate(rng.choice(PRIORITY_TOKENS[bucket]), rng),
            "status": decorate(rng.choice(CLOSED_STATUSES), rng)}


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
            log("  [COUNTEREXAMPLE] %s" % json.dumps(detail, default=str)[:800])


def _short_tb():
    return traceback.format_exc().strip().splitlines()[-1]


def expect_gate_error(fn):
    """True iff fn() raises GateError (and not some other exception type)."""
    try:
        fn()
        return False
    except GateError:
        return True
    except Exception:
        return False


# --------------------------------------------------------------------------- #
# Property 22 — block IFF open P0/P1 (the core)
# --------------------------------------------------------------------------- #
def run_property_block_semantics(seed_rng, iters):
    r = PropResult("Property 22 (block iff open P0/P1)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            n = rng.randint(0, 14)
            defects = []
            expected_block_ids = set()
            oc = {"P0": 0, "P1": 0, "P2": 0, "P3": 0, "unclassified": 0}
            for i in range(n):
                d, blocks, bucket, is_open = gen_defect(rng, i)

                # per-field totality/fail-closed cross-check against the golden oracle
                assert GATE.normalize_priority(d.get("priority")) == bucket, \
                    "normalize_priority(%r) != %r" % (d.get("priority"), bucket)
                assert GATE.is_open(d.get("status")) == is_open, \
                    "is_open(%r) != %r" % (d.get("status"), is_open)

                defects.append(d)
                if blocks:
                    expected_block_ids.add(d["id"])
                if is_open:
                    oc[bucket if bucket in oc else "unclassified"] += 1

            rng.shuffle(defects)  # order must not matter
            result = GATE.evaluate(defects)

            # the core Property 22 assertion
            assert result["blocked"] == bool(expected_block_ids), \
                "blocked=%r expected=%r" % (result["blocked"], bool(expected_block_ids))
            assert result["verdict"] == ("BLOCK" if expected_block_ids else "PASS"), \
                "verdict mismatch %r" % result["verdict"]
            assert result["blocking_count"] == len(expected_block_ids), "blocking_count mismatch"
            assert {b["id"] for b in result["blocking_defects"]} == expected_block_ids, \
                "blocking id set mismatch"
            # blocking_defects() public helper agrees with evaluate()
            assert {b["id"] for b in GATE.blocking_defects(defects)} == expected_block_ids, \
                "blocking_defects() disagrees with evaluate()"
            # derived counts + totals
            assert result["open_priority_counts"] == oc, \
                "open_priority_counts %r != %r" % (result["open_priority_counts"], oc)
            assert result["total_defects"] == len(defects), "total_defects mismatch"

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 22 — normalize_priority totality
# --------------------------------------------------------------------------- #
def run_property_normalize_totality(seed_rng, iters):
    r = PropResult("Property 22 (normalize_priority totality)")
    labelled = []
    for bucket, toks in PRIORITY_TOKENS.items():
        labelled += [(t, bucket) for t in toks]
    labelled += [(t, None) for t in UNRECOGNIZED_PRIORITY]

    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            base, bucket = rng.choice(labelled)

            # totality: result is always one of the allowed buckets
            nv = GATE.normalize_priority(base)
            assert nv in ALL_BUCKETS, "normalize_priority(%r)=%r out of taxonomy" % (base, nv)
            assert nv == bucket, "normalize_priority(%r)=%r expected %r" % (base, nv, bucket)

            # determinism
            assert GATE.normalize_priority(base) == nv, "non-deterministic"

            # case + surrounding-whitespace invariance
            for variant in (base.upper(), base.lower(), base.title(), base.swapcase(),
                            "  " + base + "  ", "\t" + base + "\n", decorate(base, rng)):
                assert GATE.normalize_priority(variant) == bucket, \
                    "case/space variant %r != %r" % (variant, bucket)

            # explicit None value normalizes to None
            assert GATE.normalize_priority(None) is None, "None value not None"

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 22 — is_open fail-closed
# --------------------------------------------------------------------------- #
def run_property_is_open_fail_closed(seed_rng, iters):
    r = PropResult("Property 22 (is_open fail-closed)")
    labelled = [(t, False) for t in CLOSED_STATUSES] + [(t, True) for t in OPEN_STATUSES]

    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            base, expected_open = rng.choice(labelled)

            assert GATE.is_open(base) == expected_open, \
                "is_open(%r)=%r expected %r" % (base, GATE.is_open(base), expected_open)

            # case + whitespace invariance
            for variant in (base.upper(), base.lower(), base.title(), base.swapcase(),
                            "  " + base + "  ", decorate(base, rng)):
                assert GATE.is_open(variant) == expected_open, \
                    "variant %r open!=%r" % (variant, expected_open)

            # fail-closed: unknown / missing / blank => OPEN (never hides a P0)
            assert GATE.is_open(None) is True, "None status not open"
            assert GATE.is_open("") is True, "empty status not open"
            assert GATE.is_open("   ") is True, "whitespace status not open"
            garbage = "status-%d-%s" % (rng.randrange(10 ** 6), rng.choice("qzx"))
            assert GATE.is_open(garbage) is True, "garbage status %r not open" % garbage

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 22 — vuln-summary auto-ingest (critical->open P0, high->open P1)
# --------------------------------------------------------------------------- #
def run_property_vuln_autoingest(seed_rng, iters):
    r = PropResult("Property 22 (vuln-summary auto-ingest)")
    with tempfile.TemporaryDirectory(prefix="rbg-vuln-") as d:
        reg_path = os.path.join(d, "registry.json")
        vuln_path = os.path.join(d, "vuln-summary.json")
        for _ in range(iters):
            iseed = seed_rng.randrange(2 ** 63)
            rng = random.Random(iseed)
            try:
                crit = rng.randint(0, 4)
                high = rng.randint(0, 4)
                totals = {"critical": crit, "high": high,
                          "moderate": rng.randint(0, 5), "low": rng.randint(0, 5),
                          "unspecified": rng.randint(0, 9)}
                with open(vuln_path, "w") as fh:
                    json.dump({"severity_totals": totals}, fh)

                # base registry of ONLY non-blocking defects, so blockers can only be vuln-derived
                base = [gen_nonblocking_defect(rng, i) for i in range(rng.randint(0, 4))]
                with open(reg_path, "w") as fh:
                    json.dump({"defects": base}, fh)

                derived = GATE.vuln_derived_defects(vuln_path)
                expected_derived = (1 if crit > 0 else 0) + (1 if high > 0 else 0)
                assert len(derived) == expected_derived, \
                    "derived count %d != %d (crit=%d high=%d)" % (
                        len(derived), expected_derived, crit, high)
                for dv in derived:
                    assert GATE.is_open(dv.get("status")) is True, "derived defect not open"
                buckets = {GATE.normalize_priority(dv.get("priority")) for dv in derived}
                if crit > 0:
                    assert "P0" in buckets, "critical>0 did not derive an open P0"
                if high > 0:
                    assert "P1" in buckets, "high>0 did not derive an open P1"

                # combined verdict: neutral registry means blocked IFF the vuln summary contributed
                combined = GATE.collect_defects(reg_path, vuln_path)
                assert len(combined) == len(base) + expected_derived, "collect_defects count"
                res = GATE.evaluate(combined)
                assert res["blocked"] == (crit > 0 or high > 0), \
                    "auto-ingest blocked=%r crit=%d high=%d" % (res["blocked"], crit, high)

                # --no-vuln equivalent (vuln path None) never adds a blocker
                reg_only = GATE.collect_defects(reg_path, None)
                assert GATE.evaluate(reg_only)["blocked"] is False, "neutral registry blocked"

                r.record_pass()
            except Exception as e:
                r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Deterministic edge cases (hand-verified) + registry/vuln loaders + real anchor
# --------------------------------------------------------------------------- #
def _write(path, obj):
    with open(path, "w") as fh:
        if isinstance(obj, str):
            fh.write(obj)
        else:
            json.dump(obj, fh)


def _cli(argv):
    """Run the gate CLI, swallowing its stdout/stderr, returning the exit code."""
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return GATE.main(argv)


def run_deterministic_checks():
    """Fixed, hand-verified cases. Returns list of (name, ok, detail)."""
    results = []

    def check(name, fn):
        try:
            fn()
            results.append((name, True, "ok"))
        except Exception as e:
            results.append((name, False, "%r | %s" % (e, _short_tb())))

    def blocked(defects):
        return GATE.evaluate(defects)["blocked"]

    # ---- block-rule truth table (hand-verified) ----
    check("empty set does not block", lambda: (not blocked([])) or _raise())
    check("open P0 blocks", lambda: assert_true(blocked([{"id": "a", "priority": "P0", "status": "open"}])))
    check("open P1 blocks", lambda: assert_true(blocked([{"id": "a", "priority": "P1", "status": "open"}])))
    check("open P2 does not block",
          lambda: assert_true(not blocked([{"id": "a", "priority": "P2", "status": "open"}])))
    check("open P3 does not block",
          lambda: assert_true(not blocked([{"id": "a", "priority": "P3", "status": "open"}])))
    check("resolved P0 does not block",
          lambda: assert_true(not blocked([{"id": "a", "priority": "P0", "status": "resolved"}])))
    check("closed P1 does not block",
          lambda: assert_true(not blocked([{"id": "a", "priority": "P1", "status": "closed"}])))
    check("synonym critical->P0 open blocks",
          lambda: assert_true(blocked([{"id": "a", "priority": "critical", "status": "open"}])))
    check("synonym high->P1 + unknown status (open) blocks",
          lambda: assert_true(blocked([{"id": "a", "priority": "high", "status": "new"}])))
    check("synonym blocker->P0 open blocks",
          lambda: assert_true(blocked([{"id": "a", "priority": "blocker", "status": "open"}])))
    check("missing status => open (fail-closed) => P0 blocks",
          lambda: assert_true(blocked([{"id": "a", "priority": "P0"}])))
    check("empty defect {} does not block (no priority)",
          lambda: assert_true(not blocked([{}])))
    check("garbage priority open does not block",
          lambda: assert_true(not blocked([{"id": "a", "priority": "wat", "status": "open"}])))
    check("mixed-case + padded '  CrItIcAl ' open blocks",
          lambda: assert_true(blocked([{"id": "a", "priority": "  CrItIcAl ", "status": "OPEN"}])))
    check("uppercase RESOLVED status unblocks a P0",
          lambda: assert_true(not blocked([{"id": "a", "priority": "P0", "status": "RESOLVED"}])))
    check("any one open P1 in a set blocks",
          lambda: assert_true(blocked([{"id": "a", "priority": "P2", "status": "open"},
                                        {"id": "b", "priority": "P1", "status": "open"}])))
    check("hand-set blocking:true on an open P3 is IGNORED (no block)",
          lambda: assert_true(not blocked([{"id": "a", "priority": "P3", "status": "open",
                                            "blocking": True}])))
    check("hand-set blocking:false on an open P0 is IGNORED (still blocks)",
          lambda: assert_true(blocked([{"id": "a", "priority": "P0", "status": "open",
                                        "blocking": False}])))

    # ---- load_registry shapes ----
    def load_registry_shapes():
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.json")
            _write(p, [{"id": "a", "priority": "P0", "status": "open"}])
            assert_true(len(GATE.load_registry(p)) == 1)          # bare list
            _write(p, {"defects": [{"id": "a"}, {"id": "b"}]})
            assert_true(len(GATE.load_registry(p)) == 2)          # object with defects
            _write(p, {"note": "no defects key"})
            assert_true(GATE.load_registry(p) == [])              # object w/o defects -> []
            assert_true(expect_gate_error(lambda: GATE.load_registry(os.path.join(d, "nope.json"))))
            _write(p, "{ not valid json ]")
            assert_true(expect_gate_error(lambda: GATE.load_registry(p)))  # invalid JSON
            _write(p, 12345)
            assert_true(expect_gate_error(lambda: GATE.load_registry(p)))  # wrong top type
            _write(p, {"defects": {"not": "a list"}})
            assert_true(expect_gate_error(lambda: GATE.load_registry(p)))  # defects not list
            _write(p, [{"id": "ok"}, "not-an-object"])
            assert_true(expect_gate_error(lambda: GATE.load_registry(p)))  # non-dict defect
    check("load_registry accepts list/object, rejects missing/invalid/wrong-shape (fail-closed)",
          load_registry_shapes)

    # ---- vuln_derived_defects edges ----
    def vuln_edges():
        with tempfile.TemporaryDirectory() as d:
            assert_true(GATE.vuln_derived_defects(None) == [])
            assert_true(GATE.vuln_derived_defects(os.path.join(d, "absent.json")) == [])
            p = os.path.join(d, "v.json")
            _write(p, {"severity_totals": {"critical": 0, "high": 0}})
            assert_true(GATE.vuln_derived_defects(p) == [])
            _write(p, {"severity_totals": {"critical": 2, "high": 1}})
            der = GATE.vuln_derived_defects(p)
            assert_true(len(der) == 2)
            assert_true(GATE.evaluate(der)["blocked"] is True)
            _write(p, {"severity_totals": {"critical": "3"}})          # numeric string -> 3
            assert_true(len(GATE.vuln_derived_defects(p)) == 1)
            _write(p, {"severity_totals": {"critical": None, "high": None}})  # None -> 0
            assert_true(GATE.vuln_derived_defects(p) == [])
            _write(p, {})                                              # no severity_totals -> []
            assert_true(GATE.vuln_derived_defects(p) == [])
            _write(p, "not json at all")
            assert_true(expect_gate_error(lambda: GATE.vuln_derived_defects(p)))
            _write(p, {"severity_totals": {"critical": "abc"}})        # non-numeric -> GateError
            assert_true(expect_gate_error(lambda: GATE.vuln_derived_defects(p)))
    check("vuln_derived_defects: missing/absent/zero -> none; crit/high -> open P0/P1; malformed -> error",
          vuln_edges)

    # ---- CLI exit-code contract (0 pass / 1 block / 2 fail-closed) ----
    def cli_exit_codes():
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "r.json")
            _write(p, {"defects": [{"id": "a", "priority": "P0", "status": "open"}]})
            assert_true(_cli(["--registry", p, "--no-vuln"]) == 1)     # blocked
            _write(p, {"defects": [{"id": "a", "priority": "P3", "status": "open"}]})
            assert_true(_cli(["--registry", p, "--no-vuln"]) == 0)     # pass
            assert_true(_cli(["--registry", os.path.join(d, "gone.json"), "--no-vuln"]) == 2)  # error
            assert_true(_cli(["--registry", p, "--no-vuln", "--list"]) == 0)  # --list always 0
            assert_true(_cli(["--selftest"]) == 0)                     # gate's own selftest passes
    check("CLI exit codes: 1 blocked / 0 pass / 2 fail-closed / --list 0 / --selftest 0",
          cli_exit_codes)

    # ---- REAL committed registry regression anchor ----
    def real_registry_anchor():
        if not REAL_REGISTRY.exists():
            raise AssertionError("real registry missing: %s" % REAL_REGISTRY)
        defects = GATE.load_registry(str(REAL_REGISTRY))
        assert_true(len(defects) >= 1)
        result = GATE.evaluate(defects)
        # currently expected: 0 open P0/P1 => not blocked
        assert_true(result["open_priority_counts"]["P0"] == 0)
        assert_true(result["open_priority_counts"]["P1"] == 0)
        assert_true(result["blocked"] is False)
        assert_true(result["verdict"] == "PASS")
    check("real docs/release-defects.json: 0 open P0/P1 => not blocked (regression anchor)",
          real_registry_anchor)

    # ---- REAL registry + REAL vuln summary via the default gate path stays consistent ----
    def real_combined_consistency():
        if not (REAL_REGISTRY.exists() and REAL_VULN_SUMMARY.exists()):
            raise AssertionError("SKIP: real registry or vuln summary absent")
        with open(REAL_VULN_SUMMARY) as fh:
            totals = (json.load(fh) or {}).get("severity_totals", {})
        crit = int(totals.get("critical", 0) or 0)
        high = int(totals.get("high", 0) or 0)
        combined = GATE.collect_defects(str(REAL_REGISTRY), str(REAL_VULN_SUMMARY))
        res = GATE.evaluate(combined)
        # the committed registry has no open P0/P1, so the combined verdict is driven purely by the
        # vuln summary's critical/high totals -> correct regardless of future CVE state.
        assert_true(res["blocked"] == (crit > 0 or high > 0))
        # today both are zero -> not blocked (matches the "currently expected" state)
        if crit == 0 and high == 0:
            assert_true(res["blocked"] is False)
    check("real registry + real vuln-summary combined verdict tracks critical/high totals",
          real_combined_consistency)

    return results


def assert_true(cond):
    if not cond:
        raise AssertionError("expected True")
    return True


def _raise():
    raise AssertionError("unreachable")


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run_all(iters, seed):
    global _LOG_FH
    _LOG_FH = open(LOG_PATH, "w")
    log("START release-blocking-gate PBT  seed=%d iters=%d  gate=%s" % (seed, iters, GATE_PATH))
    log("Feature: cross-platform-live-verification (Property 22)")

    if not GATE_PATH.exists():
        log("FATAL: gate not found at %s" % GATE_PATH)
        return 1

    det = run_deterministic_checks()
    det_failed = [d for d in det if not d[1]]
    for name, ok, detail in det:
        log("  [det] %-72s %s%s" % (name, "OK" if ok else "FAIL",
                                    "" if ok else "  (%s)" % detail))
    log("Deterministic checks: %d/%d passed" % (len(det) - len(det_failed), len(det)))

    seed_rng = random.Random(seed)
    results = [
        run_property_block_semantics(seed_rng, iters),
        run_property_normalize_totality(seed_rng, iters),
        run_property_is_open_fail_closed(seed_rng, iters),
        run_property_vuln_autoingest(seed_rng, iters),
    ]
    for r in results:
        log("  %-52s ran=%d passed=%d failed=%d" % (r.name, r.ran, r.passed, r.failed))

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
        json.dump(summary, fh, indent=2, default=str)
    log("DONE overall=%s total_failures=%d  summary=%s"
        % (summary["overall"], total_failed, SUMMARY_PATH))
    _LOG_FH.close()
    _LOG_FH = None
    return 0 if total_failed == 0 else 1


# --------------------------------------------------------------------------- #
# pytest entry points (min 100 iterations enforced)
# --------------------------------------------------------------------------- #
_PYTEST_ITERS = int(os.environ.get("RBG_ITERS", "200"))
_PYTEST_SEED = int(os.environ.get("RBG_SEED", "2205"))


def test_property_22_block_iff_open_p0_p1():
    """Feature: cross-platform-live-verification, Property 22."""
    r = run_property_block_semantics(random.Random(_PYTEST_SEED), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "block-semantics counterexamples: %r" % r.failures[:5]


def test_property_22_normalize_priority_totality():
    """Feature: cross-platform-live-verification, Property 22."""
    r = run_property_normalize_totality(random.Random(_PYTEST_SEED + 1), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "normalize-totality counterexamples: %r" % r.failures[:5]


def test_property_22_is_open_fail_closed():
    """Feature: cross-platform-live-verification, Property 22."""
    r = run_property_is_open_fail_closed(random.Random(_PYTEST_SEED + 2), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "is-open counterexamples: %r" % r.failures[:5]


def test_property_22_vuln_summary_autoingest_blocks():
    """Feature: cross-platform-live-verification, Property 22."""
    r = run_property_vuln_autoingest(random.Random(_PYTEST_SEED + 3), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "vuln-autoingest counterexamples: %r" % r.failures[:5]


def test_deterministic_edge_cases_and_real_registry_anchor():
    """Feature: cross-platform-live-verification, Property 22 (edge cases + regression anchor)."""
    det = run_deterministic_checks()
    failed = [(d[0], d[2]) for d in det if not d[1]]
    assert not failed, "deterministic/anchor failures: %r" % failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Property tests for scripts/release_blocking_gate.py")
    ap.add_argument("--iters", type=int, default=200,
                    help="randomized iterations per property (min 100 enforced)")
    ap.add_argument("--seed", type=int,
                    default=int(os.environ.get("RBG_SEED", str(int(time.time())))))
    args = ap.parse_args()
    iters = max(100, args.iters)
    sys.exit(run_all(iters, args.seed))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Property tests for the evidence generator — scripts/gen-truth-table.py (task 1.3).

Feature: cross-platform-live-verification

These tests treat the task-1.2 evidence generator as the unit under test. Because the
generator's filename is hyphenated it is loaded via importlib.util.spec_from_file_location
and its pure functions are exercised in-process (fast, no subprocess, immune to the
interactive repo-scan startup hook + ~30s output cap that make the shell flaky here):

    parse_proto / parse_server_methods / load_inventory / build_matrix /
    render_truth_table / render_gap_report / emit / count_by_level /
    rpcs_without_server_method

Three design correctness properties are asserted over >=100 randomized iterations each,
by synthesizing faithful inputs (proto text, daemon Go sources, action-inventory cells)
and checking the generator's own invariants:

  * Property 7 — Contract coverage
      For any generated proto + server-method snapshot, the audit produces exactly one
      (RPC, frontend) coverage cell per frontend, the matrix has exactly
      rpc_count * frontend_count cells, and every cell carries a concrete server-method
      flag derived from the parsed daemon source (server_implemented == rpc in methods).
      Validates Requirements 3.1, 1.1, 5.1, 6.1 (task maps: 1.6, 1.8).

  * Property 8 — Evidence-level totality + environment-blocked labeling
      For any generated inventory every cell gets exactly one taxonomy level
      (count_by_level partitions the rows); a UIA/AT-SPI-blocked cell is labeled exactly
      `environment-blocked` (never coerced to a success level); and build_matrix raises
      GeneratorError on a missing level, a duplicate cell, a missing cell, or an
      out-of-taxonomy level, so a broken matrix is never emitted.
      Validates Requirements 1.2, 1.8, 9.6, 9.7.

  * Property 9 — Doc-regeneration idempotence + coverage
      For any source snapshot, running the generator twice yields byte-identical
      truth-table.csv and gap-report output, and every proto RPC appears at least once
      (whole-word) in the regenerated report and CSV.
      Validates Requirements 1.6.

Runnable directly (writes a summary log + JSON to /tmp and exits nonzero on any failure):

    python3 scripts/tests/test_gen_truth_table.py               # 150 iters/property
    python3 scripts/tests/test_gen_truth_table.py --iters 250 --seed 42

and also under pytest (the test_* functions assert zero property failures, >=100 iters).

It NEVER modifies gen-truth-table.py. A generator invariant that does not hold is surfaced
as a counterexample (a candidate real bug), never silently patched.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import random
import re
import sys
import tempfile
import time
import traceback
from pathlib import Path

# --------------------------------------------------------------------------- #
# Locations & generator import (hyphenated filename -> importlib by path)
# --------------------------------------------------------------------------- #
REPO_ROOT = Path(__file__).resolve().parents[2]
GEN_PATH = REPO_ROOT / "scripts" / "gen-truth-table.py"

LOG_PATH = Path(os.environ.get("GEN_TT_LOG", "/tmp/gen_truth_table_pbt.log"))
SUMMARY_PATH = Path(os.environ.get("GEN_TT_SUMMARY", "/tmp/gen_truth_table_pbt_summary.json"))

_LOG_FH = None


def log(msg: str) -> None:
    """Print to stdout and (if open) to the /tmp log, flushed, so a backgrounded run
    can be observed by reading the file back."""
    line = str(msg)
    print(line, flush=True)
    global _LOG_FH
    if _LOG_FH is not None:
        _LOG_FH.write(line + "\n")
        _LOG_FH.flush()


def load_generator():
    """Load scripts/gen-truth-table.py as a module via importlib (its name has hyphens)."""
    spec = importlib.util.spec_from_file_location("gen_truth_table", str(GEN_PATH))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GEN = load_generator()

# Constants pulled from the generator so the tests stay in lockstep with it.
FRONTENDS = tuple(GEN.FRONTENDS)
EVIDENCE_LEVELS = tuple(GEN.EVIDENCE_LEVELS)
POSITIVE_LEVELS = tuple(GEN.POSITIVE_LEVELS)
GeneratorError = GEN.GeneratorError

SERVICES = ("ColimaService", "DockerService")
SURFACES = ("dashboard", "containers", "images", "volumes", "networks", "profiles",
            "config", "template", "kubernetes", "ai", "runtime", "monitoring", "")
NAME_WORDS = ("Start", "Stop", "Restart", "Delete", "Status", "Version", "List",
              "Create", "Remove", "Inspect", "Prune", "Connect", "Disconnect",
              "Exec", "Serve", "Run", "Setup", "Kill", "Clone", "Switch",
              "Process", "Stats", "Fetch", "Attach", "Commit", "Export")
# Names the generator's legacy-claim reconciliation section calls out by name; injecting
# a few exercises that code path (CONTESTED_RPCS in the generator).
CONTESTED = ("PullImage", "PushImage", "GetConfig", "SetConfig", "GetTemplate", "SetTemplate")


# --------------------------------------------------------------------------- #
# Input synthesizers (faithful to the generator's parsers + inventory schema)
# --------------------------------------------------------------------------- #
def gen_rpc_specs(rng, n):
    """Return n unique RPC specs {name, service, request, response, stream}.

    Names are globally unique CamelCase tokens (optionally a few `CONTESTED` names) so
    the proto, inventory, and gap-report line up and whole-word coverage checks are exact.
    """
    contested = list(CONTESTED)
    rng.shuffle(contested)
    seeds = contested[: rng.randint(0, min(len(contested), max(0, n // 3)))]
    specs = []
    used = set()
    i = 0
    while len(specs) < n:
        if seeds:
            name = seeds.pop()
        else:
            name = "%s%d" % (rng.choice(NAME_WORDS), i)
            i += 1
        if name in used:
            i += 1
            continue
        used.add(name)
        req = rng.choice(["Empty", rng.choice(NAME_WORDS) + "Request"])
        resp = rng.choice(["StatusResponse", "JsonResponse", "VMStatus",
                           rng.choice(NAME_WORDS) + "Response"])
        specs.append({
            "name": name,
            "service": rng.choice(SERVICES),
            "request": req,
            "response": resp,
            "stream": rng.random() < 0.3,
        })
    return specs


def build_proto_text(rng, specs):
    """Emit proto text parse_proto can parse; return (text, ordered_names_in_file_order).

    Groups RPCs by service into `service X { ... }` blocks (each closed by a lone `}`),
    with random comments/indentation to exercise the parser's whitespace tolerance, and
    an optional trailing message block (ignored by the parser since it is outside a
    service). Non-empty service blocks are always emitted, so every RPC appears.
    """
    by_svc = {svc: [sp for sp in specs if sp["service"] == svc] for svc in SERVICES}
    lines = ['syntax = "proto3";', "", "package colimaui;", "",
             'option go_package = "github.com/colima-desktop/daemon/proto";', ""]
    ordered = []
    for svc in SERVICES:
        items = by_svc[svc]
        if not items:
            continue
        lines.append("service %s {" % svc)
        for sp in items:
            if rng.random() < 0.3:
                lines.append("  // %s" % sp["name"])
            stream = "stream " if sp["stream"] else ""
            indent = "  " if rng.random() < 0.85 else "    "
            lines.append("%srpc %s(%s) returns (%s%s);"
                         % (indent, sp["name"], sp["request"], stream, sp["response"]))
            ordered.append(sp["name"])
        if rng.random() < 0.3:
            lines.append("")
        lines.append("}")
        lines.append("")
    if rng.random() < 0.5:  # a message block the parser must ignore (current=None)
        lines += ["message SomeMessage {", "  string a = 1;", "  int32 b = 2;", "}", ""]
    return "\n".join(lines) + "\n", ordered


def build_go_sources(rng, method_names):
    """Return a list of synthetic Go file contents implementing exactly `method_names`
    as concrete ColimaServer/DockerServer receiver methods (so parse_server_methods must
    return exactly that set), plus noise that must NOT be captured:
      * free functions `func helper(...)`
      * methods on other receivers `func (c *docker.Client) ...`
    """
    names = list(method_names)
    rng.shuffle(names)
    nfiles = rng.randint(1, 3)
    files = [[] for _ in range(nfiles)]
    for idx, name in enumerate(names):
        recv = rng.choice(("ColimaServer", "DockerServer"))
        var = rng.choice(("s", "srv", "d", "x"))
        gap = " " if rng.random() < 0.75 else "  "
        files[idx % nfiles].append(
            "func (%s *%s)%s%s(ctx context.Context, r *pb.Req) (*pb.Resp, error) {\n"
            "\treturn nil, nil\n}\n" % (var, recv, gap, name)
        )
    for f in files:
        # noise: free function + non-server-receiver method (never matched by the regex)
        f.append("func helperNoise(x int) error { return nil }\n")
        f.append("func (c *docker.Client) CloseIdleConnections() {}\n")
        f.append("func (p *providerImpl) resolveTarget() error { return nil }\n")
    out = []
    for f in files:
        rng.shuffle(f)
        out.append("package server\n\nimport (\n\t\"context\"\n)\n\n" + "".join(f))
    return out


def build_cells(rng, specs, force_env_keys=None):
    """Build one inventory cell per (RPC, frontend) over FRONTENDS, matching the schema
    `{id, service, rpc, surface, frontend, server_implemented, frontend_handler,
    evidence_level}`. evidence_level is a random taxonomy value; keys in force_env_keys
    are forced to `environment-blocked`. The list is shuffled to prove build_matrix is
    order-independent (output order is driven by proto declaration order, not cell order).
    """
    force_env_keys = force_env_keys or set()
    cells = []
    for sp in specs:
        for fe in FRONTENDS:
            if (sp["name"], fe) in force_env_keys:
                level = "environment-blocked"
            else:
                level = rng.choice(EVIDENCE_LEVELS)
            cells.append({
                "id": "%s.%s:%s" % (sp["service"], sp["name"], fe),
                "service": sp["service"],
                "rpc": sp["name"],
                "surface": rng.choice(SURFACES),
                "frontend": fe,
                "server_implemented": rng.random() < 0.9,
                "frontend_handler": level != "source-only",
                "evidence_level": level,
            })
    rng.shuffle(cells)
    return cells


def make_snapshot(rng, n=None):
    """Build a complete, valid source snapshot for one iteration.

    Returns a dict with the proto text + ordered names + name->service map, the chosen
    server-method subset + synthetic Go sources, the inventory cells, and a meta dict
    (schema_version/generated_at) — mirroring the real load_inputs() shape where meta is
    the whole inventory object.
    """
    if n is None:
        n = rng.randint(1, 25)
    specs = gen_rpc_specs(rng, n)
    proto_text, ordered = build_proto_text(rng, specs)
    names = [sp["name"] for sp in specs]
    k = rng.randint(0, len(names))
    server_names = set(rng.sample(names, k))
    go_sources = build_go_sources(rng, server_names)
    cells = build_cells(rng, specs)
    meta = {
        "schema_version": rng.choice([1, 2, 3]),
        "generated_at": rng.choice(["2026-07-18", "2026-01-01", "unknown"]),
        "cells": cells,
    }
    return {
        "specs": specs,
        "names": names,
        "name2svc": {sp["name"]: sp["service"] for sp in specs},
        "proto_text": proto_text,
        "ordered": ordered,
        "server_names": server_names,
        "go_sources": go_sources,
        "cells": cells,
        "meta": meta,
    }


# --------------------------------------------------------------------------- #
# Result accumulator
# --------------------------------------------------------------------------- #
class PropResult:
    def __init__(self, name):
        self.name = name
        self.ran = 0
        self.passed = 0
        self.failures = []  # list of counterexample dicts

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
            log("  [COUNTEREXAMPLE] %s" % json.dumps(detail)[:600])


def _short_tb():
    return traceback.format_exc().strip().splitlines()[-1]


def expect_raises(fn):
    """Return True iff fn() raises GeneratorError."""
    try:
        fn()
        return False
    except GeneratorError:
        return True
    except Exception:
        return False  # wrong exception type is also a failure of the invariant


# --------------------------------------------------------------------------- #
# Property 7 — Contract coverage
# --------------------------------------------------------------------------- #
def run_property_7(seed_rng, iters):
    r = PropResult("Property 7 (contract coverage)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            snap = make_snapshot(rng)
            parsed = GEN.parse_proto(snap["proto_text"])

            # proto parse fidelity: exact names, order, count, and service assignment
            assert [d.name for d in parsed] == snap["ordered"], "parse order mismatch"
            assert {d.name for d in parsed} == set(snap["names"]), "parse name-set mismatch"
            assert len(parsed) == len(snap["specs"]), "parse count mismatch"
            for d in parsed:
                assert d.service == snap["name2svc"][d.name], "parse service mismatch"

            # concrete server-method flag comes from parsing the daemon source
            methods = GEN.parse_server_methods(snap["go_sources"])
            assert methods == snap["server_names"], \
                "parse_server_methods %r != %r" % (sorted(methods), sorted(snap["server_names"]))

            rows = GEN.build_matrix(parsed, methods, snap["cells"])

            # exactly rpc_count * frontend_count cells (the core Property 7 assertion)
            expected_cells = len(snap["specs"]) * len(FRONTENDS)
            assert len(rows) == expected_cells, \
                "cell count %d != %d" % (len(rows), expected_cells)

            keys = [(row.rpc, row.frontend) for row in rows]
            assert len(keys) == len(set(keys)), "duplicate (rpc, frontend) cell"
            assert set(keys) == {(nm, fe) for nm in snap["names"] for fe in FRONTENDS}, \
                "matrix keys != full RPC x frontend product"

            # exactly one cell per frontend per RPC
            for fe in FRONTENDS:
                fe_rpcs = [row.rpc for row in rows if row.frontend == fe]
                assert len(fe_rpcs) == len(snap["names"]), "frontend %s cell count" % fe
                assert set(fe_rpcs) == set(snap["names"]), "frontend %s rpc set" % fe

            # every cell carries a concrete server-method flag == (rpc in parsed methods)
            for row in rows:
                assert row.server_implemented == (row.rpc in snap["server_names"]), \
                    "server_implemented flag wrong for %s" % row.rpc

            # missing-server list == complement, order-preserving
            missing = GEN.rpcs_without_server_method(parsed, methods)
            assert set(missing) == (set(snap["names"]) - snap["server_names"]), \
                "rpcs_without_server_method set mismatch"
            assert missing == [d.name for d in parsed if d.name not in snap["server_names"]], \
                "rpcs_without_server_method order mismatch"

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 8 — Evidence-level totality + environment-blocked labeling
# --------------------------------------------------------------------------- #
def run_property_8(seed_rng, iters):
    r = PropResult("Property 8 (evidence totality + environment-blocked)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            specs = gen_rpc_specs(rng, rng.randint(1, 20))
            proto_text, _ = build_proto_text(rng, specs)
            parsed = GEN.parse_proto(proto_text)
            names = [sp["name"] for sp in specs]
            methods = set(rng.sample(names, rng.randint(0, len(names))))

            # force a random subset of cells to environment-blocked (UIA/AT-SPI-blocked)
            all_keys = [(sp["name"], fe) for sp in specs for fe in FRONTENDS]
            env_keys = set(rng.sample(all_keys, rng.randint(0, len(all_keys))))
            cells = build_cells(rng, specs, force_env_keys=env_keys)
            rows = GEN.build_matrix(parsed, methods, cells)

            # totality: every row has exactly one taxonomy level
            for row in rows:
                assert row.evidence_level in EVIDENCE_LEVELS, \
                    "level %r not in taxonomy" % row.evidence_level
            counts = GEN.count_by_level(rows)
            assert set(counts.keys()) == set(EVIDENCE_LEVELS), "count_by_level key set"
            assert sum(counts.values()) == len(rows), \
                "levels do not partition rows (%d != %d)" % (sum(counts.values()), len(rows))

            # environment-blocked labeling: forced cells are labeled exactly that
            row_by_key = {(row.rpc, row.frontend): row for row in rows}
            for key in env_keys:
                assert row_by_key[key].evidence_level == "environment-blocked", \
                    "forced env-blocked cell %r not labeled environment-blocked" % (key,)

            # build_matrix raises on missing level / duplicate / missing cell / bad level
            good = build_cells(rng, specs)  # a fresh valid inventory to mutate

            miss_level = [dict(c) for c in good]
            del miss_level[rng.randrange(len(miss_level))]["evidence_level"]
            assert expect_raises(lambda: GEN.build_matrix(parsed, methods, miss_level)), \
                "missing evidence_level did not raise"

            bad_level = [dict(c) for c in good]
            bad_level[rng.randrange(len(bad_level))]["evidence_level"] = "totally-bogus-%d" % iseed
            assert expect_raises(lambda: GEN.build_matrix(parsed, methods, bad_level)), \
                "out-of-taxonomy evidence_level did not raise"

            dup = [dict(c) for c in good]
            dup.append(dict(dup[rng.randrange(len(dup))]))  # duplicate a (rpc, frontend)
            assert expect_raises(lambda: GEN.build_matrix(parsed, methods, dup)), \
                "duplicate cell did not raise"

            drop = [dict(c) for c in good]
            drop.pop(rng.randrange(len(drop)))  # drop a required cell
            assert expect_raises(lambda: GEN.build_matrix(parsed, methods, drop)), \
                "missing coverage cell did not raise"

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Property 9 — Doc-regeneration idempotence + coverage
# --------------------------------------------------------------------------- #
def _full_pipeline(snap):
    """Run parse -> build -> render exactly as the generator would, from source strings."""
    parsed = GEN.parse_proto(snap["proto_text"])
    methods = GEN.parse_server_methods(snap["go_sources"])
    cells = GEN.load_inventory(snap["meta"])
    rows = GEN.build_matrix(parsed, methods, cells)
    csv_text = GEN.render_truth_table(rows)
    report = GEN.render_gap_report(rows, parsed, methods, snap["meta"])
    return parsed, csv_text, report


def run_property_9(seed_rng, iters):
    r = PropResult("Property 9 (regeneration idempotence + coverage)")
    for _ in range(iters):
        iseed = seed_rng.randrange(2 ** 63)
        rng = random.Random(iseed)
        try:
            snap = make_snapshot(rng)

            parsed1, csv1, rep1 = _full_pipeline(snap)
            _, csv2, rep2 = _full_pipeline(snap)  # regenerate from the same source

            # byte-identical output on repeated runs
            assert csv1.encode("utf-8") == csv2.encode("utf-8"), "truth-table.csv not idempotent"
            assert rep1.encode("utf-8") == rep2.encode("utf-8"), "gap-report not idempotent"

            # coverage: every proto RPC appears (whole-word) in the report AND the CSV
            for name in snap["names"]:
                pat = r"\b%s\b" % re.escape(name)
                assert re.search(pat, rep1), "RPC %s absent from gap-report" % name
                assert re.search(pat, csv1), "RPC %s absent from truth-table.csv" % name

            r.record_pass()
        except Exception as e:
            r.record_fail({"iter_seed": iseed, "error": repr(e), "where": _short_tb()})
    return r


# --------------------------------------------------------------------------- #
# Deterministic edge cases (hand-verified) + real-repo anchor
# --------------------------------------------------------------------------- #
def run_deterministic_checks():
    """Fixed, hand-verified cases. Returns list of (name, ok, detail)."""
    results = []

    def check(name, fn):
        try:
            fn()
            results.append((name, True, "ok"))
        except Exception as e:
            results.append((name, False, "%r | %s" % (e, _short_tb())))

    rng = random.Random(0xC0FFEE)

    # ---- Property 7 edges ----
    def p7_single_rpc():
        specs = [{"name": "Start", "service": "ColimaService", "request": "Empty",
                  "response": "StatusResponse", "stream": False}]
        proto_text, ordered = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        assert [d.name for d in parsed] == ordered == ["Start"]
        rows = GEN.build_matrix(parsed, {"Start"}, build_cells(rng, specs))
        assert len(rows) == len(FRONTENDS)
        assert all(row.server_implemented for row in rows)
        assert GEN.rpcs_without_server_method(parsed, {"Start"}) == []

    check("P7 single RPC -> exactly len(FRONTENDS) cells", p7_single_rpc)

    def p7_two_services_partial_server():
        specs = [
            {"name": "Status", "service": "ColimaService", "request": "Empty",
             "response": "VMStatus", "stream": False},
            {"name": "ListContainers", "service": "DockerService", "request": "DockerScope",
             "response": "JsonResponse", "stream": False},
        ]
        proto_text, ordered = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        assert [d.name for d in parsed] == ordered
        methods = {"Status"}  # ListContainers intentionally missing
        rows = GEN.build_matrix(parsed, methods, build_cells(rng, specs))
        assert len(rows) == 2 * len(FRONTENDS)
        for row in rows:
            assert row.server_implemented == (row.rpc == "Status")
        assert GEN.rpcs_without_server_method(parsed, methods) == ["ListContainers"]

    check("P7 two services, partial server methods", p7_two_services_partial_server)

    def p7_parse_server_ignores_noise():
        srcs = build_go_sources(rng, {"Start", "PullImage"})
        assert GEN.parse_server_methods(srcs) == {"Start", "PullImage"}

    check("P7 parse_server_methods ignores non-server receivers/free funcs",
          p7_parse_server_ignores_noise)

    # ---- Property 8 edges ----
    def p8_env_blocked_preserved():
        specs = [{"name": "VMStats", "service": "ColimaService", "request": "ProfileRequest",
                  "response": "VMStatsEvent", "stream": True}]
        proto_text, _ = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        cells = build_cells(rng, specs, force_env_keys={("VMStats", "windows")})
        rows = GEN.build_matrix(parsed, {"VMStats"}, cells)
        row = next(r for r in rows if r.frontend == "windows")
        assert row.evidence_level == "environment-blocked"

    check("P8 forced env-blocked cell keeps environment-blocked label", p8_env_blocked_preserved)

    def p8_totality_partition():
        specs = gen_rpc_specs(rng, 5)
        proto_text, _ = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        rows = GEN.build_matrix(parsed, set(), build_cells(rng, specs))
        counts = GEN.count_by_level(rows)
        assert sum(counts.values()) == len(rows) == 5 * len(FRONTENDS)

    check("P8 count_by_level partitions all rows", p8_totality_partition)

    def p8_raises_bad_level():
        specs = gen_rpc_specs(rng, 3)
        proto_text, _ = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        cells = build_cells(rng, specs)
        cells[0]["evidence_level"] = "made-up-level"
        assert expect_raises(lambda: GEN.build_matrix(parsed, set(), cells))

    check("P8 out-of-taxonomy level raises GeneratorError", p8_raises_bad_level)

    def p8_raises_missing_cell():
        specs = gen_rpc_specs(rng, 3)
        proto_text, _ = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        cells = build_cells(rng, specs)
        cells.pop()
        assert expect_raises(lambda: GEN.build_matrix(parsed, set(), cells))

    check("P8 missing coverage cell raises GeneratorError", p8_raises_missing_cell)

    def p8_raises_duplicate_cell():
        specs = gen_rpc_specs(rng, 3)
        proto_text, _ = build_proto_text(rng, specs)
        parsed = GEN.parse_proto(proto_text)
        cells = build_cells(rng, specs)
        cells.append(dict(cells[0]))
        assert expect_raises(lambda: GEN.build_matrix(parsed, set(), cells))

    check("P8 duplicate cell raises GeneratorError", p8_raises_duplicate_cell)

    # ---- Property 9 edges ----
    def p9_idempotent_and_emit_files():
        specs = gen_rpc_specs(rng, 8)
        proto_text, _ = build_proto_text(rng, specs)
        names = [sp["name"] for sp in specs]
        server_names = set(rng.sample(names, rng.randint(0, len(names))))
        go_sources = build_go_sources(rng, server_names)
        cells = build_cells(rng, specs)
        meta = {"schema_version": 2, "generated_at": "2026-07-18", "cells": cells}
        snap = {"proto_text": proto_text, "go_sources": go_sources, "meta": meta, "names": names}

        _, csv1, rep1 = _full_pipeline(snap)
        _, csv2, rep2 = _full_pipeline(snap)
        assert csv1 == csv2 and rep1 == rep2, "in-memory render not idempotent"

        # emit() to two scratch dirs and compare file bytes (the real write path)
        parsed = GEN.parse_proto(proto_text)
        methods = GEN.parse_server_methods(go_sources)
        rows = GEN.build_matrix(parsed, methods, GEN.load_inventory(meta))
        with tempfile.TemporaryDirectory() as d1, tempfile.TemporaryDirectory() as d2:
            GEN.emit(d1, rows, parsed, methods, meta)
            GEN.emit(d2, rows, parsed, methods, meta)
            for fname in ("truth-table.csv", "gap-report.md"):
                b1 = Path(d1, fname).read_bytes()
                b2 = Path(d2, fname).read_bytes()
                assert b1 == b2, "emit() %s not byte-identical across runs" % fname
        for name in names:
            assert re.search(r"\b%s\b" % re.escape(name), rep1), "RPC %s missing from report" % name

    check("P9 render + emit() byte-identical on repeat; every RPC covered",
          p9_idempotent_and_emit_files)

    # ---- Real-repo anchor (strong Property 7/8/9 evidence on live source) ----
    def real_repo_anchor():
        proto = getattr(GEN, "DEFAULT_PROTO")
        server_dir = getattr(GEN, "DEFAULT_SERVER_DIR")
        inventory = getattr(GEN, "DEFAULT_INVENTORY")
        if not (os.path.exists(proto) and os.path.isdir(server_dir) and os.path.exists(inventory)):
            raise AssertionError("SKIP: real repo inputs not present")
        inputs = GEN.load_inputs(proto, server_dir, inventory)
        rows = GEN.build_matrix(inputs.proto_rpcs, inputs.server_methods, inputs.inventory_cells)
        # Property 7 on real data: 65 RPCs, 260 cells, every RPC has a concrete method
        assert len(inputs.proto_rpcs) == GEN.EXPECTED_TOTAL_RPCS, \
            "real proto has %d RPCs" % len(inputs.proto_rpcs)
        assert len(rows) == GEN.EXPECTED_CELLS, "real matrix has %d cells" % len(rows)
        assert GEN.rpcs_without_server_method(inputs.proto_rpcs, inputs.server_methods) == []
        # Property 8 on real data: every cell level in taxonomy; counts partition rows
        counts = GEN.count_by_level(rows)
        assert sum(counts.values()) == len(rows)
        for row in rows:
            assert row.evidence_level in EVIDENCE_LEVELS
        # Property 9 on real data: idempotent render + full RPC coverage in the report
        rep1 = GEN.render_gap_report(rows, inputs.proto_rpcs, inputs.server_methods, inputs.inventory_meta)
        rep2 = GEN.render_gap_report(rows, inputs.proto_rpcs, inputs.server_methods, inputs.inventory_meta)
        csv1 = GEN.render_truth_table(rows)
        csv2 = GEN.render_truth_table(rows)
        assert rep1 == rep2 and csv1 == csv2, "real-repo render not idempotent"
        for decl in inputs.proto_rpcs:
            assert re.search(r"\b%s\b" % re.escape(decl.name), rep1), \
                "real RPC %s missing from report" % decl.name

    check("real-repo anchor: 65 RPCs / 260 cells / idempotent / full coverage",
          real_repo_anchor)

    return results


# --------------------------------------------------------------------------- #
# Orchestration
# --------------------------------------------------------------------------- #
def run_all(iters, seed):
    global _LOG_FH
    _LOG_FH = open(LOG_PATH, "w")
    log("START gen-truth-table PBT  seed=%d iters=%d  gen=%s" % (seed, iters, GEN_PATH))
    log("Feature: cross-platform-live-verification (Properties 7, 8, 9)")
    log("FRONTENDS=%r  EVIDENCE_LEVELS=%r" % (FRONTENDS, EVIDENCE_LEVELS))

    if not GEN_PATH.exists():
        log("FATAL: generator not found at %s" % GEN_PATH)
        return 1

    det = run_deterministic_checks()
    det_failed = [d for d in det if not d[1]]
    for name, ok, detail in det:
        log("  [det] %-58s %s%s" % (name, "OK" if ok else "FAIL",
                                    "" if ok else "  (%s)" % detail))
    log("Deterministic checks: %d/%d passed" % (len(det) - len(det_failed), len(det)))

    seed_rng = random.Random(seed)
    results = [
        run_property_7(seed_rng, iters),
        run_property_8(seed_rng, iters),
        run_property_9(seed_rng, iters),
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
        json.dump(summary, fh, indent=2)
    log("DONE overall=%s total_failures=%d  summary=%s"
        % (summary["overall"], total_failed, SUMMARY_PATH))
    _LOG_FH.close()
    return 0 if total_failed == 0 else 1


# --------------------------------------------------------------------------- #
# pytest entry points (min 100 iterations enforced)
# --------------------------------------------------------------------------- #
_PYTEST_ITERS = int(os.environ.get("GEN_TT_ITERS", "150"))
_PYTEST_SEED = int(os.environ.get("GEN_TT_SEED", "1310"))


def test_property_7_contract_coverage():
    """Feature: cross-platform-live-verification, Property 7."""
    r = run_property_7(random.Random(_PYTEST_SEED), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "contract-coverage counterexamples: %r" % r.failures[:5]


def test_property_8_evidence_totality_and_environment_blocked():
    """Feature: cross-platform-live-verification, Property 8."""
    r = run_property_8(random.Random(_PYTEST_SEED + 1), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "evidence-totality counterexamples: %r" % r.failures[:5]


def test_property_9_regeneration_idempotence_and_coverage():
    """Feature: cross-platform-live-verification, Property 9."""
    r = run_property_9(random.Random(_PYTEST_SEED + 2), _PYTEST_ITERS)
    assert r.ran >= 100, "must run >=100 iterations, ran %d" % r.ran
    assert r.failed == 0, "regeneration counterexamples: %r" % r.failures[:5]


def test_deterministic_edge_cases():
    det = run_deterministic_checks()
    failed = [(d[0], d[2]) for d in det if not d[1]]
    assert not failed, "deterministic edge case failures: %r" % failed


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description="Property tests for scripts/gen-truth-table.py")
    ap.add_argument("--iters", type=int, default=150,
                    help="randomized iterations per property (min 100 enforced)")
    ap.add_argument("--seed", type=int,
                    default=int(os.environ.get("GEN_TT_SEED", str(int(time.time())))))
    args = ap.parse_args()
    iters = max(100, args.iters)
    sys.exit(run_all(iters, args.seed))


if __name__ == "__main__":
    main()

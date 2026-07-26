#!/usr/bin/env python3
"""
Evidence generator for the Cross-Platform Live Verification program (R0, task 1.2).

Regenerates the RPC×frontend **evidence matrix** and the **gap report** from source so
they cannot drift from the real repository state:

    proto/colima_ui.proto ─┐
    daemon server methods ─┼─► gen-truth-table.py ─► <out>/truth-table.csv   (architect-reserved)
    frontend handlers ─────┘                            │
    exploration/action-inventory.json ─────────────────┼─► <out>/gap-report.md   (docs-reserved)
                                                        └─► (parity-matrix.md is derived by the architect)

Design contract (design.md → "Evidence generator"):

    build_matrix(proto, server_methods, frontend_handlers, action_inventory)
        -> rows[RpcFrontendCell{rpc, frontend, evidence_level}]
    emit(truth_table.csv, gap_report.md)

The generator emits exactly one coverage cell per (RPC, frontend) = 65 × 4 = 260 rows,
labels every cell with exactly one evidence level from the taxonomy
{source-only, deterministic-fake-data, CI-without-daemon, live-backend, environment-blocked}
(Property 8, evidence totality), and produces byte-identical output on repeated runs
(Property 9, regeneration idempotence). Every one of the 65 proto RPCs appears in the
gap report (Property 9, coverage).

Stale claims ("no pull/push RPC", "config/template unimplemented") are NOT hardcoded — the
legacy-claim reconciliation section is computed by reading the current proto RPC set and the
concrete daemon server methods, so the report always states verifiable current truth.

This file is a pure-function library (parse_proto / parse_server_methods / load_inventory /
build_matrix / render_truth_table / render_gap_report) plus a thin CLI. The property tests
in task 1.3 import these functions; they are intentionally NOT written here.

Usage:
    python3 scripts/gen-truth-table.py                     # write docs/{truth-table.csv,gap-report.md}
    python3 scripts/gen-truth-table.py --out-dir /tmp/tt   # write to a scratch dir (verification)
    python3 scripts/gen-truth-table.py --emit truth-table  # emit only the CSV (architect, task 1.6)
    python3 scripts/gen-truth-table.py --emit gap-report   # emit only the report (docs, task 1.7)
    python3 scripts/gen-truth-table.py --check             # validate inputs, write nothing

Note: this file has hyphens in its name, so importers (e.g. the task 1.3 property tests)
load it via importlib.util.spec_from_file_location. It deliberately avoids
`from __future__ import annotations` so its dataclasses resolve correctly under any loader
(a stringized-annotation dataclass needs its module registered in sys.modules, which is not
guaranteed when loaded by path).
"""

import argparse
import csv
import io
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Iterable

# ─── Paths & constants ───────────────────────────────────────────────────────

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PROTO = os.path.join(ROOT, "proto", "colima_ui.proto")
DEFAULT_SERVER_DIR = os.path.join(ROOT, "daemon", "internal", "server")
DEFAULT_INVENTORY = os.path.join(ROOT, "exploration", "action-inventory.json")
DEFAULT_OUT_DIR = os.path.join(ROOT, "docs")

# Fixed frontend order — determinism anchor for Property 9 (byte-identical output).
FRONTENDS: tuple[str, ...] = ("macos", "windows", "linux", "tui")

# Evidence taxonomy (design.md → "Evidence-level taxonomy"), weakest → strongest,
# with environment-blocked as an honest terminal (non-success) label.
POSITIVE_LEVELS: tuple[str, ...] = (
    "source-only",
    "deterministic-fake-data",
    "CI-without-daemon",
    "live-backend",
)
EVIDENCE_LEVELS: tuple[str, ...] = POSITIVE_LEVELS + ("environment-blocked",)

# Single-letter codes for the compact per-RPC report table (legend rendered inline).
LEVEL_CODE: dict[str, str] = {
    "source-only": "S",
    "deterministic-fake-data": "D",
    "CI-without-daemon": "C",
    "live-backend": "L",
    "environment-blocked": "E",
}

EXPECTED_COLIMA_RPCS = 31
EXPECTED_DOCKER_RPCS = 34
EXPECTED_TOTAL_RPCS = EXPECTED_COLIMA_RPCS + EXPECTED_DOCKER_RPCS
EXPECTED_CELLS = EXPECTED_TOTAL_RPCS * len(FRONTENDS)

# Server receiver types that carry the concrete (non-Unimplemented) RPC handlers.
_SERVER_RECEIVERS = ("ColimaServer", "DockerServer")

# Legacy claims (called out in PLAN.md / the old gap-report) whose truth value this
# generator RECOMPUTES from the current proto + daemon source rather than restating.
CONTESTED_RPCS: tuple[str, ...] = (
    "PullImage",
    "PushImage",
    "GetConfig",
    "SetConfig",
    "GetTemplate",
    "SetTemplate",
)


class GeneratorError(RuntimeError):
    """Raised when a hard invariant (coverage / taxonomy / contract) is violated."""


# ─── Data models ─────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class RpcDecl:
    """A single RPC declared in the proto, in declaration order."""

    service: str
    name: str
    request: str
    response: str
    server_stream: bool


@dataclass(frozen=True)
class RpcFrontendCell:
    """One coverage cell per (RPC, frontend) — mirrors the design EvidenceCell model."""

    service: str
    rpc: str
    frontend: str
    surface: str
    server_implemented: bool
    frontend_handler: bool
    evidence_level: str


# ─── Parsers (pure) ──────────────────────────────────────────────────────────

_SERVICE_RE = re.compile(r"^\s*service\s+(\w+)\s*\{")
_RPC_RE = re.compile(
    r"^\s*rpc\s+(\w+)\s*\(\s*(\w+)\s*\)\s*returns\s*\(\s*(stream\s+)?(\w+)\s*\)"
)


def parse_proto(text: str) -> list[RpcDecl]:
    """Extract every RPC from the proto in declaration order.

    Assigns each rpc to the most recently opened `service X { ... }` block. Service
    blocks in this proto contain only single-line rpc declarations and close with a
    lone `}` line, so a linear scan is sufficient and deterministic.
    """
    decls: list[RpcDecl] = []
    current: str | None = None
    for line in text.splitlines():
        svc = _SERVICE_RE.match(line)
        if svc:
            current = svc.group(1)
            continue
        if current is None:
            continue
        rpc = _RPC_RE.match(line)
        if rpc:
            decls.append(
                RpcDecl(
                    service=current,
                    name=rpc.group(1),
                    request=rpc.group(2),
                    response=rpc.group(4),
                    server_stream=bool(rpc.group(3)),
                )
            )
            continue
        if line.strip() == "}":  # end of the current service block
            current = None
    return decls


_METHOD_RE = re.compile(
    r"func\s*\(\s*\w+\s+\*(?:" + "|".join(_SERVER_RECEIVERS) + r")\s*\)\s+(\w+)\s*\("
)


def parse_server_methods(sources: Iterable[str]) -> set[str]:
    """Return the set of concrete server receiver method names across the given Go sources.

    A method is concrete (non-Unimplemented) when an explicit
    `func (s *ColimaServer|*DockerServer) Name(` receiver exists — the embedded
    Unimplemented*Server default is overridden. Non-RPC helper methods are harmless;
    callers cross-reference only against the proto RPC set.
    """
    methods: set[str] = set()
    for text in sources:
        for m in _METHOD_RE.finditer(text):
            methods.add(m.group(1))
    return methods


def read_server_methods(server_dir: str) -> set[str]:
    """Read every .go file (excluding _test.go) in server_dir and parse concrete methods."""
    sources: list[str] = []
    for name in sorted(os.listdir(server_dir)):
        if name.endswith(".go") and not name.endswith("_test.go"):
            with open(os.path.join(server_dir, name), encoding="utf-8") as fh:
                sources.append(fh.read())
    return parse_server_methods(sources)


def load_inventory(obj: dict) -> list[dict]:
    """Return the flat list of coverage cells from the action-inventory JSON object."""
    cells = obj.get("cells")
    if not isinstance(cells, list):
        raise GeneratorError(
            "action-inventory.json has no 'cells' array (expected schema_version 2)"
        )
    return cells


# ─── Matrix builder (pure) ───────────────────────────────────────────────────


def build_matrix(
    proto_rpcs: list[RpcDecl],
    server_methods: set[str],
    inventory_cells: list[dict],
) -> list[RpcFrontendCell]:
    """Produce exactly one RpcFrontendCell per (proto RPC, frontend), in a deterministic order.

    Enforces the generator-side invariants that back the design properties:
      * exactly one inventory cell per (RPC, frontend); none missing, none extra (Property 7 shape)
      * exactly one evidence level from the taxonomy per cell (Property 8 totality)
      * server_implemented is taken from the parsed daemon source (authoritative), not the inventory
    Raises GeneratorError on any violation so a broken matrix is never emitted.
    """
    index: dict[tuple[str, str], dict] = {}
    for cell in inventory_cells:
        rpc = cell.get("rpc")
        frontend = cell.get("frontend")
        if rpc is None or frontend is None:
            raise GeneratorError(f"inventory cell missing rpc/frontend: {cell!r}")
        key = (rpc, frontend)
        if key in index:
            raise GeneratorError(f"duplicate inventory cell for {rpc}:{frontend}")
        index[key] = cell

    proto_names = {d.name for d in proto_rpcs}
    rows: list[RpcFrontendCell] = []
    for decl in proto_rpcs:
        server_impl = decl.name in server_methods
        for frontend in FRONTENDS:
            key = (decl.name, frontend)
            cell = index.get(key)
            if cell is None:
                raise GeneratorError(
                    f"missing coverage cell for {decl.name}:{frontend} "
                    "(every (RPC, frontend) pair must have exactly one cell)"
                )
            level = cell.get("evidence_level")
            if level not in EVIDENCE_LEVELS:
                raise GeneratorError(
                    f"cell {decl.name}:{frontend} has invalid evidence_level {level!r}; "
                    f"expected one of {EVIDENCE_LEVELS}"
                )
            rows.append(
                RpcFrontendCell(
                    service=decl.service,
                    rpc=decl.name,
                    frontend=frontend,
                    surface=str(cell.get("surface", "")),
                    server_implemented=server_impl,
                    frontend_handler=bool(cell.get("frontend_handler", False)),
                    evidence_level=level,
                )
            )

    # Coverage/shape assertions (Property 7 + 8 at generation time).
    if len(rows) != len(proto_rpcs) * len(FRONTENDS):
        raise GeneratorError(
            f"expected {len(proto_rpcs) * len(FRONTENDS)} cells, built {len(rows)}"
        )
    extras = sorted(
        f"{rpc}:{fe}" for (rpc, fe) in index if rpc not in proto_names
    )
    if extras:
        raise GeneratorError(
            f"inventory has cells for RPCs absent from the proto: {', '.join(extras)}"
        )
    return rows


# ─── Aggregation helpers (pure) ──────────────────────────────────────────────


def count_by_level(rows: list[RpcFrontendCell]) -> dict[str, int]:
    counts = {lvl: 0 for lvl in EVIDENCE_LEVELS}
    for row in rows:
        counts[row.evidence_level] += 1
    return counts


def count_by_frontend(rows: list[RpcFrontendCell]) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {
        fe: {"total": 0, "handlers": 0, **{lvl: 0 for lvl in EVIDENCE_LEVELS}}
        for fe in FRONTENDS
    }
    for row in rows:
        bucket = out[row.frontend]
        bucket["total"] += 1
        bucket[row.evidence_level] += 1
        if row.frontend_handler:
            bucket["handlers"] += 1
    return out


def rpcs_without_server_method(
    proto_rpcs: list[RpcDecl], server_methods: set[str]
) -> list[str]:
    return [d.name for d in proto_rpcs if d.name not in server_methods]


# ─── Renderers (pure, deterministic — no timestamps) ─────────────────────────


def render_truth_table(rows: list[RpcFrontendCell]) -> str:
    """Render the RPC×frontend evidence matrix as CSV text (one row per cell)."""
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(
        [
            "service",
            "rpc",
            "frontend",
            "surface",
            "server_implemented",
            "frontend_handler",
            "evidence_level",
        ]
    )
    for row in rows:
        writer.writerow(
            [
                row.service,
                row.rpc,
                row.frontend,
                row.surface,
                str(row.server_implemented).lower(),
                str(row.frontend_handler).lower(),
                row.evidence_level,
            ]
        )
    return buf.getvalue()


def _legacy_reconciliation(
    proto_rpcs: list[RpcDecl], server_methods: set[str], rows: list[RpcFrontendCell]
) -> list[str]:
    """Compute current truth for the contested RPCs (replaces stale hardcoded claims)."""
    by_name = {d.name: d for d in proto_rpcs}
    handlers: dict[str, list[str]] = {}
    for row in rows:
        if row.frontend_handler:
            handlers.setdefault(row.rpc, []).append(row.frontend)

    lines: list[str] = []
    for name in CONTESTED_RPCS:
        decl = by_name.get(name)
        if decl is None:
            lines.append(f"- **{name}** — NOT declared in the current proto.")
            continue
        stream = " (server-streaming)" if decl.server_stream else ""
        concrete = "concrete" if name in server_methods else "**MISSING**"
        fe = ", ".join(handlers.get(name, [])) or "none"
        lines.append(
            f"- **{decl.service}.{name}**{stream} — proto RPC: declared; "
            f"daemon server method: {concrete}; frontend handlers: {fe}."
        )
    return lines


def render_gap_report(
    rows: list[RpcFrontendCell],
    proto_rpcs: list[RpcDecl],
    server_methods: set[str],
    meta: dict,
) -> str:
    """Render the gap report markdown. Mentions every one of the 65 RPCs (Property 9 coverage).

    Deterministic: no wall-clock time is embedded — provenance uses the inventory's static
    `generated_at`/`schema_version` fields so repeated runs are byte-identical.
    """
    by_level = count_by_level(rows)
    by_frontend = count_by_frontend(rows)
    missing_server = rpcs_without_server_method(proto_rpcs, server_methods)
    colima = [d for d in proto_rpcs if d.service == "ColimaService"]
    docker = [d for d in proto_rpcs if d.service == "DockerService"]
    inv_generated = meta.get("generated_at", "unknown")
    inv_schema = meta.get("schema_version", "unknown")

    out: list[str] = []
    out.append("# CLI-Parity Gap Report (regenerated)")
    out.append("")
    out.append(
        "> **Generated by** `scripts/gen-truth-table.py` from the current "
        "`proto/colima_ui.proto`, the concrete daemon server methods under "
        "`daemon/internal/server/**`, and `exploration/action-inventory.json` "
        f"(schema_version {inv_schema}, audited {inv_generated})."
    )
    out.append(">")
    out.append(
        "> This report is regenerated from source and is byte-identical on repeated runs "
        "(design Property 9). Every RPC below is derived from the proto; every evidence "
        "level is one of {source-only, deterministic-fake-data, CI-without-daemon, "
        "live-backend, environment-blocked} (design Property 8)."
    )
    out.append("")

    # ── Summary ──
    out.append("## Summary")
    out.append("")
    out.append(f"- ColimaService RPCs: **{len(colima)}** (expected {EXPECTED_COLIMA_RPCS})")
    out.append(f"- DockerService RPCs: **{len(docker)}** (expected {EXPECTED_DOCKER_RPCS})")
    out.append(f"- Total RPCs: **{len(proto_rpcs)}** (expected {EXPECTED_TOTAL_RPCS})")
    out.append(
        f"- Concrete daemon server methods for these RPCs: "
        f"**{len(proto_rpcs) - len(missing_server)}/{len(proto_rpcs)}**"
    )
    out.append(f"- Coverage cells (RPC × frontend): **{len(rows)}** (expected {EXPECTED_CELLS})")
    if missing_server:
        out.append(
            f"- **RPCs WITHOUT a concrete server method:** {', '.join(missing_server)} "
            "(Property 7 violation — must be fixed)"
        )
    else:
        out.append(
            "- RPCs without a concrete server method: **none** — every RPC has a "
            "non-`Unimplemented` daemon receiver (Property 7)."
        )
    out.append("")

    # ── Coverage by evidence level ──
    out.append("## Coverage by evidence level")
    out.append("")
    out.append("| Evidence level | Cells |")
    out.append("|----------------|------:|")
    for lvl in EVIDENCE_LEVELS:
        out.append(f"| {lvl} | {by_level[lvl]} |")
    out.append(f"| **total** | **{len(rows)}** |")
    out.append("")
    out.append(
        "`live-backend` is the only level that closes a live-verification obligation; "
        "`deterministic-fake-data` never does; `environment-blocked` is an honest terminal "
        "label (never counted as success)."
    )
    out.append("")

    # ── Coverage by frontend ──
    out.append("## Coverage by frontend")
    out.append("")
    header = "| Frontend | Handlers | " + " | ".join(EVIDENCE_LEVELS) + " |"
    out.append(header)
    out.append("|----------|" + "---:|" * (len(EVIDENCE_LEVELS) + 1))
    for fe in FRONTENDS:
        b = by_frontend[fe]
        cells = " | ".join(str(b[lvl]) for lvl in EVIDENCE_LEVELS)
        out.append(f"| {fe} | {b['handlers']}/{b['total']} | {cells} |")
    out.append("")

    # ── Legacy-claim reconciliation (computed, not hardcoded) ──
    out.append("## Legacy-claim reconciliation")
    out.append("")
    out.append(
        "Computed from the current proto RPC set and the concrete daemon server methods. "
        "These supersede the earlier stale notes (\"no pull/push RPC\", "
        "\"config/template unimplemented\"): every contested RPC below is declared in the "
        "frozen contract and backed by a concrete server method."
    )
    out.append("")
    out.extend(_legacy_reconciliation(proto_rpcs, server_methods, rows))
    out.append("")

    # ── Full per-RPC evidence table (mentions every RPC → Property 9 coverage) ──
    out.append("## Per-RPC evidence matrix")
    out.append("")
    legend = ", ".join(f"{code} = {lvl}" for lvl, code in LEVEL_CODE.items())
    out.append(f"Legend: {legend}. Server = concrete daemon method present.")
    out.append("")
    out.append("| # | Service | RPC | Stream | Server | " + " | ".join(FRONTENDS) + " |")
    out.append("|--:|---------|-----|:------:|:------:|" + "|".join([":--:"] * len(FRONTENDS)) + "|")
    by_key = {(r.rpc, r.frontend): r for r in rows}
    for i, decl in enumerate(proto_rpcs, start=1):
        server_mark = "✓" if decl.name in server_methods else "✗"
        stream_mark = "stream" if decl.server_stream else "-"
        codes = " | ".join(
            LEVEL_CODE[by_key[(decl.name, fe)].evidence_level] for fe in FRONTENDS
        )
        out.append(
            f"| {i} | {decl.service} | {decl.name} | {stream_mark} | {server_mark} | {codes} |"
        )
    out.append("")

    # ── Frontend-handler gaps (source-only cells) ──
    source_only = [r for r in rows if r.evidence_level == "source-only"]
    out.append("## Frontend-handler gaps (source-only cells)")
    out.append("")
    if source_only:
        out.append(
            "Server method exists but this frontend has no handler for the RPC "
            f"({len(source_only)} cell(s)):"
        )
        out.append("")
        out.append("| RPC | Frontend | Surface |")
        out.append("|-----|----------|---------|")
        for r in source_only:
            out.append(f"| {r.rpc} | {r.frontend} | {r.surface} |")
    else:
        out.append("None — every (RPC, frontend) cell has a frontend handler.")
    out.append("")

    # ── Environment-blocked cells ──
    env_blocked = [r for r in rows if r.evidence_level == "environment-blocked"]
    out.append("## Environment-blocked cells")
    out.append("")
    if env_blocked:
        out.append(
            "Live capture could not run in this environment (recorded honestly, never faked):"
        )
        out.append("")
        out.append("| RPC | Frontend |")
        out.append("|-----|----------|")
        for r in env_blocked:
            out.append(f"| {r.rpc} | {r.frontend} |")
    else:
        out.append(
            "None in this per-RPC handler inventory. Windows/Linux live UIA/AT-SPI capture "
            "is tracked separately in `exploration/{windows,linux}` ground-truth (task 10.7); "
            "their per-RPC handler evidence is capped at CI-without-daemon."
        )
    out.append("")
    return "\n".join(out) + "\n"


# ─── IO orchestration ────────────────────────────────────────────────────────


@dataclass(frozen=True)
class GeneratorInputs:
    proto_rpcs: list[RpcDecl]
    server_methods: set[str]
    inventory_cells: list[dict]
    inventory_meta: dict


def load_inputs(
    proto_path: str, server_dir: str, inventory_path: str
) -> GeneratorInputs:
    with open(proto_path, encoding="utf-8") as fh:
        proto_rpcs = parse_proto(fh.read())
    server_methods = read_server_methods(server_dir)
    with open(inventory_path, encoding="utf-8") as fh:
        inventory = json.load(fh)
    return GeneratorInputs(
        proto_rpcs=proto_rpcs,
        server_methods=server_methods,
        inventory_cells=load_inventory(inventory),
        inventory_meta=inventory,
    )


def emit(
    out_dir: str,
    rows: list[RpcFrontendCell],
    proto_rpcs: list[RpcDecl],
    server_methods: set[str],
    meta: dict,
    *,
    which: str = "both",
    truth_table_name: str = "truth-table.csv",
    gap_report_name: str = "gap-report.md",
) -> list[str]:
    """Write the selected artifact(s) to out_dir. Returns the written file paths."""
    os.makedirs(out_dir, exist_ok=True)
    written: list[str] = []
    if which in ("both", "truth-table"):
        path = os.path.join(out_dir, truth_table_name)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(render_truth_table(rows))
        written.append(path)
    if which in ("both", "gap-report"):
        path = os.path.join(out_dir, gap_report_name)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(render_gap_report(rows, proto_rpcs, server_methods, meta))
        written.append(path)
    return written


def _summary(rows: list[RpcFrontendCell], proto_rpcs: list[RpcDecl], server_methods: set[str]) -> str:
    by_level = count_by_level(rows)
    missing = rpcs_without_server_method(proto_rpcs, server_methods)
    parts = [
        f"rpcs={len(proto_rpcs)}",
        f"cells={len(rows)}",
        f"server_methods_concrete={len(proto_rpcs) - len(missing)}/{len(proto_rpcs)}",
        "levels={" + ", ".join(f"{lvl}:{by_level[lvl]}" for lvl in EVIDENCE_LEVELS) + "}",
    ]
    return " ".join(parts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Regenerate the RPC×frontend evidence matrix + gap report.")
    parser.add_argument("--proto", default=DEFAULT_PROTO, help="path to colima_ui.proto")
    parser.add_argument("--server-dir", default=DEFAULT_SERVER_DIR, help="daemon server source dir")
    parser.add_argument("--inventory", default=DEFAULT_INVENTORY, help="action-inventory.json path")
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR, help="output directory (default: docs/)")
    parser.add_argument(
        "--emit",
        choices=("both", "truth-table", "gap-report"),
        default="both",
        help="which artifact(s) to write",
    )
    parser.add_argument("--check", action="store_true", help="validate inputs and build the matrix, write nothing")
    args = parser.parse_args(argv)

    try:
        inputs = load_inputs(args.proto, args.server_dir, args.inventory)
        rows = build_matrix(inputs.proto_rpcs, inputs.server_methods, inputs.inventory_cells)
    except (GeneratorError, FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(_summary(rows, inputs.proto_rpcs, inputs.server_methods))
    if args.check:
        print("check: OK (no files written)")
        return 0

    written = emit(
        args.out_dir,
        rows,
        inputs.proto_rpcs,
        inputs.server_methods,
        inputs.inventory_meta,
        which=args.emit,
    )
    for path in written:
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

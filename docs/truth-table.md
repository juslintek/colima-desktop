# Colima Desktop — RPC × Frontend Evidence Matrix

`truth-table.csv` is the machine-readable **RPC × frontend evidence matrix**, regenerated
from source by `scripts/gen-truth-table.py` (design R0). It contains **260 rows**
(65 frozen-contract RPCs × 4 frontends: macOS, Windows, Linux, TUI) — exactly one
coverage cell per (RPC, frontend) pair.

> **Superseded format note:** an earlier `truth-table.csv` enumerated a large
> action→outcome combinatorial space (VM-config cross-products). That artifact has been
> replaced by this evidence matrix as part of the R0 board-vs-reality reconciliation, so the
> table is derived from — and cannot drift from — the real proto, daemon, and frontend source.

Columns: `service, rpc, frontend, surface, server_implemented, frontend_handler, evidence_level`.

## How it is generated

```
proto/colima_ui.proto ─┐
daemon server methods ─┼─► scripts/gen-truth-table.py ─► truth-table.csv  (this file's data)
frontend handlers ─────┘                                    │
exploration/action-inventory.json ─────────────────────────┴─► gap-report.md
```

- `server_implemented` is derived from the concrete (`non-Unimplemented`) daemon receiver
  methods under `daemon/internal/server/**` — not hand-maintained.
- `frontend_handler` and `evidence_level` come from `exploration/action-inventory.json`
  (schema_version 2), the read-only per-frontend audit.
- Output is **byte-identical on repeated runs** (no embedded wall-clock time) — design
  Property 9 (regeneration idempotence), and every one of the 65 RPCs appears at least once
  (Property 9 coverage). Every cell carries exactly one evidence level (Property 8).

## Evidence-level taxonomy

| Level | Meaning |
|-------|---------|
| `source-only` | A concrete daemon method exists, but this frontend has no handler for the RPC. |
| `deterministic-fake-data` | Renders/behaves correctly against fakeDS fixtures (regression only). |
| `CI-without-daemon` | Compiles and passes its suite on a native CI runner without a live daemon. |
| `live-backend` | Verified against a live Colima daemon on the disposable `desktop-e2e` profile. |
| `environment-blocked` | Live UIA/AT-SPI capture could not run in this environment (recorded, never faked). |

`live-backend` is the only level that closes a live-verification obligation.

## Current coverage (regenerated)

- 65/65 RPCs have a concrete daemon server method (0 unimplemented).
- Per-frontend handlers: macOS 61/65, Windows 65/65, Linux 65/65, TUI 61/65.
- By evidence level: live-backend 26, CI-without-daemon 226, source-only 8,
  deterministic-fake-data 0, environment-blocked 0.
- Remaining `source-only` gaps: macOS `GetTemplate`/`SetTemplate` (template UI — R5),
  `VMStats`, `PushImage`; TUI `Version`, `StreamEvents`/`StreamLogs`/`StreamStats`.

See [gap-report.md](gap-report.md) for the full per-RPC matrix and the legacy-claim
reconciliation, and [parity/overview.md](parity/overview.md) for the parity model.

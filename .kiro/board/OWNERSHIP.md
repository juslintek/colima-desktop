# Program Board — OWNERSHIP (path → agent) + lock table

> No two write-agents may own overlapping paths. Claim a path in the LOCK TABLE before
> editing; release when done. The integration agent is the ONLY merger to `main`.

## Path ownership (disjoint by construction)

| Path | Owner agent |
|------|-------------|
| `daemon/**` | go-daemon-dev |
| `proto/**` | go-daemon-dev (proposes) → architect (approves) |
| `Sources/**` | swiftui-dev |
| `windows/**` | windows-native-dev |
| `linux/**` | linux-native-dev |
| `tui/**` | tui-dev |
| `Tests/**` | swift-test-engineer |
| `exploration/**` | *-ui-explorer agents |
| `README*`, `docs/**`, `.github/**` | docs agent |
| `scripts/**`, `Makefile`, `verify.sh` | devops |
| SINGLE-OWNER contract: `proto/colima_ui.proto`, `docs/parity-matrix.md`, `docs/truth-table.csv` | architect |

## Lock table (advisory)

| Path | Held by | Since | Task |
|------|---------|-------|------|
| `.kiro/board/**`, `README.md`, `LICENSE` | orchestrator | 2026-07-13T23:18Z | M0.1 |

## Integration
- Trunk-based; only the **integration agent** merges to `main`.
- Pre-merge gate: `scripts/verify.sh` must pass for the touched platform(s) AND must not
  regress any other platform's scoreboard in `STATUS.md`.

# Program Board — PLAN (task DAG + status)

> Single source of truth for the autonomous multi-agent program. Every agent MUST read
> this + recent `INTENT_LEDGER.md` + `CONTRACT.md` before starting a task, and append its
> outcome to `INTENT_LEDGER.md` after.

## Legend
`TODO` · `WIP` · `BLOCKED` · `REVIEW` · `DONE`

## Milestones (maximally parallel; CONTRACT freeze at end of M0 unlocks M1∥M2∥docs)

| ID | Task | Owner agent | Depends on | Paths | Status |
|----|------|-------------|-----------|-------|--------|
| M0.1 | Board substrate + seed README/LICENSE | orchestrator/architect | — | `.kiro/board/`, `README.md`, `LICENSE` | DONE |
| M0.1b | Port 10 skills + scaffold 10 agents | architect | — | `~/.kiro/skills/`, `~/.kiro/agents/` | DONE |
| M0.2 | Extract `ColimaDesktopKit`; fix Xcode-26 hang | swiftui-dev | — | `Sources/`, `project.yml` | DONE |
| M0.3 | Coverage wiring + `verify.sh` scoreboard | devops | M0.2 | `scripts/verify.sh`, `Makefile` | DONE |
| M0.4 | Finalize proto; daemon-backed mac provider; FREEZE CONTRACT v1 | go-daemon-dev + architect | M0.2 | `proto/`, `daemon/`, `Sources/Services/` | DONE |
| M1.5 | Daemon backend completeness + parity-matrix + gRPC integ tests | go-daemon-dev | M0.4✅ | `daemon/`, `docs/parity-matrix.md` | DONE |
| M2.6 | Windows WinUI 3 GUI | windows-native-dev | M0.4 | `windows/` | DONE |
| M2.7 | Linux GTK4 GUI | linux-native-dev | M0.4 | `linux/` | DONE |
| M2.8 | TUI Bubble Tea | tui-dev | M0.4 | `tui/` | DONE |
| M3.9 | Per-platform explorers → ground-truth.json | *-ui-explorer | M2.* | `exploration/` | TODO |
| M3.10 | Gap analysis → gap-report.md | architect + reviewer | M3.9 | `exploration/` | TODO |
| M3.11 | Repair 129 failures + missing tests → 100% cov | swift-test-engineer | M3.10 | `Tests/` | TODO |
| M4.12 | CLI-parity gaps on every frontend | crossplatform-parity-auditor | M1.5, M2.* | per-frontend | TODO |
| M4.13 | DependencyManager per platform | devops + native-devs | M2.* | per-frontend | TODO |
| M5.14 | Loop until verify.sh all-green | integration agent | all | — | TODO |
| M5.15 | Full OSS docs suite + release workflows + tag v1 | docs agent | M5.14 | `README`, `docs/`, `.github/` | TODO |

## Critical path
M0.2 → M0.4 (CONTRACT freeze) → { M1.5 ∥ M2.6 ∥ M2.7 ∥ M2.8 } → M3.* → M4.* → M5.14 → M5.15

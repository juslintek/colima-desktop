# Program Board — STATUS (verify.sh scoreboard)

> Updated by `scripts/verify.sh`. All applicable criteria must be GREEN per platform for v1.

Last run: 2026-07-14 (M0.3 baseline)

| Criterion | macOS | Windows | Linux | TUI | Daemon |
|-----------|-------|---------|-------|-----|--------|
| builds (0 warnings) | FAIL (2 warns) | scaffold (CI) | scaffold (CI) | PASS (go) | PASS |
| lint clean | n/a (swiftlint not installed) | n/a | n/a | n/a | ? |
| unit+integration green | PASS (69) | n/a (CI) | n/a (CI) | PASS (6 TUI) | PASS |
| explorer 0 broken interactions | ? | n/a | n/a | n/a | n/a |
| coverage = 100% | FAIL (9.8%) | n/a | n/a | n/a | ? |
| parity matrix complete | ? | n/a | n/a | n/a | n/a |
| auto-install/update verified | ? | n/a | n/a | n/a | n/a |

Legend: `?` unknown · `PASS` · `FAIL` · `n/a` not-yet-built

Baseline notes:
- macOS logic/integration tests green (53+16). Coverage 9.8% on ColimaDesktopKit — the
  bulk (Views + many Services paths) is untested; M3.11 drives this to 100%.
- 2 build warnings to clear (M3/M5 pristine pass).
- Windows/Linux/TUI frontends not yet built (M2). swiftlint not installed on host.

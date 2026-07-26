# Program Board — STATUS (verify.sh scoreboard)

> Cross-platform exit-criteria scoreboard for v1. Every applicable criterion must be GREEN per
> platform before v1. This baseline is refreshed from **real evidence only** — each cell is labelled
> with its evidence source. No value is asserted GREEN unless a run produced it.

**Last refreshed:** 2026-07-20 (R0.3 / task 1.8 — integration-agent).
**Sources:** `scripts/verify.sh` measured on this macOS host 2026-07-20 (live `desktop-e2e` e2e lane
active); CI runs `frontends.yml` #29646162198 (9/9 jobs) + `test.yml` #29646162210 cited from
`PLAN.md`; per-platform explorer artifacts under `exploration/**` (captured 2026-07-18).

## Evidence-source legend

- **local** — measured on this macOS host on 2026-07-20 (fresh `verify.sh` / on-host tooling).
- **CI** — green GitHub Actions job; run ID cited below (not fabricated).
- **CI/no-daemon** — CI job ran without a live Colima daemon: UI chrome/handlers verified, data rows are placeholder/stub.
- **live** — verified against a live Colima daemon.
- **?** — not yet verified / unknown.
- **n/a** — not applicable or not built on this host.
- Status tokens: `PASS` · `FAIL` · `present` (scaffold/binary exists) · `no` (not demonstrated).

## Scoreboard

| Criterion | macOS | Windows | Linux | TUI | Daemon |
|-----------|-------|---------|-------|-----|--------|
| builds (0 warnings) | PASS (local) | PASS (CI) | PASS (CI) | PASS (local+CI) | PASS (local+CI, cross-build mac/linux/win) |
| lint / format clean | n/a (swiftlint not installed on host) | PASS (`dotnet format`, CI) | PASS (`clippy -D warnings` + `fmt`, CI) | PASS (`go vet`, local) | PASS (`go vet`, local) |
| unit + integration green | **FAIL (local, live e2e lane — see findings)** | PASS (23/23 headless VM/service tests, CI) | PASS (9 Rust tests, CI) | PASS (56 Go tests, local+CI) | PASS (`go test` + `go test -race`, local+CI) |
| explorer surfaces · 0 capture errors | PASS (13 tabs / 1,847 AX elem, local+live) | PASS (13 surfaces / 699 UIA elem, CI/no-daemon) | PASS (12 surfaces / 887 AT-SPI elem, CI/no-daemon) | PASS (12 surfaces / PTY, CI) | n/a |
| live-backend data (real daemon) | PASS (live colima 0.10.1) | no (CI/no-daemon; live UIA env-blocked) | no (CI/no-daemon; live AT-SPI env-blocked) | no (fakeDS stub; live PTY lane open) | partial (live read-only stats/process vs `desktop-e2e`) |
| coverage (≥ COV_MIN 71%; practical max ~74%) | PASS 72.4% (local, live e2e lane) | n/a | n/a | n/a | ? (Go coverage not gated) |
| DependencyManager install/update verified | ? wired, not live-verified | ? wired, not live-verified | ? wired, not live-verified | ? probe wired, not live-verified | n/a |

## verify.sh scoreboard — measured-local 2026-07-20 (verbatim)

```
== Colima Desktop verify.sh ==
macOS build (0 warnings)           PASS
  (desktop-e2e VM detected — running live RealBackend e2e tests)
macOS unit+integration             FAIL
macOS coverage (>=71%)             PASS (72.4%)
daemon build                       PASS
daemon tests                       PASS
windows frontend                   present
linux frontend                     present
tui frontend                       present
swiftlint                          n/a (not installed)
==============================
RESULT: NOT GREEN
```

## CI evidence (cited from PLAN.md / INTENT_LEDGER.md — not fabricated)

- `frontends.yml` run **29646162198** — all 9 jobs PASS (windows-winui, linux-gtk4, macos-kit, daemon×3, tui×3). *(PLAN.md "Latest final CI evidence")*
- `test.yml` run **29646162210** — PASS. *(PLAN.md)*
- Earlier `frontends.yml` run **29635550954** — all 9 jobs PASS. *(INTENT_LEDGER 2026-07-18T10:40Z)*
- Linux AT-SPI explore run **29645595494** — 12 surfaces / 887 elements / 0 errors. *(PLAN.md)*
- TUI PTY explore run **29645819005** — 12 nonempty/distinct surfaces / 0 errors. *(PLAN.md)*

## Explorer ground-truth (`exploration/**`, captured 2026-07-18)

- **macOS** `exploration/macos/ground-truth.json` — 13 tabs, 1,847 AX elements, 13 screenshots, 0 errors; **live real backend** (colima 0.10.1, profile=default). VERIFIED.
- **Windows** `exploration/windows/ground-truth.json` — 13 surfaces, 699 UIA elements, 0 capture errors; CI runner, **no live daemon** (gRPC surfaces show placeholder). VERIFIED (CI).
- **Linux** `exploration/linux/ground-truth.json` — 12 surfaces, 887 AT-SPI elements, 0 errors; CI runner, `colima` shimmed, **no live daemon**. VERIFIED (CI).
- **TUI** `exploration/tui/ground-truth.json` — 12 surfaces, PTY frames, all_nonempty/all_distinct/validation_pass=true, 0 errors; **fakeDS stub data** (not live). VERIFIED (structure).
- **Unified** `exploration/ground-truth.json` — overall_status **VALID**; 12 canonical surfaces common to all 4 frontends; `live_backend_verified` true only for macOS.

## Findings replacing the 2026-07-14 M0.3 baseline

- The stale M0.3 scaffold values are removed: coverage `9.8%`, Windows/Linux `scaffold (CI)` / `n/a (CI)`, `parity matrix ?`, and the "frontends not yet built (M2)" note. All four frontends now build (macOS local; Windows/Linux/TUI via CI) and each has a validated explorer artifact.
- Coverage is gated at the **practical maximum** (`COV_MIN=71`, ~74% documented ceiling with the live VM), not literal 100% — literal 100% is structurally unreachable headless (`App.swift` @main, AppKit callbacks, live-only delegate paths). Measured **72.4%** locally on 2026-07-20 with the live `desktop-e2e` e2e lane.
- **DISCREPANCY — macOS `unit+integration` FAIL / `RESULT: NOT GREEN` (measured-local 2026-07-20).** A fresh `verify.sh` run on this host reports macOS unit+integration FAILING under the live `desktop-e2e` e2e lane; an `.xcresult` was produced (coverage computed at 72.4%), so at least one unit/integration/live-e2e test is currently failing — this is a real test failure, not an infra abort. This contradicts PLAN.md's "`scripts/verify.sh` is green" claim. **Flagged for the owning agent (swiftui-dev / swift-test-engineer) to diagnose;** STATUS records the measured truth. The prior recorded green run (INTENT_LEDGER iteration 4, 2026-07-17, 74.2%) predates current `Sources/**` and daemon changes.
- **Environment-bounded (Assumption A2):** Windows/Linux live-backend evidence and DependencyManager install/update remain open — live UIA/AT-SPI capture is environment-blocked on this macOS-only host, so those platforms are proven via green CI (`frontends.yml` + `test.yml`), and their live cells are recorded as `no`/`?` rather than a fabricated PASS.
- **Daemon** builds and tests PASS locally (`go test` + `go test -race`) and cross-compiles for macOS/Linux/Windows; live coverage is not gated (`?`). Live read-only VM stats/process commands were validated against `desktop-e2e`.

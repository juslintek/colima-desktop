# Program Board — PLAN

> Single source of truth for completed work, remaining work, execution order, and release gates.
> Updated 2026-07-18 after the four-platform Monitoring parity closure.
>
> Every agent must read this file, `CONTRACT.md`, `OWNERSHIP.md`, and the recent entries in
> `INTENT_LEDGER.md` before changing code. Record completed work and evidence in
> `INTENT_LEDGER.md`.

## Status legend

`TODO` · `WIP` · `BLOCKED` · `REVIEW` · `PARTIAL` · `DONE`

`DONE` means the stated acceptance criteria have evidence. A compiled or visible surface is not
proof that all actions work against a live backend.

## Current program state

- Repository: `github.com/juslintek/colima-desktop`
- Current public prerelease: `v0.2.0`
- Public site: <https://juslintek.github.io/colima-desktop/>
- Shared contract: frozen v1 proto with 31 `ColimaService` RPCs and 34 `DockerService` RPCs.
- Runtime surface parity: 12 canonical surfaces exist on macOS, Windows, Linux, and TUI.
- Unified runtime artifact: `exploration/ground-truth.json`, status `VALID`.
- Local verification: `scripts/verify.sh` is green. The coverage gate is practical/headless
  coverage, not a literal 100% Swift line requirement; the documented practical-max run is 74.2%.
- Latest final CI evidence:
  - `frontends.yml` run `29646162198`: all 9 jobs passed.
  - `test.yml` run `29646162210`: passed.
  - Linux AT-SPI run `29645595494`: 12 surfaces, 887 elements, zero errors.
  - TUI PTY run `29645819005`: 12 nonempty/distinct surfaces, zero errors.
- Evidence limitations remain: Windows and Linux were captured without a live daemon; TUI uses
  real PTY navigation/screenshots plus deterministic `fakeDS` content.

## Milestone history and corrected status

| ID | Deliverable | Status | Evidence / remaining boundary |
|----|-------------|--------|-------------------------------|
| M0.1 | Board substrate, README, license | DONE | `.kiro/board/`, `README.md`, `LICENSE` |
| M0.1b | Ten skills and ten specialist agents | DONE | Global `~/.kiro/skills/` and `~/.kiro/agents/` |
| M0.2 | `ColimaDesktopKit` extraction and Xcode-26 test-runner repair | DONE | macOS tests complete without runner hang |
| M0.3 | Coverage wiring and `verify.sh` scoreboard | DONE | `scripts/verify.sh`, Make targets, xccov/go coverage |
| M0.4 | Frozen proto/contract and provider mapping | DONE | `CONTRACT.md`, `proto/colima_ui.proto` |
| M1.5 | Shared daemon, Docker providers, parity matrix, integration tests | PARTIAL | All 31 Colima RPCs have concrete server methods; 32/34 Docker RPCs do. `PullImage` and `PushImage` remain inherited unimplemented defaults. |
| M2.6 | Windows WinUI 3 frontend | PARTIAL | Builds and exposes all required surfaces; many mutations and live-backend flows still need implementation/verification. |
| M2.7 | Linux GTK4 frontend | PARTIAL | Builds and exposes all required surfaces; Monitoring is wired, but complete action parity and live-daemon verification remain. |
| M2.8 | Bubble Tea TUI | PARTIAL | All 12 surfaces load; Monitoring selection/kill works. Most advertised write actions are not yet key-bound. |
| M3.9 | Native explorers and platform ground truth | DONE | macOS 13/1,847 AX/live; Windows 13/699 UIA/CI; Linux 12/887 AT-SPI/CI; TUI 12 PTY/fakeDS |
| M3.10 | Unified parity analysis | DONE | `DISC-03` resolved; 12 common surfaces; active limitations retained |
| M3.11 | macOS test repair and practical coverage | DONE | Green practical gate; literal 100% is structurally unreachable headlessly and is not a release blocker |
| M4.12 | Full functional CLI parity on every frontend | PARTIAL | Surface parity is done. Per-action parity is not; see R2–R5. |
| M4.13 | DependencyManager implementation | PARTIAL | Platform implementations exist (Homebrew/winget/Linux package managers/TUI probe); destructive install, update, and onboarding flows need native live verification. |
| M5.14 | Current verification loop green | DONE | Local verification and final CI are green for current gates |
| M5.15 | OSS docs, release automation, and public release | PARTIAL | Docs/site and macOS `v0.2.0` prerelease exist. Cross-platform artifacts, production signing/update configuration, and the v1 tag remain. |

## Source-of-truth corrections required first

The current `docs/gap-report.md` contains stale daemon statements. A source audit on 2026-07-18
found:

- `ColimaService`: 31 declared RPCs, 31 concrete `ColimaServer` methods.
- `DockerService`: 34 declared RPCs, 32 concrete `DockerServer` methods.
- `GetConfig`, `SetConfig`, `GetTemplate`, and `SetTemplate` are implemented in
  `daemon/internal/server/config_server.go`.
- `PullImage` and `PushImage` are declared in the proto and client layer but have no concrete
  `DockerServer` methods.

Do not use generated `Unimplemented*Server` defaults as evidence that every RPC is missing. The
concrete receiver method inventory is authoritative.

## Remaining roadmap

### R0 — Reconcile planning and capability evidence

| ID | Priority | Task | Owner | Depends on | Acceptance |
|----|----------|------|-------|------------|------------|
| R0.1 | P0 | Regenerate `docs/gap-report.md` and `docs/parity-matrix.md` from current proto/server/frontend source; remove stale config/template and “no pull/push RPC” claims | crossplatform-parity-auditor | — | Every RPC row is checked against concrete server and client methods; report distinguishes implemented, UI-wired, runtime-tested, and live-tested |
| R0.2 | P0 | Produce a machine-readable per-frontend action inventory, not only a surface inventory | architect + native agents | R0.1 | Each canonical action maps to proto RPC, frontend handler, tests, and runtime evidence |
| R0.3 | P1 | Replace stale `.kiro/board/STATUS.md` baseline with current build/test/explorer/coverage status | integration agent | R0.1 | STATUS matches latest CI and local verification; no M0-era scaffold values remain |
| R0.4 | P1 | Audit legacy TODO documents and close, migrate, or delete obsolete entries | architect | R0.1 | `IMPLEMENTATION_PLAN_V2.md`, E2E plans, and architecture docs no longer contradict this plan |

### R1 — Finish shared daemon and provider behavior

| ID | Priority | Task | Owner | Depends on | Acceptance |
|----|----------|------|-------|------------|------------|
| R1.1 | P0 | Implement `DockerServer.PullImage` as a real progress stream | go-daemon-dev | R0.2 | Local/SSH/WSL2 providers work; cancellation and error propagation tested with bufconn |
| R1.2 | P0 | Implement `DockerServer.PushImage` as a real progress stream | go-daemon-dev | R0.2 | Same provider, streaming, cancellation, and error guarantees as pull |
| R1.3 | P1 | Add integration tests for all 31 Colima RPCs and 34 Docker RPCs | go-daemon-dev + test-engineer | R1.1, R1.2 | No inherited unimplemented route; deterministic success/error tests cover every RPC |
| R1.4 | P1 | Exercise local Unix socket, remote SSH, and Windows WSL2/npipe providers in native CI or dedicated test hosts | go-daemon-dev + devops | R1.3 | Provider-specific smoke tests and failure diagnostics are recorded; no secrets in artifacts |
| R1.5 | P2 | Add fault-injection coverage for Docker permission denied, interrupted streams, socket loss, and timeouts | test-engineer | R1.3 | Errors are contextual, cancellation-safe, and do not leak goroutines/resources |

### R2 — Complete TUI interaction parity

Current state: all 12 surfaces load data. Implemented global keys are quit/help/navigation/refresh;
Monitoring additionally supports selection and `KillProcess(profile, pid, 9)`. Other displayed action
hints are not handlers yet.

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R2.1 | P0 | Add VM start/stop/restart/delete/update/prune and SSH-config actions | R0.2 | Keys invoke exact RPC/profile; confirmation for destructive actions; success/error states and teatests |
| R2.2 | P0 | Add container create/start/stop/restart/kill/pause/resume/remove/rename/logs/inspect/top/stats/changes actions | R0.2 | Selection model, dialogs/prompts, streaming cancellation, focused tests |
| R2.3 | P1 | Add image pull/push/remove/tag/search/history/inspect/prune actions | R1.1, R1.2 | Progress UI and cancellation work against a real daemon |
| R2.4 | P1 | Add volume and network create/remove/inspect/prune/connect/disconnect actions | R0.2 | All Docker mutations available and tested |
| R2.5 | P1 | Wire Kubernetes start/stop/reset/exec keys currently shown by the UI | R0.2 | Keys call all four RPCs; exec output/error handling tested |
| R2.6 | P1 | Add profile create/delete/clone/select and full refresh on profile switch | R0.2 | Active profile updates every tab and daemon scope consistently |
| R2.7 | P1 | Add runtime docker/containerd/incus switch and runtime update actions currently shown by the UI | R0.2 | Immutable-change warnings, confirmation, progress, and refresh tested |
| R2.8 | P2 | Add config edit/save plus template edit/save flows | R0.2 | Typed validation, YAML round trip, and daemon errors shown clearly |
| R2.9 | P2 | Add AI setup/run/serve/stop flows and streamed output | R0.2 | Runner/model/port inputs validated; streams cancel cleanly |
| R2.10 | P2 | Add continuous events/logs/stats modes while retaining bounded Monitoring refresh | R1.3 | No goroutine leaks; pause/cancel/back navigation tested |
| R2.11 | P2 | Replace fakeDS-only runtime proof with a live-daemon PTY suite | R2.1–R2.10 | Ground truth clearly separates PTY structure from live data/action evidence |

### R3 — Complete Windows functional parity

The current runtime artifact proves WinUI surfaces and automation trees, not backend mutations.
The “~47 RPC” estimate in the old gap report must be replaced by R0.2 before implementation.

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R3.1 | P0 | Audit every command binding and `DaemonClient` method against the frozen contract | R0.2 | Exact missing-handler list with no estimate-only claims |
| R3.2 | P0 | Wire VM lifecycle, profile, SSH, update, and prune commands | R3.1 | MVVM commands invoke real gRPC; busy/error/confirmation states tested |
| R3.3 | P0 | Wire Docker container/image/volume/network mutations and streams | R1.1, R1.2, R3.1 | Full DockerService action coverage with cancellation |
| R3.4 | P1 | Wire Kubernetes, AI, runtime, config/template, and Monitoring streaming/actions | R3.1 | All ColimaService actions represented and tested |
| R3.5 | P1 | Verify local WSL2/Docker and remote-SSH modes on native Windows hosts | R1.4, R3.2–R3.4 | Live action transcript, UIA capture, and provider failure cases committed |
| R3.6 | P2 | Package and test an MSIX or documented unpackaged/self-contained installer path | R3.2–R3.5 | Clean Windows machine install, launch, update, and uninstall pass |

### R4 — Complete Linux functional parity

Monitoring already uses bounded `VMStats`, `ProcessList`, and `KillProcess` with GTK updates kept on
the GLib main context. Other action coverage must be inventoried rather than inferred from AT-SPI
control presence.

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R4.1 | P0 | Audit every GTK callback against the frozen contract and generated tonic clients | R0.2 | Exact action matrix replaces the old “~49 RPC” estimate |
| R4.2 | P0 | Complete VM lifecycle/profile/SSH/update/prune callbacks | R4.1 | Async work captures only Send data; all GTK mutation stays on GLib main thread |
| R4.3 | P0 | Complete Docker container/image/volume/network mutations and streams | R1.1, R1.2, R4.1 | Every required action works and is cancellation-safe |
| R4.4 | P1 | Complete Kubernetes, AI, runtime, config/template, and remaining Monitoring behavior | R4.1 | Handler and error-state tests plus accessibility identifiers |
| R4.5 | P1 | Add Rust unit/integration tests around RPC result handling and GTK-independent state | R4.2–R4.4 | Deterministic test layer runs without a display where possible |
| R4.6 | P1 | Run explorer and action suite with a live Linux daemon | R4.2–R4.5 | No `colima` shim for the live lane; AT-SPI evidence records real state changes |
| R4.7 | P2 | Produce and test Flatpak/AppImage and distro package artifacts | R4.6 | Fresh Ubuntu/Fedora install, dependency bootstrap, update, and uninstall pass |

### R5 — Finish macOS product gaps and test debt

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R5.1 | P1 | Add Template read/edit/save UI over implemented `GetTemplate`/`SetTemplate` | R0.2 | Validation, save, restart implications, and tests included |
| R5.2 | P1 | Resolve orphaned `CreateContainerView`: wire it into navigation/actions or delete it | R0.2 | No unreachable production view or placeholder-only test remains |
| R5.3 | P2 | Test autostart menu states, brew-missing install path, kubectl exec, and deterministic permission/interruption errors | R1.5 | TODOs in `docs/e2e-real-mode-execution.md` are closed with evidence or explicit constraints |
| R5.4 | P2 | Replace the snapshot placeholder test with meaningful visual regression coverage | R5.1, R5.2 | Stable light/dark snapshots for critical surfaces |
| R5.5 | P3 | Evaluate optional product enhancements: current reference styling, settings tooltips, guided setup, process tree/sparklines, Cmd+K search, Docker events, streamed logs/stats | R0.4 | Each legacy idea is accepted with a spec or explicitly rejected; no ambiguous TODO remains |

### R6 — Live backend, accessibility, and dependency verification

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R6.1 | P0 | Create safe native live-daemon lanes for Windows and Linux | R1.4, R3.*, R4.* | Dedicated disposable profiles/hosts; secrets and machine data never uploaded |
| R6.2 | P1 | Extend UIA/AT-SPI/PTY explorers from surface capture to critical action flows | R2.*, R3.*, R4.* | Start/stop, create/remove, config, Kubernetes, runtime, and Monitoring actions have runtime evidence |
| R6.3 | P1 | Verify DependencyManager onboarding/install/update on clean macOS, Windows, and Linux machines | M4.13 | Installed, missing, outdated, cancelled, offline, and permission-denied paths pass |
| R6.4 | P1 | Replace TUI fakeDS as the only data proof with a live daemon lane while keeping deterministic fakeDS regression tests | R2.11 | DISC-07 can be closed without losing deterministic tests |
| R6.5 | P1 | Normalize canonical automation keys for Runtime and AI Workloads | R6.2 | Close DISC-01 and DISC-02; preserve user-facing platform conventions if desired |
| R6.6 | P3 | Decide whether Community (macOS-only) and Settings (Windows-only) remain intentional platform extras | R0.2 | DISC-04 and DISC-05 documented as accepted differences or scheduled for implementation |

### R7 — Quality, security, and release hardening

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R7.1 | P1 | Keep practical coverage gates green and add tests for every new action | R1–R6 | `scripts/verify.sh` green; no claim of fabricated literal 100% headless coverage |
| R7.2 | P1 | Run race/leak/cancellation checks for Go streams and long-running UI operations | R1–R4 | `go test -race`, cancellation tests, and resource cleanup pass |
| R7.3 | P1 | Perform dependency/license/security audit and generate SBOMs | R1–R6 | No known critical vulnerability; licenses and third-party notices published |
| R7.4 | P2 | Performance test startup, idle resource use, large Docker lists, logs, stats, and accessibility traversal | R2–R6 | Budgets documented and regressions gated |
| R7.5 | P2 | Make all interactive controls keyboard-accessible and consistently named | R2–R6 | AX/UIA/AT-SPI audits have no critical unlabeled or unreachable action |

### R8 — Cross-platform v1 release

| ID | Priority | Task | Depends on | Acceptance |
|----|----------|------|------------|------------|
| R8.1 | P0 | Extend `release.yml` beyond macOS to Windows, Linux, daemon, and TUI artifacts | R2–R7 | Versioned artifacts for all supported OS/architectures, checksums, and SBOMs |
| R8.2 | P0 | Configure production macOS signing, notarization, Sparkle Ed25519 key, and appcast | R7.3 | No placeholder `SUPublicEDKey`; clean-machine Gatekeeper install/update passes |
| R8.3 | P0 | Sign/package Windows and Linux deliverables and document trust/install behavior | R3.6, R4.7, R7.3 | Clean-machine install/update/uninstall evidence |
| R8.4 | P1 | Publish complete v1 docs: installation, troubleshooting, architecture, security, privacy, screenshots, limitations, and contributor guide | R8.1–R8.3 | Website and repository docs match shipped artifacts and current parity evidence |
| R8.5 | P1 | Run release-candidate soak on all platforms and remote/local providers | R6.*, R7.*, R8.1–R8.4 | No P0/P1 defect; rollback plan tested; artifacts reproducible |
| R8.6 | P0 | Tag and publish `v1.0.0` only after all v1 gates pass | R8.5 | Signed tag, release notes, assets, checksums, appcast, Pages update, and post-release smoke test |

## Active runtime discrepancies

| ID | Status | Required disposition |
|----|--------|----------------------|
| DISC-01 | Active, low | Normalize or explicitly accept macOS `runtimeControls` versus canonical `runtime` |
| DISC-02 | Active, low | Normalize or explicitly accept AI Workloads automation keys |
| DISC-03 | RESOLVED | Monitoring exists on all four platforms; keep regression evidence |
| DISC-04 | Active, informational | Decide whether macOS-only Community is an accepted extra |
| DISC-05 | Active, informational | Decide whether Windows-only Settings is an accepted extra |
| DISC-06 | Active, informational | Add live-backend Windows/Linux/TUI evidence |
| DISC-07 | Active, medium | Add live-daemon TUI data/action evidence; retain fakeDS for deterministic regression tests |

## Execution order

```text
R0 evidence reconciliation
  ├─→ R1 daemon completion
  ├─→ R2 TUI actions ───────────────┐
  ├─→ R3 Windows actions/provider ──┼─→ R6 live/action exploration
  ├─→ R4 Linux actions/provider ────┤
  └─→ R5 macOS gaps ────────────────┘
                                      └─→ R7 hardening
                                            └─→ R8 cross-platform v1 release
```

Parallel work is allowed only with disjoint path ownership. Backend contract changes land before
frontend consumers. Platform work is accepted only after native CI or the best available native
host validation.

## Next executable batch

1. **R0.1/R0.2:** regenerate an exact RPC/action matrix from source and correct stale gap docs.
2. **R1.1/R1.2:** implement daemon `PullImage` and `PushImage` streams with integration tests.
3. In parallel after R0.2:
   - **R2.1/R2.2:** TUI VM and container actions.
   - **R3.1:** Windows command-binding audit.
   - **R4.1:** Linux callback audit.
   - **R5.1/R5.2:** macOS template UI and orphaned create-container decision.
4. **R6.1:** provision safe disposable Windows/Linux live-daemon test lanes.

## Global acceptance gates

Every remaining task must satisfy all applicable gates:

- Builds without new warnings on its native platform.
- Targeted unit/integration tests pass; changed Go concurrency also passes `go test -race`.
- Destructive actions require confirmation and use disposable test resources.
- No generated placeholders, fake success artifacts, secrets, or user data are committed.
- Explorer evidence records real runtime behavior; environment-blocked output is never labeled a
  successful ground truth.
- Accessibility identifiers/names exist for all interactive controls.
- Documentation states whether evidence is source-only, deterministic fake data, CI without a
  daemon, or live-backend verified.
- `scripts/verify.sh`, `frontends.yml`, and `test.yml` are green before a release candidate.
- Main is clean, synchronized with `origin/main`, and temporary worktrees/branches are removed.

## Explicit non-goals / accepted constraints

- Literal 100% Swift line coverage is not a headless release gate because `@main`, AppKit
  callbacks, and live-only delegates are structurally unreachable in that environment. Improve
  meaningful behavior coverage instead.
- Platform-specific Community and Settings surfaces are not contract requirements unless R6.6
  decides otherwise.
- fakeDS remains useful for deterministic TUI rendering tests, but cannot close live-backend
  verification.
- Do not add Electron or replace native frontends; native SwiftUI, WinUI 3, GTK4, and Bubble Tea
  remain architectural requirements.

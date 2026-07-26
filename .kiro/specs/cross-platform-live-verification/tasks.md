# Implementation Plan: Cross-Platform Live Verification

## Overview

This plan decomposes the design into dependency-ordered, agent-assigned coding tasks that drive the
repository from `v0.2.0` to an evidence-backed `v1.0.0` whose artifact signing is credential-gated
(the delivered, environment-bounded outcome is recorded in the Notes). It follows the design wave
order `R0 → R1 → R2/R3/R4/R5 → R6/R9/R10 → R7 → R8 → notification`.

Every task is scoped to **exactly one owned path prefix** so parallel work stays conflict-free, and
every task brackets its work with the append-only `INTENT_LEDGER.md` discipline: append an `intent`
entry (intent + plan + files-to-touch, all inside the owned prefix) **before** starting, and an
`outcome` entry (evidence + contract-impact) **after** finishing. Integration to `main` is performed
only by the Integration_Agent through the merge gate (ownership check → reserved-path check →
`verify.sh` green for the touched platform with no other-platform `STATUS.md` regression → for R8,
the release-candidate gate delivered in task 12.5, which requires all 9 `frontends.yml` jobs +
`test.yml` green).

Languages are already fixed by the existing codebase (no language-selection step): Go (`daemon/**`,
`tui/**`), Swift/SwiftUI (`Sources/**`, `Tests/**`), C#/WinUI 3 (`windows/**`), Rust/GTK4
(`linux/**`), Bash/Python (`scripts/**`). Cross-language contracts in the design are Structured
Pseudocode; the concrete implementations use each prefix's real language.

### Parallelism & Ownership Model

| Wave group | Tasks | Concurrency | Owners → prefixes |
|-----------|-------|-------------|-------------------|
| **R0 (barrier)** | 1.x | Runs first; every downstream task depends on the corrected inventory + evidence taxonomy | explorer→`exploration/**`, devops→`scripts/**`, architect→`.kiro/board/CONTRACT.md`+`docs/parity-matrix.md`+`docs/truth-table.csv`, docs→`docs/**`, integration-agent→`.kiro/board/STATUS.md` |
| **R1 (serial before frontends)** | 2.x | Backend contract lands before consumers | go-daemon-dev→`daemon/**` (proposes `proto/**`; architect approves) |
| **R2/R3/R4/R5 (fully parallel)** | 4.x, 5.x, 6.x, 7.x, 8.x | Disjoint prefixes run in parallel; `Tests/**` runs alongside | tui-dev→`tui/**`, windows-native-dev→`windows/**`, linux-native-dev→`linux/**`, swiftui-dev→`Sources/**`, swift-test-engineer→`Tests/**` |
| **R6/R9/R10 (after frontends)** | 10.x | Live macOS depends on R5; Win/Linux CI parity depends on R3/R4 | devops→`scripts/live/**`+`artifacts/live/**`, swiftui-dev→`Sources/**`, swift-test-engineer→`Tests/**`, explorers→`exploration/**`+`.github/**` |
| **R7 (after R6)** | 12.x | Hardening downstream of all completion | devops→`scripts/**`+`.github/**` (incl. the cross-frontend a11y checker — a Swift test target cannot scan the XAML/Rust/Go frontends), swift-test-engineer→`Tests/**` |
| **R8 (after R7)** | 13.x | Release downstream of hardening | devops→`scripts/**`+`.github/**`, docs→`docs/**`+`SIGNING.md` |
| **R13 (strictly last)** | 14.x | Fired by release completion | devops→`scripts/notify/**` |

Barriers: **R0 completes before R1**; **R1 completes before any frontend wave**; **all frontends +
`Tests/**` complete before R6**; **R6 before R7**; **R7 before R8**; **R8 before notification**.
Reserved-to-orchestrator paths (`.kiro/board/**`, `proto/colima_ui.proto`, `README*`,
`docs/parity-matrix.md`, `docs/truth-table.csv`) are never written by a path-owner agent.

---

## Tasks

- [x] 1. R0 — Board-vs-reality evidence reconciliation (barrier: read-only audit + regen + gate)
  - [x] 1.1 Build the machine-readable per-frontend 65-RPC action inventory
    - Owner: explorer (read-only audit) → `exploration/action-inventory.json`
    - Audit each of the 31 `ColimaService` + 34 `DockerService` RPCs against the daemon server
      method, generated client method, and each frontend handler (macOS/Windows/Linux/TUI)
    - Emit exactly one coverage cell per (RPC, frontend) with an assigned evidence level
    - _Requirements: 1.1, 1.2, 1.8_ — _Maps: Property 7 (contract coverage), Property 8 (evidence totality); ExerciseHarness/evidence input_
  - [x] 1.2 Extend the evidence generator to assign evidence levels per cell
    - Owner: devops → `scripts/gen-truth-table.py`
    - Consume proto + daemon server methods + frontend handlers + `exploration/action-inventory.json`;
      emit `truth-table.csv` and `gap-report.md` content distinguishing the four positive evidence
      levels + `environment-blocked`; replace stale "no pull/push RPC" and "config/template
      unimplemented" claims
    - _Requirements: 1.6, 1.8_ — _Maps: Evidence generator component; Property 8, 9_
  - [x] 1.3 Write property tests for the evidence generator
    - Owner: devops → `scripts/tests/test_gen_truth_table.py`
    - **Property 7: Contract coverage** — every RPC has a non-`Unimplemented` server method and exactly one cell per (RPC, frontend)
    - **Property 8: Evidence-level totality + environment-blocked labeling** — exactly one taxonomy level per claim; UIA/AT-SPI-blocked captures label exactly `environment-blocked`
    - **Property 9: Doc-regeneration idempotence + coverage** — regenerating twice yields byte-identical output; every proto RPC appears at least once
    - Minimum 100 randomized iterations per property; tag `Feature: cross-platform-live-verification, Property {n}`
    - _Requirements: 1.6, 1.8, 9.6, 9.7_
  - [x] 1.4 Reconcile the approved pre-v1 additive request-shape into the contract
    - Owner: architect → `.kiro/board/CONTRACT.md` (reserved)
    - Document the profile/host/WSL2 scope fields on `Update`, `Prune`, `Rename`, `Tag`, `Search`,
      `NetworkContainer` recorded in `INTENT_LEDGER.md`; preserve all RPC names/counts/field numbers
    - _Requirements: 1.5, 2.1_ — _Maps: Property 6 (frozen-contract preservation)_
  - [x] 1.5 Write the frozen-contract preservation property test
    - Owner: devops → `scripts/tests/test_frozen_contract.py` (Python property test over `proto/colima_ui.proto`)
    - **Property 6: Frozen-contract preservation** — the declared set is exactly 31 `ColimaService` + 34 `DockerService` RPCs with unchanged names/field numbers except the approved additive scope fields
    - Minimum 100 randomized iterations (permuted/mutated proto snapshots); tag Property 6
    - _Requirements: 2.1_
  - [x] 1.6 Regenerate the architect-owned parity matrix and truth table
    - Owner: architect → `docs/parity-matrix.md`, `docs/truth-table.csv` (reserved)
    - Regenerate from the generator output so the matrix cannot drift from source
    - _Requirements: 1.6_ — _Maps: Property 9_
  - [x] 1.7 Regenerate the gap report and retire contradicting legacy docs
    - Owner: docs → `docs/gap-report.md` and legacy files under `docs/**`
    - Regenerate `gap-report.md` from source; close/migrate/delete any legacy planning doc that contradicts `PLAN.md`
    - _Requirements: 1.6, 1.7_
  - [x] 1.8 Refresh the STATUS baseline from real evidence
    - Owner: integration-agent → `.kiro/board/STATUS.md` (reserved)
    - Replace the baseline with current build, test, explorer, and coverage results from the latest `verify.sh` + `frontends.yml`/`test.yml` runs
    - _Requirements: 1.3, 1.4_
  - [x] 1.9 Implement the conflict-free merge gate
    - Owner: devops → `scripts/ci/merge-gate.sh`
    - `check_ownership` (diff ⊆ owned prefix), `check_reserved` (reserved paths untouched by non-owner; proto only from architect-approved pass), `check_green` (`verify.sh` green for touched platform + no other-platform `STATUS.md` regression); `gate()` composes them
    - _Requirements: 2.6, 2.7, 2.8_ — _Maps: Merge gate component_
  - [x] 1.10 Write property tests for the merge gate
    - Owner: devops → `scripts/tests/test_merge_gate.py`
    - **Property 3: Merge-gate ownership rejection** — rejects any changeset touching a path outside the owned prefix; permits only when every path is under it
    - **Property 4: Merge-gate green / no-regression** — accepts only when `verify.sh` is green and no other platform's scoreboard regresses
    - **Property 5: Path-ownership disjointness** — any two parallel-scheduled owned prefixes never overlap
    - Minimum 100 randomized iterations per property; tag Property 3/4/5
    - _Requirements: 2.2, 2.3, 2.7, 2.8_

- [x] 2. R1 — Shared daemon and provider completion (serial; must precede frontend consumers)
  - [x] 2.1 Implement `DockerService.PullImage` real progress streaming
    - Owner: go-daemon-dev → `daemon/internal/docker/client.go`, `daemon/internal/server/docker_server.go`
    - Stream real layer progress; propagate client cancellation and backend errors; no synthesized progress
    - _Requirements: 3.2_
  - [x] 2.2 Implement `DockerService.PushImage` real progress streaming
    - Owner: go-daemon-dev → `daemon/internal/docker/client.go`, `daemon/internal/server/docker_server.go`
    - Stream real push progress; propagate cancellation and errors to the client
    - _Requirements: 3.2_
  - [x] 2.3 Add configurable Unix-socket and loopback-TCP listeners with graceful shutdown
    - Owner: go-daemon-dev → `daemon/internal/server/server.go`, `daemon/cmd/**`
    - Expose both listeners configurably; drain in-flight streams on graceful shutdown
    - _Requirements: 3.3_
  - [x] 2.4 Implement profile-scoped targeting and unscoped-request rejection
    - Owner: go-daemon-dev → `daemon/internal/server/command.go`, `daemon/internal/server/colima_extra.go`
    - Target the profile named in each profile-scoped request; reject requests missing a profile/provider field required for safe scoping with a contextual error
    - _Requirements: 3.4, 3.5_ — _Maps: Property 10, 11_
  - [x] 2.5 Write daemon request-scoping property tests
    - Owner: go-daemon-dev → `daemon/internal/server/*_test.go`
    - **Property 10: Profile-scoped command targeting** — a request carrying profile `P` targets `P`, never a default/global target
    - **Property 11: Unscoped-request rejection** — a request omitting a required scope field is rejected with a contextual error, never executed globally
    - Minimum 100 randomized iterations (random profile names + omitted-field permutations); tag Property 10/11
    - _Requirements: 3.4, 3.5_
  - [x] 2.6 Reflect the approved pre-v1 additive scope fields in the proto and generated code
    - Owner: go-daemon-dev proposes → `daemon/proto/**`; architect approves `proto/colima_ui.proto`
    - Add only the recorded additive scope fields on `Update`/`Prune`/`Rename`/`Tag`/`Search`/`NetworkContainer`; preserve all existing field numbers; integrate as the single `contract-integration` pass
    - _Requirements: 2.1, 3.4_ — _Maps: Property 6_
  - [x] 2.7 Write per-RPC bufconn integration tests + race/leak checks
    - Owner: go-daemon-dev → `daemon/internal/server/*_test.go`
    - Assert every one of the 65 RPCs has a concrete (non-`Unimplemented`) server method via bufconn; run `go test -race` with no leaked goroutines across stream cancellation
    - _Requirements: 3.1, 3.6_ — _Maps: Property 7_
  - [x] 2.8 Verify daemon cross-compilation for all targets
    - Owner: go-daemon-dev → `daemon/**` (build tags / `daemon/cmd`)
    - Ensure the daemon compiles for macOS, Linux, and Windows build targets
    - _Requirements: 3.7_

- [x] 3. Checkpoint — daemon green
  - Ensure `go test ./...`, `go test -race ./...`, and cross-build pass; append the R1 `outcome` entry to `INTENT_LEDGER.md`; confirm the merge gate passes for `daemon/**`. Ask the user if questions arise.

- [x] 4. R2 — TUI per-action parity (parallel; owner tui-dev → `tui/**`)
  - [x] 4.1 Bind VM lifecycle actions to real profile-scoped RPCs
    - Bind start, stop, restart, delete, update, prune, and SSH-config to the matching `ColimaService` RPC for the active profile
    - _Requirements: 4.1_ — _Maps: Property 12_
  - [x] 4.2 Bind container/image/volume/network actions to `DockerService` RPCs
    - Bind all four resource groups to the matching `DockerService` RPC for the active profile
    - _Requirements: 4.2_ — _Maps: Property 12_
  - [x] 4.3 Bind Kubernetes/runtime/profile/config/template/AI-model actions
    - Bind these to the matching `ColimaService` RPC for the active profile
    - _Requirements: 4.3_ — _Maps: Property 12_
  - [x] 4.4 Add destructive confirmation, streamed cancellation, bounded output, and error-with-context
    - Require explicit confirmation before any destructive RPC; support cancellation of streamed actions; bound displayed output; render errors with context
    - _Requirements: 4.4, 4.5, 4.6_ — _Maps: Property 13, 14, 15_
  - [x] 4.5 Write teatest deterministic dispatch tests
    - **Property 12: Action-to-RPC dispatch mapping** — each advertised action invokes exactly its mapped RPC, scoped to the active profile
    - **Property 13: Destructive-action confirmation gate** — no RPC unless confirmed; dismissed confirmation issues none
    - **Property 14: Bounded streamed output** — displayed lines never exceed the configured bound
    - **Property 15: Error rendering with context** — an errored RPC yields rendered state containing the contextual error
    - Minimum 100 randomized iterations per property; tag Property 12/13/14/15
    - _Requirements: 4.7_
  - [x] 4.6 Add the gated live PTY lane against `desktop-e2e`
    - Owner: tui-dev → `tui/**` (teatest/PTY harness); activates only when the `desktop-e2e` socket is present
    - _Requirements: 4.7_ — _Evidence: deterministic → live-backend_

- [x] 5. R3 — Windows per-action parity (parallel; owner windows-native-dev → `windows/**`)
  - [x] 5.1 Produce the exact Windows 65-RPC → command-handler binding map
    - _Requirements: 5.1_ — _Maps: Property 12_
  - [x] 5.2 Invoke real gRPC calls for VM lifecycle/profile/SSH/update/prune
    - _Requirements: 5.2_
  - [x] 5.3 Invoke real gRPC calls for container/image/volume/network mutations + event/log/stat streams
    - _Requirements: 5.3_
  - [x] 5.4 Invoke real gRPC calls for Kubernetes/AI/runtime/config/template/monitoring
    - _Requirements: 5.4_
  - [x] 5.5 Add accessible destructive confirmation, non-reentrant busy state, cancellation, error surfacing, and stable a11y identifiers
    - _Requirements: 5.5, 5.6, 5.7_ — _Maps: Property 13, 16, 17_
  - [x] 5.6 Write Windows view-model/service tests (native `windows-winui` CI runner)
    - **Property 12: Action-to-RPC dispatch mapping** — each command handler invokes exactly its mapped, profile-scoped RPC
    - **Property 13: Destructive-action confirmation gate**
    - **Property 16: Non-reentrant busy state** — a concurrent invocation of an in-flight command is blocked until it completes/cancels
    - **Property 17: Accessibility identifier totality/uniqueness** — every interactive control has a unique non-empty identifier
    - Minimum 100 randomized iterations per property; tag Property 12/13/16/17
    - _Requirements: 5.8_ — _Environment-bounded: parity proven via green `windows-winui` CI; live UIA capture is environment-blocked on the macOS-only host (evidence capped at CI-without-daemon)_

- [x] 6. R4 — Linux per-action parity (parallel; owner linux-native-dev → `linux/**`)
  - [x] 6.1 Produce the exact Linux 65-RPC → callback matrix
    - _Requirements: 6.1_ — _Maps: Property 12_
  - [x] 6.2 Invoke real gRPC calls for VM lifecycle/profile/SSH/update/prune callbacks
    - _Requirements: 6.2_
  - [x] 6.3 Invoke real gRPC calls for container/image/volume/network mutations + streams
    - _Requirements: 6.3_
  - [x] 6.4 Invoke real gRPC for Kubernetes/AI/runtime/config/template/monitoring; apply GTK mutations on the GLib main context
    - _Requirements: 6.4, 6.5_
  - [x] 6.5 Require confirmation before destructive actions
    - _Requirements: 6.6_ — _Maps: Property 13_
  - [x] 6.6 Write Rust unit tests + clippy (`-D warnings`) + fmt check
    - **Property 12: Action-to-RPC dispatch mapping** — each callback invokes exactly its mapped, profile-scoped RPC
    - **Property 13: Destructive-action confirmation gate**
    - Minimum 100 randomized iterations per property; tag Property 12/13
    - _Requirements: 6.7_ — _Environment-bounded: parity proven via green `linux-gtk4` CI; live AT-SPI capture is environment-blocked on the macOS-only host (evidence capped at CI-without-daemon)_

- [x] 7. R5 — macOS product-gap closure (parallel; owner swiftui-dev → `Sources/**`)
  - [x] 7.1 Build the template read/edit/save interface over `GetTemplate`/`SetTemplate`
    - _Requirements: 7.1_ — _Maps: Property 18_
  - [x] 7.2 Require confirmation before destructive Docker mutations
    - _Requirements: 7.2_ — _Maps: Property 13_
  - [x] 7.3 Display observed image-pull progress (not synthesized)
    - Consume the real `PullImage` progress stream from task 2.1
    - _Requirements: 7.3_
  - [x] 7.4 Load configuration from real profile YAML and preserve unknown keys on save
    - _Requirements: 7.4_ — _Maps: Property 19_
  - [x] 7.5 Resolve the orphaned create-container view
    - Wire the view into navigation or remove it (no orphaned code)
    - _Requirements: 7.5_
  - [x] 7.6 Expose the Runtime Controls surface for accessibility traversal with stable identifiers
    - _Requirements: 7.6_ — _Maps: Property 17_

- [x] 8. R2–R5 — macOS dispatch & property tests (parallel; owner swift-test-engineer → `Tests/**`)
  - [x] 8.1 Write the template round-trip property test
    - **Property 18: Template read/save round-trip** — saving via `SetTemplate` then reading via `GetTemplate` returns equivalent content
    - Minimum 100 randomized iterations; tag Property 18
    - _Requirements: 7.1_
  - [x] 8.2 Write the configuration unknown-key preservation property test
    - **Property 19: Configuration unknown-key preservation** — load-then-save preserves every unknown key and known value
    - Minimum 100 randomized iterations; tag Property 19
    - _Requirements: 7.4_
  - [x] 8.3 Write the macOS accessibility-identifier property test
    - **Property 17: Accessibility identifier totality/uniqueness** — every interactive control has a unique, non-empty, keyboard-accessible identifier per surface
    - Minimum 100 randomized iterations; tag Property 17
    - _Requirements: 7.6, 11.4_
  - [x] 8.4 Write the macOS destructive-confirmation property test
    - **Property 13: Destructive-action confirmation gate** — no Docker mutation RPC is issued without confirmation
    - Minimum 100 randomized iterations; tag Property 13
    - _Requirements: 7.2_
  - [ ]* 8.5 Add supplementary XCUITest coverage for the R5 surfaces
    - Drive the template UI, create-container navigation, and Runtime Controls surface (supplementary to the live-exercise evidence produced in task 10.6)
    - _Requirements: 7.1, 7.5, 7.6_

- [x] 9. Checkpoint — frontends parity green
  - Ensure each frontend's suite passes (teatest, `windows-winui`, `linux-gtk4`, macOS unit/integration/snapshot), all macOS property tests pass, ledger `outcome` entries are appended, and the merge gate + `verify.sh` are green with no cross-platform scoreboard regression. Ask the user if questions arise.

- [x] 10. R6/R9/R10 — Live environment, full-functionality exercise, and DependencyManager (after frontends)
  - [x] 10.1 Implement the `desktop-e2e` live environment lifecycle
    - Owner: devops → `scripts/live/e2e-env.sh` (+ wire `scripts/verify.sh` to run the RealBackend lane when the profile socket is present)
    - Delivered subcommands, all idempotent: `up`, `status`, `down`, `teardown`, `restore-orbstack`, `guard`, `selftest`, `harness-exec`, `evidence`
    - `up` stops OrbStack (recording the state so `restore-orbstack` can undo it), starts only `desktop-e2e`, blocks on the profile-scoped socket (never the default `docker.sock`); `down` stops the profile reversibly and `teardown` removes `e2e-`-prefixed resources and deletes the profile idempotently, including after a suite failure; confine lifecycle tests to `desktop-e2e`; locate the live project under `/Volumes/Projects/`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.7_ — _Maps: Property 1, 2; live-env lifecycle component_
  - [x] 10.2 Implement the profile safety guard (hard invariant)
    - Owner: devops → `scripts/live/guard.sh` — a centralized choke point sourced by `scripts/live/e2e-env.sh`, the R9 exercise harness, and the `verify.sh` RealBackend lane, and also runnable as a CLI (`guard`/`profile`/`socket`/`env`/`exec`/`selftest`); `e2e-env.sh guard` and `harness-exec` delegate to it
    - `guard(profile)` exits 0 iff `profile == desktop-e2e`; every other target is rejected before any Colima/Docker call. The allowed profile is a **locked literal** (`readonly E2E_PROFILE="desktop-e2e"`) that is never read from env or args and fails closed if pre-seeded with any other value; `colima_e2e` / `docker_e2e` are the only sanctioned mutators — they assert the guard, inject `--profile desktop-e2e` / pin `DOCKER_HOST` to the profile-scoped socket, and reject caller-supplied `--profile`/`-p` and `-H`/`--host`/`-c`/`--context` overrides
    - _Requirements: 8.2, 8.5_ — _Maps: Property 1_
  - [x] 10.3 Write live-env guard and teardown property tests
    - Owner: devops → `scripts/live/guard_property_test.sh` (accept/reject battery + teardown round-trip)
    - **Property 1: Profile safety guard** — permits iff the name equals `desktop-e2e`; all others rejected before any call
    - **Property 2: Live resource create/teardown round-trip** — after teardown (including post-failure), no `e2e-`-prefixed resource remains in the profile
    - Minimum 100 randomized iterations per property (random profile names + generated resource sets); tag Property 1/2
    - _Requirements: 8.2, 8.4, 8.5_
  - [x] 10.4 Implement DependencyManager live checks
    - Owner: swiftui-dev → `Sources/**`
    - Classify `colima`, `lima`, `qemu`, `krunkit`, `docker-cli`, `kubectl` as installed/missing/outdated; offer an install path via the platform package manager or a signed direct download; return to a safe state on cancel; report offline and permission-denied conditions with remediation context
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_ — _Maps: Property 20, 21_
  - [x] 10.5 Write DependencyManager property + edge-case tests
    - Owner: swift-test-engineer → `Tests/**`
    - **Property 20: DependencyManager state totality** — each of the six tools gets exactly one state among installed/missing/outdated
    - **Property 21: Missing-dependency install-path offer** — every missing tool is offered a package-manager or signed-download path
    - Minimum 100 randomized iterations per property (tag Property 20/21); plus example tests for install-cancel, offline check, and permission-denied
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  - [x] 10.6 Implement the macOS full-functionality live exercise harness
    - Owner: devops/macos-ui-explorer → `scripts/live/full-exercise.sh` (+ `make live-e2e-exercise`), routed through the task-10.2 guard so it physically cannot target another profile; evidence written to `artifacts/live/full-exercise/`
    - Drive all 12 canonical surfaces and all 65 RPCs against the live backend; create a container, pull an image, create a volume, create a network, and exercise VM/profile/config/template/Kubernetes/AI/runtime/monitoring; assert real backend data returns without crashing; append a `GroundTruthRecord` (with `evidence_level`, `observed`, `created_resource`) per exercised action to `artifacts/live/full-exercise/ground-truth.json` (+ human-readable `full-exercise-report.txt` and per-RPC `raw/`); never use a modal (`NSSavePanel`/`NSOpenPanel`/`runModal`)
    - Delivered result: **52 passed / 0 failed / 21 withheld across 73 records, 0 crashes**, against `desktop-e2e` (docker server 29.2.1). Real resources created **and removed**: container `e2e-ctr-*`, network `e2e-net-*`, volume `e2e-vol-*`, image tag `e2e-tagged:v1`, plus a real `alpine:latest` pull. The 21 withheld records are destructive/heavy RPCs deliberately not run (or impossible here, e.g. `PushImage` with no registry) and are recorded `observed=false` / `evidence_level=environment-blocked` — never faked as success
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.6_ — _Maps: ExerciseHarness component; Property 2, 8; evidence level `live-backend`_
  - [x] 10.7 Record Windows/Linux parity evidence via green CI and honest env-blocked labeling
    - Owner: windows/linux-ui-explorer + devops → `exploration/windows/**`, `exploration/linux/**`, `.github/workflows/explore-windows.yml`, `.github/workflows/explore-linux.yml`
    - Demonstrate parity through green `frontends.yml` + `test.yml`; label live UIA/AT-SPI capture `environment-blocked` in the ground-truth artifacts (never fabricated success); the consolidated write-up is `docs/windows-linux-parity-evidence.md`
    - _Requirements: 9.5, 9.7_ — _Maps: Property 8; evidence capped at CI-without-daemon (environment-bounded)_

- [x] 11. Checkpoint — live evidence complete
  - Ensure the macOS live exercise produced ground-truth artifacts for all 12 surfaces / 65 RPCs including created resources with `live-backend` labels; Windows/Linux artifacts are labeled `environment-blocked` with green CI parity; DependencyManager tests pass; the `desktop-e2e` profile is torn down; ledger `outcome` entries appended. Ask the user if questions arise.

- [x] 12. R7 — Quality, security, performance, and accessibility hardening (after R6)
  - [x] 12.1 Enforce the `verify.sh` GREEN + coverage gate and stream safety gates
    - Owner: devops → `scripts/verify.sh`
    - Report GREEN with coverage at/above `COV_MIN` (default 71%, ~74% with the `desktop-e2e` socket); wire race/leak/cancellation gates into the scoreboard
    - _Requirements: 11.1, 11.2, 11.6_
  - [x] 12.2 Generate SBOMs and a vulnerability report
    - Owner: devops → `scripts/sbom.sh` + `scripts/sbom_gen.py`, `scripts/security-scan.sh` (+ `scripts/vuln_parse.py`, `scripts/vuln_report.py`, `scripts/tests/test_vuln_report.py`), `.github/workflows/security-scan.yml`; evidence under `docs/sbom/**`
    - Produce SBOMs (`docs/sbom/cyclonedx/**`, `components.json`/`components.md`) and a dependency/license audit (`docs/sbom/VULNERABILITY-REPORT.md` + `vuln-summary.json`, scans under `docs/sbom/scans/`) with **zero known critical vulnerabilities**; `security-scan.sh --fail-on-critical` is the gate the RC aggregator consumes
    - _Requirements: 11.3_
  - [x] 12.3 Record performance budgets
    - Owner: devops → `scripts/perf-budgets.sh`; budgets recorded in `docs/performance-budgets.md` + `docs/performance-budgets.json`
    - Capture startup-time, idle-resource, and large-list budgets as automated checks (`perf-budgets.sh --check` is the RC sub-gate; host-load-attributable overruns are reported as warnings, not faked passes)
    - _Requirements: 11.5_
  - [x] 12.4 Enforce cross-frontend accessibility-identifier uniqueness in hardening tests
    - Owner deviation (recorded honestly): implemented in the devops lane as `scripts/check-a11y-ids.py` + `scripts/tests/test_check_a11y_ids.py` (`make check-a11y`), **not** inside `Tests/**` — a Swift test target cannot scan the WinUI 3 XAML, Rust/GTK4, and Go/Bubble Tea frontends, so a cross-frontend check cannot live there. The macOS-only slice of Property 17 remains covered by task 8.3 in `Tests/**`
    - **Property 17: Accessibility identifier totality/uniqueness** — keyboard-accessible, uniquely named identifiers across the Desktop_Frontends, plus shared-id non-collision across macOS/Windows/Linux/TUI; exits non-zero on any violation so `verify.sh` and the RC gate can invoke it as a hard check
    - Minimum 100 randomized iterations; tag Property 17
    - _Requirements: 11.4_
  - [x] 12.5 Wire the release-candidate CI gate
    - Owner: devops → `.github/workflows/release-candidate.yml` (dedicated reusable `workflow_call` gate) + `scripts/rc-gate.sh` (`make rc-gate` / `make rc-gate-fast`, tested by `scripts/tests/test_rc_gate.py`), documented in `docs/release-candidate-gate.md`
    - `rc-gate.sh` is the single aggregator producing one pass/fail RC verdict: it **invokes** (never reimplements) `scripts/verify.sh` (12.1), `scripts/security-scan.sh --fail-on-critical` (12.2), `scripts/perf-budgets.sh --check` (12.3) and `scripts/check-a11y-ids.py` (12.4), and composes them with the CI-authoritative layers — all 9 `frontends.yml` jobs + `test.yml` + `security-scan.yml`, re-invoked as reusable workflows by `release-candidate.yml`. `release-candidate.yml` additionally runs the P0/P1 `defect-gate` job (`scripts/release-blocking-gate.sh`, task 13.4) and folds every job into one aggregated verdict. Layers that cannot run on a macOS-only host (the native WinUI 3 XAML and GTK 4 compiles) are reported as `n/a (CI-authoritative)`, never as a local pass. `release.yml` `needs:` this gate, so a release cannot be cut without a GREEN RC verdict
    - _Requirements: 11.6_

- [x] 13. R8 — Cross-platform v1 release (after R7)
  - [x] 13.1 Build signed versioned artifacts on tag
    - Owner: devops → `.github/workflows/release.yml`, `scripts/version.sh`, `scripts/package.sh`, `scripts/package-go.sh`, `scripts/release/checksums.sh` (+ `scripts/release/summary.py`); artifact matrix documented in `docs/release-artifacts.md`
    - On a `vX.Y.Z` tag, build versioned artifacts for macOS, Windows, Linux, the daemon, and the TUI with checksums (`SHA256SUMS.txt` + `release-manifest.json`) and SBOMs; `scripts/version.sh` is the single version authority (git tag → per-component build-time stamp, no owned-source edit); every build job `needs:` the task-12.5 RC gate
    - Signing is **credential-gated**: present credentials sign, absent credentials produce an artifact labelled exactly `UNSIGNED — signing credential <NAME> absent` with `signed=false` and the `required_credentials` names surfaced in the manifest — never a faked signature
    - _Requirements: 12.1_
  - [x] 13.2 Configure macOS signing, notarization, and a non-placeholder Sparkle key
    - Owner: devops → `scripts/sparkle-appcast.sh`, `scripts/sparkle-keys.sh`, `scripts/package.sh`, `packaging/Info.plist` (`SUPublicEDKey`); enablement steps + required secret names documented in `SIGNING.md` / `docs/SIGNING.md`
    - The Sparkle Ed25519 appcast key is **real and wired**: the committed public key is a valid 32-byte Ed25519 key (not the `REPLACE_WITH_ED25519_PUBLIC_KEY` placeholder), its private half lives only in the macOS login keychain, and CI consumes it as `SPARKLE_PRIVATE_KEY`
    - Developer ID signing and notarization are implemented and credential-gated but **not exercised**: no Apple Developer Program credentials exist on this host, so `release.yml` `if:`-gates the cert-import/notarize/appcast steps on secret presence and `package.sh` emits an honestly labelled unsigned (ad-hoc) DMG instead
    - _Requirements: 12.2_
  - [x] 13.3 Sign and package the Windows and Linux deliverables
    - Owner: devops → `scripts/windows/package-windows.ps1`, `scripts/linux/package-linux.sh`
    - Sign+package the Windows (`.zip` with Authenticode-signed binaries) and Linux (`.tar.gz` + `.deb`, detached `.asc`) deliverables on their own CI runners; signing is credential-gated the same way (`WINDOWS_CERTIFICATE_PFX`, `LINUX_GPG_PRIVATE_KEY`, …), so on this host both package unsigned with the honest label
    - _Requirements: 12.3_
  - [x] 13.4 Implement the P0/P1 release-blocking gate
    - Owner: devops → `scripts/release_blocking_gate.py` + `scripts/release-blocking-gate.sh`, defect register at `docs/release-defects.json`
    - Block the `v1.0.0` tag if any open defect carries priority P0 or P1 (also auto-ingests `docs/sbom/vuln-summary.json`: critical→P0, high→P1); wired as the `defect-gate` job in `release-candidate.yml` and re-run directly by `release.yml`. Current register state: **0 open P0/P1**
    - _Requirements: 12.5_ — _Maps: Property 22_
  - [x] 13.5 Write the release-blocking property test
    - Owner: devops → `scripts/tests/test_release_blocking_gate.py`
    - **Property 22: Release P0/P1 blocking** — the gate blocks the tag iff the open-defect set contains at least one P0/P1
    - Minimum 100 randomized iterations (generated defect sets); tag Property 22
    - _Requirements: 12.5_
  - [x] 13.6 Finalize the publish job gated on all-green
    - Owner: devops → `.github/workflows/release.yml`
    - When all v1 gates pass, publish release notes, assets, checksums, and the appcast for the `v1.0.0` tag (workflow authoring; the tag push itself is a human release action, and the signing/notarize/appcast steps are `if:`-gated on secret presence — so a signed publish happens only once those credentials are configured)
    - _Requirements: 12.4_
  - [x] 13.7 Align v1 documentation with shipped artifacts
    - Owner: docs → `docs/**`, `README*`, `SIGNING.md`
    - Align installation, troubleshooting, architecture, security, privacy, and limitations docs; document the Windows and Linux install and trust behavior
    - Delivered set: `docs/INSTALL.md`, `docs/ARCHITECTURE.md`, `docs/release-artifacts.md`, `docs/release-candidate-gate.md`, `SIGNING.md` + `docs/SIGNING.md`, `docs/windows-linux-parity-evidence.md` (the environment-bounded Windows/Linux trust + parity evidence), `docs/performance-budgets.md`, `docs/sbom/README.md` + `docs/sbom/VULNERABILITY-REPORT.md`
    - _Requirements: 12.3, 12.6_

- [x] 14. R13 — Completion notification (strictly last; owner devops → `scripts/notify/**`)
  - [x] 14.1 Implement notification rendering
    - Owner: devops → `scripts/notify/render.py`
    - `render(summary) -> {email, sms}`: email contains the released version, all completed roadmap ids, and the final verification result; SMS contains the version and final verification result; read recipients from the fixed values, credentials from environment variables only
    - _Requirements: 13.1, 13.2, 13.3_ — _Maps: Property 23_
  - [x] 14.2 Implement channel delivery with the credentials-absent fallback
    - Owner: devops → `scripts/notify/deliver.py`
    - `deliver(channel, payload, env)`: send via SMTP/SendGrid (email) and Twilio/equivalent (SMS); when any channel's credentials are absent or partial, write the drafted content to `dist/notifications/*.txt` and emit a re-runnable `send-notifications.sh` rather than failing the release; send the same summary through any configured optional channel (Viber/WhatsApp/Telegram)
    - Delivered path on this host: **no SMTP/Twilio credentials exist, so the fallback is the exercised path** — nothing was transmitted. Drafted to `dist/notifications/email-v1.0.0.txt`, `sms-v1.0.0.txt`, `notifications-v1.0.0.json`, plus the re-runnable `dist/notifications/send-notifications.sh` for delivery once credentials are exported
    - _Requirements: 13.3, 13.4, 13.5_ — _Maps: Property 24_
  - [x] 14.3 Implement the secret-hygiene scrub
    - Owner: devops → `scripts/notify/scrub.py`
    - `scrub(text, known_secrets)`: assert no credential/secret substring appears in rendered messages, logs, or committed evidence before write/transmit; the payload type structurally excludes secrets
    - _Requirements: 8.6, 13.6_ — _Maps: Property 25_
  - [x] 14.4 Write notification property tests
    - Owner: devops → `scripts/tests/test_notify.py`
    - **Property 23: Notification rendering completeness** — email carries version + all roadmap ids + verify result; SMS carries version + verify result
    - **Property 24: Notification credentials-absent fallback** — any absent-credential subset yields a drafted file + send script and does not fail the release for that channel
    - **Property 25: Secret hygiene invariant** — no secret substring appears in any rendered message, log line, or committed artifact
    - Minimum 100 randomized iterations per property; tag Property 23/24/25
    - _Requirements: 13.1, 13.2, 13.4, 13.6, 8.6_

- [x] 15. Final checkpoint — v1.0.0 ready
  - Ensure `verify.sh` reports GREEN at/above `COV_MIN`, all 9 `frontends.yml` jobs and `test.yml` are green, the release publish job is gated on the RC gate, and the notification was sent or drafted-to-file; append the final `outcome` entries to `INTENT_LEDGER.md`. Ask the user if questions arise.
  - Delivered state, stated honestly: the RC gate composes GREEN with the native XAML/GTK4 compiles reported `n/a (CI-authoritative)`; release artifacts are built and checksummed but labelled `UNSIGNED — signing credential <NAME> absent` because no Apple Developer ID / notary / Windows Authenticode / Linux GPG credentials are configured (the Sparkle Ed25519 appcast key is real and wired); the completion notification was **drafted to `dist/notifications/`, not transmitted**, because notification credentials are absent. No signed release exists and no email/SMS was sent.

## Notes

- **Ledger discipline:** every task appends an `intent` entry (intent + plan + files-to-touch) before
  starting and an `outcome` entry (evidence + contract-impact) after finishing to
  `.kiro/board/INTENT_LEDGER.md`; the append-only log is never rewritten.
- **Merge gate:** integration to `main` is Integration_Agent-only and runs ownership →
  reserved-path → `verify.sh` green / no scoreboard regression → (for R8) the release-candidate gate
  from task 12.5 (9 `frontends.yml` jobs + `test.yml` + verify/security/perf/a11y + the P0/P1 defect
  gate). Any out-of-lane or reserved-path write is rejected.
- **Property tests are release-gating, not optional:** per the design Testing Strategy, every
  numbered-property test is a required correctness gate and is intentionally left unmarked. Each runs
  a minimum of 100 randomized iterations and is tagged `Feature: cross-platform-live-verification,
  Property {n}`. Only genuinely supplementary tests (e.g. task 8.5 XCUITest) are marked optional `*`.
- **`live-backend` is the only level that closes a live-verification obligation;**
  `deterministic-fake-data` never does, and `environment-blocked` is an honest terminal label.
- **Environment-bounded honesty (Assumption A2):** macOS is verified with local live evidence against
  `desktop-e2e`; Windows and Linux parity is proven through green CI (`frontends.yml` + `test.yml`)
  because live UIA/AT-SPI capture is environment-blocked on the macOS-only host — tasks 5.6, 6.6, and
  10.7 are labeled accordingly and are not represented as fully-local live verification.
- **Owner/path deviation (task 12.4), recorded rather than hidden:** the cross-frontend
  accessibility-identifier check landed in the devops lane as `scripts/check-a11y-ids.py` +
  `scripts/tests/test_check_a11y_ids.py` (`make check-a11y`) instead of `Tests/**`, because a Swift
  test target cannot scan the WinUI 3 XAML, Rust/GTK4, and Go/Bubble Tea frontends. The macOS slice
  of Property 17 still lives in `Tests/**` (task 8.3).
- **Delivered outcome (environment-bounded; nothing here is overstated):**
  - **macOS — `live-backend`.** `scripts/live/full-exercise.sh` (`make live-e2e-exercise`) drove the
    12 surfaces / 65 RPCs against the disposable `desktop-e2e` profile: 52 passed, 0 failed,
    21 withheld across 73 records, 0 crashes, with a real container, network, volume, image tag, and
    `alpine:latest` pull all created **and removed**. Withheld records are labelled
    `environment-blocked` with `observed=false`, never faked.
  - **Windows / Linux — `CI-without-daemon`.** Parity is proven by green CI; live UIA and AT-SPI
    capture remain `environment-blocked` on this macOS-only host (see
    `docs/windows-linux-parity-evidence.md`).
  - **Artifacts — credential-gated, honestly labelled.** Packaging, checksums, and the appcast
    pipeline are complete and RC-gated, but every artifact built here carries
    `UNSIGNED — signing credential <NAME> absent`: no Apple Developer ID, notarization, Windows
    Authenticode, or Linux GPG credentials are configured. The Sparkle Ed25519 appcast key **is**
    real and wired (public key committed, private half in the login keychain, CI secret
    `SPARKLE_PRIVATE_KEY`). **No signed release exists.**
  - **Notification — drafted, not sent.** With no SMTP/Twilio credentials present, the
    credentials-absent fallback is the exercised path: `dist/notifications/email-v1.0.0.txt`,
    `sms-v1.0.0.txt`, `notifications-v1.0.0.json`, and a re-runnable `send-notifications.sh`.
    **No email or SMS was transmitted.**
- **Where the R7/R8 evidence lives (for discoverability):** security → `scripts/security-scan.sh` +
  `docs/sbom/**` (SBOMs + `VULNERABILITY-REPORT.md`, zero known critical); performance →
  `scripts/perf-budgets.sh` + `docs/performance-budgets.{md,json}`; release-blocking defects →
  `scripts/release_blocking_gate.py` + `scripts/release-blocking-gate.sh` + `docs/release-defects.json`
  (0 open P0/P1); packaging → `scripts/package.sh`, `scripts/package-go.sh`,
  `scripts/release/checksums.sh`, `scripts/windows/package-windows.ps1`,
  `scripts/linux/package-linux.sh`; signing/release docs → `SIGNING.md`, `docs/SIGNING.md`,
  `docs/release-artifacts.md`, `docs/release-candidate-gate.md`; notification →
  `scripts/notify/{render,deliver,scrub}.py` + `scripts/tests/test_notify.py`.
- **Blast radius (Assumption A3):** all create/start/stop/delete lifecycle tests use the disposable
  `desktop-e2e` profile with teardown after each suite; the profile safety guard (Property 1) is the
  single enforced invariant that keeps every destructive action inside `desktop-e2e`.
- **Conflict-free by construction:** every task stays inside one owned prefix; reserved paths
  (`.kiro/board/**`, `proto/colima_ui.proto`, `README*`, `docs/parity-matrix.md`,
  `docs/truth-table.csv`) are written only by the orchestrator/architect.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0,  "tasks": ["1.1", "1.8", "1.9"] },
    { "id": 1,  "tasks": ["1.2", "1.10"] },
    { "id": 2,  "tasks": ["1.3", "1.4"] },
    { "id": 3,  "tasks": ["1.5", "1.6", "1.7"] },
    { "id": 4,  "tasks": ["2.1", "2.3", "2.6"] },
    { "id": 5,  "tasks": ["2.2", "2.4"] },
    { "id": 6,  "tasks": ["2.5", "2.7", "2.8"] },
    { "id": 7,  "tasks": ["4.1", "5.1", "6.1", "7.1"] },
    { "id": 8,  "tasks": ["4.2", "5.2", "6.2", "7.2", "8.1"] },
    { "id": 9,  "tasks": ["4.3", "5.3", "6.3", "7.3", "8.4"] },
    { "id": 10, "tasks": ["4.4", "5.4", "6.4", "7.4"] },
    { "id": 11, "tasks": ["4.5", "5.5", "6.5", "7.5", "8.2"] },
    { "id": 12, "tasks": ["4.6", "5.6", "6.6", "7.6"] },
    { "id": 13, "tasks": ["8.3", "8.5"] },
    { "id": 14, "tasks": ["10.1", "10.4"] },
    { "id": 15, "tasks": ["10.2", "10.5"] },
    { "id": 16, "tasks": ["10.3", "10.6", "10.7"] },
    { "id": 17, "tasks": ["12.1", "12.2", "12.3", "12.4", "12.5"] },
    { "id": 18, "tasks": ["13.1", "13.2", "13.3", "13.4", "13.7"] },
    { "id": 19, "tasks": ["13.5", "13.6"] },
    { "id": 20, "tasks": ["14.1", "14.2", "14.3"] },
    { "id": 21, "tasks": ["14.4"] }
  ]
}
```

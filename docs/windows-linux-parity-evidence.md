# Windows & Linux Parity Evidence (R9.5 / task 10.7)

> **What this document is.** The honest, per-frontend / per-RPC-area record of *how* Windows
> (WinUI 3) and Linux (GTK 4) parity is evidenced for the `v1.0.0` release, given that the
> verification host is **macOS-only**. It states, for every RPC area, what is proven **on-host**,
> what is proven **on green CI**, and what is **environment-blocked on this host** — with links to
> the exact CI job names that carry each proof.
>
> **Assumption A2 (from requirements).** macOS receives full live real-backend testing locally
> against the disposable `desktop-e2e` profile (task 10.6). Windows and Linux parity is proven
> through **green CI** (native compile + tests in `frontends.yml` and `test.yml`) rather than live
> UI testing on this host, because **live UIA and AT-SPI capture against a running daemon are
> environment-blocked on a macOS-only host**.
>
> **No live Windows or Linux run happened on the macOS verification host.** Any Windows/Linux
> element captures under `exploration/**` were produced on hosted CI runners **without a live
> colima daemon** (UI chrome only). This document never claims otherwise.

Related: `docs/parity-matrix.md` + `docs/truth-table.csv` (architect-owned per-RPC×frontend
handler/evidence matrix), `docs/gap-report.md` (source gap analysis), `exploration/ground-truth.json`
(unified capture summary), `exploration/windows/EVIDENCE.md` + `exploration/linux/EVIDENCE.md`
(durable per-artifact evidence labels).

---

## 1. Evidence-level taxonomy (spec convention)

Every cell below carries **exactly one** level from the frozen taxonomy (design "Evidence &
Traceability"), ordered weakest → strongest:

| Level | Meaning | Where it comes from |
|-------|---------|---------------------|
| `source-only` | A concrete handler exists in source | audit of frontend code |
| `deterministic-fake-data` | Renders/behaves correctly against fake fixtures | unit / view-model / render tests |
| `CI-without-daemon` | **Compiles and passes tests on a native runner with no live daemon** | `frontends.yml`, `test.yml` |
| `live-backend` | Verified against a live Colima daemon (`desktop-e2e`) | macOS RealBackend lane / live exercise |
| `environment-blocked` | Capture could not run in this environment (recorded, never faked) | live UIA / AT-SPI on a macOS-only host |

**Windows and Linux are capped at `CI-without-daemon`.** The native runners compile the real WinUI 3
XAML / GTK 4 code and run the deterministic test suites, but neither runner has a live colima daemon,
and live UIA/AT-SPI capture against a real backend cannot run on the macOS-only host — that dimension
is honestly labeled `environment-blocked`. `live-backend` is **not** claimed for Windows or Linux.

> Note on the term "CI-native": the native-runner **compile** (WinUI XAML on `windows-latest`, GTK 4
> on `ubuntu-latest`) is the strongest thing the CI proves beyond source; in the frozen 5-level
> taxonomy it still belongs to the **`CI-without-daemon`** band (compiles + tests, no live daemon).
> This document uses "native compile" as descriptive detail, not as a separate taxonomy level.

---

## 2. Per-frontend summary

| Frontend | Native compile | Deterministic tests (no daemon) | Live UI vs. live backend | Evidence ceiling |
|----------|----------------|----------------------------------|--------------------------|------------------|
| **macOS** (SwiftUI) | on-host (`xcodebuild`) + CI `macos-kit` | unit + integration + snapshot (on-host + CI) | **live-exercised on-host** vs. `desktop-e2e` (task 10.6) | **`live-backend`** |
| **Windows** (WinUI 3) | CI `windows-winui` (native XAML compile) | **69 headless view-model/service tests** (net8.0) | **`environment-blocked`** on the macOS host | **`CI-without-daemon`** |
| **Linux** (GTK 4) | CI `linux-gtk4` (native compile) | **27 Rust unit tests + clippy `-D warnings` + `fmt --check`** | **`environment-blocked`** on the macOS host | **`CI-without-daemon`** |
| **TUI** (Bubble Tea) | on-host + CI `tui` (×3 OS) | teatest dispatch/render + gated live PTY lane (task 4.6) | live PTY lane gated on `desktop-e2e` socket | `deterministic-fake-data` → `live-backend` (gated) |
| **Daemon** (Go) | on-host + CI `daemon` (×3 OS), 5-target cross-build | `go test` + `go test -race`, per-RPC bufconn (65/65) | live read-only stats/process vs. `desktop-e2e` | `CI-without-daemon` + partial live |

macOS is the **only** frontend with `live-backend` evidence. Windows and Linux are proven to full
per-action parity in source (65/65 RPC handlers each — see `windows/RPC_AUDIT.md`,
`linux/RPC_AUDIT.md`) and to compile + pass their deterministic suites on their **native** CI
runners; their live-UI-vs-live-backend dimension is `environment-blocked` on this host.

---

## 3. Per-RPC-area × frontend evidence matrix

The 65 frozen-contract RPCs (31 `ColimaService` + 34 `DockerService`) grouped by area. Cells give
the honest evidence level for **Windows** and **Linux**; the macOS column is shown for contrast
(live-exercised in task 10.6). "Handler" = a concrete command handler / callback is wired in source
(verified by each frontend's `RPC_AUDIT.md`, 65/65).

| RPC area (RPCs) | Windows | Linux | macOS (contrast) |
|-----------------|---------|-------|------------------|
| VM lifecycle — Start/Stop/Restart/Delete/Status/Version/Update/Prune/SSHConfig | handler ✓ · `CI-without-daemon` · live-UIA `environment-blocked` | handler ✓ · `CI-without-daemon` · live-AT-SPI `environment-blocked` | `live-backend` |
| Machines — ListMachines | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Profiles — ListProfiles/CreateProfile/DeleteProfile/CloneProfile | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Config / Template — GetConfig/SetConfig/GetTemplate/SetTemplate | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Kubernetes — Start/Stop/Reset/Exec | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| AI models — ModelSetup/ModelRun/ModelServe/ModelStop | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Runtime — SwitchRuntime/UpdateRuntime | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Monitoring — VMStats/ProcessList/KillProcess | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Containers — list/action/create/rename/logs/inspect/top/stats/changes/prune | handler ✓ · `CI-without-daemon` · live-UIA `environment-blocked` | handler ✓ · `CI-without-daemon` · live-AT-SPI `environment-blocked` | `live-backend` |
| Images — list/pull/remove/inspect/history/tag/push/search/prune | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Volumes — list/create/remove/inspect/prune | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Networks — list/create/remove/inspect/connect/disconnect/prune | handler ✓ · `CI-without-daemon` | handler ✓ · `CI-without-daemon` | `live-backend` |
| Streams — StreamEvents/StreamLogs/StreamStats | handler ✓ · `CI-without-daemon` (bounded-output tested) | handler ✓ · `CI-without-daemon` (bounded-output tested) | `live-backend` |

**Reading the Windows/Linux cells:** the RPC handler exists and compiles natively on the real
runner, and the deterministic (no-daemon) test suite exercises dispatch/scope/confirmation/streaming
behavior — that is `CI-without-daemon`. Driving those same surfaces with a live UIA/AT-SPI session
**against a running daemon** is `environment-blocked` on the macOS-only host (called out explicitly
for the two areas — VM lifecycle and Containers — where a live GUI walk-through would add the most,
and applies uniformly to every area).

---

## 4. CI jobs that carry the evidence

All jobs below are authored under `.github/workflows/**`. Green runs are the parity proof for
Windows and Linux.

### `frontends.yml` — 9 jobs

| Job | Runner | What it proves | Evidence level |
|-----|--------|----------------|----------------|
| `windows-winui` | `windows-latest` | **Native WinUI 3 XAML compile** + **69 headless view-model/service tests** (`Tests/ColimaDesktop.Windows.Tests.csproj`, net8.0) | `CI-without-daemon` |
| `linux-gtk4` | `ubuntu-latest` | `cargo fmt --check` + **`cargo clippy --all-targets -- -D warnings`** + **native GTK 4 compile** + **`cargo test`** (27 tests) | `CI-without-daemon` |
| `daemon` (×3) | macos / ubuntu / windows | `go build` + `go test` for the shared daemon on all three OSes | `CI-without-daemon` |
| `tui` (×3) | macos / ubuntu / windows | `go build` + `go test` for the TUI on all three OSes | `deterministic-fake-data` |
| `macos-kit` | `macos-latest` | `xcodebuild test` — macOS unit + integration | `deterministic-fake-data` (+ `live-backend` on-host, task 10.6) |

The `windows-winui` and `linux-gtk4` jobs were **aligned in this task (10.7)** so they run the
same deterministic suites that already pass on-host (see §5), not just the native compile. That
makes the green CI run the *authoritative* record of the native XAML/GTK compile plus the test
suites — the two things that cannot run on the macOS-only host to full depth.

### `test.yml` — macOS unit + integration

Runs `xcodebuild build-for-testing` + unit + integration on `macos-15`. Release-candidate gate
alongside the 9 `frontends.yml` jobs.

### `explore-windows.yml` / `explore-linux.yml` — UI-chrome capture (no live daemon)

These capture the accessibility tree on hosted runners **without a live daemon**:

- `explore-windows.yml` (`windows-latest`, FlaUI / UIA3) → `exploration/windows/ground-truth.json`
  (13 surfaces, 699 UIA elements, 0 capture errors). gRPC-backed surfaces show
  `Status(StatusCode="Unavailable", …)` — **no live backend**.
- `explore-linux.yml` (`ubuntu-latest`, pyatspi + xdotool under Xvfb) →
  `exploration/linux/ground-truth.json` (12 surfaces, 887 AT-SPI elements, 0 errors). Backend
  surfaces show `✗ Error: transport error` — **no live backend** (colima is shimmed only so the
  main window renders instead of onboarding).

These prove **UI structure / widget presence** (`CI-without-daemon`). They do **not** prove
live-backend behavior, and they are **not** a live run on the macOS host. The live-backend
dimension for both is `environment-blocked`.

---

## 5. On-host cross-check (what actually passed locally)

The deterministic suites the CI jobs run are known-green on-host; the CI job is the authoritative
record because it also performs the **native** WinUI/GTK compile that the macOS host cannot.

| Suite | On-host result | Source |
|-------|----------------|--------|
| Windows headless view-model/service tests | **69 passing, 0 failed** (net8.0, built + run via `dotnet` on the macOS host) | INTENT_LEDGER task 5.6 |
| Linux Rust unit tests | **27 passing, 0 failed** | INTENT_LEDGER task 6.6 |
| Linux clippy | **`cargo clippy --all-targets -- -D warnings` → 0 warnings** | INTENT_LEDGER task 6.6 |
| Linux format | **`cargo fmt --check` → clean** | INTENT_LEDGER task 6.6 |
| Daemon | `go test ./...` + `go test -race ./...` green; **5-target cross-build** (darwin/arm64, darwin/amd64, linux/amd64, linux/arm64, windows/amd64) | INTENT_LEDGER tasks 2.7 / 2.8 |

> The **native WinUI 3 XAML compile** and the **native GTK 4 compile** are the two things that are
> environment-blocked on the macOS-only host (no Windows SDK / `XamlCompiler.exe`; GTK live AT-SPI
> runtime). They are proven only by the `windows-winui` / `linux-gtk4` CI jobs on their real
> runners. The Windows headless test project is `net8.0` (cross-platform), which is why its 69 tests
> can also run on the macOS host — but the XAML app compile cannot.

Latest cited green CI evidence (from `PLAN.md` / `STATUS.md`, not fabricated here): `frontends.yml`
run **29646162198** (9/9 jobs), `test.yml` run **29646162210**; earlier `frontends.yml` run
**29635550954** (9/9); Linux AT-SPI explore **29645595494**; TUI PTY explore **29645819005**.

---

## 6. Honest boundaries (what is NOT claimed)

- **No live Windows run on the macOS host.** WinUI parity is green CI (`windows-winui`) + 69
  headless tests. Live UIA against a running daemon is `environment-blocked`.
- **No live Linux run on the macOS host.** GTK 4 parity is green CI (`linux-gtk4`) + 27 tests +
  clippy `-D warnings` + `fmt`. Live AT-SPI against a running daemon is `environment-blocked`.
- The `exploration/windows` and `exploration/linux` element captures are **CI, no-daemon, UI-chrome
  only** — not live-backend, not run on this host.
- The Windows/Linux **live-backend** cells are intentionally left unproven and labeled
  `environment-blocked`; `deterministic-fake-data`/`CI-without-daemon` never close a live-backend
  obligation, and `environment-blocked` is an honest terminal label — never a fabricated pass.

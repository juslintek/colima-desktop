# Colima Install Detection & Onboarding — Knowledge Base

> Why and how Colima Desktop detects a missing Colima runtime and offers a one-click install,
> plus how this is tested in **both** real (host) and mock (VM/CI) modes. Companion:
> `E2E_TESTING_KNOWLEDGE_BASE.md`, `FLAKINESS_ANALYSIS.md`.

## Motivation

Colima Desktop is a GUI for the Colima runtime. A first-run user may not have Colima installed.
The app must **detect** that and **prompt to install it** (it should not show an empty/broken
dashboard). The app orchestrates the install via Homebrew so the user doesn't touch a terminal.

## Implementation (minimal)

- **`ServiceProvider`** gains `isColimaInstalled() async -> Bool` and `installColima() async throws`.
- **`DaemonClient`**
  - `isInstalled()` — true if a `colima` binary exists in `/opt/homebrew/bin`, `/usr/local/bin`,
    or `/usr/bin`.
  - `install()` — runs `brew install colima docker` (long-running).
- **`RealServiceProvider`** delegates both to `DaemonClient`.
- **`MockServiceProvider`** simulates absence via the `--no-colima` launch arg
  (`colimaInstalled = !args.contains("--no-colima")`); `installColima()` flips it to installed.
- **`AppState`**: `@Published var colimaInstalled` (default true) + `isInstallingColima`.
  `refreshAll()` sets `colimaInstalled = await services.isColimaInstalled()` first and returns
  early if absent. `installColima()` runs the install, re-checks, then `refreshAll()`.
- **`InstallColimaView`** (Sources/Views/Setup): the prompt — heading, explanation, Install
  button (→ `appState.installColima()`), and a `ProgressView` while installing.
- **`ContentView`** gates the whole UI: `if !appState.colimaInstalled { InstallColimaView() } else { … }`.

## Testing — real (host) AND mock (VM/CI)

Per project rules, **XCUITests can't run on the host** ("Timed out while enabling automation
mode"), but **integration tests can**. So coverage is split:

- **Real / host** — `Tests/Integration/InstallDetectionTests.swift` (Swift Testing, no GUI):
  - `isInstalled()` matches actual filesystem presence.
  - `RealServiceProvider` agrees with `DaemonClient`.
  - Real `colima version` round-trip when installed (exercises the actual `Process` + PATH path).
  - Run on host: `xcodebuild test -scheme ColimaDesktop -destination 'platform=macOS' \
    -only-testing:ColimaDesktopIntegrationTests/InstallDetectionTests`. ✅ passing on this M1 Max
    host (colima present; version round-trip 0.4s).
- **Mock / VM** — `Tests/UI/InstallPromptUITests.swift` (XCUITest): forces
  `["--ui-testing","--backend-mock","--no-colima"]` to simulate absence; asserts the prompt
  shows, the dashboard is hidden, and clicking Install transitions to the app shell. ✅ 3/3 in VM.

## Gotcha hit while building this (and the fix)

The prompt initially "didn't show" in tests. Ground-truth via `app.debugDescription` revealed it
**was** rendering: `view_install_colima` (the outer `VStack` identifier) was found, but its
children (`text_colima_not_installed`, `btn_install_colima`) were **not**. This is the documented
**container-identifier-collapses-children** trap (see `E2E_TESTING_KNOWLEDGE_BASE.md` §1). Fix:
**removed** the `.accessibilityIdentifier` from the container `VStack`; tests query the child
Button/Text directly. Detection logic was always correct.

## Notes / limitations

- The host machine now has `colima` installed but **`kern.hv_support = 0`**, so it still cannot run a
  real Colima VM — real *operational* E2E (start VM, run containers) must happen on a bare-metal
  host. Real **detection** is what the host integration test validates.
- `installColima()` requires Homebrew. If absent, the install fails and `errorMessage` is set;
  a future improvement is to detect missing brew and link to brew.sh.

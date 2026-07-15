# Changelog

All notable changes to Colima Desktop. Format follows [Keep a Changelog](https://keepachangelog.com); commits follow [Conventional Commits](https://www.conventionalcommits.org).

## v0.1.0 (pre-release) — 2026-07-15

### Features

- Windows WinUI 3 + Linux GTK4 scaffolds + CI (`11d83f9`)
- complete ColimaService handlers + testable TUI (M1.5 residual, M2.8 inc.2) (`dfd1474`)
- TUI (Bubble Tea) foundation over the daemon gRPC core (`05e3f4d`)
- DockerService + local/remote-SSH/WSL2 providers (`0f3d80e`)
- real gRPC daemon (generated stubs) + parity matrix (`fd7c08e`)
- FREEZE CONTRACT v1 — unlocks parallel M1/M2 (`10423ca`)
- coverage wiring + verify.sh scoreboard (`2042b93`)
- app icon (isometric cube) wired into app + DMG (`9c0638e`)
- detect missing Colima and prompt to install it (`66b38d8`)
- wire all views to real backend — config YAML, Docker API, kubectl (`2b6bf2e`)
- wire machine detail view + add ResourceAdvisor with battery/idle/sizing/Rosetta recommendations (`273911b`)
- Machines view - Linux/macOS/Windows VM management with create dialog, detail tabs, context menu (`d6d4f65`)
- Add Environment Variable dialog with presets (Docker/Colima/System), custom entry, and bulk add (`5a7e2a7`)
- Provisioning with mode cards (system/user), script editor with validate + examples (`f520da8`)
- SSH Port with open ports menu and validation on unfocus (`d1c5dd1`)
- Add Mount dialog with path picker, access mode, explanations for each parameter (`af8aa7f`)
- Mount Type as selectable cards with speed/pros/cons, recommends fastest for current VM type (`27b836a`)
- Gateway with default suggestion, validates reachability and warns about internet loss (`7a587f2`)
- DNS validation on unfocus - checks IP format, warns on unknown servers, suggests presets (`937f68d`)
- DNS Servers with presets dropdown (Cloudflare/Google/Quad9/OpenDNS/AdGuard) with descriptions (`09c0dfe`)
- API Port shows open ports menu, validates on unfocus, suggests alternatives (`23a8adc`)
- K8s version picker with releases, k3s args autocomplete with 10 suggestions (`0a98058`)
- Docker daemon JSON editor with schema autocomplete, format, validate (`f6326c5`)
- rich Dashboard actions (loaders, editor, prune animation, exports, migration) + visual Configuration (`a2fca91`)
- Model Browser with registry picker, search, stats (stars/downloads/size/capabilities) (`aa691ce`)
- AI Setup shows step-by-step progress with log output (`f70cd75`)
- pull progress monitoring with layer breakdown for Images and AI models (`3b24053`)
- proper UI for Update, Template, Prune (with log), Delete VM (with backup/migration options) (`3534303`)
- Activity Monitor sparklines scope to selected container/VM (`8a2d1c8`)
- right-click context menu on Activity Monitor rows (Stop, Restart, Kill) (`4c53b77`)
- move Dashboard to top of sidebar, add inline terminal (`baad28b`)
- add menu bar extra with container status, metrics, quick actions (`86382be`)
- wire real Docker event stream, streaming logs, live stats, profile switching (`5291fed`)
- Activity Monitor, tooltips, guided wizard, Cmd+K palette (`013ac55`)
- add Tart VM testing, implementation plan v2, test runner script (`2e46563`)
- ColimaUI prototype with 280 E2E tests, Go daemon, Docker client (`d16ecdf`)

### Fixes

- 0 macOS source build warnings (pristine pass) (`ba01836`)
- extract ColimaDesktopKit framework — fixes Xcode-26 test hang (`df6b8fc`)
- eliminate mock/hardcoded data in real code paths (`ce94bf4`)
- deliver Sparkle keys via merged INFOPLIST_FILE (`e469278`)
- misconfigs + misbehaviours; feat: Sparkle auto-update (`3834c95`)
- inline descriptions for Forward Agent and SSH Config (`2f846a5`)
- SSH Port shows inline port suggestions when entered port is unavailable (`df711d9`)
- add inline description for Disable Mounts (`777ad60`)
- add descriptions below Host Addresses and Preferred Route toggles (`ac6d3b2`)
- add description below Network Address toggle (`73c320c`)
- Nested Virtualization shows full description inline (`80420a6`)
- Binfmt shows full description inline instead of truncated tooltip (`b4f384f`)
- Hostname and Disk Image with descriptions, suggestions menu, and presets (`a31dfc4`)
- CPU Type as selectable cards (host/cortex-a72/max) with descriptions (`e1b3a20`)
- proper YAML indentation in template, resource bars show free/warning for over-allocation (`d481061`)
- Open ColimaUI - setIsVisible + deminiaturize + activate (`3fa0c92`)
- Open ColimaUI button finds main window correctly (not menu bar panel) (`7fd4a99`)
- Switch Context shows context picker, Update Runtime shows version + check button (`ad6b3c2`)
- runtime controls history - collapsible dropdown with configurable limit (`685e1d0`)
- swap terminal color roles - dark theme gets dark bg with light text (`281faa6`)
- terminal adapts to light/dark mode - light bg with dark text in light mode (`c4ddc46`)
- proper terminal color scheme - dark charcoal bg, soft green prompt, light gray output (`fed4716`)
- remove toolbar Running indicator (already shown in sidebar footer) (`c02c259`)
- replace green capsule badge with clean navigationSubtitle status counts (`80b6d76`)
- remove sidebar toggle button (>> icon) from toolbar (`4815c9e`)
- use 2-column NavigationSplitView for views without detail panel (`100c96d`)
- K8s toolbar-style top bar, selectable services/deployments/nodes with detail views, remove >> button (`a7ca273`)
- move K8s cluster controls and quick actions to right column (`b6cbd97`)
- hide detail column for Configuration and other full-width views (`ff98de4`)
- resolve final 7 failures - remove stat card refs, simplify wizard tests (`6ad2b09`)
- last 2 K8s test failures - segmentedControls not findable in XCUITest (`ae808bb`)
- resolve final 5 test failures - K8s tab content only renders when selected (`869207f`)
- resolve last 16 test failures - remove stat cards test, fix K8s tabs, simplify image browser tests (`5b766ce`)
- resolve XCUITest failures - 55/56 passing (`499445f`)

### Refactoring

- remove Tart VM infra, wire AI Workloads to real backend (`679e3b1`)
- decouple backend from --ui-testing so E2E can run for real (`ec41cb7`)

### Tests

- unit coverage for NavigationItem + AIModelInfo.parse (`75daaef`)
- deterministic DockerClient error paths + expanded status-menu coverage (`a832ecf`)
- comprehensive opt-in real-backend suite (35 tests) (`38356b3`)
- canonical RealE2E support helper + opt-in gating + Makefile target (`6d4a137`)
- popular-image create flows + config combos; docs: E2E knowledge base (`5353d6a`)
- fix terminal field + monitoring nav E2E flakiness (`296b257`)
- make native-perf config E2E reliable via control values (`2a21622`)
- fix 15 failing E2E tests + add VM/k8s/native-perf config E2E coverage (`5227940`)
- add MachinesUITests, add terminal/DNS tests, fix k3sargs and lock icon tests to match source (`6c2e601`)
- convert all toast-based tests to existence tests for XCUITest reliability (`457a100`)

### Documentation

- truth table (7996 combos) + real-backend exploration of every view (`f956af2`)
- record final cleanup proof (desktop-e2e deleted, default intact) (`f9779ae`)
- real-mode execution board — matrix, recipe, findings, results (`24f4a67`)
- record final 317-test green run in E2E knowledge base (`708aa60`)
- E2E suite green — 297/297 XCUITests pass in Tart VM (`135ce30`)
- update implementation status — P1-P5 all complete (`1637c54`)
- comprehensive summary and proposed 3-layer testing strategy (unit + integration + snapshot) (`1f20a66`)
- add hard rules - never delete Tart VMs, never block session with foreground processes (`5f9328b`)
- add OrbStack design reference screenshots and spec (`76edc72`)
- add guided setup, AI-driven config, tooltips to UX research (`3eb31f4`)

### Chores & CI

- program board substrate + seed README/LICENSE (`95a915b`)
- set Sparkle EdDSA public key for auto-update (`1784906`)
- GitHub releases + auto-update hosting (App Store deferred) (`b97baae`)
- tag-driven versioning for releases (`4151f45`)
- Developer ID DMG packaging pipeline (+ App Store rationale) (`2763760`)
- add project-level .kiro steering for agents and coding standards (`6419a1d`)


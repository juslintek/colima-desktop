# Program Board — INTENT LEDGER (append-only)

> Protocol: BEFORE acting, append an entry with `intent`, `plan`, `files-to-touch`.
> AFTER acting, append an `outcome` + any `contract-impact`. Never rewrite prior entries.

---

### 2026-07-13T23:18Z · orchestrator · M0.1
- **intent:** Stand up the coordination substrate + seed OSS docs so parallel agents can start conflict-free.
- **plan:** Create `.kiro/board/{PLAN,INTENT_LEDGER,CONTRACT,OWNERSHIP,STATUS,DECISIONS}.md`; seed `README.md`, `LICENSE`.
- **files-to-touch:** `.kiro/board/*`, `README.md`, `LICENSE`.
- **outcome:** DONE. Created `.kiro/board/{PLAN,INTENT_LEDGER,CONTRACT,OWNERSHIP,STATUS,DECISIONS}.md`, seeded `README.md` + MIT `LICENSE`. CONTRACT v1 drafted from existing `proto/colima_ui.proto` (comprehensive: lifecycle/ssh/profiles/config/k8s/AI/runtime/monitoring). Board ready for parallel agents.
- **contract-impact:** none (proto unchanged; freeze deferred to M0.4).

---

### 2026-07-13T23:20Z · swiftui-dev · M0.2
- **intent:** Fix the Xcode-26 test-runner hang by extracting `ColimaDesktopKit` framework so logic tests link the module instead of hosting the `@main` app.
- **plan:** Add framework target in `project.yml`; move App/Models/Services/Views into the framework (app target becomes a thin `@main` shell + `main.swift`); unit/integration tests depend on the framework with `@testable import ColimaDesktopKit` and NO TEST_HOST; XCUITest keeps minimal host.
- **files-to-touch:** `project.yml`, `Sources/**` (module boundary only), `Tests/**` imports.
- **outcome:** DONE ✅. Created `ColimaDesktopKit` framework (App/Models/Services/Views); app target reduced to `Sources/Main/main.swift` calling `ColimaDesktopApp.main()`; `ColimaDesktopApp` made `public`. Tests link the framework (`@testable import ColimaDesktopKit`, no TEST_HOST). RESULT: Xcode-26 hang GONE — unit **53 tests/5 suites PASS (0.036s)**, integration **16 tests/4 suites PASS (1.1s)**. Build SUCCEEDED. Previously hung 704s.
- **contract-impact:** none (public surface limited to `ColimaDesktopApp`).

---

### 2026-07-14T22:45Z · architect+go-daemon-dev · M0.4
- **intent:** Freeze CONTRACT v1 to unlock parallel M1 (daemon) ∥ M2 (frontends) ∥ docs.
- **plan:** Map ServiceProvider ↔ proto; capture Docker resource ops as a frozen addendum (Part B) to be added to the proto as DockerService in M1.5 (v1-additive, non-breaking); document provider mapping (mac direct-access; win/linux/tui gRPC).
- **outcome:** DONE 🔒. CONTRACT.md frozen at v1 (Parts A colima / B docker / C install). proto ColimaService frozen; ListMachines + DockerService are v1-additive. mac keeps native direct-access provider (0-overhead); a mac gRPC client is deferred (optional, not blocking).
- **contract-impact:** CONTRACT v1 FROZEN. Frontend agents build against Parts A+B+C.

---

### 2026-07-14T22:58Z · go-daemon-dev + architect · M1.5 (increment 1)
- **intent:** Make the daemon a real gRPC server (was a compile-only hand-stub) and author the parity matrix.
- **plan:** Add ListMachines to proto; install protoc-gen-go/-go-grpc; generate real pb.go+grpc.pb.go; delete hand stub; rewire server.go to generated registrar; bufconn integration tests; write docs/parity-matrix.md.
- **outcome:** DONE (increment 1). Real gRPC codegen in daemon/proto/*.pb.go; server.go uses pb.RegisterColimaServiceServer; KubeExec→KubernetesExec; ListMachines handler added. `go build` green; bufconn tests PASS (Version/Status/ListMachines round-trip over the wire). parity-matrix.md authored (8 sections A–H).
- **contract-impact:** ListMachines added to proto (v1-additive, matches CONTRACT). DockerService (Part B) + remote-SSH + WSL2 providers + model/config RPC handlers = M1.5 increment 2 (next).

---

### 2026-07-14T23:50Z · go-daemon-dev · M1.5 (increment 2)
- **intent:** Add DockerService (CONTRACT Part B) + local/remote-SSH/WSL2 providers to the daemon.
- **plan:** Extend proto with DockerService (JSON-passthrough) + messages; regenerate; write internal/docker client (HTTP over unix socket) + transport selection (local unix / remote-SSH via x/crypto/ssh+agent / WSL2 npipe via winio on Windows); implement all handlers; register; bufconn tests; windows cross-compile check.
- **outcome:** DONE. DockerService serves 31 RPCs (containers/images/volumes/networks CRUD + prune + inspect + logs/top/stats/changes + StreamEvents/Logs/Stats). Providers: local (real), remote-SSH (x/crypto/ssh + agent auth, InsecureIgnoreHostKey), WSL2 (windows-only winio npipe; !windows returns clear error). `go build` + `GOOS=windows go build` both green. bufconn tests: ListContainers + ContainerAction round-trip PASS.
- **contract-impact:** DockerService added to proto/colima_ui.proto — fulfills CONTRACT v1 Part B (v1-additive, ColimaService unchanged). Residual thin ColimaService handlers (profiles/config/template/model/runtime) still return generated Unimplemented defaults — tracked as M1.5 follow-up (low-risk CLI wrappers).

---

### 2026-07-15T00:02Z · tui-dev · M2.8 (increment 1)
- **intent:** Stand up the TUI (Bubble Tea, Go) reusing the daemon's gRPC client against the frozen CONTRACT.
- **plan:** Create `tui/` Go module (replace → ../daemon for proto); a client wrapper over ColimaService+DockerService; a Bubble Tea app with tabbed views (Dashboard/Containers/Images/Volumes/Networks/Profiles) reading live daemon data. Build must be green; teatest later.
- **files-to-touch:** `tui/**` (disjoint; owned by tui-dev).
- **outcome:** (pending)

- **outcome (M2.8 inc.1):** DONE. tui/ Go module builds+vets clean. gRPC client wrapper over ColimaService+DockerService (Dial unix socket). Bubble Tea tabbed UI: Dashboard/Containers/Images/Volumes/Networks/Profiles/Machines, live daemon data, ←/→/1-7 nav, r refresh, q quit. Both daemon + tui binaries compile. Next (inc.2): wire remaining Docker surfaces + teatest golden tests.

---

### 2026-07-15T00:20Z · go-daemon-dev + tui-dev · M1.5-residual + M2.8 inc.2
- **outcome:** DONE. (1) daemon ColimaService residual handlers implemented as colima CLI wrappers: CreateProfile, DeleteProfile, CloneProfile, SwitchRuntime, UpdateRuntime, ModelSetup(stream), ModelRun(stream), ModelServe, ModelStop. GetConfig/SetConfig/GetTemplate/SetTemplate remain Unimplemented (config proto↔yaml marshaling; documented follow-up). build+tests+win-cross all green. (2) TUI Model refactored to a DataSource interface; 6 unit tests (view renders all tabs, tab-nav wraps, number-key select, quit, bodyMsg render, profiles loader) PASS.
- **contract-impact:** none (handlers fill existing frozen RPCs).

---

### 2026-07-15T00:35Z · windows-native-dev + linux-native-dev + devops · M2.6 + M2.7 (scaffold)
- **outcome:** Windows WinUI 3 scaffold (windows/: csproj with WindowsAppSDK+grpc-dotnet+Grpc.Tools, DaemonClient.cs, App, README) and Linux GTK4 scaffold (linux/: Cargo.toml gtk4-rs+tonic, build.rs proto codegen, client.rs, main.rs with 13 surfaces, README). Proto copied into each. CI workflow .github/workflows/frontends.yml builds daemon+tui (mac/linux/win), windows-winui (windows-latest), linux-gtk4 (ubuntu-latest), macos-kit tests (macos-latest).
- **honesty:** windows/ and linux/ CANNOT build on this macOS host — they are verified by the native CI runners (integration gate honored off-host). They are canonical scaffolds (gRPC client + surface skeleton + build docs), not yet full-surface implementations.
- **contract-impact:** none (clients consume frozen CONTRACT v1).

---

### 2026-07-15T08:05Z · devops + docs · release + pages pipelines
- **outcome:** DONE. (1) scripts/changelog.sh — conventional-commits → Keep-a-Changelog markdown; generated CHANGELOG.md (122 lines). (2) release.yml enhanced: generates tag changelog as release notes (--notes-file), publishes DMG **and** a zipped precompiled .app; DMG/notarize/appcast steps already present. (3) .github/workflows/pages.yml — deploys site/ to GitHub Pages (auto-enable). (4) site/index.html — landing page (hero, features, platform matrix, install, live changelog fetched from raw CHANGELOG.md). README links website + changelog.
- **note:** Pages URL https://juslintek.github.io/colima-desktop/ goes live after the pages workflow runs on push. Release assets build when a vX.Y.Z tag is pushed.

Read /Volumes/Projects/colima-desktop/Sources/docs/FRESH_SESSION_CONTEXT.md and /Volumes/Projects/colima-desktop/Sources/docs/BACKEND_INTEGRATION_CHECKLIST.md

ralph: Implement full Colima backend integration with 100% test coverage. Work through all 78 checklist items until every one is [x].

Order of operations:
1. SSH into host, run `brew install colima docker` (CLI only — NEVER Docker Desktop), then `colima start --vm-type vz --mount-type virtiofs` in background. Wait for socket at ~/.colima/default/docker.sock.
2. Refactor AppState: replace all 45 `if useMocks` branches with a MockServiceProvider implementing ServiceProvider protocol. AppState should never check useMocks — it just calls services.method(). Init becomes AppState(services:).
3. Fix DaemonClient: remove Go daemon dependency, fall back to direct `colima` CLI via Process(). All methods must work without the Go binary.
4. Write Tests/Unit/RealBackendTests.swift — tests using RealServiceProvider against live Docker socket. Cover containers, images, volumes, networks, profiles, VM lifecycle.
5. Run tests in VM via `ssh host`, fix failures, repeat until all pass.
6. Update BACKEND_INTEGRATION_CHECKLIST.md marking [x] as each item is verified.

Critical rules:
- Colima IS the Docker runtime. NEVER install Docker Desktop.
- `docker` = CLI client that talks to Colima's socket. Install via `brew install docker`.
- Background long processes: `command > /tmp/log 2>&1 &`
- Build: `xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet`
- Test: `ssh host "cd '/Volumes/My Shared Files/project' && xcodebuild test -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath /tmp/DD -only-testing:ColimaDesktopUnitTests"`
- Module: `@testable import ColimaDesktop`
- NOT DONE until all 78 items are checked.

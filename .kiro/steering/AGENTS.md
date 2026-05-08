# ColimaUI Project Agents

## Project Context
- **App**: ColimaUI — native macOS GUI for Colima container runtime
- **Stack**: SwiftUI + AppKit, Go daemon, gRPC, Docker API over Unix socket
- **Working dir**: /Volumes/Projects/colima-ui
- **Build**: `xcodegen generate && xcodebuild build -scheme ColimaUI -destination 'platform=macOS' -quiet`
- **Tests**: XCUITests in Tart VM (never on host desktop)
- **Repo**: github.com/juslintek/colima-ui (private)
- **Password for sudo**: `liepos10`

## Agent Roles

### lead (Curator/Observer)
- Monitors subagent progress
- Checks Tart VM status periodically
- Reports results to user
- Never writes code directly — delegates everything
- Kills stuck processes after timeout

### swiftui-dev (Implementation)
- Writes SwiftUI views matching OrbStack design reference
- Reads `ColimaUI/docs/ORBSTACK_DESIGN_REFERENCE.md` before any view work
- Must verify build compiles (0 errors) before committing
- Uses mock data from `ColimaUI/Models/MockData.swift`

### test-engineer (Testing)
- Manages Tart VM lifecycle (clone → run → test → delete)
- Fixes XCUITest failures
- Pattern: test element existence, NOT toast behavior (toasts unreliable in XCUITest)
- VNC monitoring: `tart run <vm> --vnc` exposes VNC on port 5900

### go-backend (Daemon)
- Go gRPC daemon in `daemon/`
- Wraps Colima's `app.App` for VM lifecycle
- Docker API proxy for container operations
- Build: `cd daemon && go build -o ../build/colima-daemon ./cmd`

## Tart VM Testing Protocol

```bash
# 1. Clone fresh VM (instant)
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest test-vm

# 2. Run with VNC + directory mount
tart run test-vm --vnc --dir="project:/Volumes/Projects/colima-ui"
# VNC available at vnc://192.168.64.X:5900 (get IP with `tart ip test-vm`)

# 3. SSH in and run tests
ssh admin@$(tart ip test-vm)  # password: admin
cd /Volumes/My\ Shared\ Files/project
./scripts/run_ui_tests.sh

# 4. Cleanup
tart stop test-vm && tart delete test-vm
```

## Key Files
- `ColimaUI/docs/ORBSTACK_DESIGN_REFERENCE.md` — exact UI spec
- `ColimaUI/App/AppState.swift` — all state + actions
- `ColimaUI/Models/MockData.swift` — test fixtures
- `project.yml` — XcodeGen spec (regenerate with `xcodegen generate`)
- `Makefile` — build/test commands

## Rules
- NEVER run XCUITests on host desktop (steals focus, unreliable)
- ALWAYS use Tart VM for E2E tests
- Build must compile with 0 errors before any commit
- Commit messages: conventional commits format
- All views must have accessibilityIdentifier for testing

## HARD RULES — DO NOT VIOLATE

### Tart VM Management
- **NEVER delete a cloned Tart VM image** — only `tart stop` then `tart run` to restart
- **NEVER re-clone** unless the VM is corrupted — use `tart stop` + `tart run` to restart existing
- **NEVER re-pull** the OCI base image — it's already cached locally

### Long-Running Processes
- **NEVER run long processes in foreground** — they block the chat session
- **ALWAYS background** with `&` and track via PID/log file:
  ```bash
  command > /tmp/task.log 2>&1 &
  echo $! > /tmp/task.pid
  ```
- **ALWAYS return immediately** after launching — check status separately
- This applies to: `tart run`, `tart clone`, `xcodebuild test`, any download, any build >30s
- Use subagents for tasks that need monitoring loops

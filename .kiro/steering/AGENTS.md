# Colima Desktop Project Agents

## Project Context
- **App**: Colima Desktop — native macOS GUI for Colima container runtime
- **Stack**: SwiftUI + AppKit, Go daemon, gRPC, Docker API over Unix socket
- **Working dir**: /Volumes/Projects/colima-desktop
- **Build**: `xcodegen generate && xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -quiet`
- **Tests**: 3-layer pyramid (unit/integration/snapshot) + XCUITest E2E — all on host
- **Repo**: github.com/juslintek/colima-desktop (private)
- **Password for sudo**: `liepos10`

## Agent Roles

### swiftui-dev (Implementation)
- Writes SwiftUI views matching OrbStack design reference
- Reads `Sources/docs/ORBSTACK_DESIGN_REFERENCE.md` before any view work
- Must verify build compiles (0 errors) before committing
- Uses mock data from `Sources/Models/MockData.swift`

### test-engineer (Testing)
- Runs all tests on host directly
- Unit/integration tests: fast, deterministic
- XCUITest: runs on host (`make test-ui`)
- Pattern: test element existence, NOT toast behavior

### go-backend (Daemon)
- Go gRPC daemon in `daemon/`
- Wraps Colima's `app.App` for VM lifecycle
- Docker API proxy for container operations
- Build: `cd daemon && go build -o ../build/colima-daemon ./cmd`

## Testing Strategy

### 3-Layer Pyramid
```
┌─────────────────────────────────────────┐
│   Snapshot Tests (visual regression)     │  ~3 sec
├─────────────────────────────────────────┤
│   Integration Tests (ViewInspector)      │  ~10 sec
├─────────────────────────────────────────┤
│   Unit Tests (Swift Testing @Test)       │  ~1 sec
└─────────────────────────────────────────┘
```

**Run on host:**
```bash
make test-unit          # Swift Testing — AppState, validation, models
make test-integration   # ViewInspector — view logic without rendering
make test-snapshots     # swift-snapshot-testing — visual regression
make test-ui            # XCUITest — full E2E with app running
make test               # unit + integration (default)
make test-real-e2e      # Real-backend tests (requires colima profile desktop-e2e)
```

### Test Targets
| Target | Framework | What it tests |
|--------|-----------|---------------|
| `ColimaDesktopUnitTests` | Swift Testing | AppState, validation, models, services |
| `ColimaDesktopIntegrationTests` | ViewInspector | View rendering, bindings, navigation |
| `ColimaDesktopSnapshotTests` | swift-snapshot-testing | Visual regression (light/dark) |
| `ColimaDesktopUITests` | XCUITest | Full E2E with app running |

## Key Files
- `Sources/docs/ORBSTACK_DESIGN_REFERENCE.md` — exact UI spec
- `Sources/docs/TESTING_STRATEGY.md` — full testing rationale
- `Sources/App/AppState.swift` — all state + actions
- `Sources/Models/MockData.swift` — test fixtures
- `project.yml` — XcodeGen spec (regenerate with `xcodegen generate`)
- `Package.swift` — SPM deps (ViewInspector, swift-snapshot-testing)
- `Makefile` — build/test commands

## Rules
- Build must compile with 0 errors before any commit
- Commit messages: conventional commits format
- All views must have accessibilityIdentifier for testing
- All tests run on host — no VMs

## Stall Prevention Rules

**CRITICAL: Never let a session go idle. If a tool call is cancelled or fails, immediately continue with the next action.**

### When a tool call is cancelled:
1. **Do NOT wait** — treat it as a failed operation and move on
2. **Log what happened** — tell the user "Tool X was cancelled, continuing with Y"
3. **Try an alternative** — if one approach fails, switch to another immediately

### When a command hangs (>30s):
1. Background it: `command > /tmp/log 2>&1 &`
2. Continue with other work
3. Check back later with `tail /tmp/log`

### When waiting for external processes:
1. **Never block on a single operation** — always have a fallback plan
2. **If colima start hangs** — kill it, check logs, try different flags

### Between tool calls:
1. **Always have a next action ready** — never end a response without completing the task or stating what's next
2. **If stuck on one item** — skip it, work on the next item, come back later
3. **Batch independent operations** — don't serialize things that can run in parallel

### Long-Running Processes
- **NEVER run long processes in foreground** — they block the chat session
- **ALWAYS background** with `&` and track via PID/log file:
  ```bash
  command > /tmp/task.log 2>&1 &
  echo $! > /tmp/task.pid
  ```
- **ALWAYS return immediately** after launching — check status separately
- This applies to: `xcodebuild test`, any download, any build >30s

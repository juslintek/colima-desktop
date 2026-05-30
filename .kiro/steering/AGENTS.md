# Colima Desktop Project Agents

## Project Context
- **App**: Colima Desktop — native macOS GUI for Colima container runtime
- **Stack**: SwiftUI + AppKit, Go daemon, gRPC, Docker API over Unix socket
- **Working dir**: /Volumes/Projects/colima-desktop
- **Build**: `xcodegen generate && xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -quiet`
- **Tests**: 3-layer pyramid (unit/integration/snapshot) + smoke E2E in Tart VM
- **Repo**: github.com/juslintek/colima-desktop (private)
- **Password for sudo**: `liepos10`

## VM Infrastructure

### Tart VM (macOS — primary test runner)

**Persistent VM:** `colima-test-vnc` (macOS Tahoe + Xcode 26.4)

**SSH access (passwordless via key):**
```bash
ssh tart-vm                    # uses ~/.ssh/config entry
ssh tart-vm "command"          # run command remotely
```

**SSH config entry** (`~/.ssh/config`):
```
Host tart-vm
    HostName 192.168.64.8
    User admin
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
```

**Start VM (if stopped):**
```bash
tart run colima-test-vnc --dir=project:/Volumes/Projects/colima-desktop --vnc > /tmp/tart-run.log 2>&1 &
echo $! > /tmp/tart-run.pid
```

**Project path inside VM:** `/Volumes/My Shared Files/project/`

**Run tests in VM:**
```bash
./scripts/run_vm_tests.sh                              # unit tests (default)
./scripts/run_vm_tests.sh ColimaDesktopIntegrationTests # integration
./scripts/run_vm_tests.sh ColimaDesktopUITests          # E2E smoke
```

### UTM VM (Windows/Linux — future use)

For Windows ARM64 or Linux VMs, use UTM with `utmctl`:
```bash
utmctl list                          # list VMs
utmctl start "VM Name"               # start
utmctl exec "VM Name" --cmd "cmd"    # run command in guest
utmctl ip-address "VM Name"          # get IP
```

### VM Setup Rules

**When setting up a new VM for SSH:**
1. Start the VM and get its IP: `tart ip <vm-name>`
2. Copy SSH key: `cat ~/.ssh/id_ed25519.pub | sshpass -p <password> ssh user@<ip> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"`
3. Add entry to `~/.ssh/config` with `StrictHostKeyChecking no` and `UserKnownHostsFile /dev/null`
4. Verify: `ssh <host-alias> "echo OK"`
5. Remove sshpass usage — always use key-based auth after setup

## Agent Roles

### lead (Curator/Observer)
- Monitors subagent progress
- Checks Tart VM status periodically
- Reports results to user
- Never writes code directly — delegates everything
- Kills stuck processes after timeout

### swiftui-dev (Implementation)
- Writes SwiftUI views matching OrbStack design reference
- Reads `Sources/docs/ORBSTACK_DESIGN_REFERENCE.md` before any view work
- Must verify build compiles (0 errors) before committing
- Uses mock data from `Sources/Models/MockData.swift`

### test-engineer (Testing)
- Runs tests via `ssh tart-vm` (never on host)
- Unit/integration tests: fast, deterministic, no GUI needed
- E2E smoke tests: only in Tart VM
- Pattern: test element existence, NOT toast behavior

### go-backend (Daemon)
- Go gRPC daemon in `daemon/`
- Wraps Colima's `app.App` for VM lifecycle
- Docker API proxy for container operations
- Build: `cd daemon && go build -o ../build/colima-daemon ./cmd`

## Testing Strategy

### 3-Layer Pyramid (fast, deterministic)
```
┌─────────────────────────────────────────┐
│   Snapshot Tests (visual regression)     │  ~3 sec
├─────────────────────────────────────────┤
│   Integration Tests (ViewInspector)      │  ~10 sec
├─────────────────────────────────────────┤
│   Unit Tests (Swift Testing @Test)       │  ~1 sec
└─────────────────────────────────────────┘
```

**Run locally or in VM:**
```bash
make test-unit          # Swift Testing — AppState, validation, models
make test-integration   # ViewInspector — view logic without rendering
make test-snapshots     # swift-snapshot-testing — visual regression
make test               # unit + integration (default)
```

**E2E smoke (VM only):**
```bash
make test-smoke         # XCUITests in Tart VM
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
- `scripts/run_vm_tests.sh` — run tests inside Tart VM

## Rules
- NEVER run XCUITests on host desktop (steals focus, unreliable)
- ALWAYS use `ssh tart-vm` for VM access (never sshpass)
- ALWAYS use key-based SSH auth for VMs (set up authorized_keys)
- Build must compile with 0 errors before any commit
- Commit messages: conventional commits format
- All views must have accessibilityIdentifier for testing
- Unit/integration tests CAN run on host (no GUI needed)

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
2. **Set explicit timeouts** — `ssh -o ConnectTimeout=5`, `curl --max-time 10`
3. **If colima start hangs** — kill it, check logs, try different flags

### Between tool calls:
1. **Always have a next action ready** — never end a response without either completing the task or stating what's next
2. **If stuck on one item** — skip it, work on the next item, come back later
3. **Batch independent operations** — don't serialize things that can run in parallel

### Session continuity:
1. **After any interruption** — re-read the task list, check what's done, continue from where you left off
2. **Before long operations** — tell the user what you're about to do and what the fallback is
3. **If a task has failed twice** — stop, explain the blocker, ask the user for guidance instead of retrying forever

## HARD RULES — DO NOT VIOLATE

### Tart VM Management
- **NEVER delete a cloned Tart VM image** — only `tart stop` then `tart run` to restart
- **NEVER re-clone** unless the VM is corrupted — use `tart stop` + `tart run` to restart existing
- **NEVER re-pull** the OCI base image — it's already cached locally

### SSH
- **NEVER use sshpass** in scripts — always key-based auth via ~/.ssh/config
- **NEVER hardcode IPs** in scripts — use SSH host aliases from config
- **If SSH hangs** — VM likely needs restart: `tart stop <vm> && tart run <vm> ... &`

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

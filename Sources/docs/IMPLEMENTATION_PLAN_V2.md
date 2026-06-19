# ColimaUI — Implementation Plan v2

## Testing Strategy: host machines (Isolated, No Desktop Interference)

### Why Tart
- Runs macOS VMs using Apple Virtualization.framework (native speed)
- Complete isolation — tests run inside a VM, never touch host desktop
- Instant cloning — fresh VM per test run in seconds
- `--dir` flag mounts source code via virtio-fs
- Handles networking, SSH, port management automatically

### Local Testing (Makefile)

```makefile
VM_NAME = colima-test-$(shell date +%s)
BASE_IMAGE = ghcr.io/cirruslabs/macos-sequoia-base:latest

test:
	tart clone $(BASE_IMAGE) $(VM_NAME)
	tart run $(VM_NAME) --dir=.:/project "/project/scripts/run_tests.sh"
	tart delete $(VM_NAME)

test-quick:
	# Reuse existing VM for faster iteration
	tart run colima-test-persistent --dir=.:/project "/project/scripts/run_tests.sh"
```

### Test Runner Script (`scripts/run_tests.sh`)

```bash
#!/bin/bash
set -e
cd /project

# Install deps (cached in VM image for speed)
which xcodegen || brew install xcodegen
which colima || brew install colima docker

# Start Colima inside the VM
colima start --vm-type vz --cpus 4 --memory 8

# Create test fixtures
docker pull nginx:latest && docker run -d --name web-server nginx:latest
docker pull redis:7-alpine && docker create --name redis-cache redis:7-alpine
docker pull postgres:16 && docker run -d --name postgres-db postgres:16
docker run -d --name api-service node:20-slim sleep infinity
docker run -d --name worker python:3.12 sleep infinity && docker pause worker

# Generate project and run tests
xcodegen generate
xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
  -only-testing:ColimaUIUITests \
  -resultBundlePath /project/TestResults.xcresult

echo "EXIT: $?"
```

### GitHub Actions (Self-Hosted Apple Silicon Runner)

```yaml
name: ColimaUI Tests (host machine)
on: [push]
jobs:
  test:
    runs-on: self-hosted-mac  # Apple Silicon Mac
    steps:
      - uses: actions/checkout@v4
      - name: Run Tests in Isolated VM
        run: |
          VM="runner-${{ github.run_id }}"
          tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest $VM
          tart run $VM --dir=.:/project "/project/scripts/run_tests.sh"
          tart delete $VM
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: TestResults.xcresult
```

### Pre-baked VM Image (for speed)

Build a custom Tart image with all deps pre-installed:

```bash
# One-time: create optimized test image
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest colima-test-base
tart run colima-test-base  # SSH in and install:
# brew install xcodegen colima docker
# colima start && colima stop  # pre-download VM image
# tart stop colima-test-base

# Push to registry for CI
tart push colima-test-base ghcr.io/juslintek/colima-test-base:latest
```

---

## Backend Implementation Notes

### Go Daemon (`daemon/`)

**Architecture:**
```
daemon/
├── cmd/main.go              # Entry point, Unix socket listener
├── internal/
│   ├── server/server.go     # gRPC handlers wrapping Colima
│   ├── monitor/monitor.go   # VM stats polling (SSH to /proc)
│   └── events/events.go     # Docker event stream forwarding
├── proto/service.go          # Generated proto stubs
└── go.mod
```

**Key implementation details:**
- `app.New()` creates Colima app instance — call once, reuse
- `config.SetProfile(name)` switches active profile (global state — serialize access)
- Long-running ops (Start/Restart) use streaming RPCs for progress
- VM stats: poll via `colima ssh -- cat /proc/stat /proc/meminfo` every 2-5s
- Process list: `colima ssh -- ps aux --no-headers` parsed into structs
- Kill process: `colima ssh -- kill -<signal> <pid>`

**Concurrency model:**
- Single gRPC server, multiple concurrent clients
- Mutex around profile switching (Colima's global state)
- Stats streaming uses dedicated goroutine per subscriber
- Docker events forwarded from `docker events --format json`

### Swift DockerClient (`ColimaUI/Services/DockerClient.swift`)

**Key implementation details:**
- Unix socket via raw `socket()` + `connect()` (not URLSession — more reliable)
- HTTP/1.1 with `Connection: close` for simplicity
- Chunked transfer encoding parsing for streaming endpoints (logs, stats, events)
- Container stats: `GET /containers/{id}/stats?stream=true` — parse JSON lines
- Logs: `GET /containers/{id}/logs?follow=true&stdout=true&stderr=true` — multiplexed stream
- Events: `GET /events?filters={"type":["container"]}` — JSON stream for real-time UI updates

**Error handling:**
- Socket not found → "Colima is not running" error state
- 404 → resource not found (container deleted externally)
- 409 → conflict (container already started/stopped)
- Connection reset → VM crashed, trigger reconnect

### Swift DaemonClient (`ColimaUI/Services/DaemonClient.swift`)

**Current: CLI bridge (Phase 1)**
- Executes `colima` commands via `Process`
- Parses stdout (JSON where available, text otherwise)
- Simple, works immediately, no proto compilation needed

**Future: gRPC client (Phase 2)**
- Use `grpc-swift` (NIO-based) with Unix socket transport
- Streaming RPCs for Start progress, VM stats
- Protobuf for type-safe serialization
- Requires `protoc` + `grpc-swift` plugin in build pipeline

### AppState Dual-Mode (`ColimaUI/App/AppState.swift`)

```swift
class AppState: ObservableObject {
    private let useMocks: Bool
    private let services: ServiceProvider?
    
    // Every action method:
    func startContainer(name: String) {
        guard requiresVM("Start") else { return }
        if useMocks {
            // Instant mock mutation for UI tests
            containers[i].state = "running"
            showToast("Container '\(name)' started")
        } else {
            // Real async operation
            Task { @MainActor in
                try await services!.startContainer(id: name)
                await refreshContainers()
                showToast("Container '\(name)' started")
            }
        }
    }
}
```

---

## Implementation Phases

### Phase 1: Production-Quality Mocked GUI ← CURRENT
- [x] Three-column OrbStack-style layout
- [x] All views with realistic mock data
- [x] All interactions mocked with state mutations
- [x] 280 E2E tests with 100% accessibility coverage
- [x] Validation on all inputs
- [x] Sheets for inspect/logs/terminal/stats
- [ ] **TODO: Update views to match latest OrbStack screenshots**
- [ ] **TODO: Add tooltips to all settings**
- [ ] **TODO: Add guided setup wizard**
- [ ] **TODO: Activity Monitor with tree view + sparklines**
- [ ] **TODO: Cmd+K global search**

### Phase 2: Real Backend Integration
- [x] Go daemon (compiles, wraps Colima)
- [x] Swift DockerClient (HTTP over Unix socket)
- [x] Swift DaemonClient (CLI bridge)
- [x] ServiceProvider protocol + RealServiceProvider
- [x] AppState dual-mode (useMocks flag)
- [ ] **TODO: Wire Docker events for real-time UI updates**
- [ ] **TODO: Streaming logs/stats**
- [ ] **TODO: Profile switching with full refresh**

### Phase 3: Testing with Tart
- [ ] Install Tart locally (`brew install cirruslabs/cli/tart`)
- [ ] Create pre-baked test VM image
- [ ] Write `scripts/run_tests.sh`
- [ ] Update Makefile with `make test` target
- [ ] Set up self-hosted GitHub Actions runner
- [ ] Get all 280 tests passing on host

### Phase 4: VM Management (Machines)
- [ ] Linux VMs via Lima (already in Colima)
- [ ] macOS VMs via Virtualization.framework
- [ ] Windows VMs via QEMU + HVF
- [ ] Unified "Machines" sidebar section

### Phase 5: Intelligence & Polish
- [ ] Hardware detection + smart defaults
- [ ] First-run guided wizard
- [ ] AI-driven setup (rule-based + optional LLM)
- [ ] Contextual tooltips on all settings
- [ ] Inline recommendations (💡 / ⚠️)
- [ ] Battery-aware mode
- [ ] Cmd+K command palette
- [ ] Sparkline charts in Activity Monitor
- [ ] Compose stack grouping
- [ ] "Copy as CLI command" on every action

---

## File Structure (Current)

```
colima-ui/
├── .github/workflows/test.yml    # CI (GitHub Actions)
├── Makefile                       # Build + test commands
├── project.yml                    # XcodeGen spec
├── proto/colima_ui.proto          # gRPC service definition
├── daemon/                        # Go gRPC daemon
│   ├── cmd/main.go
│   ├── internal/server/server.go
│   ├── proto/service.go
│   └── go.mod
├── ColimaUI/                      # Swift app
│   ├── App/
│   │   ├── ColimaUIApp.swift
│   │   ├── AppDelegate.swift
│   │   └── AppState.swift         # 1101 lines, dual-mode
│   ├── Models/
│   │   ├── MockData.swift
│   │   ├── MockDetailData.swift
│   │   └── MockK8sData.swift
│   ├── Services/
│   │   ├── DockerClient.swift     # HTTP over Unix socket
│   │   ├── DaemonClient.swift     # Colima CLI bridge
│   │   └── ServiceProvider.swift  # Protocol + Real impl
│   ├── Views/                     # All SwiftUI views
│   └── docs/
│       ├── FEATURE_CHECKLIST.md
│       ├── APPLICATION_BEHAVIOR.md
│       ├── UX_RESEARCH.md
│       ├── UX_DX_ANALYSIS.md
│       └── INTEGRATION_TESTS.md
├── ColimaUITests/                 # Unit tests
├── ColimaUIUITests/               # 280 E2E XCUITests
├── scripts/
│   └── run_tests.sh              # host machine test runner
└── vendor/                        # Reference docs
    ├── colima/                    # Colima source
    ├── colima-docs/               # Scraped docs
    └── docker-api/                # Swagger spec
```

---

## Next Immediate Steps

1. **Install Tart** and create test VM image
2. **Run tests on host** — fix any remaining failures
3. **Update GUI** to match all OrbStack screenshots (tooltips, activity monitor, guided setup)
4. **Push and verify CI** passes on host

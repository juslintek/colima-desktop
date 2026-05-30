# Colima Desktop — Implementation Status & Plan

## What's DONE ✅

### 1. Architecture Refactor (Complete)
- **AppState** uses `ServiceProvider` protocol uniformly — zero `if useMocks` branches
- **MockServiceProvider** implements full protocol for UI testing (`--ui-testing` flag)
- **RealServiceProvider** wraps DockerClient + DaemonClient
- **DaemonClient** works via direct CLI (no Go daemon needed), resolves PATH to find colima/limactl
- **DockerClient** uses raw Unix sockets (no URLSession/URLProtocol) for reliable HTTP

### 2. Docker API Integration (Complete)
All Docker operations work against live socket at `~/.colima/default/docker.sock`:
- Containers: list, create, start, stop, kill, restart, pause, unpause, remove, rename, logs, inspect, top, stats, changes, prune
- Images: list, pull, remove, inspect, history, tag, push, search, prune
- Volumes: list, create, remove, inspect, prune
- Networks: list, create, remove, inspect, connect, disconnect, prune
- Streaming: events, logs, stats (real-time via raw sockets)

### 3. VM Lifecycle (Complete)
- start/stop/restart/delete via `colima` CLI
- Status with JSON parsing (cpu, memory, disk, runtime, arch)
- SSH config retrieval
- Profile listing
- Version detection

### 4. Dashboard (Partial)
- VM status indicator (running/stopped) — ✅ real
- Resource display (CPU/Memory/Disk/Runtime/Version) — ✅ now reads from AppState.vmCPU etc.
- Template editor — ❌ hardcoded content, doesn't read real file

### 5. Tests (Complete)
- 58 unit tests pass (14 AppState/MockData + 44 real backend tests)
- Tests run on host against live Colima

### 6. Colima Skill (Complete)
- `~/.kiro/skills/colima/SKILL.md` — 371 lines, verified against source code

### 7. Configuration View (Complete)
- Reads/writes `~/.colima/<profile>/colima.yaml` directly (NEVER uses `colima template`)
- `ColimaConfig` struct with full YAML parsing/serialization
- Loads real config on `.onAppear`, populates all `@State` vars
- Save writes YAML + restarts VM to apply changes
- Reset to defaults supported

### 8. Runtime Controls (Complete)
- Command palette executes real commands via `Process()`
- Quick commands (docker, nerdctl, incus) run against live system
- Command history preserved

### 9. Monitoring View (Complete)
- Container stats loaded from real Docker API (`/containers/{id}/stats`)
- CPU/memory sparklines populated from live data
- Process tree shows real container resource usage

### 10. Sheet Views (Complete)
- StatsSheetView: real stats + top from Docker API
- ChangesSheetView: real container filesystem changes
- HistorySheetView: real image layer history
- SearchSheetView: real Docker Hub search
- CommandRunnerView: real command execution
- MockLogsView/MockTerminalView: real execution

### 11. Kubernetes View (Complete)
- Loads pods/services/deployments/nodes/events via `kubectl get -o json`
- Detail views load individual resources
- Only active when k8s is enabled

---

## What's LEFT TO DO ❌

### Priority 1: Configuration View — ✅ DONE

### Priority 2: Runtime Controls — ✅ DONE

### Priority 3: Monitoring View — ✅ DONE

### Priority 4: Sheet Views — ✅ DONE

### Priority 5: Kubernetes View — ✅ DONE

### Priority 6: AI Workloads View (Low — requires krunkit)
**File:** `Sources/Views/AI/AIWorkloadsView.swift`

**Problem:** Models from `MockK8sData.aiModels`.

**Fix:** Add `colima model list` integration. Only works with krunkit VM type.

### Priority 7: Container Search (Low)
**File:** `Sources/Views/Containers/ContainersView.swift` line 278

**Problem:** `MockDetailData.searchResults(term:)` — hardcoded search results.

**Fix:** Already have `services.searchImages(term:)` which calls Docker Hub API. Wire it up.

---

## Key Technical Constraints (from colima skill)

1. **NEVER run `colima template`, `colima start --edit`, or bare `colima ssh`** — they open editors/shells and HANG
2. **Read/write YAML directly** at `~/.colima/<profile>/colima.yaml`
3. **Immutable after creation:** arch, runtime, vmType, mountType — disable in UI when VM exists
4. **Disk can only increase** — validate in UI
5. **Memory is float32** in YAML (can be 2.5 GiB)
6. **`colima start` when already running** just warns — use `colima restart` to apply changes
7. **JSON memory/disk are in bytes** — divide by 1024³ for GiB display
8. **Colima runs on HOST only** — Tart VM cannot do nested virtualization

---

## Recommended Session Prompt

```
ralph: Continue Colima Desktop real backend integration. Use the colima skill.

Current state: AppState refactored (no useMocks), Docker API works, 58 tests pass.

Remaining work (in priority order):
1. ConfigurationView — read/write ~/.colima/default/colima.yaml (NEVER use colima template — it opens editor). Add readConfig/writeConfig to DaemonClient. Load on .onAppear, save writes YAML + restarts.
2. RuntimeControlsView — replace MockDetailData.commandOutput with real Process() execution
3. MonitoringView — replace MockDetailData.containerStats with real Docker API stats
4. Sheet views (Stats, Changes, History, Search) — wire to real ServiceProvider data
5. KubernetesView — add kubectl JSON integration (only when k8s enabled)

Rules:
- Run on HOST machine (not Tart VM — no nested virt)
- NEVER run interactive colima commands (template, ssh without --, start --edit)
- Read/write YAML files directly for config changes
- Build: xcodegen generate && xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet
- Test: xcodebuild test -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:ColimaDesktopUnitTests
```

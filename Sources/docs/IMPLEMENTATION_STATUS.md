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

---

## What's LEFT TO DO ❌

### Priority 1: Configuration View (Critical)
**File:** `Sources/Views/Configuration/ConfigurationView.swift` (65KB, 700+ lines)

**Problem:** All settings are local `@State` with hardcoded defaults. Never reads from `~/.colima/default/colima.yaml`. Save/Load/Reset buttons call stub methods in AppState.

**Fix needed:**
1. Add `readConfig(profile:)` and `writeConfig(profile:, config:)` to ServiceProvider/DaemonClient
   - Read: `cat ~/.colima/<profile>/colima.yaml` → parse YAML → return struct
   - Write: serialize struct → write to `~/.colima/<profile>/colima.yaml`
   - **NEVER use `colima template` or `colima start --edit`** — they open editors
2. Add `@Published var colimaConfig: ColimaConfig?` to AppState
3. ConfigurationView `.onAppear` loads real config, populates all `@State` vars
4. "Save Configuration" writes back to YAML, then `colima stop && colima start` to apply
5. "Reset to Defaults" reads the template file and applies it
6. Mark immutable fields as disabled when VM exists (arch, runtime, vmType, mountType)

### Priority 2: Runtime Controls (Medium)
**File:** `Sources/Views/RuntimeControls/RuntimeControlsView.swift`

**Problem:** Command output is faked via `MockDetailData.commandOutput(tool:args:)`

**Fix:** Execute real commands via `Process()` and capture output. Add `executeCommand(tool:args:)` to ServiceProvider that runs the command and returns stdout.

### Priority 3: Monitoring View (Medium)
**File:** `Sources/Views/Monitoring/MonitoringView.swift`

**Problem:** Stats come from `MockDetailData.containerStats(name:)` — hardcoded values.

**Fix:** Use `services.containerStats(id:)` which already works via Docker API. The view needs to call AppState methods that return real data.

### Priority 4: Sheet Views (Medium)
**Files:** `Sources/Views/Components/` — StatsSheetView, ChangesSheetView, HistorySheetView, SearchSheetView

**Problem:** All use `MockDetailData.*` for their content.

**Fix:** These sheets are opened by AppState methods that already fetch real data (inspectContainer, containerLogs, etc.) and set `sheetContent`. The sheet views just need to use `appState.sheetContent` instead of calling MockDetailData directly. Some (Stats, History) need AppState methods that fetch and set the data.

### Priority 5: Kubernetes View (Low — requires k8s enabled)
**File:** `Sources/Views/Kubernetes/KubernetesView.swift`

**Problem:** All pods, services, deployments, nodes, events from `MockK8sData`.

**Fix:** Add kubectl integration to ServiceProvider:
- `kubectl get pods -o json`
- `kubectl get services -o json`
- `kubectl get deployments -o json`
- `kubectl get nodes -o json`
- `kubectl get events -o json`

Parse JSON and populate AppState. Only works when `kubernetes.enabled = true`.

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

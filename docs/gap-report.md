# CLI-Parity Gap Report

> **Generated:** 2026-07-16 (static code analysis)
> **Method:** Compared `docs/parity-matrix.md` and `.kiro/board/CONTRACT.md` against
> implemented source in `daemon/`, `tui/`, `windows/`, `linux/`, and `Sources/`.
> **Limitation:** This report is based on static analysis of the source code only.
> Per-platform UI explorers (AX tree / AT-SPI / UIA) were not executed because
> this analysis was performed in a headless CI-like environment without access to
> running GUI instances. Runtime verification should be performed in M3.9.

---

## Summary

| Frontend | CONTRACT RPCs Wired | Total Required | Coverage | Rating |
|----------|:------------------:|:--------------:|:--------:|:------:|
| **macOS (SwiftUI)** | 53 | 53 | 100% | ✅ Full |
| **Daemon (Go gRPC)** | 53 | 53 | 100% | ✅ Full |
| **TUI (Bubble Tea)** | 5 | 53 | 9% | 🔴 Scaffold |
| **Windows (WinUI 3)** | 3 | 53 | 6% | 🔴 Scaffold |
| **Linux (GTK4)** | 2 | 53 | 4% | 🔴 Scaffold |

The daemon serves the full CONTRACT surface (22 ColimaService + 31 DockerService RPCs).
macOS accesses all operations via `RealServiceProvider` → `DaemonClient` + `DockerClient`.
The TUI, Windows, and Linux frontends are functional scaffolds wiring only a handful of
read-only RPCs; they require significant development before reaching parity.

---

## Per-Frontend Analysis

### macOS (SwiftUI) — ✅ Full Coverage

The macOS frontend implements a `ServiceProvider` protocol with 80+ methods covering
every CONTRACT capability. `RealServiceProvider` delegates to `DaemonClient` (Colima
ops) and `DockerClient` (Docker API socket). Views exist for every surface:

| Category | Status | Notes |
|----------|:------:|-------|
| A. VM lifecycle (8 RPCs) | ✅ | Start/Stop/Restart/Delete/Status/Version/Update/Prune |
| B. SSH/Profiles (6 RPCs) | ✅ | SSHConfig, List/Create/Delete/Clone Profiles, ListMachines |
| C. Configuration (4 RPCs) | 🟡 | GetConfig/SetConfig wired; GetTemplate/SetTemplate not yet in UI |
| D. Kubernetes (4 RPCs) | ✅ | Start/Stop/Reset/Exec via `KubernetesView` |
| E. Docker containers (16 ops) | ✅ | Full CRUD + logs/inspect/top/stats/changes/prune |
| F. Docker images (9 ops) | ✅ | list/pull/remove/inspect/history/tag/push/search/prune |
| G. Docker volumes (5 ops) | ✅ | list/create/remove/inspect/prune |
| H. Docker networks (7 ops) | ✅ | list/create/remove/inspect/connect/disconnect/prune |
| I. Streams (3 ops) | ✅ | events/logs/stats streaming |
| J. AI models (5 RPCs) | ✅ | list/pull/run/serve/stop |
| K. Runtime/Monitoring (5 RPCs) | ✅ | SwitchRuntime/UpdateRuntime/VMStats/ProcessList/KillProcess |
| L. Turnkey/Install (2 ops) | 🟡 | `isColimaInstalled()`/`installColima()` exist; DependencyManager todo |

**Gaps on macOS:**
1. Template editing UI (GetTemplate/SetTemplate) — protocol exists, UI not wired.
2. DependencyManager (auto-update deps) — planned M4.13, not implemented.
3. `SwitchRuntime`/`UpdateRuntime` marked 🟡 in parity-matrix (partial UI).

---

### Daemon (Go gRPC) — ✅ Full Coverage

`daemon/internal/server/` implements:
- `ColimaServer` (22 RPCs): Start, Stop, Restart, Delete, Status, Version, Update,
  Prune, SSHConfig, ListProfiles, ListMachines, CreateProfile, DeleteProfile,
  CloneProfile, KubernetesStart/Stop/Reset/Exec, SwitchRuntime, UpdateRuntime,
  ModelSetup/Run/Serve/Stop, ProcessList, KillProcess, VMStats.
- `DockerServer` (31 RPCs via `docker.Client`): ListContainers, ContainerAction
  (start/stop/kill/restart/pause/unpause), CreateContainer, RenameContainer,
  ContainerLogs, InspectContainer, ContainerTop, ContainerStats, ContainerChanges,
  PruneContainers, ListImages, RemoveImage, InspectImage, ImageHistory, TagImage,
  SearchImages, PruneImages, ListVolumes, CreateVolume, RemoveVolume, InspectVolume,
  PruneVolumes, ListNetworks, CreateNetwork, RemoveNetwork, InspectNetwork,
  ConnectNetwork, DisconnectNetwork, PruneNetworks, StreamEvents, StreamLogs, StreamStats.

**Not implemented in daemon:**
1. `GetConfig` / `SetConfig` / `GetTemplate` / `SetTemplate` — stubs in proto, not in server.go.
2. `PullImage` / `PushImage` — not exposed as gRPC RPCs (client uses Docker API direct).
3. `ModelList` — noted as "pending" in parity-matrix; model listing is not a separate RPC.

---

### TUI (Bubble Tea) — 🔴 Scaffold (9% coverage)

The TUI connects to the daemon via gRPC (`internal/client/client.go`) and presents
7 tabs: Dashboard, Containers, Images, Volumes, Networks, Profiles, Machines.

**Wired RPCs (read-only):**
| RPC | Tab | Implementation |
|-----|-----|---------------|
| `Status` | Dashboard | ✅ Displays profile, state, runtime, cpu, mem |
| `ListProfiles` | Profiles | ✅ Lists profiles with status/arch/cpus |
| `ListMachines` | Machines | ✅ Lists Lima VMs |
| `ListContainers` | Containers | ✅ Via DockerService, JSON list |
| `ListImages` | Images | ✅ Via DockerService, JSON list |

**Missing (44 RPCs not wired):**
- VM lifecycle: Start, Stop, Restart, Delete, Version, Update, Prune
- SSH: SSHConfig
- Profiles: CreateProfile, DeleteProfile, CloneProfile
- Configuration: GetConfig, SetConfig, GetTemplate, SetTemplate
- Kubernetes: all 4 RPCs
- AI Models: all 5 RPCs
- Runtime/Monitoring: SwitchRuntime, UpdateRuntime, VMStats, ProcessList, KillProcess
- Docker write ops: all container actions, create, rename, logs, inspect, etc.
- Docker images: pull, remove, inspect, history, tag, push, search, prune
- Docker volumes: create, remove, inspect, prune (ListVolumes shows placeholder)
- Docker networks: all ops (tab shows placeholder)
- Streams: events, logs, stats

**UX gaps:**
- No action key-bindings (start/stop VM, manage containers)
- Volumes/Networks tabs show placeholder text, not live data
- No detail views or inspect capability
- No progress/streaming display

---

### Windows (WinUI 3) — 🔴 Scaffold (6% coverage)

The Windows frontend (`windows/`) is a .NET 8 WinUI 3 project with `DaemonClient.cs`
wrapping `ColimaService` + `DockerService` gRPC stubs.

**Wired RPCs:**
| RPC | Method | Notes |
|-----|--------|-------|
| `Status` | `StatusAsync(profile)` | ✅ |
| `ListProfiles` | `ProfilesAsync()` | ✅ |
| `ListContainers` | `ContainersAsync(profile, wsl2)` | ✅ |

**Missing (50 RPCs not wired):**
- Entire VM lifecycle (Start/Stop/Restart/Delete/Version/Update/Prune)
- SSH, Configuration, Kubernetes, AI Models, Runtime, Monitoring
- All Docker image/volume/network operations
- Streams (events/logs/stats)
- No UI views beyond `App.xaml.cs` shell

**Build note:** Requires Windows + .NET 8 SDK + Windows App SDK. Cannot be verified
on this macOS host. Code is internally consistent with proper proto reference.

---

### Linux (GTK4 / Rust) — 🔴 Scaffold (4% coverage)

The Linux frontend (`linux/`) is a Rust/GTK4 application using `tonic` for gRPC.
It defines 13 placeholder surfaces in a `Stack` widget but wires only 2 RPCs.

**Wired RPCs:**
| RPC | Method | Notes |
|-----|--------|-------|
| `Status` | `status(profile)` | ✅ |
| `ListContainers` | `containers(profile)` | ✅ |

**Missing (51 RPCs not wired):**
- Everything except Status and ListContainers
- All 13 UI surfaces are placeholders (labels only)
- No reactive data binding, no user interaction handlers

**Build note:** Requires Linux + GTK4 + Rust toolchain. Cannot be verified on this
macOS host. Code compiles against tonic-build with the shared proto definition.

---

## Gap Priority Matrix

Ordered by impact (how much CLI functionality is blocked):

| Priority | Frontend | Gap Category | RPCs Missing | Effort |
|:--------:|----------|-------------|:------------:|:------:|
| P0 | TUI | VM lifecycle actions | 7 | Medium |
| P0 | TUI | Docker container write ops | 11 | Medium |
| P0 | Windows | All — only scaffold exists | 50 | Large |
| P0 | Linux | All — only scaffold exists | 51 | Large |
| P1 | TUI | Kubernetes | 4 | Small |
| P1 | TUI | Docker resource mgmt (images/vols/nets) | 16 | Medium |
| P1 | TUI | Streaming (events/logs/stats) | 3 | Medium |
| P2 | TUI | AI models | 5 | Small |
| P2 | TUI | Configuration | 4 | Small |
| P2 | TUI | Monitoring | 3 | Small |
| P2 | macOS | Template UI | 2 | Small |
| P3 | All | DependencyManager/turnkey | 2 | Medium |
| P3 | Daemon | GetConfig/SetConfig/Templates | 4 | Small |
| P3 | Daemon | PullImage/PushImage RPCs | 2 | Small |

---

## Recommendations

1. **TUI is closest to useful** — it has the gRPC client and tab structure; adding
   action commands (start/stop, container actions) would make it a functional daily-driver.

2. **Windows and Linux need full buildout** — both have correct scaffolding (proto,
   gRPC client, project structure) but no UI or business logic beyond stubs. These
   should be prioritized in M4.12.

3. **Daemon config RPCs** — `GetConfig`/`SetConfig`/`GetTemplate`/`SetTemplate` are
   defined in the proto but not implemented in `server.go`. The macOS client works
   around this by reading YAML files directly, but cross-platform frontends need
   these RPCs to be implemented.

4. **Streaming in non-macOS** — none of the other frontends implement streaming
   (VMStats, StreamEvents, StreamLogs, StreamStats). This is required for monitoring
   and live log tailing.

5. **Testing** — only the macOS frontend has comprehensive test suites (unit,
   integration, snapshot, UI). TUI has 1 test file. Windows and Linux have 0 tests.

## CI status (2026-07-18, frontends.yml)

All nine jobs are green in GitHub Actions run `29635550954`:

- `windows-winui` — success. Fixed protobuf generation ordering, gRPC streaming
  extensions, unsupported WinUI `x:Bind` indexers/type conversions, and invalid
  two-way `ComboBox`/`NumberBox` bindings.
- `linux-gtk4` — success. Installed libadwaita, wrapped Unix sockets with
  `hyper_util::rt::TokioIo`, and moved all GTK widget updates onto the GLib main
  context through `async-channel` + `spawn_future_local`.
- `macos-kit` — success.
- daemon on macOS, Ubuntu, Windows — success.
- TUI on macOS, Ubuntu, Windows — success.

## Runtime exploration status

macOS M3.9 is complete at `exploration/macos/ground-truth.json`: all 13 surfaces,
1,847 real AX elements, 13 screenshots, zero capture errors. System Events was used
for 12 surfaces; Configuration's unusually large tree used Peekaboo's AX snapshot
fallback after the bounded System Events traversal timed out.

Windows UIAutomation and Linux AT-SPI runtime captures remain environment-blocked:
this host has no project Windows/Linux GUI guest with the built application. CI proves
both applications compile, but hosted CI runners do not provide a reliable interactive
desktop session for honest UI-tree capture. Do not substitute static/source-derived
records for runtime ground truth.


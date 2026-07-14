# Program Board — CONTRACT

**Status:** 🔒 FROZEN v1 (2026-07-14, M0.4)
**Source of truth:** `proto/colima_ui.proto` (colima ops) + the Docker addendum below.
**Owner:** `go-daemon-dev` (proposes) → `architect` (approves). Change = version bump + ledger ack by all frontend agents.

Every frontend (macOS SwiftUI, Windows WinUI 3, Linux GTK4, TUI) implements a client that
maps 1:1 to this surface, mirroring the Swift `ServiceProvider` protocol.

## Part A — colima ops (frozen, from `proto/colima_ui.proto` · service `ColimaService`)
VM: Start(stream)·Stop·Restart(stream)·Delete·Status·Version·Update·Prune
SSH: SSHConfig
Profiles: ListProfiles·CreateProfile·DeleteProfile·CloneProfile
Config: GetConfig·SetConfig·GetTemplate·SetTemplate (ColimaConfig incl. network, kubernetes, mounts, provision, env)
Kubernetes: KubernetesStart·KubernetesStop·KubernetesReset·KubernetesExec
AI Models: ModelSetup(stream)·ModelRun(stream)·ModelServe·ModelStop
Runtime: SwitchRuntime·UpdateRuntime
Monitoring: VMStats(stream)·ProcessList·KillProcess
Machines (Lima): ListMachines  ← add to proto in M1.5 (present in ServiceProvider)

## Part B — Docker resource ops (frozen surface; ADDED to proto as `DockerService` in M1.5)
These are handled today by direct Docker API access on macOS; M1.5 exposes them as gRPC RPCs
so Windows/Linux/TUI get identical behavior. Surface (from ServiceProvider):
- Containers: list, start, stop, kill, restart, pause, unpause, remove, create(name,image),
  rename, logs, inspect, top, stats, changes, prune  (+ streamEvents, streamLogs, streamStats)
- Images: list, pull, remove, inspect, history, tag, push, search, prune
- Volumes: list, create, remove, inspect, prune
- Networks: list, create, remove, inspect, connect, disconnect, prune

## Part C — Installation / turnkey (M4.13)
- isColimaInstalled() → Bool
- installColima()  (hybrid: brew/winget/apt → direct signed download)
- DependencyManager: track + update colima/lima/qemu/krunkit/docker-cli/kubectl

## Provider mapping (choice 1=a native + 2=c)
- **macOS**: `RealServiceProvider` = direct-access provider (colima/limactl/kubectl CLI +
  Docker API unix socket). Native, zero-overhead — this IS mac's implementation of the contract.
  A daemon-backed gRPC provider is OPTIONAL (deferred; not required to unblock frontends).
- **Windows**: gRPC client → daemon; providers: remote-colima (SSH/gRPC) + local WSL2/Docker.
- **Linux**: gRPC client → daemon; provider: local colima.
- **TUI**: in-process or gRPC → daemon.

## Frozen version history
- **v1 (2026-07-14):** Parts A+B+C above. `proto/colima_ui.proto` ColimaService is frozen;
  ListMachines + DockerService RPCs are v1-additive (added in M1.5 without breaking A).

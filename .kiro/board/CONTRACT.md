# Program Board — CONTRACT

**Status:** 🔒 v1 RPC surface FROZEN (2026-07-14, M0.4) · request shapes revised **v1.1** (2026-07-18, approved additive scope correction — see "Request-shape revision (v1.1)" and "Version history" below)
**Source of truth:** `proto/colima_ui.proto` (colima ops) + the Docker addendum below.
**Owner:** `go-daemon-dev` (proposes) → `architect` (approves). Change = version bump + ledger ack by all frontend agents.

**Frozen invariants (unchanged across v1 → v1.1):** RPC **names**, RPC **counts** (31 `ColimaService` + 34 `DockerService` = **65** total), and existing proto **field numbers**. The v1.1 revision is **additive request-shape scoping only**: no RPC was renamed, added, or removed, and no existing field number changed.

Every frontend (macOS SwiftUI, Windows WinUI 3, Linux GTK4, TUI) implements a client that
maps 1:1 to this surface, mirroring the Swift `ServiceProvider` protocol.

## Part A — colima ops (frozen RPC names/numbers, from `proto/colima_ui.proto` · service `ColimaService`)
VM: Start(stream)·Stop·Restart(stream)·Delete·Status·Version·Update†·Prune†
SSH: SSHConfig
Profiles: ListProfiles·CreateProfile·DeleteProfile·CloneProfile
Config: GetConfig·SetConfig·GetTemplate·SetTemplate (ColimaConfig incl. network, kubernetes, mounts, provision, env)
Kubernetes: KubernetesStart·KubernetesStop·KubernetesReset·KubernetesExec
AI Models: ModelSetup(stream)·ModelRun(stream)·ModelServe·ModelStop
Runtime: SwitchRuntime·UpdateRuntime
Monitoring: VMStats(stream)·ProcessList·KillProcess
Machines (Lima): ListMachines  ← add to proto in M1.5 (present in ServiceProvider)

† **v1.1 profile-scoping:** `Update` now takes `ProfileRequest`, and `Prune`'s `PruneRequest` gained a `profile` field, so both target a named profile instead of global colima state. RPC names and existing field numbers are unchanged. See "Request-shape revision (v1.1)" below.

## Part B — Docker resource ops (frozen RPC names/numbers; ADDED to proto as `DockerService` in M1.5)
These are handled today by direct Docker API access on macOS; M1.5 exposes them as gRPC RPCs
so Windows/Linux/TUI get identical behavior. Surface (from ServiceProvider):
- Containers: list, start, stop, kill, restart, pause, unpause, remove, create(name,image),
  rename‡, logs, inspect, top, stats, changes, prune  (+ streamEvents, streamLogs, streamStats)
- Images: list, pull, remove, inspect, history, tag‡, push, search‡, prune
- Volumes: list, create, remove, inspect, prune
- Networks: list, create, remove, inspect, connect‡, disconnect‡, prune

‡ **v1.1 provider-scoping:** the `rename`, `tag`, `search`, and network `connect`/`disconnect` request messages (`RenameRequest`, `TagRequest`, `SearchRequest`, `NetworkContainerRequest`) gained `host` + `wsl2` fields so a call can route to a remote-SSH host or a local WSL2/Docker engine instead of implicitly hitting the local daemon. RPC names and existing field numbers are unchanged. See "Request-shape revision (v1.1)" below.

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

## Request-shape revision (v1.1 — approved additive scope correction)

The v1 RPC **surface** (names, counts, field numbers) is frozen, but several v1 **request shapes**
could not name the profile or provider they targeted. That was a safety defect: an unscoped
`Update`/`Prune` would act on the default/global colima state, and an unscoped Docker mutation would
act on whatever engine the local daemon happened to front. Disposable live testing (the isolated
`desktop-e2e` profile, Assumption A3) and the Windows dual-provider model (remote colima over SSH
vs. a local WSL2/Docker engine) both require every profile/provider-sensitive request to state its
target. Windows, TUI, and daemon owners independently reproduced this as a live-safety blocker.

An architect-approved `contract-integration` pass (2026-07-18) corrected this **additively** — new
fields only, with no rename/add/remove of any RPC and no change to any existing field number:

| Request (RPC) | Service | Added scope capability | Why |
|---------------|---------|------------------------|-----|
| `ProfileRequest` (`Update`) | ColimaService | `profile` | Target the named profile, not global colima state |
| `PruneRequest` (`Prune`) | ColimaService | `profile` (field 2; `all` field 1 unchanged) | Scope prune to a profile |
| `RenameRequest` (`RenameContainer`) | DockerService | `host`, `wsl2` | Route to a remote-SSH host or a local WSL2 engine |
| `TagRequest` (`TagImage`) | DockerService | `host`, `wsl2` | Same provider scoping |
| `SearchRequest` (`SearchImages`) | DockerService | `host`, `wsl2` | Same provider scoping |
| `NetworkContainerRequest` (`ConnectNetwork` / `DisconnectNetwork`) | DockerService | `host`, `wsl2` | Same provider scoping |

Scope-field semantics (shared with the Docker requests that already carried them — `DockerScope`,
`IdRequest`, `NameRequest`, `ContainerActionRequest`, `CreateContainerRequest`): `profile` selects
the daemon's target backend; `host` (optional, `user@host`; empty = local) selects a remote
colima/Lima host over SSH; `wsl2` selects a local WSL2/Docker engine on Windows.

**Preserved invariants (Requirement 2.1 / design Property 6):** exactly **31 `ColimaService` + 34
`DockerService` = 65** RPCs, unchanged RPC **names**, and unchanged existing proto **field numbers**;
new fields were appended with new field numbers only. **Enforcement:** a request that omits a
profile/provider field required for safe scoping is **rejected with a contextual error** rather than
executed against global/local state (Requirement 3.5).

**Status:** implemented and integrated in `proto/colima_ui.proto` and the daemon/TUI/Windows/Linux
consumers — this section reconciles `CONTRACT.md` with that already-shipped change; it does not
propose new work. Evidence: INTENT_LEDGER `2026-07-18T20:25Z` and `2026-07-18T20:39Z`
(`contract-integration · v1 pre-release scope repair`).

## Version history
- **v1 (2026-07-14, M0.4 — FROZEN):** Parts A+B+C above. `proto/colima_ui.proto` `ColimaService`
  is frozen; `ListMachines` + `DockerService` RPCs are v1-additive (added in M1.5 without breaking
  Part A).
- **v1.1 (2026-07-18 — approved additive scope correction):** A single architect-approved
  `contract-integration` pass made every provider/profile-sensitive request carry its target,
  resolving independently reproduced Windows/TUI/daemon safety blockers. `Update` now takes
  `ProfileRequest`; `PruneRequest` gained `profile`; `RenameRequest`, `TagRequest`, `SearchRequest`,
  and `NetworkContainerRequest` gained `host` + `wsl2` provider-scope fields. **RPC names, counts
  (31 + 34 = 65), and all existing field numbers are unchanged** — the change is purely additive
  request-shape scoping, so the old unscoped shapes are no longer treated as frozen. See INTENT_LEDGER
  `2026-07-18T20:25Z` and `2026-07-18T20:39Z` (`contract-integration · v1 pre-release scope repair`).

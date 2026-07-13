# Program Board — CONTRACT (versioned interface)

**Status:** DRAFT (freezes to v1 at end of M0.4)
**Source of truth:** `proto/colima_ui.proto` (gRPC). Owner: `go-daemon-dev` (changes via change-request to architect).

## Contract v1 surface (from `proto/colima_ui.proto`, service `ColimaService`)

Every frontend (macOS SwiftUI, Windows WinUI 3, Linux GTK4, TUI) MUST implement a client
that mirrors the SwiftUI `ServiceProvider` protocol and maps 1:1 to these RPCs.

### VM Lifecycle
`Start`(stream ProgressEvent) · `Stop` · `Restart`(stream) · `Delete` · `Status` · `Version` · `Update` · `Prune`

### SSH
`SSHConfig`

### Profiles
`ListProfiles` · `CreateProfile` · `DeleteProfile` · `CloneProfile`

### Configuration
`GetConfig` · `SetConfig` · `GetTemplate` · `SetTemplate` (ColimaConfig: cpu, memory, disk, arch, vm_type, mount_type, runtime, network, kubernetes, mounts, provision, env, …)

### Kubernetes
`KubernetesStart` · `KubernetesStop` · `KubernetesReset` · `KubernetesExec`

### AI Models
`ModelSetup`(stream) · `ModelRun`(stream) · `ModelServe` · `ModelStop`

### Runtime
`SwitchRuntime` · `UpdateRuntime`

### Monitoring
`VMStats`(stream) · `ProcessList` · `KillProcess`

## Backend providers (daemon-side, choice 2=c)
- **local-colima** (macOS/Linux): colima/limactl/kubectl CLI + Docker API (unix socket).
- **remote-ssh** (Windows + any): control a remote colima/Lima host over SSH/gRPC.
- **wsl2-docker** (Windows): local Docker over WSL2 / npipe.

## Change protocol
Breaking changes require: (1) change-request entry in `INTENT_LEDGER.md`, (2) version bump
here (v1→v2), (3) acknowledgement by every dependent frontend agent before merge.

## Frozen version history
- v1: (pending freeze at M0.4)

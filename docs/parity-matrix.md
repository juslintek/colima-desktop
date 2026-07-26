# CLI-Parity Matrix

> **Owner: architect** (single source of truth, reserved). **Regenerated from source** by
> `scripts/gen-truth-table.py` from the current `proto/colima_ui.proto`, the concrete daemon
> server methods under `daemon/internal/server/**`, and `exploration/action-inventory.json`
> (schema_version 2, audited 2026-07-18). It is derived from the SAME
> `build_matrix()` rows as `docs/truth-table.csv`, so the two cannot drift; regenerating is
> byte-identical on repeated runs and every proto RPC appears at least once (design Property 9).
>
> This supersedes the earlier hand-maintained CLI→status matrix (which could drift and carried
> stale claims). Every cell is exactly one level from the taxonomy {source-only,
> deterministic-fake-data, CI-without-daemon, live-backend, environment-blocked} (design
> Property 8); `live-backend` is the only level that closes a live-verification obligation and
> `environment-blocked` is an honest terminal label (never counted as success).

## Summary

- ColimaService RPCs: **31** (expected 31)
- DockerService RPCs: **34** (expected 34)
- Total RPCs: **65** (expected 65)
- Concrete daemon server methods: **65/65**
- Coverage cells (RPC × frontend): **260** (expected 260)
- RPCs without a concrete server method: **none** — every RPC has a non-`Unimplemented` daemon receiver (Property 7).

## Coverage by evidence level

| Evidence level | Cells |
|----------------|------:|
| source-only | 8 |
| deterministic-fake-data | 0 |
| CI-without-daemon | 226 |
| live-backend | 26 |
| environment-blocked | 0 |
| **total** | **260** |

## Coverage by frontend

| Frontend | Handlers | source-only | deterministic-fake-data | CI-without-daemon | live-backend | environment-blocked |
|----------|---:|---:|---:|---:|---:|---:|
| macos | 61/65 | 4 | 0 | 37 | 24 | 0 |
| windows | 65/65 | 0 | 0 | 65 | 0 | 0 |
| linux | 65/65 | 0 | 0 | 65 | 0 | 0 |
| tui | 61/65 | 4 | 0 | 59 | 2 | 0 |

## Legacy-claim reconciliation

Computed from the current proto RPC set and the concrete daemon server methods (not hardcoded).
These supersede the earlier stale notes ("no pull/push RPC", "config/template unimplemented"):

- **DockerService.PullImage** (server-streaming) — proto RPC: declared; daemon server method: concrete; frontend handlers: macos, windows, linux, tui.
- **DockerService.PushImage** (server-streaming) — proto RPC: declared; daemon server method: concrete; frontend handlers: windows, linux, tui.
- **ColimaService.GetConfig** — proto RPC: declared; daemon server method: concrete; frontend handlers: macos, windows, linux, tui.
- **ColimaService.SetConfig** — proto RPC: declared; daemon server method: concrete; frontend handlers: macos, windows, linux, tui.
- **ColimaService.GetTemplate** — proto RPC: declared; daemon server method: concrete; frontend handlers: windows, linux, tui.
- **ColimaService.SetTemplate** — proto RPC: declared; daemon server method: concrete; frontend handlers: windows, linux, tui.

## Per-RPC × frontend evidence matrix

Legend: S = source-only, D = deterministic-fake-data, C = CI-without-daemon, L = live-backend, E = environment-blocked. Server = concrete daemon method present. Every one of the 65 RPCs is listed (Property 9 coverage).

### ColimaService (31 RPCs)

| # | RPC | Surface | Stream | Server | macos | windows | linux | tui |
|--:|-----|---------|:------:|:------:|:--:|:--:|:--:|:--:|
| 1 | Start | dashboard | stream | yes | C | C | C | C |
| 2 | Stop | dashboard | - | yes | C | C | C | C |
| 3 | Restart | dashboard | stream | yes | C | C | C | C |
| 4 | Delete | profiles | - | yes | C | C | C | C |
| 5 | Status | dashboard | - | yes | L | C | C | C |
| 6 | Version | dashboard | - | yes | C | C | C | S |
| 7 | Update | runtime | - | yes | C | C | C | C |
| 8 | Prune | runtime | - | yes | C | C | C | C |
| 9 | SSHConfig | profiles | - | yes | C | C | C | C |
| 10 | ListProfiles | profiles | - | yes | L | C | C | C |
| 11 | ListMachines | machines | - | yes | C | C | C | C |
| 12 | CreateProfile | profiles | - | yes | C | C | C | C |
| 13 | DeleteProfile | profiles | - | yes | C | C | C | C |
| 14 | CloneProfile | profiles | - | yes | C | C | C | C |
| 15 | GetConfig | configuration | - | yes | L | C | C | C |
| 16 | SetConfig | configuration | - | yes | L | C | C | C |
| 17 | GetTemplate | configuration | - | yes | S | C | C | C |
| 18 | SetTemplate | configuration | - | yes | S | C | C | C |
| 19 | KubernetesStart | kubernetes | - | yes | C | C | C | C |
| 20 | KubernetesStop | kubernetes | - | yes | C | C | C | C |
| 21 | KubernetesReset | kubernetes | - | yes | C | C | C | C |
| 22 | KubernetesExec | kubernetes | - | yes | C | C | C | C |
| 23 | ModelSetup | ai_workloads | stream | yes | C | C | C | C |
| 24 | ModelRun | ai_workloads | stream | yes | C | C | C | C |
| 25 | ModelServe | ai_workloads | - | yes | C | C | C | C |
| 26 | ModelStop | ai_workloads | - | yes | C | C | C | C |
| 27 | SwitchRuntime | runtime | - | yes | L | C | C | C |
| 28 | UpdateRuntime | runtime | - | yes | L | C | C | C |
| 29 | VMStats | monitoring | stream | yes | S | C | C | C |
| 30 | ProcessList | monitoring | - | yes | C | C | C | C |
| 31 | KillProcess | monitoring | - | yes | C | C | C | C |

### DockerService (34 RPCs)

| # | RPC | Surface | Stream | Server | macos | windows | linux | tui |
|--:|-----|---------|:------:|:------:|:--:|:--:|:--:|:--:|
| 1 | ListContainers | containers | - | yes | L | C | C | C |
| 2 | ContainerAction | containers | - | yes | L | C | C | C |
| 3 | CreateContainer | containers | - | yes | L | C | C | C |
| 4 | RenameContainer | containers | - | yes | C | C | C | C |
| 5 | ContainerLogs | containers | - | yes | L | C | C | C |
| 6 | InspectContainer | containers | - | yes | C | C | C | C |
| 7 | ContainerTop | containers | - | yes | C | C | C | C |
| 8 | ContainerStats | containers | - | yes | L | C | C | C |
| 9 | ContainerChanges | containers | - | yes | C | C | C | C |
| 10 | PruneContainers | containers | - | yes | C | C | C | C |
| 11 | ListImages | images | - | yes | L | C | C | C |
| 12 | PullImage | images | stream | yes | L | C | C | C |
| 13 | RemoveImage | images | - | yes | L | C | C | L |
| 14 | InspectImage | images | - | yes | L | C | C | L |
| 15 | ImageHistory | images | - | yes | C | C | C | C |
| 16 | TagImage | images | - | yes | L | C | C | C |
| 17 | PushImage | images | stream | yes | S | C | C | C |
| 18 | SearchImages | images | - | yes | C | C | C | C |
| 19 | PruneImages | images | - | yes | C | C | C | C |
| 20 | ListVolumes | volumes | - | yes | L | C | C | C |
| 21 | CreateVolume | volumes | - | yes | L | C | C | C |
| 22 | RemoveVolume | volumes | - | yes | L | C | C | C |
| 23 | InspectVolume | volumes | - | yes | L | C | C | C |
| 24 | PruneVolumes | volumes | - | yes | C | C | C | C |
| 25 | ListNetworks | networks | - | yes | L | C | C | C |
| 26 | CreateNetwork | networks | - | yes | L | C | C | C |
| 27 | RemoveNetwork | networks | - | yes | L | C | C | C |
| 28 | InspectNetwork | networks | - | yes | L | C | C | C |
| 29 | ConnectNetwork | networks | - | yes | C | C | C | C |
| 30 | DisconnectNetwork | networks | - | yes | C | C | C | C |
| 31 | PruneNetworks | networks | - | yes | C | C | C | C |
| 32 | StreamEvents | monitoring | stream | yes | C | C | C | S |
| 33 | StreamLogs | containers | stream | yes | C | C | C | S |
| 34 | StreamStats | containers | stream | yes | C | C | C | S |

## Frontend-handler gaps (source-only cells)

Server method exists but this frontend has no handler for the RPC (8 cell(s)). This is where the corrected claims land — e.g. the macOS **template** gap (`GetTemplate`/`SetTemplate`) is `source-only` (server-side concrete; the macOS UI handler is pending task 7.1), not "unimplemented":

| RPC | Frontend | Surface |
|-----|----------|---------|
| Version | tui | dashboard |
| GetTemplate | macos | configuration |
| SetTemplate | macos | configuration |
| VMStats | macos | monitoring |
| PushImage | macos | images |
| StreamEvents | tui | monitoring |
| StreamLogs | tui | containers |
| StreamStats | tui | containers |

## Environment-blocked cells

None in this per-RPC handler inventory. Windows/Linux live UIA/AT-SPI capture is tracked separately in `exploration/{windows,linux}` ground-truth (task 10.7); their per-RPC handler evidence is capped at CI-without-daemon.


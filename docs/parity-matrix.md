# CLI-Parity Matrix

> Single source of truth (owner: architect) mapping every Colima CLI capability to its
> backend RPC (CONTRACT v1), the Swift `ServiceProvider` method, the UI surface, and its test.
> Frontends (macOS SwiftUI ✅ exists · Windows WinUI 3 · Linux GTK4 · TUI) must each cover every
> row. Status legend: ✅ done · 🟡 partial · ⬜ todo · n/a.

## A. VM lifecycle
| CLI | Backend RPC | ServiceProvider | UI surface | mac | win | linux | tui | Test |
|-----|-------------|-----------------|-----------|:--:|:--:|:--:|:--:|------|
| `colima start` | Start (stream) | startVM | Dashboard ▸ Start | ✅ | ⬜ | ⬜ | ⬜ | ColimaLifecycleUITests |
| `colima stop` | Stop | stopVM | Dashboard ▸ Stop | ✅ | ⬜ | ⬜ | ⬜ | ColimaLifecycleUITests |
| `colima restart` | Restart (stream) | restartVM | Dashboard ▸ Restart | ✅ | ⬜ | ⬜ | ⬜ | ColimaLifecycleUITests |
| `colima delete` | Delete | deleteVM | Profiles ▸ Delete | ✅ | ⬜ | ⬜ | ⬜ | VMConfigurationFlowUITests |
| `colima status` | Status | vmStatus | Dashboard header | ✅ | ⬜ | ⬜ | ⬜ | AppShellUITests |
| `colima version` | Version | vmVersion | About | ✅ | ⬜ | ⬜ | ⬜ | RealBackendTests |
| `colima update` | Update | updateVM | Runtime Controls | ✅ | ⬜ | ⬜ | ⬜ | RealBackendTests |
| `colima prune [--all]` | Prune | pruneVM | Runtime Controls | 🟡 | ⬜ | ⬜ | ⬜ | RealBackendTests |

## B. SSH / profiles
| CLI | RPC | ServiceProvider | UI | mac | win | linux | tui | Test |
|-----|-----|-----------------|----|:--:|:--:|:--:|:--:|------|
| `colima ssh-config` | SSHConfig | sshConfig | Dashboard ▸ SSH Config | ✅ | ⬜ | ⬜ | ⬜ | ColimaLifecycleUITests |
| `colima list` | ListProfiles | listProfiles | Profiles | ✅ | ⬜ | ⬜ | ⬜ | ProfileManagementUITests |
| `colima start --profile` | CreateProfile | createProfile | Profiles ▸ New | ✅ | ⬜ | ⬜ | ⬜ | VMConfigurationFlowUITests |
| `colima delete --profile` | DeleteProfile | deleteProfile | Profiles ▸ Delete | ✅ | ⬜ | ⬜ | ⬜ | ProfileManagementUITests |
| `colima clone` (hidden) | CloneProfile | cloneProfile | Profiles ▸ Clone | 🟡 | ⬜ | ⬜ | ⬜ | VMConfigurationFlowUITests |
| `limactl list --json` | ListMachines* | listMachines | Machines | ✅ | ⬜ | ⬜ | ⬜ | MachinesUITests |

## C. Configuration
| CLI/file | RPC | ServiceProvider | UI | mac | win | linux | tui | Test |
|----------|-----|-----------------|----|:--:|:--:|:--:|:--:|------|
| read `colima.yaml` | GetConfig | readConfig | Configuration | ✅ | ⬜ | ⬜ | ⬜ | ConfigurationUITests |
| write `colima.yaml` | SetConfig | writeConfig | Configuration ▸ Save | ✅ | ⬜ | ⬜ | ⬜ | NativePerformanceConfigUITests |
| template | GetTemplate/SetTemplate | — | Configuration | ⬜ | ⬜ | ⬜ | ⬜ | — |
| cpu/mem/disk/vmType/mountType/arch/runtime/net/k8s | (ColimaConfig) | read/writeConfig | Configuration cards | ✅ | ⬜ | ⬜ | ⬜ | NativePerformanceConfigUITests |

## D. Kubernetes
| CLI | RPC | ServiceProvider | UI | mac | win | linux | tui | Test |
|-----|-----|-----------------|----|:--:|:--:|:--:|:--:|------|
| `colima kubernetes start` | KubernetesStart | k8sStart | Kubernetes ▸ Start | ✅ | ⬜ | ⬜ | ⬜ | KubernetesLifecycleUITests |
| `... stop` | KubernetesStop | k8sStop | Kubernetes ▸ Stop | ✅ | ⬜ | ⬜ | ⬜ | KubernetesLifecycleUITests |
| `... reset` | KubernetesReset | k8sReset | Kubernetes ▸ Reset | ✅ | ⬜ | ⬜ | ⬜ | KubernetesLifecycleUITests |
| `kubectl …` | KubernetesExec | kubectlExec | Kubernetes tabs | ✅ | ⬜ | ⬜ | ⬜ | KubernetesLifecycleUITests |

## E. Docker resources (CONTRACT Part B → DockerService in M1.5)
| Area | RPC (M1.5) | ServiceProvider | UI | mac | win | linux | tui | Test |
|------|-----------|-----------------|----|:--:|:--:|:--:|:--:|------|
| Containers list/start/stop/kill/restart/pause/unpause/remove/create/rename/logs/inspect/top/stats/changes/prune | Docker* | (16 methods) | Containers | ✅ | ⬜ | ⬜ | ⬜ | ContainerManagementUITests, RealBackendTests |
| Images list/pull/remove/inspect/history/tag/push/search/prune | Docker* | (9) | Images | ✅ | ⬜ | ⬜ | ⬜ | ImageManagementUITests, RealBackendTests |
| Volumes list/create/remove/inspect/prune | Docker* | (5) | Volumes | ✅ | ⬜ | ⬜ | ⬜ | VolumeManagementUITests |
| Networks list/create/remove/inspect/connect/disconnect/prune | Docker* | (7) | Networks | ✅ | ⬜ | ⬜ | ⬜ | NetworkManagementUITests |
| streams: events/logs/stats | Docker* (stream) | stream* | Monitoring/Logs | ✅ | ⬜ | ⬜ | ⬜ | MonitoringUITests |

## F. AI models (krunkit)
| CLI | RPC | ServiceProvider | UI | mac | win | linux | tui | Test |
|-----|-----|-----------------|----|:--:|:--:|:--:|:--:|------|
| `colima model list` | (ModelList*) | modelList | AI ▸ Downloaded | ✅ | ⬜ | ⬜ | ⬜ | AIWorkloadsUITests |
| `colima model pull` | ModelSetup/pull* | modelPull | AI ▸ Pull | ✅ | ⬜ | ⬜ | ⬜ | AIWorkloadsUITests |
| `colima model run` | ModelRun (stream) | modelRun | AI ▸ Run | ✅ | ⬜ | ⬜ | ⬜ | AIWorkloadsUITests |
| `colima model serve` | ModelServe | modelServe | AI ▸ Serve | ✅ | ⬜ | ⬜ | ⬜ | AIWorkloadsUITests |
| stop | ModelStop | modelStop | AI ▸ Stop | ✅ | ⬜ | ⬜ | ⬜ | AIWorkloadsUITests |

## G. Runtime / monitoring
| CLI | RPC | ServiceProvider | UI | mac | win | linux | tui | Test |
|-----|-----|-----------------|----|:--:|:--:|:--:|:--:|------|
| switch runtime | SwitchRuntime | (via config) | Runtime Controls | 🟡 | ⬜ | ⬜ | ⬜ | RuntimeControlsUITests |
| update runtime | UpdateRuntime | updateVM | Runtime Controls | 🟡 | ⬜ | ⬜ | ⬜ | RuntimeControlsUITests |
| process list | ProcessList | processList | Monitoring | ✅ | ⬜ | ⬜ | ⬜ | MonitoringUITests |
| kill process | KillProcess | killProcess | Monitoring | ✅ | ⬜ | ⬜ | ⬜ | MonitoringUITests |
| VM stats | VMStats (stream) | streamStats | Monitoring | ✅ | ⬜ | ⬜ | ⬜ | MonitoringUITests |

## H. Turnkey (M4.13)
| Capability | ServiceProvider | UI | mac | win | linux | tui | Test |
|-----------|-----------------|----|:--:|:--:|:--:|:--:|------|
| detect colima | isColimaInstalled | Onboarding | ✅ | ⬜ | ⬜ | ⬜ | InstallDetectionTests |
| install colima + deps | installColima / DependencyManager | Onboarding | 🟡 | ⬜ | ⬜ | ⬜ | InstallPromptUITests |
| track + auto-update deps | DependencyManager | Settings | ⬜ | ⬜ | ⬜ | ⬜ | — |

`*` = RPC to be added to `proto/colima_ui.proto` in M1.5 (ListMachines, DockerService, model list). v1-additive.

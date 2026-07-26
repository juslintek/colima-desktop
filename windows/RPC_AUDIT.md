# Windows frozen-v1 RPC audit

Audited **2026-07-21** against `windows/Proto/colima_ui.proto` (v1.1),
`windows/Services/DaemonClient.cs`, `windows/Services/DaemonRequestFactory.cs`,
`windows/ViewModels/*.cs`, and `windows/Views/*.xaml.cs`:

> **65/65 frozen-contract RPCs (31 `ColimaService` + 34 `DockerService`) map to a concrete
> `DaemonClient` method AND a concrete WinUI view-model command handler. Zero gaps.**

Every row below was checked against source (no estimates). This is source + deterministic-test
evidence, not a claim of native Windows/WSL2 live proof — see the Verification boundary.

Legend: **VM** = view-model command surfacing the action (CommunityToolkit `[RelayCommand]` →
`<Name>Command`); **DaemonClient** = the gRPC client helper it calls. Docker rows capture one
immutable `ConnectionSettings.CaptureDockerTarget()` → `DockerTarget{Profile,Host,Wsl2}` snapshot per
action so a settings change can never split one multi-step action across profiles/providers.

## ColimaService (31/31)

| # | RPC | WinUI command handler (ViewModel) | DaemonClient method | Scope / result / cancellation |
|---|-----|-----------------------------------|---------------------|-------------------------------|
| 1 | Start | `DashboardViewModel.StartCommand` | `StartStream` | Selected profile; server-streaming progress; `IncludeCancelCommand` + `OnNavigatedFrom` cancel; incomplete stream fails |
| 2 | Stop | `DashboardViewModel.StopCommand` | `StopAsync` | Selected profile; `StatusResponse` enforced |
| 3 | Restart | `DashboardViewModel.RestartCommand` | `RestartStream` | Selected profile; cancellable progress; incomplete stream fails |
| 4 | Delete | `DashboardViewModel.DeleteCommand` (via `DashboardPage.DeleteVm_Click` → `ConfirmDeleteVmDialog`) | `DeleteAsync` | Selected profile; accessible confirmation; `StatusResponse` enforced |
| 5 | Status | `DashboardViewModel`/`KubernetesViewModel`/`MonitoringViewModel` load | `StatusAsync` | Selected profile; gRPC failures shown in error banner |
| 6 | Version | `DashboardViewModel` load + `DaemonClient.CheckHealthAsync` | `VersionAsync` | Global; bounded health check uses this RPC |
| 7 | Update | `RuntimeViewModel.UpdateColimaCommand` | `UpdateAsync` → `DaemonRequestFactory.Profile` | **Profile-scoped (v1.1 `ProfileRequest`)** |
| 8 | Prune | `RuntimeViewModel.PruneCommand` (via `RuntimePage.Prune_Click`/`PruneAll_Click`) | `PruneAsync` → `DaemonRequestFactory.Prune` | **Profile-scoped (v1.1 `PruneRequest.profile`)**; confirmation; `all` flag |
| 9 | SSHConfig | `DashboardViewModel.ShowSshConfigCommand` | `SSHConfigAsync` | Selected profile |
| 10 | ListProfiles | `ProfilesViewModel` load | `ListProfilesAsync` | Global; gRPC failures shown |
| 11 | ListMachines | `MachinesViewModel` load / `RefreshCommand` | `ListMachinesAsync` | Global; gRPC failures shown |
| 12 | CreateProfile | `ProfilesViewModel.CreateProfileCommand` | `CreateProfileAsync` | Required name; `StatusResponse` enforced |
| 13 | DeleteProfile | `ProfilesViewModel.DeleteProfileCommand` (via `ProfilesPage.DeleteProfile_Click`) | `DeleteProfileAsync` | Required name; accessible confirmation; status enforced |
| 14 | CloneProfile | `ProfilesViewModel.CloneProfileCommand` | `CloneProfileAsync` | Required source+destination; status enforced |
| 15 | GetConfig | `ConfigurationViewModel` load | `GetConfigAsync` | Selected profile |
| 16 | SetConfig | `ConfigurationViewModel.SaveConfigCommand` | `SetConfigAsync` | Selected profile; status enforced |
| 17 | GetTemplate | `ConfigurationViewModel.LoadTemplateCommand` | `GetTemplateAsync` | Global template fields loaded into editor |
| 18 | SetTemplate | `ConfigurationViewModel.SaveTemplateCommand` | `SetTemplateAsync` | Edited fields written; status enforced |
| 19 | KubernetesStart | `KubernetesViewModel.StartKubernetesCommand` | `KubernetesStartAsync` | Selected profile; status enforced |
| 20 | KubernetesStop | `KubernetesViewModel.StopKubernetesCommand` | `KubernetesStopAsync` | Selected profile; status enforced |
| 21 | KubernetesReset | `KubernetesViewModel.ResetKubernetesCommand` (via `KubernetesPage.ResetKubernetes_Click`) | `KubernetesResetAsync` | Selected profile; accessible confirmation; status enforced |
| 22 | KubernetesExec | `KubernetesViewModel.ExecKubectlCommand` | `KubernetesExecAsync` | Selected profile; non-zero exit / error → actionable failure |
| 23 | ModelSetup | `AIWorkloadsViewModel.SetupModelCommand` | `ModelSetupStream` | Selected profile; cancellable progress; runner setup (see note) |
| 24 | ModelRun | `AIWorkloadsViewModel.RunModelCommand` | `ModelRunStream` | Selected profile; cancellable progress |
| 25 | ModelServe | `AIWorkloadsViewModel.ServeModelCommand` | `ModelServeAsync` | Selected profile; status enforced |
| 26 | ModelStop | `AIWorkloadsViewModel.StopModelCommand` | `ModelStopAsync` | Selected profile; status enforced |
| 27 | SwitchRuntime | `RuntimeViewModel.SwitchRuntimeCommand` | `SwitchRuntimeAsync` | Selected profile; status enforced |
| 28 | UpdateRuntime | `RuntimeViewModel.UpdateRuntimeCommand` | `UpdateRuntimeAsync` | Selected profile; status enforced |
| 29 | VMStats | `MonitoringViewModel.StartStatsStreamCommand` | `VMStatsStream` | Selected profile; page-lifetime cancellation via `StreamLifetime` |
| 30 | ProcessList | `MonitoringViewModel` load / `RefreshProcessesCommand` | `ProcessListAsync` | Selected profile |
| 31 | KillProcess | `MonitoringViewModel.KillProcessCommand` (via `MonitoringPage.KillProcess_Click`) | `KillProcessAsync` | Selected profile; accessible confirmation; status enforced |

## DockerService (34/34)

Every request carries `profile`, `host`, and `wsl2` from one immutable `DockerTarget` snapshot
(`DaemonRequestFactory` copies all three onto `DockerScope`/`IdRequest`/`NameRequest`/
`ContainerActionRequest`/`CreateContainerRequest`/`RenameRequest`/`TagRequest`/`SearchRequest`/
`NetworkContainerRequest`). `JsonResponse.error` and unsuccessful `StatusResponse` are converted to
actionable failures (`DaemonResponse.EnsureJson`/`EnsureSuccess`) before a view-model can treat them
as success.

| # | RPC | WinUI command handler (ViewModel) | DaemonClient method | Scope / result behavior |
|---|-----|-----------------------------------|---------------------|-------------------------|
| 1 | ListContainers | `ContainersViewModel` load | `ListContainersAsync` | Full target (`all=true`) |
| 2 | ContainerAction | `ContainersViewModel` Start/Stop/Kill/Restart/Pause/Unpause/Remove`Container`Command (via `ContainersPage.ContainerAction_Click`) | `ContainerActionAsync` | Full target; kill/remove accessibly confirmed |
| 3 | CreateContainer | `ContainersViewModel.CreateContainerCommand` | `CreateContainerAsync` | Full target |
| 4 | RenameContainer | `ContainersViewModel.RenameContainerCommand` | `RenameContainerAsync` | **Full target — host/wsl2 carried (v1.1 `RenameRequest`)** |
| 5 | ContainerLogs | `ContainersViewModel.ContainerLogsCommand` | `ContainerLogsAsync` | Full target |
| 6 | InspectContainer | `ContainersViewModel.InspectContainerCommand` | `InspectContainerAsync` | Full target |
| 7 | ContainerTop | `ContainersViewModel.ContainerTopCommand` | `ContainerTopAsync` | Full target |
| 8 | ContainerStats | `ContainersViewModel.ContainerStatsCommand` | `ContainerStatsAsync` | Full target |
| 9 | ContainerChanges | `ContainersViewModel.ContainerChangesCommand` | `ContainerChangesAsync` | Full target |
| 10 | PruneContainers | `ContainersViewModel.PruneContainersCommand` (via `ContainersPage.PruneContainers_Click`) | `PruneContainersAsync` | Full target; confirmation; JSON errors enforced |
| 11 | ListImages | `ImagesViewModel` load | `ListImagesAsync` | Full target |
| 12 | PullImage | `ImagesViewModel.PullImageCommand` | `PullImageStream` | Full target; server-streaming; cancellable progress |
| 13 | RemoveImage | `ImagesViewModel.RemoveImageCommand` (via `ImagesPage.RemoveImage_Click`) | `RemoveImageAsync` | Full target; confirmation; status enforced |
| 14 | InspectImage | `ImagesViewModel.InspectImageCommand` | `InspectImageAsync` | Full target |
| 15 | ImageHistory | `ImagesViewModel.ImageHistoryCommand` | `ImageHistoryAsync` | Full target |
| 16 | TagImage | `ImagesViewModel.TagImageCommand` | `TagImageAsync` | **Full target — host/wsl2 carried (v1.1 `TagRequest`)** |
| 17 | PushImage | `ImagesViewModel.PushImageCommand` | `PushImageStream` | Full target; server-streaming; cancellable progress |
| 18 | SearchImages | `ImagesViewModel.SearchImagesCommand` | `SearchImagesAsync` | **Full target — host/wsl2 carried (v1.1 `SearchRequest`)** |
| 19 | PruneImages | `ImagesViewModel.PruneImagesCommand` (via `ImagesPage.PruneImages_Click`) | `PruneImagesAsync` | Full target; confirmation |
| 20 | ListVolumes | `VolumesViewModel` load | `ListVolumesAsync` | Full target |
| 21 | CreateVolume | `VolumesViewModel.CreateVolumeCommand` | `CreateVolumeAsync` | Full target |
| 22 | RemoveVolume | `VolumesViewModel.RemoveVolumeCommand` (via `VolumesPage.RemoveVolume_Click`) | `RemoveVolumeAsync` | Full target; confirmation; status enforced |
| 23 | InspectVolume | `VolumesViewModel.InspectVolumeCommand` | `InspectVolumeAsync` | Full target |
| 24 | PruneVolumes | `VolumesViewModel.PruneVolumesCommand` (via `VolumesPage.PruneVolumes_Click`) | `PruneVolumesAsync` | Full target; confirmation |
| 25 | ListNetworks | `NetworksViewModel` load | `ListNetworksAsync` | Full target |
| 26 | CreateNetwork | `NetworksViewModel.CreateNetworkCommand` | `CreateNetworkAsync` | Full target |
| 27 | RemoveNetwork | `NetworksViewModel.RemoveNetworkCommand` (via `NetworksPage.RemoveNetwork_Click`) | `RemoveNetworkAsync` | Full target; confirmation; status enforced |
| 28 | InspectNetwork | `NetworksViewModel.InspectNetworkCommand` | `InspectNetworkAsync` | Full target |
| 29 | ConnectNetwork | `NetworksViewModel.ConnectNetworkCommand` | `ConnectNetworkAsync` | **Full target — host/wsl2 carried (v1.1 `NetworkContainerRequest`)** |
| 30 | DisconnectNetwork | `NetworksViewModel.DisconnectNetworkCommand` | `DisconnectNetworkAsync` | **Full target — host/wsl2 carried (v1.1 `NetworkContainerRequest`)** |
| 31 | PruneNetworks | `NetworksViewModel.PruneNetworksCommand` (via `NetworksPage.PruneNetworks_Click`) | `PruneNetworksAsync` | Full target; confirmation |
| 32 | StreamEvents | `ContainersViewModel.StreamEventsCommand` | `StreamEventsStream` | Full target; explicit stop / page cancellation; bounded output |
| 33 | StreamLogs | `ContainersViewModel.StreamLogsCommand` | `StreamLogsStream` | Full target; explicit stop / page cancellation; bounded output |
| 34 | StreamStats | `ContainersViewModel.StreamStatsCommand` | `StreamStatsStream` | Full target; explicit stop / page cancellation; bounded output |

## v1.1 request-shape scope (previously "frozen limitations" — now RESOLVED)

The approved pre-v1 additive request-shape correction (INTENT_LEDGER `2026-07-18T20:25Z` +
`2026-07-18T20:39Z`, `contract-integration`) closed the provider/profile-scope gaps this audit
previously documented. Confirmed against `windows/Proto/colima_ui.proto` and
`windows/Services/DaemonRequestFactory.cs`:

- **The 5 Docker provider-scope RPCs now carry `host` + `wsl2`.** `RenameRequest` (`host=4`,
  `wsl2=5`), `TagRequest` (`host=5`, `wsl2=6`), `SearchRequest` (`host=3`, `wsl2=4`), and
  `NetworkContainerRequest` (`host=4`, `wsl2=5`, used by both `ConnectNetwork` and
  `DisconnectNetwork`) can select remote-SSH or local WSL2. `DaemonRequestFactory.RenameContainer`/
  `TagImage`/`SearchImages`/`NetworkContainer` copy `target.Host`/`target.Wsl2` from the captured
  `DockerTarget`, so these are no longer profile-only.
- **`Update` and `Prune` now carry the profile.** `Update` takes `ProfileRequest`
  (`DaemonRequestFactory.Profile`), and `PruneRequest` gained `profile=2`
  (`DaemonRequestFactory.Prune`). Both are profile-scoped from `RuntimeViewModel.ActiveProfile`; they
  no longer target implicit global colima state.

RPC names, counts (31 `ColimaService` + 34 `DockerService` = 65), and existing field numbers are
unchanged; only additive scope fields were introduced. `windows/Proto/colima_ui.proto` is
byte-synchronized with the canonical proto except its `csharp_namespace = "Colimaui"` option.

### Remaining honest boundary (message shape, not a mapping gap)

- `ModelRequest` (`ModelSetup`) has `profile` + `runner` but no model-name field. Windows presents
  `ModelSetup` as **runner** setup and does not pretend a model field was transmitted. This is a
  frozen message-shape characteristic, not a missing handler — `ModelSetup` is fully wired
  (`AIWorkloadsViewModel.SetupModelCommand` → `DaemonClient.ModelSetupStream`).

## Verification boundary

- `windows/Tests`: headless compile of all service/view-model production sources plus **42
  deterministic test cases** (across `ConnectionAndPayloadTests`, `OperationBehaviorTests`,
  `DestructiveConfirmationGateTests`, and `AutomationIdInventoryTests`) covering request scope incl.
  the v1.1 host/wsl2/profile fields (`ExtendedProviderRequestsCopyHostAndWsl2Selection`,
  `ColimaMaintenanceRequestsCarryNormalizedProfile`), response-error conversion, non-reentrant busy
  state (`OperationGate`), cancellation (`StreamLifetime`), bounded streamed output
  (`StreamOutput.AppendBounded`), the fail-closed destructive-confirmation gate
  (`ViewModelBase.RunDestructiveAsync` — no RPC without confirmation; deny/dismiss/no-handler issues
  none; non-reentrant), stable accessibility identifiers, and loopback-only endpoint enforcement
  (`DaemonEndpoint`). `dotnet test` on the macOS host: **42/42 passed**.
- Every destructive view-model command routes through the fail-closed `RunDestructiveAsync` gate, so
  no destructive RPC fires without an explicit confirmation regardless of entry point. The view wires
  the gate to `DestructiveConfirmationDialog`, which sets `AutomationProperties.AutomationId` =
  `Confirm<Action>Dialog` and an automation name — accessible and testable (Requirements 5.5, 5.7).
- Every interactive control across `MainWindow.xaml` + all 13 pages carries a stable, unique
  `AutomationProperties.AutomationId` (mirroring its `AutomationProperties.Name`), and every error
  `InfoBar` is an `AutomationProperties.LiveSetting="Assertive"` live region. `AutomationIdInventoryTests`
  parses each XAML surface as XML and asserts well-formedness + interactive-control id
  presence/uniqueness (139 interactive controls) + accessible error banners — the structural check
  that stands in for the WinUI XamlCompiler, which cannot run on the macOS host (Requirements 5.6, 5.7).
- Native WinUI XAML compilation and live local-WSL2 / remote-SSH action proof require a Windows host.
  The macOS host cannot execute WindowsAppSDK's `XamlCompiler.exe` and is not WSL2/UIA evidence; the
  authoritative compile is the `windows-winui` CI job (evidence capped at `CI-without-daemon` per
  Assumption A2). Live UIA capture is `environment-blocked` on the macOS-only host.

# Colima Desktop — Windows (WinUI 3)

Native Windows frontend (WinUI 3 / WinRT, C#). Talks to the shared Go daemon over
gRPC (`grpc-dotnet`). Supports a **remote** colima/Lima host (SSH/gRPC) and a **local
WSL2/Docker** engine (CONTRACT v1, choice 2=c).

> **Platform-gated:** builds only on Windows with the Windows App SDK. Not compilable on the
> macOS CI host — verified by the `windows-native-dev` agent / GitHub Actions `windows-latest`.

## Prerequisites

- Windows 10 19041 (2004) or Windows 11
- .NET 8 SDK (`winget install Microsoft.DotNet.SDK.8`)
- Windows App SDK 1.5+ (`dotnet workload install windowsdesktop` or Visual Studio 2022 with
  WinUI 3 / Windows App SDK workload)
- `protoc` + `Grpc.Tools` — auto-restored from NuGet via `ColimaDesktop.Windows.csproj`

## Build & run

```powershell
cd windows
dotnet restore
dotnet build -c Debug
dotnet run --project ColimaDesktop.Windows.csproj
```

Or open `ColimaDesktop.Windows.csproj` in Visual Studio 2022 and press F5.

## Architecture

```
ColimaDesktop.Windows/
├── App.xaml / App.xaml.cs          — Application startup; creates DaemonClient,
│                                     ConnectionSettings, DependencyManager singletons
├── MainWindow.xaml / .cs           — NavigationView shell; routes to 13 pages
├── Services/
│   ├── DaemonClient.cs             — grpc-dotnet wrapper for ColimaService + DockerService
│   │                                 (all 65 frozen-v1 RPCs); reconnect + health checks
│   ├── ConnectionSettings.cs       — immutable remote-SSH/local-WSL2/profile snapshots
│   ├── DaemonConnectionManager.cs  — bounded health/bootstrap on loopback only
│   └── DependencyManager.cs        — detect/install WSL2 and Docker; validates only a daemon
│                                     bundled beside the installed app
├── ViewModels/
│   ├── ViewModelBase.cs            — ObservableObject base; RunAsync error handling; LoadCommand
│   ├── DashboardViewModel.cs       — VM status, start/stop/restart streaming, SSH config
│   ├── ContainersViewModel.cs      — list/start/stop/kill/restart/pause/unpause/remove/
│   │                                 create/rename/inspect/top/stats/changes/logs/prune
│   ├── ImagesViewModel.cs          — list/pull/remove/inspect/history/tag/push/search/prune
│   ├── VolumesViewModel.cs         — list/create/remove/inspect/prune
│   ├── NetworksViewModel.cs        — list/create/remove/inspect/connect/disconnect/prune
│   ├── MachinesViewModel.cs        — ListMachines (Lima)
│   ├── KubernetesViewModel.cs      — start/stop/reset cluster, kubectl exec
│   ├── ConfigurationViewModel.cs   — GetConfig/SetConfig/GetTemplate/SetTemplate;
│   │                                 CPU/mem/disk/runtime/vmType/arch/k8s/rosetta/mountType
│   ├── RuntimeViewModel.cs         — SwitchRuntime/UpdateRuntime/Update/Prune
│   ├── AIWorkloadsViewModel.cs     — ModelSetup/ModelRun(stream)/ModelServe/ModelStop
│   ├── ProfilesViewModel.cs        — ListProfiles/CreateProfile/DeleteProfile/CloneProfile
│   ├── MonitoringViewModel.cs      — VMStats(stream)/ProcessList/KillProcess
│   └── SettingsViewModel.cs        — DependencyManager UI + ConnectionSettings toggle
├── Views/
│   ├── DashboardPage.xaml/.cs      — mirrors macOS Dashboard surface
│   ├── ContainersPage.xaml/.cs     — mirrors macOS Containers surface
│   ├── ImagesPage.xaml/.cs         — mirrors macOS Images surface
│   ├── VolumesPage.xaml/.cs        — mirrors macOS Volumes surface
│   ├── NetworksPage.xaml/.cs       — mirrors macOS Networks surface
│   ├── MachinesPage.xaml/.cs       — Lima machines list
│   ├── KubernetesPage.xaml/.cs     — Kubernetes cluster controls + kubectl exec
│   ├── ConfigurationPage.xaml/.cs  — ColimaConfig editor (all resource/VM/k8s fields)
│   ├── RuntimePage.xaml/.cs        — runtime switch/update + colima update/prune
│   ├── AIWorkloadsPage.xaml/.cs    — model pull/run/serve/stop + prompt + output
│   ├── ProfilesPage.xaml/.cs       — profile list with inline create/delete/clone/select
│   ├── MonitoringPage.xaml/.cs     — live VM stats stream + process table + kill
│   └── SettingsPage.xaml/.cs       — DependencyManager onboarding + backend toggle
├── Converters/
│   ├── ValueConverters.cs          — BoolToVisibility, NullToVisibility, BoolToStatus, etc.
│   └── ConverterResources.xaml     — ResourceDictionary declaring all converters
└── Proto/
    └── colima_ui.proto             — copy of repo root proto; Grpc.Tools generates gRPC stubs
```

## Backend modes (CONTRACT v1 Part C)

| Mode | How to configure | What it uses |
|------|-----------------|--------------|
| Local WSL2 / Docker | Settings page → "Local WSL2 / Docker" | Native daemon on `127.0.0.1:50051`, routing Docker requests to WSL2 |
| Remote SSH / gRPC | Settings page → "Remote SSH / gRPC" + SSH target | Daemon reached through a pre-opened loopback SSH tunnel; Docker `host` is the SSH target |

The `DependencyManager` on the Settings page detects and installs:
- **WSL2** via `winget install Microsoft.WSL`
- **Docker Desktop** via `winget install Docker.DockerDesktop`

It does **not** download or execute an unverified daemon. Automatic startup is allowed only when an
exact `colima-daemon.exe` file is installed beside the application, resolves inside that directory,
and is not a reparse point. The daemon is started with
`--listen tcp:127.0.0.1:50051`; non-loopback gRPC endpoints are rejected. Install the daemon through
the trusted application package or a documented local build/package process.

## CONTRACT coverage

All CONTRACT v1 surfaces are bound to gRPC calls. See [`RPC_AUDIT.md`](RPC_AUDIT.md) for the exact
65-RPC inventory, frozen-message provider limitations, and evidence boundary.

| CONTRACT section | Covered |
|-----------------|---------|
| Part A — VM lifecycle (start/stop/restart/delete/status/version/update/prune) | ✅ DashboardPage |
| Part A — SSH config | ✅ DashboardPage |
| Part A — Profiles (list/create/delete/clone) | ✅ ProfilesPage |
| Part A — Machines (ListMachines) | ✅ MachinesPage |
| Part A — Config (GetConfig/SetConfig/GetTemplate/SetTemplate) | ✅ ConfigurationPage |
| Part A — Kubernetes (start/stop/reset/exec) | ✅ KubernetesPage |
| Part A — AI Models (setup/run/serve/stop) | ✅ AIWorkloadsPage |
| Part A — Runtime (switch/update) | ✅ RuntimePage |
| Part A — Monitoring (VMStats stream/ProcessList/KillProcess) | ✅ MonitoringPage |
| Part B — Containers (16 operations) | ✅ ContainersPage |
| Part B — Images (9 operations) | ✅ ImagesPage |
| Part B — Volumes (5 operations) | ✅ VolumesPage |
| Part B — Networks (7 operations) | ✅ NetworksPage |
| Part C — DependencyManager (WSL2/Docker install + trusted daemon detection) | ✅ SettingsPage |

## Deterministic tests

The headless project compiles all production service and view-model sources without launching
WinUI, then verifies payload scope, provider rejection, application-level response errors, busy
state, cancellation, confirmation decisions, and loopback enforcement:

```powershell
dotnet test Tests/ColimaDesktop.Windows.Tests.csproj
```

## AutomationProperties

Every interactive control carries `AutomationProperties.Name` for UI Automation testability (per
`native-windows-winui` skill). Navigation items are named `NavDashboard`, `NavContainers`, etc.
Buttons follow the pattern `BtnStartVM`, `BtnRefreshContainers`, etc.

## Notes

- XAML binding uses `x:Bind` (compile-time) throughout for type safety and performance.
- ViewModels use `CommunityToolkit.Mvvm` source generators (`[ObservableProperty]`,
  `[RelayCommand]`). No manual `INotifyPropertyChanged` boilerplate.
- Streaming RPCs (Start, Restart, PullImage, PushImage, VMStats, ModelSetup, ModelRun,
  StreamEvents, StreamLogs, StreamStats) consume `AsyncServerStreamingCall<T>` with cancellation
  propagated into gRPC and page-lifecycle cleanup.
- The `DaemonClient` lazily creates the gRPC channel and supports `Reconnect(address)` to
  switch backends without restarting the app.

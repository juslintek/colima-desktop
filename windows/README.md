# Colima Desktop — Windows (WinUI 3)

Native Windows frontend (WinUI 3 / WinRT, C#). Talks to the shared Go daemon over
gRPC (`grpc-dotnet`). Supports a **remote** colima/Lima host (SSH/gRPC) and a **local
WSL2/Docker** engine (CONTRACT v1, choice 2=c).

> Platform-gated: builds only on Windows with the Windows App SDK. Not compilable on the
> macOS CI host — verified by the `windows-native-dev` agent / GitHub Actions `windows-latest`.

## Prerequisites
- Windows 10 19041+ / Windows 11
- .NET 8 SDK, Windows App SDK 1.5+
- `dotnet workload install winui` (or Visual Studio 2022 with WinUI workload)
- `protoc` + `Grpc.Tools` (restored via NuGet from `Proto/colima_ui.proto`)

## Build & run
```powershell
dotnet restore
dotnet build -c Debug
dotnet run --project ColimaDesktop.Windows.csproj
```

## Architecture
- `Services/DaemonClient.cs` — grpc-dotnet client for ColimaService + DockerService.
- `Views/` — NavigationView surfaces mirroring the SwiftUI app (Dashboard, Containers,
  Images, Volumes, Networks, Kubernetes, Profiles, Configuration, AI, Monitoring, Machines,
  Runtime Controls, Community) + a remote/WSL2 backend toggle.
- `Proto/colima_ui.proto` — copied from repo root `proto/` at build (Grpc.Tools codegen).

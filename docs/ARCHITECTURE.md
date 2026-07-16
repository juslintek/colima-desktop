# Architecture

## Overview

Colima Desktop follows a **shared-daemon, native-frontend** architecture. A single Go
daemon exposes a gRPC API that every frontend (macOS, Windows, Linux, TUI) consumes.
This ensures identical behavior across platforms while allowing each frontend to use its
platform's native UI toolkit.

```
              ┌──────────────────────────────────────────────┐
   SwiftUI ──▶│                                              │
   WinUI 3 ──▶│   colima-daemon (Go, gRPC over Unix socket)  │──▶ colima CLI
   GTK4    ──▶│   Providers: local · remote-SSH · WSL2        │──▶ limactl
   TUI     ──▶│                                              │──▶ Docker socket
              └──────────────────────────────────────────────┘
```

---

## Components

### 1. Daemon (`daemon/`)

The daemon is a Go binary that listens on a Unix socket (or TCP) and serves two gRPC
services defined in `proto/colima_ui.proto`:

- **ColimaService** (22 RPCs) — VM lifecycle, profiles, SSH, configuration, Kubernetes,
  AI models, runtime management, and monitoring.
- **DockerService** (31 RPCs) — container, image, volume, and network CRUD plus
  streaming (events, logs, stats).

The daemon wraps:
- `colima` CLI (via `github.com/abiosoft/colima/app`) for VM operations
- Direct Docker API access (via HTTP over Unix socket) for container resources
- `kubectl` CLI for Kubernetes exec

**Key design choices:**
- Stateless — all state lives in Colima/Lima/Docker; the daemon is a pass-through.
- Provider pattern — `docker.Target{Profile, Host, WSL2}` selects the Docker endpoint.
- Graceful shutdown on SIGINT/SIGTERM.
- bufconn-based integration tests (no real socket needed).

### 2. macOS Frontend (`Sources/`)

Native SwiftUI application structured as a framework + thin app shell:

```
Sources/
├── App/            AppState (single source of truth), AppDelegate
├── Services/       ServiceProvider protocol, RealServiceProvider, DaemonClient, DockerClient
├── Models/         Data models, ColimaConfig, MockData
├── Views/          SwiftUI views organized by feature
│   ├── Dashboard/
│   ├── Containers/
│   ├── Images/
│   ├── Volumes/
│   ├── Networks/
│   ├── Kubernetes/
│   ├── Profiles/
│   ├── Machines/
│   ├── Configuration/
│   ├── Monitoring/
│   ├── AI/
│   ├── RuntimeControls/
│   └── Components/    Shared sheets, command palette, tooltips
└── Main/           @main entry point
```

**Architecture decisions:**
- **ColimaDesktopKit framework** — all logic lives here. The app target is just
  `@main` + assets. This avoids the Xcode-26 "test runner hung" bug by allowing
  tests to link the framework directly.
- **ServiceProvider protocol** — abstracts backend access. In production,
  `RealServiceProvider` calls the daemon. In tests, `MockServiceProvider` is used.
- **AppState** — single `@ObservableObject` holding all application state, injected
  as `@EnvironmentObject` into the view hierarchy.
- **Direct Docker API** — on macOS, `DockerClient` speaks to the Docker socket
  directly (no daemon needed for Docker ops), providing the lowest-latency path.

### 3. Windows Frontend (`windows/`)

WinUI 3 application using the Windows App SDK (.NET 8):

- `DaemonClient.cs` — gRPC client over TCP (`grpc-dotnet`).
- Proto stubs generated at build time via `Grpc.Tools`.
- Targets remote Colima hosts (SSH tunnel) or local WSL2/Docker.

### 4. Linux Frontend (`linux/`)

GTK4 application written in Rust:

- `tonic` gRPC client connecting to the local daemon.
- `tonic-build` generates stubs from the shared proto at compile time.
- 13 UI surfaces defined in a `GtkStack` (placeholder).

### 5. TUI (`tui/`)

Terminal interface built with [Bubble Tea](https://github.com/charmbracelet/bubbletea):

- 7-tab layout: Dashboard, Containers, Images, Volumes, Networks, Profiles, Machines.
- Same gRPC client (`tui/internal/client`) as other frontends.
- Designed for headless/SSH environments.

---

## Proto Contract

`proto/colima_ui.proto` is the **single source of truth** for the daemon API.
It is frozen at CONTRACT v1 (2026-07-14). Changes require a version bump and
multi-team acknowledgment.

Services:
- `ColimaService` — 22 RPCs (unary + server-streaming)
- `DockerService` — 31 RPCs (unary + server-streaming)

All frontends generate client stubs from this proto:
- Go: `protoc-gen-go` + `protoc-gen-go-grpc`
- C#: `Grpc.Tools` (build-time codegen)
- Rust: `tonic-build`

---

## Data Flow

### Read operation (e.g., list containers)

```
Frontend → gRPC call (ListContainers) → Daemon
  Daemon → Docker HTTP API (GET /containers/json) → Docker Engine
  Daemon ← JSON response ← Docker Engine
Frontend ← JsonResponse (raw JSON string) ← Daemon
  Frontend → parse JSON → render in UI
```

### Write operation (e.g., start VM)

```
Frontend → gRPC call (Start, streaming) → Daemon
  Daemon → colima app.Start(config) → Colima/Lima
  Daemon → ProgressEvent stream → Frontend
Frontend → update UI progress bar
  Daemon → final ProgressEvent{Done: true} → Frontend
```

### Streaming (e.g., container stats)

```
Frontend → gRPC call (StreamStats, server-streaming) → Daemon
  Daemon → Docker HTTP API (GET /containers/{id}/stats?stream=1) → Docker
  Daemon ← chunk ← Docker (repeating)
  Daemon → JsonResponse per chunk → Frontend
Frontend → parse + render real-time chart
```

---

## Testing Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  XCUITest (UI)              — Full E2E with running app          │
├─────────────────────────────────────────────────────────────────┤
│  Snapshot Tests             — Visual regression (light/dark)     │
├─────────────────────────────────────────────────────────────────┤
│  Integration Tests          — ViewInspector, view logic          │
├─────────────────────────────────────────────────────────────────┤
│  Unit Tests                 — AppState, models, validation       │
├─────────────────────────────────────────────────────────────────┤
│  Daemon Tests (bufconn)     — gRPC RPCs without real socket      │
├─────────────────────────────────────────────────────────────────┤
│  TUI Tests                  — Bubble Tea model test              │
└─────────────────────────────────────────────────────────────────┘
```

- macOS uses `--ui-testing` launch argument to inject `MockServiceProvider`
- Daemon tests use `bufconn` (in-memory gRPC transport)
- Real-backend tests run against a dedicated `desktop-e2e` Colima profile

---

## Key Design Principles

1. **Native first** — no Electron, no cross-platform UI frameworks. Each platform
   uses its native toolkit for best performance and OS integration.
2. **Shared contract** — the proto is the single source of truth. All platforms
   implement the same surface.
3. **Stateless daemon** — no database, no persistent state in the daemon itself.
   All state is held by Colima, Lima, Docker, and Kubernetes.
4. **Test pyramid** — fast unit tests at the base, expensive E2E at the top.
5. **Mock-first UI development** — views can be developed and tested without a
   running backend using mock data.

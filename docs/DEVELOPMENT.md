# Development Guide

This guide covers day-to-day development workflows for each component of Colima Desktop.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/juslintek/colima-desktop.git
cd colima-desktop

# Build everything (macOS)
make build

# Run tests
make test

# Start developing
make daemon    # start daemon in background
make run       # launch the macOS app
```

---

## Repository Layout

```
.
├── daemon/             Go gRPC daemon
│   ├── cmd/            Entry point (main.go)
│   ├── internal/
│   │   ├── server/     ColimaServer + DockerServer implementations
│   │   └── docker/     Docker API client (HTTP over socket)
│   └── proto/          Generated Go stubs
├── Sources/            macOS SwiftUI app
│   ├── App/            AppState, AppDelegate
│   ├── Services/       ServiceProvider, DaemonClient, DockerClient
│   ├── Models/         Data models + mock data
│   └── Views/          Feature-organized SwiftUI views
├── Tests/              macOS test suites
│   ├── Unit/           Swift Testing
│   ├── Integration/    ViewInspector
│   ├── Snapshot/       swift-snapshot-testing
│   ├── UI/             XCUITest
│   └── Support/        Shared test helpers
├── tui/                Bubble Tea terminal UI
├── windows/            WinUI 3 frontend
├── linux/              GTK4/Rust frontend
├── proto/              Source-of-truth protobuf definitions
├── scripts/            Build, packaging, CI scripts
├── packaging/          Info.plist, entitlements, DMG config
└── docs/               Documentation
```

---

## Daemon Development

### Build and run

```bash
cd daemon
go build -o ../build/colima-daemon ./cmd
../build/colima-daemon --socket /tmp/colima-desktop.sock
```

### Regenerate proto stubs

When `proto/colima_ui.proto` changes:

```bash
make proto
# or manually:
protoc --go_out=daemon --go-grpc_out=daemon proto/colima_ui.proto
```

### Run tests

```bash
cd daemon
go test ./...
```

Tests use `bufconn` for in-memory gRPC transport — no running daemon needed.

### Adding a new RPC

1. Define the RPC in `proto/colima_ui.proto`
2. Run `make proto` to regenerate stubs
3. Implement in `daemon/internal/server/server.go` (ColimaService) or
   `daemon/internal/server/docker_server.go` (DockerService)
4. Add a test in the corresponding `_test.go` file
5. Update `docs/parity-matrix.md` with the new row

---

## macOS Frontend Development

### Setup

```bash
brew install xcodegen
xcodegen generate    # creates ColimaDesktop.xcodeproj
open ColimaDesktop.xcodeproj
```

### Build from command line

```bash
make app
# or:
xcodegen generate
xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -quiet
```

### Running with mock data

The app detects `--ui-testing` or `--backend-mock` in launch arguments and uses
`MockServiceProvider` instead of connecting to the real daemon. This is useful for
UI development without needing Colima running.

In Xcode: Edit Scheme → Run → Arguments → Add `--backend-mock`.

### Testing

```bash
make test-unit          # Swift Testing (fast, ~1s)
make test-integration   # ViewInspector (view logic, ~10s)
make test-snapshots     # Visual regression (light/dark, ~3s)
make test-ui            # XCUITest E2E (requires app launch, ~60s)
make test               # unit + integration (default)
```

### Code organization rules

- **One view per file**, max 200 lines. Extract subviews as needed.
- **All interactive elements** must have `.accessibilityIdentifier()`.
- **State** flows through `AppState` (`@EnvironmentObject`).
- **ID naming**: `tab_containers`, `btn_start_vm_dashboard`, `field_config_cpus`.

### Adding a new view

1. Create `Sources/Views/<Feature>/<Feature>View.swift`
2. Add navigation entry in `Sources/Views/ContentView.swift`
3. Wire actions through `AppState` → `ServiceProvider`
4. Add mock data in `Sources/Models/MockData.swift` if needed
5. Write unit test for any state logic
6. Write integration test with ViewInspector for view behavior

---

## TUI Development

### Build and run

```bash
cd tui
go build -o colima-tui .
./colima-tui --socket /tmp/colima-desktop.sock
```

The TUI requires a running daemon. Start one first:
```bash
./build/colima-daemon &
```

### Architecture

- `internal/ui/model.go` — Bubble Tea model (tabs, state, rendering)
- `internal/client/client.go` — gRPC client wrapper
- `main.go` — entry point, connects client, launches program

### Adding a new tab/feature

1. Add the tab name to `Tabs` slice in `model.go`
2. Add a case in `loadTab()` to fetch data via the client
3. Add a renderer function for the tab content
4. Add keybindings in `Update()` for tab-specific actions

---

## Windows Development

### Requirements
- Windows 10/11
- Visual Studio 2022 or .NET 8 CLI
- Windows App SDK

### Build

```bash
cd windows
dotnet build
```

### Adding RPCs

1. The proto is at `windows/Proto/colima_ui.proto` (copy from root `proto/`)
2. Add wrapper method to `Services/DaemonClient.cs`
3. Build — stubs are auto-generated by `Grpc.Tools`

---

## Linux Development

### Requirements
- Rust 1.75+, Cargo
- GTK4 development libraries (`libgtk-4-dev`)
- protobuf compiler (`protoc`)

### Build

```bash
cd linux
cargo build
```

### Architecture
- `src/main.rs` — GTK4 application with Stack-based navigation
- `src/client.rs` — tonic gRPC client wrapper
- `build.rs` — tonic-build proto compilation
- `proto/colima_ui.proto` — copy from root `proto/`

---

## Working with the Proto

The proto file at `proto/colima_ui.proto` is the **contract**. It defines:
- Message types (request/response structures)
- Service interfaces (ColimaService, DockerService)
- Streaming RPCs (server-side streaming for long operations)

Each frontend has its own copy or reference to this proto and generates stubs in
its build system. When the proto changes:

1. Update `proto/colima_ui.proto`
2. Regenerate Go stubs: `make proto`
3. Copy to `windows/Proto/` and `linux/proto/` (or symlink)
4. Rebuild all affected frontends

---

## Debugging

### Daemon
```bash
# Run with verbose output
./build/colima-daemon --socket /tmp/colima-desktop.sock 2>&1 | tee /tmp/daemon.log

# Test a specific RPC with grpcurl
grpcurl -plaintext -unix /tmp/colima-desktop.sock colimaui.ColimaService/Version
```

### macOS app
- Use Xcode's debugger (breakpoints in SwiftUI views, AppState)
- Console.app for system logs from the app
- `--backend-mock` for testing UI without backend

### TUI
- Pass `TEA_LOG=/tmp/tui.log` to enable Bubble Tea debug logging
- The `r` key refreshes all data from the daemon

---

## CI/CD

- **macOS tests**: Run on every push via GitHub Actions (`xcodebuild test`)
- **Daemon tests**: `go test ./...` in CI
- **Release**: `make package-dmg` creates a notarized DMG (macOS)
- **Sparkle**: Auto-update via `appcast.xml` on GitHub Pages

---

## Code Style

- **Swift**: SwiftLint defaults, strict optionals, no force unwraps
- **Go**: `gofmt` + `go vet`, error wrapping with `fmt.Errorf`
- **Rust**: `cargo fmt` + `cargo clippy`
- **C#**: .NET conventions, nullable enabled

All code should compile warning-free.

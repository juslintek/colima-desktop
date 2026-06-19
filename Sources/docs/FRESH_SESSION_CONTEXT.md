# Colima Desktop — Backend Integration & Test Coverage

## What This Is

Colima Desktop is a native macOS SwiftUI app that provides a GUI for Colima (container runtime).
It talks to Docker Engine API over Unix socket (`~/.colima/<profile>/docker.sock`) — NO Docker Desktop needed.
Colima itself provides the Docker daemon inside a Linux VM.

## Current State

- App builds and runs (scheme: `ColimaDesktop`, dir: `/Volumes/Projects/colima-desktop`)
- 45 `if useMocks` branches in `Sources/App/AppState.swift` — mock mode fakes everything
- `RealServiceProvider` exists but is untested — wraps `DockerClient` (HTTP over Unix socket) + `DaemonClient` (colima CLI)
- host machine (`colima-test-vnc`) available via `ssh host` — has Xcode 26.4, macOS Tahoe
- Project mounted in VM at `/Volumes/My Shared Files/project/`
- Colima needs to be installed in VM: `brew install colima docker` (docker = CLI client only)

## Architecture

```
┌─────────────────────────────────────────────┐
│  Colima Desktop.app (SwiftUI)               │
│  └─ AppState → ServiceProvider protocol     │
│       ├─ MockServiceProvider (test fixtures) │
│       └─ RealServiceProvider                 │
│            ├─ DockerClient (HTTP/Unix sock)  │
│            └─ DaemonClient (colima CLI)      │
└─────────────────────────────────────────────┘
         │                        │
   Docker socket            colima CLI
   ~/.colima/default/       /usr/local/bin/colima
   docker.sock
         │
┌────────┴────────┐
│  Colima Linux VM │  ← `colima start` creates this
│  (containerd +   │
│   dockerd)       │
└─────────────────┘
```

## What Needs To Be Done

1. **VM Setup**: Install colima + docker CLI on host, `colima start`
2. **Fix DaemonClient**: Make it work without Go daemon — direct CLI fallback
3. **Real Backend Tests**: Test every operation against live Docker socket
4. **Remove mock branches**: AppState should use ServiceProvider protocol uniformly
5. **100% test coverage**: Unit + integration tests for all 78 operations

## Key Files

- `Sources/App/AppState.swift` — 1175 lines, 45 mock branches, 80+ methods
- `Sources/Services/ServiceProvider.swift` — protocol + RealServiceProvider
- `Sources/Services/DockerClient.swift` — HTTP client for Docker API v1.46
- `Sources/Services/DaemonClient.swift` — wraps `colima` CLI
- `Tests/Unit/AppStateTests.swift` — 17 tests (validation only)
- `Sources/docs/BACKEND_INTEGRATION_CHECKLIST.md` — 78-item checklist
- `project.yml` — XcodeGen spec (scheme: ColimaDesktop)

## Commands

```bash
# Build
xcodegen generate && xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -quiet

# Run unit tests
xcodebuild test -scheme ColimaDesktop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:ColimaDesktopUnitTests

# SSH to VM
ssh host

# Start VM if stopped
tart run colima-test-vnc --dir=project:/Volumes/Projects/colima-desktop --vnc > /tmp/tart-run.log 2>&1 &

# In VM: install colima
brew install colima docker

# In VM: start colima (creates Docker socket)
colima start --vm-type vz --mount-type virtiofs
```

## Rules

- NEVER install Docker Desktop — Colima IS the Docker runtime
- NEVER run XCUITests on host — only on host
- NEVER run long processes in foreground — background with &
- Module import: `@testable import ColimaDesktop`
- Docker socket path: `~/.colima/<profile>/docker.sock`

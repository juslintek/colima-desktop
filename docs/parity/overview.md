# Parity Overview

This document explains the CLI-parity model used to track feature completeness across
Colima Desktop's four frontends.

## What Is CLI Parity?

CLI parity means every operation available via the `colima` command line is also
accessible through the graphical/terminal interfaces. The goal: a user should never
need to drop to a terminal for basic Colima operations.

## The Contract

The frozen API contract (`.kiro/board/CONTRACT.md`) defines 53 operations organized
into three parts:

| Part | Description | RPC Count |
|------|-------------|:---------:|
| **A** | Colima operations (VM, SSH, Profiles, Config, K8s, AI, Runtime, Monitoring) | 22 |
| **B** | Docker resource operations (Containers, Images, Volumes, Networks, Streams) | 31 |
| **C** | Installation/turnkey (detect, install, auto-update) | — |

Parts A and B are exposed as gRPC services in `proto/colima_ui.proto`. Part C is
implemented per-platform (native package managers).

## Frontend Status

| Frontend | Toolkit | Connection | Coverage |
|----------|---------|------------|:--------:|
| macOS | SwiftUI | Direct (colima CLI + Docker socket) | 100% |
| Windows | WinUI 3 / .NET 8 | gRPC over TCP | 6% |
| Linux | GTK4 / Rust | gRPC over Unix socket | 4% |
| TUI | Bubble Tea / Go | gRPC over Unix socket | 9% |

See [gap-report.md](../gap-report.md) for the detailed per-frontend analysis.

## The Parity Matrix

The [parity-matrix.md](../parity-matrix.md) is the authoritative tracking document.
It maps each CLI command to:

1. The backend RPC it requires
2. The Swift `ServiceProvider` method
3. The UI surface where it appears
4. Per-frontend implementation status (✅ done / 🟡 partial / ⬜ todo)
5. The test that verifies it

## How Parity Is Verified

### Static analysis (current)
Source code is analyzed to determine which gRPC RPCs each frontend's client wires up,
and which UI surfaces exist for user interaction.

### Runtime verification (M3.9, planned)
Per-platform UI explorers traverse the accessibility tree of running applications to
produce `ground-truth.json` files documenting actual UI elements:
- **macOS**: AXUIElement traversal
- **Windows**: UIA (Microsoft UI Automation)
- **Linux**: AT-SPI2 (dogtail/pyatspi)
- **TUI**: teatest golden-file comparison

### Test coverage
The macOS frontend has a comprehensive test suite:
- Unit tests (Swift Testing) — AppState logic
- Integration tests (ViewInspector) — view rendering
- Snapshot tests — visual regression
- XCUITest E2E — full user flows

Other frontends have minimal test coverage currently.

## Categories

The parity matrix is organized into these categories:

| ID | Category | Key Operations |
|----|----------|---------------|
| A | VM lifecycle | start, stop, restart, delete, status, version, update, prune |
| B | SSH / Profiles | ssh-config, list, create, delete, clone, machines |
| C | Configuration | read config, write config, templates |
| D | Kubernetes | start, stop, reset, exec |
| E | Docker resources | containers, images, volumes, networks (full CRUD) |
| F | AI models | list, pull, run, serve, stop |
| G | Runtime / Monitoring | switch runtime, process list, kill, VM stats |
| H | Turnkey / Install | detect colima, install, dependency management |

## Achieving Parity

The path to 100% parity on each frontend:

1. **Wire the gRPC client** — connect to each RPC the daemon exposes
2. **Build UI surfaces** — create views/pages for each operation category
3. **Add user interactions** — buttons, forms, keybindings for write operations
4. **Implement streaming** — progress bars, live logs, real-time stats
5. **Test** — unit + integration + E2E verification
6. **Document** — update the parity matrix as each feature lands

## Related Documents

- [Parity Matrix](../parity-matrix.md) — detailed per-row tracking
- [Gap Report](../gap-report.md) — analysis of current gaps
- [Architecture](../ARCHITECTURE.md) — system design
- [CONTRACT](.kiro/board/CONTRACT.md) — frozen API surface

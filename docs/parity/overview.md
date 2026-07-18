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
implemented per-platform (native package managers / DependencyManager).

## Four Parity Dimensions

Parity is not binary. Each frontend is assessed across four independent dimensions:

| Dimension | macOS | Windows | Linux | TUI |
|-----------|:-----:|:-------:|:-----:|:---:|
| **Compile** (CI green) | ✅ | ✅ | ✅ | ✅ |
| **Surface presence** (runtime-verified) | 13/13 ✅ | 13/13 ✅ | 12/12 ✅ | 12/12 ✅ |
| **Interaction coverage** (source + AX) | ~95% ✅ | ~20% 🟡 | ~15% 🟡 | ~25% 🟡 |
| **Backend-connected runtime** | ✅ Live | ❌ Not verified | ❌ Not verified | ❌ fakeDS |

Surface presence is runtime-verified from `exploration/ground-truth.json` (M3.9
artifacts). All 12 CONTRACT-required surfaces are present on all 4 platforms.
Two additional platform-specific extras exist: Community (macOS), Settings (Windows).

## Frontend Status

| Frontend | Toolkit | Connection | Compile | Surfaces | Backend |
|----------|---------|------------|:-------:|:--------:|:-------:|
| macOS | SwiftUI + AppKit | Direct (colima CLI + Docker socket) | ✅ | 13/13 | ✅ Live |
| Windows | WinUI 3 / .NET 8 | gRPC over TCP | ✅ | 13/13 | ❌ CI only |
| Linux | GTK4 / Rust | gRPC over Unix socket | ✅ | 12/12 | ❌ CI only |
| TUI | Bubble Tea / Go | gRPC over Unix socket | ✅ | 12/12 | ❌ fakeDS |

All CONTRACT surfaces present on all platforms. Linux and TUI have 12 surfaces
(matching the 12 CONTRACT-required capabilities); macOS and Windows include
platform-specific extras (community, settings).

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

### Compile parity (CI)
`frontends.yml` GitHub Actions — all 9 jobs green (run 29635550954). Builds daemon,
TUI, macOS Kit tests, WinUI 3, and GTK4 on their respective native runners.

### Surface presence (M3.9 runtime captures)
Per-platform UI explorers traverse the accessibility tree / UIA tree / AT-SPI tree
of running applications and produce `ground-truth.json` files. These are the
authoritative surface inventories:

- **macOS** (`exploration/macos/ground-truth.json`): AXUIElement traversal +
  Peekaboo fallback. 13 surfaces, 1,847 AX elements. **Live backend** (colima 0.10.1).
- **Windows** (`exploration/windows/ground-truth.json`): FlaUI/UIA3 traversal.
  13 surfaces, 699 UIA elements. CI runner, no live daemon.
- **Linux** (`exploration/linux/ground-truth.json`): pyatspi DFS + xdotool grid.
  12 surfaces, 887 AT-SPI elements. CI runner, no live daemon. colima shimmed.
- **TUI** (`exploration/tui/ground-truth.json`): PTY screenshots + fakeDS.
  12 surfaces, all fingerprints unique. No live daemon; stub data.

The unified summary is in `exploration/ground-truth.json` (M3.10 artifact).

### Interaction coverage (source analysis + AX interactive roles)
Beyond presence, each surface's interactive elements (buttons, forms, key-bindings)
are assessed to determine which CONTRACT operations are user-actionable. macOS has
live-backend verification; others rely on XAML/Rust/Go source analysis.

### Backend-connected runtime behavior
Only macOS has a live-backend ground-truth capture. Windows, Linux, and TUI need a
running colima daemon to verify this dimension. The `desktop-e2e` colima profile
pattern (used for macOS Swift tests) can be replicated per-platform.

### Test coverage
The macOS frontend has a comprehensive test suite (74.2% coverage with live e2e,
71.9% headless): unit (Swift Testing), integration (ViewInspector), snapshot tests,
and XCUITest E2E. Other frontends have minimal test coverage currently.

## Canonical Surface List

Twelve surfaces are present across all four platforms (runtime-confirmed):

| # | Surface | CONTRACT Part |
|---|---------|:-------------:|
| 1 | Dashboard | A (VM status) |
| 2 | Containers | B (Docker) |
| 3 | Images | B (Docker) |
| 4 | Volumes | B (Docker) |
| 5 | Networks | B (Docker) |
| 6 | Kubernetes | A |
| 7 | Configuration | A |
| 8 | Machines | A |
| 9 | Profiles | A |
| 10 | AI Workloads | A |
| 11 | Runtime | A |
| 12 | Monitoring | A |

Two additional platform-specific surfaces: Community (macOS-only extra),
Settings (Windows-only extra).

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
2. **Build UI surfaces** — all 12 CONTRACT surfaces are now present ✅
3. **Add user interactions** — buttons, forms, keybindings for write operations
4. **Implement streaming** — progress bars, live logs, real-time stats
5. **Test** — unit + integration + live-backend E2E verification
6. **Document** — update the parity matrix as each feature lands

## Related Documents

- [Parity Matrix](../parity-matrix.md) — detailed per-row tracking
- [Gap Report](../gap-report.md) — analysis of current gaps
- [Architecture](../ARCHITECTURE.md) — system design
- [CONTRACT](../../.kiro/board/CONTRACT.md) — frozen API surface
- [exploration/ground-truth.json](../../exploration/ground-truth.json) — unified runtime artifact (M3.10)

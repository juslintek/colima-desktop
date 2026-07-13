<div align="center">

# Colima Desktop

**A free, open-source, native desktop & terminal UI for [Colima](https://github.com/abiosoft/colima) — a genuine OrbStack alternative.**

Manage container VMs, Docker, Kubernetes, profiles, and AI workloads across macOS, Windows, and Linux — plus a full-featured TUI.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20TUI-blue)
![Status](https://img.shields.io/badge/status-pre--v1-orange)

</div>

## Why Colima Desktop?

Colima is a fantastic, free container runtime — but it's CLI-only. Colima Desktop gives it a
first-class graphical and terminal experience, targeting parity with (and a free alternative to)
OrbStack:

- **Native everywhere** — SwiftUI on macOS, WinUI 3 on Windows, GTK4 on Linux, Bubble Tea in the terminal. No Electron, zero overhead.
- **One backend brain** — a shared Go daemon (gRPC) drives every frontend identically.
- **Full CLI parity** — everything `colima` can do, from a UI: VM lifecycle, profiles, Docker, Kubernetes (k3s), configuration, networking, runtimes, and AI models.
- **Turnkey** — auto-installs and auto-updates Colima and its dependencies on first launch.
- **Remote + local** — manage a local machine or a remote colima/Lima host over SSH; on Windows, drive local WSL2/Docker too.

## Architecture

```
              ┌──────────────────────────────────────────────┐
   SwiftUI ──▶│                                              │
   WinUI 3 ──▶│   colima-daemon (Go, gRPC: colima_ui.proto)  │──▶ colima / limactl / kubectl
   GTK4    ──▶│   providers: local · remote-SSH · WSL2/Docker│──▶ Docker API (socket/npipe)
   TUI     ──▶│                                              │
              └──────────────────────────────────────────────┘
```

## Status

Pre-v1, under active (autonomous) development. See [`.kiro/board/PLAN.md`](.kiro/board/PLAN.md)
for the live roadmap and [`docs/`](docs/) for design/testing notes. Full install docs, screenshots,
and release binaries land at the v1 tag.

## Building (macOS, today)

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS'
```

## Contributing

Contributions are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) (published at v1) and the
roadmap in [`.kiro/board/PLAN.md`](.kiro/board/PLAN.md). This project follows trunk-based development
and conventional commits.

## License

[MIT](LICENSE) © Linas Jusys and contributors.

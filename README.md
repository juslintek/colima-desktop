<div align="center">

# Colima Desktop

**A free, open-source, native desktop & terminal UI for [Colima](https://github.com/abiosoft/colima) — a genuine OrbStack alternative.**

Manage container VMs, Docker, Kubernetes, profiles, and AI workloads across macOS, Windows, and Linux — plus a full-featured TUI.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20TUI-blue)
![Version](https://img.shields.io/badge/version-v1.0.0-blue)
[![Website](https://img.shields.io/badge/website-colima--desktop-6366f1)](https://juslintek.github.io/colima-desktop/)

</div>

## Links

- **Website:** https://juslintek.github.io/colima-desktop/
- **Downloads:** [Releases](https://github.com/juslintek/colima-desktop/releases)
- **Install guide:** [docs/INSTALL.md](docs/INSTALL.md)
- **Signing & trust:** [docs/SIGNING.md](docs/SIGNING.md)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md)

## Why Colima Desktop?

Colima is a fantastic, free container runtime — but it's CLI-only. Colima Desktop gives it a
first-class graphical and terminal experience, targeting parity with (and a free alternative to)
OrbStack:

- **Native everywhere** — SwiftUI on macOS, WinUI 3 on Windows, GTK4 on Linux, Bubble Tea in the terminal. No Electron, zero overhead.
- **One backend brain** — a shared Go daemon (gRPC) drives every frontend identically.
- **Full CLI parity** — everything `colima` can do, from a UI: VM lifecycle, profiles, Docker, Kubernetes (k3s), configuration, networking, runtimes, and AI models.
- **Dependency-aware** — detects `colima`, `lima`, `qemu`, `krunkit`, `docker-cli`, and `kubectl`, and offers an install path for anything missing.
- **Auto-updating on macOS** — the app checks for updates via Sparkle over a GitHub-hosted appcast.
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

Five shipped components: the four native frontends plus the shared Go daemon. The daemon exposes the
frozen v1 gRPC contract (31 `ColimaService` RPCs + 34 `DockerService` RPCs); every frontend is a
client of it. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## Download & Install

Releases are published to [GitHub Releases](https://github.com/juslintek/colima-desktop/releases)
when a `vX.Y.Z` tag is pushed. `v1.0.0` is the first fully cross-platform release. Each release
provides the following per-platform artifacts (`<version>` = the release version, e.g. `1.0.0`):

| Platform | Artifact(s) | Install |
|----------|-------------|---------|
| **macOS** | `Colima Desktop-<version>.dmg`, `ColimaDesktop-<version>-macos.app.zip` | Open the `.dmg`, drag the app to Applications. |
| **Windows** | `ColimaDesktop-<version>-windows-x64.zip` | Extract, run `ColimaDesktop.Windows.exe`. |
| **Linux** | `colima-desktop-<version>-linux-<arch>.tar.gz`, `colima-desktop_<version>_<debarch>.deb` | `tar xzf` and run, or `sudo apt install ./<file>.deb`. |
| **Daemon / TUI** | `colima-daemon-<version>-macos-universal`, `colima-tui-<version>-macos-universal` | Standalone binaries (bundled inside the macOS app). |
| **Checksums / SBOM** | `SHA256SUMS.txt`, `release-manifest.json`, `colima-desktop-<version>-sbom.tar.gz` | Verify downloads (below). |

Colima itself is a prerequisite on every platform. Full per-platform steps, prerequisites, and
build-from-source instructions are in **[docs/INSTALL.md](docs/INSTALL.md)**; the exact artifact
matrix is in **[docs/release-artifacts.md](docs/release-artifacts.md)**.

### Verify your download

Every release includes a `SHA256SUMS.txt` manifest. Check integrity before running:

```bash
# macOS / Linux
shasum -a 256 -c SHA256SUMS.txt        # or: sha256sum -c SHA256SUMS.txt
```
```powershell
# Windows
Get-FileHash -Algorithm SHA256 ColimaDesktop-<version>-windows-x64.zip
# ...compare against SHA256SUMS.txt (or release-manifest.json)
```

### Signing & trust (honest state)

Code signing is **credential-gated**: when the maintainer's signing secrets are configured in CI, the
release pipeline signs artifacts and **verifies** the signatures — macOS Developer ID + notarization,
Windows Authenticode, Linux GPG. Until those secrets are set, released artifacts are built **unsigned
but labeled honestly** (`UNSIGNED — signing credential <NAME> absent` in `release-manifest.json`); no
signature is ever faked and no private key is committed. In the unsigned state, verify downloads by
checksum, and expect an OS trust prompt (macOS Gatekeeper, Windows SmartScreen "unknown publisher").
The per-platform install and trust behavior, the required secrets, and the exact verification commands
are documented in **[docs/SIGNING.md](docs/SIGNING.md)**.

### Auto-update (macOS)

The macOS app auto-updates via [Sparkle](https://sparkle-project.org). The Ed25519 appcast key is real
and wired into the app (`SUPublicEDKey` in the bundle); the release pipeline publishes a signed
`appcast.xml` when the Sparkle signing secret is present in CI. The app checks the feed on launch.

## Status

`v1.0.0` release engineering is complete; the pipeline builds and checksums every component on a
version tag, gated on the release-candidate checks (all 9 `frontends.yml` jobs + `test.yml` +
`scripts/verify.sh` + security/perf/accessibility gates).

Verification depth is honest and platform-bounded (the verification host is macOS-only):

- **macOS** — the reference frontend, verified live against a real Colima backend from a disposable
  `desktop-e2e` profile (all 12 canonical surfaces, real resource creation).
- **Windows & Linux** — parity is proven through green CI (native WinUI 3 / GTK 4 compile + the
  deterministic test suites on their own runners). Live GUI-vs-live-backend capture is
  environment-blocked on a macOS-only host and labeled as such. See
  [docs/windows-linux-parity-evidence.md](docs/windows-linux-parity-evidence.md).

The roadmap lives in [`.kiro/board/PLAN.md`](.kiro/board/PLAN.md).

## Build from source

Quick macOS build (full per-platform instructions in [docs/INSTALL.md](docs/INSTALL.md)):

```bash
brew install xcodegen
xcodegen generate
xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS'
```

The Go daemon and TUI build with `go build` from `daemon/` and `tui/`; the Windows frontend builds
with `dotnet` (Windows), and the Linux frontend with `cargo` (GTK4 dev libraries required).

## Contributing

Contributions are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the roadmap in
[`.kiro/board/PLAN.md`](.kiro/board/PLAN.md). This project follows trunk-based development and
conventional commits.

## License

[MIT](LICENSE) © Linas Jusys and contributors.

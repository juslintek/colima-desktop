# Installation

Colima Desktop provides native applications for macOS, Windows, and Linux, plus a
cross-platform terminal UI. All frontends communicate with a shared Go daemon over gRPC.

## Prerequisites

### All platforms
- [Colima](https://github.com/abiosoft/colima) v0.8+ installed and accessible in `$PATH`
- A running Colima instance (or the app's onboarding will offer to install it)

### macOS
- macOS 14 (Sonoma) or later
- Xcode 15+ (for building from source)
- Go 1.21+ (for building the daemon)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Windows
- Windows 10 1809+ or Windows 11
- .NET 8 SDK
- Windows App SDK 1.5+
- Colima reachable via SSH tunnel or WSL2 (Windows does not run Colima natively)

### Linux
- GTK4 4.12+ development libraries
- Rust 1.75+ and Cargo
- protobuf compiler (`protoc`)
- Colima installed locally

### TUI (any platform)
- Go 1.21+
- Terminal with 256-color support recommended

---

## Install from Release (recommended)

Releases are published to [GitHub Releases](https://github.com/juslintek/colima-desktop/releases)
when a `vX.Y.Z` tag is pushed; `v1.0.0` is the first fully cross-platform release. Below, `<version>`
is the release version (e.g. `1.0.0`) and `<arch>`/`<debarch>` is your CPU architecture
(`arm64`/`amd64`, Debian `arm64`/`amd64`). The full artifact matrix is in
[release-artifacts.md](release-artifacts.md).

- **macOS**: download `Colima Desktop-<version>.dmg` (or `ColimaDesktop-<version>-macos.app.zip`),
  open it, and drag **Colima Desktop** to Applications.
- **Windows**: download `ColimaDesktop-<version>-windows-x64.zip`, extract it, and run
  `ColimaDesktop.Windows.exe`. (A self-contained `.zip` — there is no MSIX installer.)
- **Linux**: download `colima-desktop-<version>-linux-<arch>.tar.gz` (relocatable) or
  `colima-desktop_<version>_<debarch>.deb` (system-wide). (A `.tar.gz`/`.deb` — there is no Flatpak
  or AppImage.)

  ```bash
  # tar.gz (no root)
  tar xzf colima-desktop-<version>-linux-<arch>.tar.gz
  ./colima-desktop-<version>-linux-<arch>/colima-desktop

  # .deb (system-wide; resolves GTK deps)
  sudo apt install ./colima-desktop_<version>_<debarch>.deb
  ```
- **Daemon / TUI**: standalone binaries `colima-daemon-<version>-macos-universal` and
  `colima-tui-<version>-macos-universal` are attached to the release (the daemon is also bundled
  inside the macOS app). The daemon cross-builds for macOS, Linux, and Windows in CI; the Windows
  and Linux frontends bundle/launch or connect to their own daemon (loopback TCP on Windows, local
  socket on Linux).

### Verify your download

Every release ships a `SHA256SUMS.txt` manifest (and a machine-readable `release-manifest.json`).
Check integrity before running:

```bash
# macOS / Linux
shasum -a 256 -c SHA256SUMS.txt        # or: sha256sum -c SHA256SUMS.txt
```
```powershell
# Windows
Get-FileHash -Algorithm SHA256 ColimaDesktop-<version>-windows-x64.zip
# ...compare against SHA256SUMS.txt (or release-manifest.json)
```

### Signing & trust

Code signing is **credential-gated and honest**. When the maintainer's signing secrets are
configured, the pipeline signs and verifies each artifact (macOS Developer ID + notarization,
Windows Authenticode, Linux GPG); until then, artifacts are built **unsigned but labeled**
(`UNSIGNED — signing credential <NAME> absent` in `release-manifest.json`) — never a faked signature.
In the unsigned state you may see a trust prompt:

- **macOS** — Gatekeeper blocks an unsigned/un-notarized app. Verify by checksum first; a
  signed+notarized build opens without a warning.
- **Windows** — SmartScreen shows an "unknown publisher" warning for the unsigned `.exe`; choose
  **More info → Run anyway** after verifying the checksum.
- **Linux** — verify the detached GPG signature (`<artifact>.asc`) against the maintainer key when
  present, otherwise verify by checksum.

The exact per-platform signing, install, trust behavior, and verification commands (including
`signtool verify` and `gpg --verify`) are documented in **[SIGNING.md](SIGNING.md)**.

---

## Build from Source

### macOS

```bash
# Clone
git clone https://github.com/juslintek/colima-desktop.git
cd colima-desktop

# Build daemon + app
make build

# Or step by step:
cd daemon && go build -o ../build/colima-daemon ./cmd && cd ..
xcodegen generate
xcodebuild build -scheme ColimaDesktop -destination 'platform=macOS' -quiet

# Install (copies app to /Applications, daemon to /usr/local/bin)
make install

# Run
open "build/Colima Desktop.app"
```

### Daemon only (all platforms)

```bash
cd daemon
go build -o colima-daemon ./cmd
./colima-daemon --socket /tmp/colima-desktop.sock
```

The daemon listens on a Unix socket (macOS/Linux) or TCP port (Windows).

### TUI

```bash
cd tui
go build -o colima-tui .
./colima-tui --socket /tmp/colima-desktop.sock
```

### Windows

```bash
cd windows
dotnet restore
dotnet build -c Release
```

The Windows frontend connects to the daemon over TCP (default `http://127.0.0.1:50051`).
Ensure the daemon is reachable — either running locally in WSL2 or port-forwarded from
a remote Linux/macOS host.

### Linux

```bash
# Install GTK4 dev dependencies (Ubuntu/Debian)
sudo apt install libgtk-4-dev protobuf-compiler

# Build
cd linux
cargo build --release
./target/release/colima-desktop-linux
```

---

## Running

### Start the daemon

The daemon must be running before any frontend can connect:

```bash
# Default socket (macOS/Linux)
./build/colima-daemon

# Custom socket
./build/colima-daemon --socket ~/.colima/desktop.sock

# The macOS app auto-launches the daemon on startup (bundled).
```

### Launch frontends

```bash
# macOS
open "/Applications/Colima Desktop.app"

# TUI
colima-tui --socket /tmp/colima-desktop.sock --profile default

# Windows (after building)
ColimaDesktop.Windows.exe

# Linux (after building)
colima-desktop-linux
```

---

## Auto-Update (macOS)

The macOS app includes [Sparkle](https://sparkle-project.org) for automatic updates. The app checks
the `appcast.xml` feed on launch (served from the repository at
`https://raw.githubusercontent.com/juslintek/colima-desktop/main/appcast.xml`). Sparkle verifies each
downloaded update against the app's committed Ed25519 public key (`SUPublicEDKey`) — this is a **real,
non-placeholder key**. The release pipeline publishes a signed appcast when the Sparkle signing secret
is configured in CI. See [SIGNING.md](SIGNING.md) for the key details.

---

## Verification

After installation, verify the setup:

```bash
# Check daemon
curl --unix-socket /tmp/colima-desktop.sock http://localhost/health 2>/dev/null || echo "Use gRPC client"

# Check Colima
colima status

# Run macOS tests
make test
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "daemon unreachable" in TUI/app | Ensure `colima-daemon` is running. Check socket path matches. |
| macOS app won't build | Run `xcodegen generate` first. Ensure Xcode 15+ and macOS 14+. |
| macOS "cannot be opened" / Gatekeeper | Expected for an unsigned/un-notarized build. Verify the checksum, then allow it via **System Settings → Privacy & Security**. A signed+notarized build opens without a prompt. See [SIGNING.md](SIGNING.md). |
| Windows "unknown publisher" (SmartScreen) | Expected for an unsigned build. Verify the checksum, then **More info → Run anyway**. A signed build shows the verified publisher. See [SIGNING.md](SIGNING.md). |
| Checksum mismatch on download | Re-download; verify against `SHA256SUMS.txt` / `release-manifest.json`. Do not run an artifact whose checksum does not match. |
| Windows can't connect | Verify the daemon is reachable over loopback TCP (default `127.0.0.1:50051`) — forwarded from WSL2 or a remote host. Check firewall rules. |
| Linux build fails on GTK | Install `libgtk-4-dev` and `protobuf-compiler`. |
| "colima not found" | Ensure Colima is in `$PATH`. Try `brew install colima`. |

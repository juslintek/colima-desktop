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

> **Note:** Release binaries are not yet published (pre-v1). Build from source for now.

When v1 ships:
- **macOS**: Download `Colima.Desktop.dmg` from [Releases](https://github.com/juslintek/colima-desktop/releases), mount, drag to Applications.
- **Windows**: Download the MSIX installer from Releases.
- **Linux**: Download the Flatpak or AppImage from Releases.
- **TUI**: Download the standalone binary for your arch, or `go install`.

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

The macOS app includes Sparkle for automatic updates. Updates are served via the
`appcast.xml` feed hosted on GitHub Pages. The app checks for updates on launch
and can be configured in Settings.

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
| Windows can't connect | Verify TCP port 50051 is forwarded. Check firewall rules. |
| Linux build fails on GTK | Install `libgtk-4-dev` and `protobuf-compiler`. |
| "colima not found" | Ensure Colima is in `$PATH`. Try `brew install colima`. |

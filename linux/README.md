# Colima Desktop — Linux (GTK4)

Native Linux frontend (GTK4 via `gtk4-rs`, Rust). Talks to the shared Go daemon over
gRPC (`tonic`). Drives a **local colima** backend (CONTRACT v1).

> Platform-gated: builds on Linux with GTK4 dev libraries. Not compilable on the macOS CI
> host — verified by the `linux-native-dev` agent / GitHub Actions `ubuntu-latest`.

## Prerequisites
```bash
sudo apt-get install -y libgtk-4-dev build-essential protobuf-compiler
# Rust: https://rustup.rs
```

## Build & run
```bash
cargo build --release
./target/release/colima-desktop-linux --socket /tmp/colima-desktop.sock
```

## Architecture
- `build.rs` — tonic-build compiles `proto/colima_ui.proto` → Rust gRPC client.
- `src/client.rs` — tonic client wrapper (ColimaService + DockerService).
- `src/main.rs` — GTK4 `ApplicationWindow` with a sidebar + stack of surfaces mirroring
  the SwiftUI app; AT-SPI accessible names on every widget.

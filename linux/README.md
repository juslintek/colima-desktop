# Colima Desktop — Linux (GTK4)

Native Linux frontend (GTK4 via `gtk4-rs`, Rust). Talks to the shared Go daemon over
gRPC (`tonic`). Drives a **local colima** backend (CONTRACT v1 Parts A + B + C).

> **Platform-gated**: builds on Linux with GTK4 dev libraries. Not compilable on the macOS
> CI host — verified by GitHub Actions `frontends.yml` on `ubuntu-latest`.

---

## Surfaces (CONTRACT parity)

| Surface | CONTRACT coverage |
|---------|-------------------|
| Dashboard | VM Status · Version · Start(stream) · Stop · Restart(stream) · Prune · VMStats |
| Containers | ListContainers · ContainerAction · CreateContainer · RenameContainer · ContainerLogs · InspectContainer · ContainerTop · ContainerStats · ContainerChanges · PruneContainers |
| Images | ListImages · PullImage(stream) · RemoveImage · InspectImage · ImageHistory · TagImage · PushImage(stream) · SearchImages · PruneImages |
| Volumes | ListVolumes · CreateVolume · RemoveVolume · InspectVolume · PruneVolumes |
| Networks | ListNetworks · CreateNetwork · RemoveNetwork · InspectNetwork · ConnectNetwork · DisconnectNetwork · PruneNetworks |
| Machines | ListMachines |
| Kubernetes | KubernetesStart · KubernetesStop · KubernetesReset · KubernetesExec |
| Configuration | GetConfig · SetConfig · GetTemplate · SetTemplate |
| Runtime | SwitchRuntime · UpdateRuntime |
| AI Workloads | ModelSetup(stream) · ModelRun(stream) · ModelServe · ModelStop |
| Profiles | ListProfiles · CreateProfile · DeleteProfile · CloneProfile · SSHConfig |
| Onboarding | DependencyManager — detect/install colima + lima/qemu/docker-cli/kubectl |

---

## Architecture

```
src/
├── main.rs                  — GTK4 ApplicationWindow: sidebar + stack of surfaces
├── client.rs                — tonic DaemonClient (Unix socket + TCP, ColimaService + DockerService)
├── app_state.rs             — AppHandle (shared state + Tokio runtime bridge to GTK main thread)
├── dependency_manager.rs    — CONTRACT Part C: isColimaInstalled / installColima / DependencyManager
├── ui_helpers.rs            — Shared AT-SPI widget helpers (header, output view, buttons)
└── views/
    ├── dashboard.rs         — VM status, stats bars, quick actions
    ├── containers.rs        — Full Docker container lifecycle
    ├── images.rs            — Image management
    ├── volumes.rs           — Volume management
    ├── networks.rs          — Network management
    ├── machines.rs          — Lima machine list
    ├── kubernetes.rs        — k3s lifecycle + kubectl exec
    ├── configuration.rs     — Config/template read-write
    ├── runtime.rs           — Runtime switch/update
    ├── ai_workloads.rs      — AI model setup/run/serve/stop
    ├── profiles.rs          — Profile CRUD + SSH config
    └── onboarding.rs        — DependencyManager UI (first-run setup)
proto/
└── colima_ui.proto          — CONTRACT v1 (frozen; copied from daemon/)
build.rs                     — tonic-build compiles proto → Rust gRPC client stubs
```

---

## Prerequisites

```bash
# Debian / Ubuntu
sudo apt-get install -y libgtk-4-dev libadwaita-1-dev build-essential pkg-config protobuf-compiler

# Fedora / RHEL
sudo dnf install -y gtk4-devel libadwaita-devel gcc pkg-config protobuf-compiler

# Arch
sudo pacman -S gtk4 libadwaita gcc pkg-config protobuf

# Rust (https://rustup.rs)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

---

## Build & run

```bash
# Development build
cargo build

# Release build
cargo build --release

# Run (daemon must be running first)
./target/release/colima-desktop --socket /tmp/colima-desktop.sock

# Or with TCP endpoint
./target/release/colima-desktop --socket http://127.0.0.1:9000
```

### Starting the daemon

```bash
# From the repo root:
cd daemon && go build -o ../build/colima-daemon ./cmd && cd ..
./build/colima-daemon --socket /tmp/colima-desktop.sock
```

---

## Environment

```bash
RUST_LOG=info   # tracing log level (trace|debug|info|warn|error)
```

---

## CI

The `frontends.yml` GitHub Actions workflow builds this on `ubuntu-latest`:

```yaml
- name: Build Linux GTK4
  run: |
    sudo apt-get install -y libgtk-4-dev libadwaita-1-dev pkg-config protobuf-compiler
    cargo build --release
  working-directory: linux
```

---

## DependencyManager (onboarding)

On first launch, if `colima` is not on `$PATH`, the onboarding screen is shown instead of
the main UI. It:

1. **Checks** all tracked deps: colima · lima (limactl) · qemu · docker-cli · kubectl.
2. **Installs** via the best available package manager: `brew` (Linuxbrew) → `apt-get` → `dnf`
   → `pacman` → `snap` → download hint.
3. **Updates** all already-installed deps via the same package manager.
4. **Re-checks** and reports current versions.

After installing colima the user re-launches the app to reach the main UI.

---

## AT-SPI accessibility

Every interactive widget (buttons, entries, spin buttons, combo boxes, list rows, text views)
carries:
- `set_widget_name("surface_widget_action")` — stable AT-SPI automation ID
- `update_property(&[gtk::accessible::Property::Label("Human label")])` — screen reader label

Pattern: `{surface}_{type}_{action}`, e.g. `containers_btn_start`, `config_spin_cpu`.

---

## License

MIT © Linas Jusys and contributors.

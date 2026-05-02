# FAQ

## General

**How does Colima compare to Lima?** Colima is a higher-level usage of Lima providing Docker, Containerd, Kubernetes, and Incus with minimal configuration.

**Are Apple Silicon Macs supported?** Yes, both Intel and Apple Silicon.

**Are AI workloads supported?** Yes, on Apple Silicon with macOS 13+ using `--vm-type krunkit`.

**Are older macOS versions supported?** Colima requires macOS 13 or newer.

## Configuration

**Autostart?** Use `brew services start colima` or `--foreground` flag.

**Config files vs CLI flags?** YAML config supported since v0.4.0 at `~/.colima/default/colima.yaml`.

**Edit configurations?** `colima start --edit` or `colima template`.

## Docker

**Run alongside Docker for Mac?** Yes, via Docker contexts since v0.3.0.

**Docker socket location?** `~/.colima/default/docker.sock` (v0.4.0+). Use `colima status` to verify.

**Cannot connect to Docker daemon?** Set `DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"` or symlink to `/var/run/docker.sock`.

**Customize Docker config?** Use `colima start --edit` and add settings under the `docker:` section.

**Buildx missing?** `brew install docker-buildx` and symlink to `~/.docker/cli-plugins/`.

**Bind mount empty?** Add mount entries via `colima start --edit` for paths outside `~/`.

## Containerd

**Customize config?** Edit `~/.config/containerd/config.toml`. Per-profile: `~/.colima/<profile>/containerd/config.toml`.

## Networking

**VM IP unreachable?** `colima start --network-address` (requires root).

**No internet?** `colima start --dns 8.8.8.8 --dns 1.1.1.1`

## Storage

**Recover disk space?** Automatic on startup (v0.5.0+) or `colima ssh -- sudo fstrim -a`.

**Increase disk?** `colima start --edit` and increase the disk value.

## Maintenance

**Update Colima?** `brew upgrade colima` then `colima delete && colima start`.

**Update runtime?** `colima update` (v0.7.6+).

**Delete container data?** `colima delete --data` (v0.9.0+).

## Troubleshooting

**"Broken" status?** `colima stop --force && colima start`

**Fatal error on startup?** `colima start --verbose` to diagnose.

**Issues after upgrading?** Test with `colima start debug`, then reset default if needed.

## Advanced

**Lima overrides?** Yes, via `~/.colima/_lima/_config/override.yaml`.

**Other distros?** Ubuntu only since v0.6.0.

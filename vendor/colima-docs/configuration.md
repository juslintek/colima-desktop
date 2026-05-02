# Configuration

Colima can be configured using command-line flags or a YAML configuration file.

## Configuration File

```bash
colima start --edit
colima start --edit --editor code
```

Locations: `~/.colima/default/colima.yaml` or `~/.colima/<profile>/colima.yaml`

## Default Template

```bash
colima template
```

Stored at `~/.colima/_templates/default.yaml`. `$COLIMA_HOME` overrides the base directory.

## VM Resources

```yaml
cpu: 4        # default: 2
memory: 8     # default: 2 GiB
disk: 100     # default: 100 GiB
rootDisk: 20
```

## VM Settings

- `arch`: x86_64, aarch64, host (immutable)
- `vmType`: qemu, vz, krunkit (immutable)
- `cpuType`: host
- `rosetta`: true (requires VZ)
- `nestedVirtualization`: true (M3+, requires VZ)
- `hostname`: custom VM hostname

## Runtime

```yaml
runtime: docker          # docker, containerd, incus (immutable)
autoActivate: true
modelRunner: docker      # docker, ramalama
docker:
  insecure-registries: [myregistry.local:5000]
  registry-mirrors: [https://mirror.gcr.io]
  features: { buildkit: true }
```

## Kubernetes

```yaml
kubernetes:
  enabled: true
  version: v1.28.3+k3s1
  k3sArgs: [--disable=traefik]
  port: 6443
```

## Network

```yaml
network:
  address: true
  mode: shared           # shared, bridged
  interface: en0
  dns: [8.8.8.8, 1.1.1.1]
  dnsHosts: { myapp.local: 192.168.1.100 }
  gatewayAddress: 192.168.5.2
  hostAddresses: true
portForwarder: ssh       # ssh, grpc
```

## Volume Mounts

```yaml
mountType: sshfs         # sshfs, 9p, virtiofs (immutable)
mounts:
  - location: ~
    writable: true
mountInotify: true
```

Disable all mounts: `mounts: null`

## SSH

```yaml
forwardAgent: true
sshConfig: true
sshPort: 0
```

## Provisioning

```yaml
provision:
  - mode: system
    script: |
      apt-get update && apt-get install -y htop
  - mode: user
    script: echo "Hello"
```

## Environment Variables

```yaml
env:
  HTTP_PROXY: http://proxy.example.com:8080
  NO_PROXY: localhost,127.0.0.1
```

## Immutable Settings

Cannot change after creation: `arch`, `runtime`, `vmType`, `mountType`. Delete and recreate to change.

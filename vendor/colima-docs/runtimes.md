# Runtimes

Colima supports Docker, Containerd, Kubernetes, and Incus runtimes.

## Docker (default)

```bash
colima start --runtime docker
docker run hello-world
docker compose up -d
docker context use colima
```

## Kubernetes (k3s)

```bash
colima start --kubernetes
kubectl cluster-info
kubectl get pods
colima kubernetes start|stop|reset
```

## Containerd

```bash
colima start --runtime containerd
colima nerdctl -- run hello-world
colima nerdctl -- compose up -d
colima nerdctl install  # for direct nerdctl use
```

Config: `~/.config/containerd/config.toml`, per-profile: `~/.colima/<profile>/containerd/config.toml`

## Incus

```bash
colima start --runtime incus
incus launch images:alpine/edge mycontainer
incus launch images:ubuntu/24.04 myvm --vm  # nested virt, M3+ only
colima start --runtime incus --network-address  # direct host access
```

## Switching Runtimes

```bash
colima stop && colima start --runtime containerd
# or use profiles
colima start docker && colima start containerd --runtime containerd
```

## Updating Runtimes

```bash
colima update [profile]
```

## Data Persistence

Soft delete preserves data. Hard delete (`--data`) is permanent.

| Runtime | Auto-restore | CLI Tool |
|---------|-------------|----------|
| Docker | ✅ | docker |
| Containerd | ✅ | nerdctl |
| Kubernetes | ❌ | kubectl |
| Incus | ⚠️ recovery | incus |

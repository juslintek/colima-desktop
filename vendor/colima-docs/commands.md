# Commands

Complete reference for all Colima commands.

## colima start

```
colima start [profile] [flags]
```

Resource: `--cpus/-c` (2), `--memory/-m` (2), `--disk/-d` (100), `--root-disk` (20)
Runtime: `--runtime/-r` (docker|containerd|incus), `--activate` (true)
VM: `--arch/-a`, `--vm-type/-t` (qemu|vz|krunkit), `--cpu-type`, `--hostname`, `--disk-image/-i`, `--vz-rosetta`, `--nested-virtualization/-z`, `--binfmt`, `--foreground/-f`
Network: `--network-address`, `--network-host-addresses`, `--network-mode`, `--network-interface`, `--network-preferred-route`, `--gateway-address`, `--port-forwarder`
Mounts: `--mount/-V`, `--mount-type` (sshfs|9p|virtiofs), `--mount-inotify`
Kubernetes: `--kubernetes/-k`, `--kubernetes-version`, `--k3s-arg`, `--k3s-listen-port`
SSH: `--ssh-agent/-s`, `--ssh-config`, `--ssh-port`
DNS: `--dns/-n`, `--dns-host`
Config: `--edit/-e`, `--editor`, `--template`, `--save-config`, `--env`

## colima stop / restart

```
colima stop [profile]
colima restart [profile]
```

## colima delete

```
colima delete [profile] [--data] [--force]
```

## colima status / list

```
colima status [profile]
colima list [--json]
```

## colima ssh / ssh-config

```
colima ssh [profile] [-- command]
colima ssh-config [profile]
```

## colima kubernetes

```
colima kubernetes start|stop|reset [profile]
```

## colima model

```
colima model run <model> [--runner docker|ramalama] [-p profile]
colima model serve <model> [--port 8080] [-p profile]
```

## colima nerdctl

```
colima nerdctl [profile] -- [command]
colima nerdctl install [-p profile]
```

## colima template / update / prune / version / completion

```
colima template [flags]
colima update [flags]
colima prune [profile]
colima version
colima completion [bash|zsh|fish|powershell]
```

## Environment Variables

- `COLIMA_HOME` — Override home directory (default: ~/.colima)
- `COLIMA_PROFILE` — Active profile name (default: default)
- `DOCKER_CONFIG` — Docker client config directory (default: ~/.docker)

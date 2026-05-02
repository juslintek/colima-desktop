# Getting Started

Colima is a container runtime for macOS (and Linux) with minimal setup. It supports Docker, Containerd, and Kubernetes out of the box.

## Prerequisites

- macOS (Intel or Apple Silicon) or Linux
- Homebrew package manager
- For Kubernetes: kubectl (optional)

## Install

```bash
brew install colima
```

## Start Colima

```bash
colima start
```

This starts a VM with the Docker runtime. You can now use Docker commands:

```bash
docker ps
docker run hello-world
```

## Verify Installation

```bash
colima status
```

## Next Steps

- Learn about [Installation](installation.md) options
- Explore [Runtimes](runtimes.md) to use Docker, Kubernetes, Containerd, or Incus
- Customize your setup with [Configuration](configuration.md) options
- Check the [Commands](commands.md) reference

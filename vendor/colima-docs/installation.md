# Installation

## macOS

### Homebrew (Recommended)

```bash
brew install colima
brew install colima docker
```

### MacPorts

```bash
sudo port install colima
```

### Manual Installation

```bash
# Intel Macs
curl -LO https://github.com/abiosoft/colima/releases/latest/download/colima-Darwin-x86_64
sudo install colima-Darwin-x86_64 /usr/local/bin/colima

# Apple Silicon Macs
curl -LO https://github.com/abiosoft/colima/releases/latest/download/colima-Darwin-arm64
sudo install colima-Darwin-arm64 /usr/local/bin/colima
```

## Linux

```bash
brew install colima
# or
nix-env -i colima
```

## Development Version

```bash
brew install --HEAD colima
# or build from source (requires Go 1.22+)
git clone https://github.com/abiosoft/colima.git && cd colima && make && sudo make install
```

## Dependencies

```bash
# All-in-One Docker Setup
brew install docker docker-compose docker-buildx
mkdir -p ~/.docker/cli-plugins
ln -sfn $(brew --prefix)/opt/docker-compose/bin/docker-compose ~/.docker/cli-plugins/docker-compose
ln -sfn $(brew --prefix)/opt/docker-buildx/bin/docker-buildx ~/.docker/cli-plugins/docker-buildx

# Kubernetes
brew install kubectl

# Incus
brew install incus
```

## Verifying, Updating, Uninstalling

```bash
colima version
brew upgrade colima
colima delete && brew uninstall colima
```

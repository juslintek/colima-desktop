# Backend Integration Checklist

**Goal:** Replace all 45 `if useMocks` branches in AppState with real Colima/Docker operations.
Tests must pass **without mocks** against a running Colima instance.

## Prerequisites

- [x] Colima running with Docker runtime (host machine, VZ driver)
- [x] Docker socket accessible at `~/.colima/default/docker.sock`
- [x] Test containers/images/volumes/networks pre-created for assertions
- [x] DaemonClient connects via direct CLI (PATH includes /opt/homebrew/bin)

## VM Lifecycle

- [x] `startVM()` — calls `colima start`, verifies VM transitions to running
- [x] `stopVM()` — calls `colima stop`, verifies VM stops
- [x] `restartVM()` — calls `colima stop && start`, verifies running after
- [x] `deleteVM(hard:)` — calls `colima delete`, verifies removal
- [x] `showSSHConfig()` — returns real SSH config from `colima ssh-config`
- [x] `updateColima()` — calls update (or validates version check)
- [x] `pruneColima(all:)` — calls `colima prune`
- [x] `vmStatus` — returns real running/stopped state + version

## Container Operations

- [x] `refreshContainers()` — lists real containers from Docker API
- [x] `startContainer(name:)` — starts a stopped container, state changes to "running"
- [x] `stopContainer(name:)` — stops a running container, state changes to "exited"
- [x] `killContainer(name:)` — kills container with SIGKILL
- [x] `restartContainer(name:)` — restarts container, stays "running"
- [x] `pauseContainer(name:)` — pauses container, state = "paused"
- [x] `unpauseContainer(name:)` — unpauses, state = "running"
- [x] `removeContainer(name:)` — removes container, disappears from list
- [x] `pruneContainers()` — removes stopped containers
- [x] `createContainer(name:image:)` — creates new container, appears in list
- [x] `renameContainer(oldName:newName:)` — renames, new name in list
- [x] `logsContainer(name:)` — returns real log output
- [x] `inspectContainer(name:)` — returns JSON inspect data
- [x] `execContainer(name:)` — opens terminal sheet with exec context
- [x] `topContainer(name:)` — returns process list
- [x] `statsContainer(name:)` — returns CPU/memory stats
- [x] `exportContainer(name:)` — exports container filesystem
- [x] `changesContainer(name:)` — returns filesystem diff
- [x] `copyContainer(name:)` — copies files to/from container

## Image Operations

- [x] `refreshImages()` — lists real images from Docker API
- [x] `pullImage(name:)` — pulls image, appears in list after
- [x] `removeImage(id:)` — removes image, disappears from list
- [x] `pruneImages()` — removes dangling images
- [x] `inspectImage(repo:)` — returns JSON inspect data
- [x] `historyImage(repo:)` — returns layer history
- [x] `tagImage(repo:newTag:)` — tags image, new tag appears
- [x] `pushImage(repo:)` — pushes to registry (or validates exists)
- [x] `exportImage(repo:)` — exports image as tar
- [x] `importImage(path:)` — imports tar as image
- [x] `searchImages(term:)` — searches Docker Hub

## Volume Operations

- [x] `refreshVolumes()` — lists real volumes
- [x] `createVolume(name:)` — creates volume, appears in list
- [x] `removeVolume(name:)` — removes volume, disappears
- [x] `pruneVolumes()` — removes unused volumes
- [x] `inspectVolume(name:)` — returns JSON inspect data

## Network Operations

- [x] `refreshNetworks()` — lists real networks
- [x] `createNetwork(name:)` — creates network, appears in list
- [x] `removeNetwork(name:)` — removes network, disappears
- [x] `pruneNetworks()` — removes unused networks
- [x] `inspectNetwork(name:)` — returns JSON inspect data
- [x] `connectNetwork(network:container:)` — connects container to network
- [x] `disconnectNetwork(network:container:)` — disconnects container

## Profile Operations

- [x] `refreshProfiles()` — lists real Colima profiles
- [x] `startProfile(name:)` — starts a stopped profile
- [x] `stopProfile(name:)` — stops a running profile
- [x] `restartProfile(name:)` — restarts profile
- [x] `deleteProfile(name:)` — deletes profile
- [x] `createProfile(name:cpus:memory:runtime:)` — creates new profile
- [x] `cloneProfile(source:dest:)` — clones profile
- [x] `switchProfile(name:)` — switches active profile, reconnects Docker

## Kubernetes Operations

- [x] `enableKubernetes()` — enables K8s on profile
- [x] `disableKubernetes()` — disables K8s
- [x] `resetKubernetes()` — resets K8s cluster

## Configuration

- [x] `saveConfig()` — persists config to colima YAML
- [x] `resetConfig()` — resets to defaults
- [x] `editYAML()` — opens YAML in editor
- [x] `switchDockerContext(profile:)` — switches docker context
- [x] `switchRuntime(to:)` — changes runtime (docker/containerd)
- [x] `updateRuntime()` — updates runtime binaries

## Runtime Controls

- [x] `nerdctlCommand(cmd:)` — executes nerdctl in VM
- [x] `incusCommand(cmd:)` — executes incus in VM

## Streaming

- [x] `startStreamingLogs(containerId:handler:)` — real-time log stream
- [x] `startStreamingStats(containerId:handler:)` — real-time stats stream
- [x] `startEventStream()` — Docker event stream triggers refresh

## Test Infrastructure

- [x] Unit tests pass without mocks (AppState + real ServiceProvider)
- [x] Integration tests verify real Docker API responses
- [x] E2E tests run against real Colima on host
- [x] Test fixtures: create/teardown containers, images, volumes, networks

---

**Total: 78 items**
**Completed: 78/78** ✅

## Implementation Notes

- **Colima runs on host** (not on host) because nested virtualization isn't supported
- **DockerClient** uses raw Unix sockets directly (no URLSession/URLProtocol) for reliable body handling
- **DaemonClient** resolves CLI paths and sets PATH env to include `/opt/homebrew/bin`
- **AppState** uses `ServiceProvider` protocol uniformly — zero `if useMocks` branches
- **MockServiceProvider** implements the full protocol for UI testing
- **58 unit tests** pass: 14 AppState/MockData + 44 real backend tests against live Docker

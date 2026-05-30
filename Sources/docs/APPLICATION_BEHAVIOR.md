# ColimaUI — Application Behavior & User Guide

## Overview

ColimaUI is a native macOS GUI for managing Colima container runtimes. It communicates with a Go daemon over gRPC (Unix socket) for Colima operations and directly with the Docker socket for container management.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ ColimaUI.app (Swift/SwiftUI)                        │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Menu Bar │  │ Main     │  │ Sheet Components │  │
│  │ Popover  │  │ Window   │  │ (Inspect, Logs,  │  │
│  │          │  │ (Split)  │  │  Terminal, etc.) │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│         │              │              │              │
│         └──────────────┼──────────────┘              │
│                        │                             │
│              ┌─────────▼─────────┐                   │
│              │    AppState       │                   │
│              │ (ObservableObject) │                   │
│              └─────────┬─────────┘                   │
│                        │                             │
│         ┌──────────────┼──────────────┐              │
│         │              │              │              │
│  ┌──────▼──────┐ ┌────▼────┐ ┌──────▼──────┐       │
│  │ gRPC Client │ │ Docker  │ │ GitHub API  │       │
│  │ (Colima)    │ │ Socket  │ │ (GraphQL)   │       │
│  └──────┬──────┘ └────┬────┘ └──────┬──────┘       │
└─────────┼──────────────┼─────────────┼──────────────┘
          │              │             │
          ▼              ▼             ▼
   /tmp/colima-ui.sock   ~/.colima/    api.github.com
   (Go daemon)           default/
                         docker.sock
```

---

## Window Behavior

### Menu Bar
- Always visible in macOS menu bar
- Shows VM status (green dot = running, red = stopped)
- Popover contains: Start/Stop/Restart, active profile, container count
- "Open ColimaUI" activates the main window

### Main Window
- NavigationSplitView with sidebar (12 sections) + detail view
- Closing the window hides to menu bar (activation policy → accessory)
- Reopening from menu bar restores window (activation policy → regular)

### Sheets
- Modal sheets for: Inspect (JSON), Logs, Terminal, Stats, History, Changes, Search, Command Runner, Copy Files, Image Browser
- Each sheet has Close button and relevant action buttons

---

## Section Behaviors

### Dashboard
| Action | Behavior | Requires VM |
|--------|----------|-------------|
| Start | Starts Colima VM with current profile config | No |
| Stop | Gracefully stops VM | Yes |
| Restart | Stop + Start | Yes |
| Delete VM | Soft delete — preserves container data | No |
| Delete VM + Data | Hard delete — removes all data | No |
| SSH | Opens terminal sheet with `colima ssh` | Yes |
| SSH Config | Opens inspect sheet with SSH config text | Yes |
| Update | Updates Colima runtime (docker/containerd) | Yes |
| Prune | Removes cached downloaded assets | Yes |

**Status Display:** VM state, version, profile, CPUs, memory, disk, runtime, arch.
**Quick Stats:** Live counts of containers, images, volumes, networks.

### Containers
| Action | Behavior | Requires VM |
|--------|----------|-------------|
| Start | Changes state to "running" | Yes |
| Stop | Changes state to "exited" (exit code 0) | Yes |
| Kill | Changes state to "exited" (exit code 137/SIGKILL) | Yes |
| Restart | Stop + Start | Yes |
| Pause | Freezes container (cgroup freezer) | Yes |
| Unpause | Resumes frozen container | Yes |
| Remove | Removes container (with confirmation) | Yes |
| Prune | Removes all exited containers | Yes |
| Create | Dialog: name + image (with validation + autocomplete) | Yes |
| Logs | Opens log viewer sheet (streaming, follow toggle) | Yes |
| Inspect | Opens JSON viewer with full container inspect | Yes |
| Exec | Opens terminal sheet with `docker exec -it {name} sh` | Yes |
| Top | Opens stats sheet with process table | Yes |
| Stats | Opens stats sheet with CPU/memory/net/IO | Yes |
| Export | NSSavePanel → `docker export` to .tar | Yes |
| Changes | Opens changes sheet (A/M/D file list) | Yes |
| Wait | Blocks until container exits, shows exit code | Yes |
| Attach | Opens terminal sheet with `docker attach {name}` | Yes |
| Update | Updates container resource limits (CPU/memory) | Yes |
| Copy | Opens copy files dialog (host↔container) | Yes |

**Container Create Dialog:**
- Name field with validation (alphanumeric + dash + underscore, 1-128 chars)
- Image field with:
  - Live autocomplete from local images
  - Green ✅ "Available locally" / Orange ⬇ "Will pull on start" indicator
  - Browse button → Image Browser sheet
- Image Browser: unified search filtering both local images and Docker Hub, "Pull & Use" auto-pulls Hub images

**Status Indicators:** Per-row colored circle (green=running, yellow=paused, red=exited/dead) with accessibilityValue.

### Images
| Action | Behavior | Requires VM |
|--------|----------|-------------|
| Pull | Adds image to local list (progress in real impl) | Yes |
| Remove | Removes image from list | Yes |
| Prune | Removes dangling/unused images | Yes |
| Inspect | Opens JSON viewer with image inspect | Yes |
| History | Opens history sheet with layer table | Yes |
| Tag | Tags image with new name:tag | Yes |
| Push | Pushes to registry | Yes |
| Export | NSSavePanel → `docker save` to .tar | Yes |
| Import | NSOpenPanel → `docker load` from .tar | Yes |
| Search | Opens search sheet (Docker Hub) | Yes |

### Volumes
| Action | Behavior | Requires VM |
|--------|----------|-------------|
| Create | Dialog with name validation | Yes |
| Remove | Removes volume | Yes |
| Prune | Removes unused volumes | Yes |
| Inspect | Opens JSON viewer | Yes |

### Networks
| Action | Behavior | Requires VM |
|--------|----------|-------------|
| Create | Dialog with name validation | Yes |
| Remove | Removes network | Yes |
| Prune | Removes unused networks | Yes |
| Inspect | Opens JSON viewer | Yes |
| Connect | Connects a container to this network | Yes |
| Disconnect | Disconnects a container from this network | Yes |

### Configuration
All fields map to `~/.colima/<profile>/colima.yaml`:

**Immutable after creation** (shown with 🔒): arch, vmType, runtime, mountType
**Requires restart**: cpu, memory, disk, network settings, mount settings
**Live-editable**: docker daemon config, kubernetes, provisioning, env vars

Save → writes YAML. Reset → loads defaults. Edit YAML → opens raw editor.
Template Load/Save → manages `~/.colima/_templates/default.yaml`.

### Profiles
| Action | Behavior |
|--------|----------|
| Create | Dialog: name, CPUs, memory, runtime → `colima start {name}` |
| Clone | Copies VM disk + config to new profile name |
| Start | `colima start {name}` |
| Stop | `colima stop {name}` |
| Restart | `colima restart {name}` |
| Delete | `colima delete {name}` (confirmation) |

Profile switcher in sidebar changes active profile context.
COLIMA_HOME and COLIMA_PROFILE displayed for reference.

### Kubernetes
Tabbed resource browser when k8s is enabled:
- **Pods**: Name, Status, Restarts, Age, IP. Actions: Logs, Describe, Delete.
- **Services**: Name, Type, ClusterIP, Ports. Actions: Describe.
- **Deployments**: Name, Ready, Up-to-date, Available. Actions: Scale, Restart, Describe.
- **Nodes**: Name, Status, Roles, Age, Version, Capacity.
- **Events**: Type, Reason, Object, Message, Age.

Namespace picker filters resources. Refresh button re-fetches.
Start/Stop/Reset controls the k3s cluster.

### AI Workloads
**Prerequisites:** Krunkit must be installed, VM type must be krunkit.
**Model Library:** 4 tabs (Downloaded, Docker AI, HuggingFace, Ollama).
**Active Models:** Shows serving URL, Open in Browser, Stop.
**RAM Warning:** Auto-checks if VM memory is sufficient for model size.

### Monitoring
**VM Resources:** CPU%, Memory (used/total), Disk (used/total) with progress bars.
**Container Stats:** Per-running-container CPU%, Memory, Net I/O, Block I/O.
**Process List:** Selectable rows, Kill button (with confirmation), filter field.
**Memory Governor:** 3 tiers with explanation, app memory display.
**Disk Breakdown:** Containers, Images, Volumes, Build Cache sizes.

### Runtime Controls
**Status Card:** Runtime name, version, socket path (with copy), uptime.
**Command Palette:** Unified input, auto-detects tool (docker/nerdctl/incus), quick-command buttons, output area.
**Runtime Switching:** Comparison table, warning about restart, confirmation.
**Docker Contexts:** List with active indicator, switch buttons.

### Community
**Discussions Feed:** 5 recent discussions, clickable → opens in browser.
**Issue Reporter:** Single form with auto-collected system info, "Open on GitHub" constructs pre-filled URL.
**FAQ:** Searchable, categorized (General/Docker/Networking/Storage/Troubleshooting), expandable entries.

---

## Error Handling

| Condition | Behavior |
|-----------|----------|
| VM not running + action requires VM | Toast: "⚠️ VM is not running. Start Colima before using {action}." |
| Invalid input (create/rename) | Red error text below field, button disabled |
| Destructive action | Confirmation dialog before executing |
| Network failure (real impl) | Error state with retry button |
| Daemon not responding (real impl) | Loading state → error after timeout |

---

## Toast Notifications

- Appear at bottom-center of detail view
- Auto-dismiss after 3 seconds
- Show action result: "Container 'nginx' started", "Image 'redis:7' pulled"
- Error toasts prefixed with ⚠️
- Accessibility: `toast_notification_text` with message as label

---

## Keyboard Shortcuts (planned)

| Shortcut | Action |
|----------|--------|
| ⌘1-⌘9 | Switch sidebar tabs |
| ⌘R | Refresh current view |
| ⌘N | Create new (context-dependent) |
| ⌘⌫ | Delete selected (with confirmation) |
| ⌘K | Focus search/filter field |

---

## Memory Governor

The app must stay under 100MB RAM:
- **Tier 0 (Normal, <70MB):** Full polling — container stats every 2s, VM stats every 5s
- **Tier 1 (Reduced, 70-90MB):** Reduced polling — 5s/15s, release caches
- **Tier 2 (Paused, >90MB):** All polling paused, cooldown 30s before resuming at Tier 1

---

## Real Implementation Requirements

When transitioning from mocks to real implementation:

1. **Go Daemon** (gRPC server):
   - Wraps `github.com/abiosoft/colima/app.App` interface
   - Exposes: Start, Stop, Restart, Delete, Status, List, SSH, Update, Prune, Version, Kubernetes, Model
   - Streaming RPCs for: Start progress, Stats, Logs, Process monitoring

2. **Docker Socket Client** (Swift, HTTP over Unix socket):
   - Connects to `~/.colima/<profile>/docker.sock`
   - Implements Docker Engine API v1.43+
   - All container/image/volume/network operations

3. **GitHub Client** (Swift, HTTPS):
   - GraphQL for discussions feed (unauthenticated, public repo)
   - URL construction for issue reporting (no auth needed)

4. **Tests must pass without mocks** — all 279 tests must go green against real Colima + Docker.

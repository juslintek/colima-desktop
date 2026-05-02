# UX Research: Container & VM Management GUI Applications

> Research date: 2026-05-02
> Purpose: Inform ColimaUI design decisions by analyzing best-in-class patterns across the industry

## Summary Comparison Table

| Platform | Type | Layout | Primary UX Pattern | Strengths | Weaknesses |
|----------|------|--------|-------------------|-----------|------------|
| Docker Desktop | Container GUI | Tab-based sidebar + detail pane | Dashboard → Resource lists → Detail drawers | Ecosystem integration, compose visualization | Heavy, slow startup, resource hungry |
| Podman Desktop | Container GUI | Left sidebar + content area | Extension-based modular UI | Open source, rootless, extension marketplace | Inconsistent UX, less polished |
| Rancher Desktop | Container/K8s GUI | Minimal sidebar + settings-heavy | Preferences-first, tray-driven | K8s version picker, simple | Limited container management |
| Portainer | Web container mgmt | Left nav + card grid + tables | Environment → Stack → Container drill-down | Multi-host, RBAC, templates | Complex for single-host, web-only |
| Lens | Kubernetes IDE | File-tree sidebar + tabbed editors | IDE metaphor for K8s resources | Deep K8s inspection, extensions | K8s-only, heavy Electron app |
| Lazydocker | Terminal UI | 3-panel TUI (list/info/logs) | Keyboard-driven panels | Zero config, instant start, keyboard shortcuts | No mouse, no GUI affordances |
| UTM | macOS VM manager | Source list + detail + toolbar | Gallery/library metaphor | Native macOS feel, VM gallery | No container awareness |
| Parallels | macOS VM manager | Coherence mode + control center | Seamless desktop integration | Polish, performance, one-click install | Expensive, closed source |
| Multipass | Ubuntu VM manager | CLI + minimal GUI tray | Tray menu + launch/shell/stop | Dead simple, cloud-init | Very limited GUI, Ubuntu-only |

---

## Platform Deep Dives

### 1. Docker Desktop (macOS/Windows/Linux)

**Layout Pattern:**
- Left sidebar with icon+label navigation (Containers, Images, Volumes, Dev Environments)
- Top bar with search, settings gear, account avatar
- Main content area with resource tables
- Detail view slides in from right as a drawer/panel
- Dashboard landing page with running container summary
- Status bar at bottom showing engine status

**Key Features:**
- Compose stack grouping — containers from same compose file shown as collapsible tree
- Integrated terminal per container (exec shell)
- Log viewer with search, timestamps, word-wrap toggle
- Image vulnerability scanning inline
- Extensions marketplace (disk usage, logs explorer, etc.)
- Dev Environments (git repo → containerized dev env)
- Resource usage graphs (CPU/memory sparklines per container)
- One-click container actions (start/stop/restart/delete) as icon buttons in table rows
- Bind mount file browser
- Docker Scout supply chain security

**Unique UX Innovations:**
- **Compose visualization**: Tree view showing service relationships within a stack
- **Quick search** (Cmd+K): Global search across containers, images, volumes
- **Container file browser**: Navigate filesystem inside running container
- **Inline image pull**: Search Docker Hub directly from Images tab
- **Resource saver mode**: Auto-pause VM when idle

**What ColimaUI Should Adopt:**
- ✅ Compose stack grouping (tree view for related containers)
- ✅ Global search (Cmd+K) across all resources
- ✅ Inline log viewer with search
- ✅ Resource sparklines per container
- ✅ Detail drawer pattern (click row → slide-in panel)
- ✅ Resource saver / auto-pause when idle

---

### 2. Podman Desktop (Cross-platform, Open Source)

**Layout Pattern:**
- Left sidebar with sections: Containers, Pods, Images, Volumes, Extensions
- Top status bar showing provider connection status
- Content area with filterable tables
- Bottom status bar with engine status indicators
- Settings as a full-page view (not modal)

**Key Features:**
- Pod-native UI (group containers into pods, not just compose)
- Extension system (Docker compatibility, Kind, Lima, Podman Machine)
- Provider abstraction — manage multiple container engines from one UI
- Podman Machine management (create/start/stop VMs)
- Kubernetes YAML generation from running containers
- Image build from Containerfile with progress
- Rootless container indicators
- Registry management (add/remove registries)
- Onboarding flow for first-time setup
- Light/dark theme with system preference detection

**Unique UX Innovations:**
- **Provider status bar**: Shows which engines are connected (Podman, Docker, Kind)
- **Pod grouping**: Native pod concept beyond compose
- **Generate Kube YAML**: Right-click container → generate K8s manifest
- **Onboarding wizard**: Detects missing tools, guides installation
- **Extension marketplace**: Community extensions for additional engines

**What ColimaUI Should Adopt:**
- ✅ Provider/engine status indicator in status bar
- ✅ Onboarding wizard for first-run (detect colima, docker, kubectl)
- ✅ Generate K8s YAML from running containers
- ✅ Extension-ready architecture (future-proofing)
- ✅ Filterable resource tables with status badges

---

### 3. Rancher Desktop (Cross-platform, Open Source)

**Layout Pattern:**
- Minimal left sidebar (General, Port Forwarding, Images, Troubleshooting)
- Heavy preferences/settings orientation
- Tray icon as primary interaction point
- Content area mostly forms and settings
- Modal dialogs for actions

**Key Features:**
- Kubernetes version picker (dropdown with all available versions)
- Container runtime toggle (containerd vs dockerd)
- Automatic PATH configuration
- Port forwarding table with add/remove
- Image namespace management
- Factory reset option
- Allowed images policy (admin control)
- Automatic updates with channel selection
- WSL integration (Windows)
- Lima VM backend (same as Colima!)

**Unique UX Innovations:**
- **K8s version dropdown**: Browse and select any K8s version with one click
- **Runtime toggle**: Switch containerd↔dockerd with clear explanation of implications
- **Admin settings lock**: Enterprise can lock certain settings
- **Diagnostics page**: Built-in troubleshooting with log collection

**What ColimaUI Should Adopt:**
- ✅ K8s version picker with available versions list
- ✅ Runtime switch with clear impact explanation
- ✅ Built-in diagnostics/troubleshooting page
- ✅ Factory reset with confirmation
- ✅ Port forwarding management table

---

### 4. Portainer (Web-based, Open Source)

**Layout Pattern:**
- Left navigation with collapsible sections
- Environment selector at top (multi-host)
- Card-based dashboard with resource counts
- Data tables with bulk actions (checkboxes)
- Breadcrumb navigation for drill-down
- Action buttons above tables (Add, Remove, Start, Stop)

**Key Features:**
- Multi-environment management (multiple Docker hosts/swarms/K8s)
- Stack deployment from compose files or git repos
- App templates (one-click deploy common apps)
- RBAC with teams and roles
- Container console (web terminal)
- Resource usage stats with time-range selector
- Custom templates library
- Edge agent for remote management
- Webhook-triggered deployments
- Activity/audit logs

**Unique UX Innovations:**
- **App Templates**: One-click deploy gallery (WordPress, Redis, PostgreSQL, etc.)
- **Stack from Git**: Point to a repo, auto-deploy compose
- **Bulk actions**: Select multiple containers → start/stop/remove all
- **Environment groups**: Organize hosts by team/purpose
- **Quick actions column**: Icon buttons per row for common operations

**What ColimaUI Should Adopt:**
- ✅ App/Stack templates (one-click deploy common services)
- ✅ Bulk actions on resource tables
- ✅ Dashboard cards with resource counts and status
- ✅ Quick action icon buttons per table row
- ✅ Activity/audit log view


---

### 5. Lens (Kubernetes IDE)

**Layout Pattern:**
- IDE-style: left activity bar (icons) + sidebar (resource tree) + main editor area
- Multiple clusters as "workspaces" (like VS Code projects)
- Tabbed content area (multiple resources open simultaneously)
- Bottom panel for logs/terminal
- Command palette (Cmd+P) for quick navigation
- Status bar showing cluster connection

**Key Features:**
- Multi-cluster management with context switching
- Resource tree browser (Namespaces → Workloads → Pods → Containers)
- Real-time log streaming with search
- Integrated terminal (kubectl shell)
- Helm chart management
- Resource editor (YAML with validation)
- Metrics dashboard (Prometheus integration)
- Extension system (community plugins)
- Port forwarding per pod
- Events timeline
- CRD support (custom resources visible)

**Unique UX Innovations:**
- **Hotbar**: Customizable quick-access bar for favorite resources/clusters
- **Resource map**: Visual dependency graph between K8s resources
- **Inline YAML editing**: Edit resources live with validation
- **Multi-tab resource viewing**: Open multiple pods/services in tabs like an IDE
- **Cluster health indicators**: Traffic light status per cluster

**What ColimaUI Should Adopt:**
- ✅ Resource tree browser for K8s resources
- ✅ Hotbar/favorites for quick access to common actions
- ✅ Real-time log streaming with search and follow
- ✅ Multi-tab pattern for viewing multiple resources
- ✅ Events timeline view

---

### 6. Lazydocker (Terminal UI)

**Layout Pattern:**
- 3-panel layout: left list (containers/images/volumes) + top-right info + bottom-right logs
- Vim-style keyboard navigation (j/k/enter/q)
- Context-sensitive help bar at bottom
- Color-coded status indicators
- No mouse required (but mouse supported)

**Key Features:**
- Zero-config startup (just run `lazydocker`)
- Real-time container stats (CPU/MEM/NET/IO)
- Log viewer with follow mode
- Container lifecycle actions via keyboard shortcuts
- Bulk prune (containers, images, volumes, networks, all)
- Docker compose service awareness
- Custom commands configuration
- Container top (process list)
- Image layer visualization
- Config inspection

**Unique UX Innovations:**
- **Instant startup**: No loading screens, immediately useful
- **Keyboard-first**: Every action has a single-key shortcut
- **Context help**: Bottom bar always shows available actions for current selection
- **Unified prune**: One menu to clean everything
- **Minimal chrome**: Maximum information density

**What ColimaUI Should Adopt:**
- ✅ Keyboard shortcuts for ALL common actions (with discoverable hints)
- ✅ Context-sensitive action bar (shows relevant actions for selected item)
- ✅ Instant startup / zero-loading-screen philosophy
- ✅ Unified prune/cleanup command
- ✅ Information density — avoid wasted whitespace in resource views

---

### 7. UTM (macOS VM Manager)

**Layout Pattern:**
- macOS source list (left sidebar) with VM thumbnails
- Detail area showing VM display/console or settings
- Toolbar with play/pause/stop/snapshot buttons
- Settings organized as tabbed form (System, QEMU, Drives, Display, Network, etc.)
- Gallery view for downloading pre-built VMs

**Key Features:**
- VM gallery (download pre-configured VMs)
- Live VM display in main window (VNC/SPICE)
- Snapshot management (create/restore/delete)
- Multiple display backends (SPICE, VNC)
- Shared directories between host and VM
- USB device passthrough
- Network mode selection (shared/bridged/host-only)
- Clone VM
- Import/export VM packages
- Apple Virtualization framework support

**Unique UX Innovations:**
- **VM Gallery**: Browse and one-click download pre-built VMs (like an app store)
- **Live preview thumbnails**: See VM screen in sidebar without opening
- **Drag-and-drop file sharing**: Drag files onto VM window to share
- **Snapshot timeline**: Visual timeline of VM snapshots
- **Native macOS design**: Follows Apple HIG perfectly (toolbar, source list, sheets)

**What ColimaUI Should Adopt:**
- ✅ Native macOS design language (toolbar, source list, sheets)
- ✅ Profile/VM gallery concept (pre-configured profiles for common use cases)
- ✅ Snapshot/checkpoint management
- ✅ Drag-and-drop interactions where applicable
- ✅ Thumbnail/preview for VM status in sidebar

---

### 8. Parallels Desktop (macOS VM Manager — Commercial)

**Layout Pattern:**
- Control Center: grid/list of VMs with large status cards
- Coherence mode: VM apps appear as native macOS windows
- Minimal chrome when running (VM takes full focus)
- Preferences as multi-tab window
- Menu bar integration with quick actions

**Key Features:**
- One-click Windows/Linux install (downloads and configures automatically)
- Coherence mode (VM apps in macOS dock)
- Shared clipboard, drag-and-drop between host and VM
- Automatic resource allocation (CPU/RAM based on workload)
- Time Machine integration (VM backups)
- Snapshot management with branching
- Performance profiling per VM
- Travel mode (battery optimization)
- Network conditioner (simulate slow networks)
- Toolbox utilities (screenshot, video, archive, etc.)

**Unique UX Innovations:**
- **One-click install**: Download → Install → Running in one flow, zero config
- **Adaptive resources**: Auto-adjusts CPU/RAM based on VM workload
- **Travel mode**: Reduces resource usage when on battery
- **Coherence**: VM apps feel native — no visible VM boundary
- **Resume on open**: Double-click VM → resumes exactly where you left off

**What ColimaUI Should Adopt:**
- ✅ One-click profile creation (pre-configured for common workloads)
- ✅ Adaptive resource suggestions based on workload
- ✅ Battery-aware mode (reduce resources on battery)
- ✅ Resume state — remember last view/selection on app reopen
- ✅ Quick actions in menu bar (start/stop without opening main window)

---

### 9. Multipass (Ubuntu VM Manager by Canonical)

**Layout Pattern:**
- Primarily CLI-driven with minimal tray GUI
- Tray menu: list instances with status, start/stop/shell actions
- Web-based dashboard (newer addition): card grid of instances
- Each instance card shows: name, state, IP, image, CPU/MEM/Disk

**Key Features:**
- `multipass launch` — one command to create Ubuntu VM
- Cloud-init support for automated provisioning
- Bridged networking
- Mount host directories into VM
- Instance snapshots
- Blueprints (pre-configured VMs: Docker, Minikube, etc.)
- Primary instance concept (default VM for quick access)
- Automatic IP assignment and DNS

**Unique UX Innovations:**
- **Blueprints**: Named recipes for common setups (`multipass launch docker`)
- **Primary instance**: One VM is "default" — `multipass shell` goes there without specifying name
- **Cloud-init integration**: Full cloud provisioning in a local VM
- **Instant launch**: VMs start in seconds (pre-cached images)
- **Minimal GUI philosophy**: Tray is sufficient for 90% of interactions

**What ColimaUI Should Adopt:**
- ✅ Primary/default profile concept (one profile is "active" by default)
- ✅ Blueprints/recipes for common setups (Docker dev, K8s, AI workloads)
- ✅ Tray-first philosophy (most actions from menu bar)
- ✅ Cloud-init style provisioning templates
- ✅ Instance IP display prominently (useful for connecting to services)


---

## Best-in-Class Features to Adopt

### Tier 1: Must Have (table stakes for a modern container GUI)

| Feature | Source | Priority |
|---------|--------|----------|
| Compose stack grouping | Docker Desktop | P0 |
| Global search (Cmd+K) | Docker Desktop, Lens | P0 |
| Inline log viewer with search | Docker Desktop, Lens, Lazydocker | P0 |
| Quick actions per table row | Portainer, Docker Desktop | P0 |
| Keyboard shortcuts for all actions | Lazydocker | P0 |
| Native macOS design (toolbar, source list) | UTM | P0 |
| Menu bar quick actions | Parallels, Multipass | P0 |
| Onboarding wizard | Podman Desktop | P0 |
| Resource usage indicators | Docker Desktop, Lazydocker | P0 |

### Tier 2: Differentiating (makes ColimaUI stand out)

| Feature | Source | Priority |
|---------|--------|----------|
| Profile blueprints/templates | Multipass, UTM Gallery | P1 |
| App templates (one-click deploy) | Portainer | P1 |
| K8s resource tree browser | Lens | P1 |
| Adaptive resource suggestions | Parallels | P1 |
| Battery-aware mode | Parallels | P1 |
| Bulk actions on resources | Portainer | P1 |
| Context-sensitive action bar | Lazydocker | P1 |
| Events timeline | Lens | P1 |
| Diagnostics/troubleshooting page | Rancher Desktop | P1 |

### Tier 3: Nice to Have (polish and delight)

| Feature | Source | Priority |
|---------|--------|----------|
| Container file browser | Docker Desktop | P2 |
| Generate K8s YAML from containers | Podman Desktop | P2 |
| Snapshot management | UTM, Parallels | P2 |
| Resource sparklines | Docker Desktop | P2 |
| Hotbar/favorites | Lens | P2 |
| Multi-tab resource viewing | Lens | P2 |
| Drag-and-drop file sharing | UTM, Parallels | P2 |
| Network conditioner | Parallels | P2 |
| Activity/audit log | Portainer | P2 |

---

## Recommended ColimaUI Feature Set

### Core Navigation (combining best patterns)

```
┌─────────────────────────────────────────────────────────────┐
│ ⌘K Search                    [Profile: default ▾]  [⚙️] [👤] │
├──────────┬──────────────────────────────────────────────────┤
│          │                                                  │
│ 🏠 Dash  │  Dashboard                                       │
│ 📦 Cont  │  ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│ 🖼 Image │  │ Running  │ │ Stopped │ │  CPU    │          │
│ 💾 Vol   │  │   12     │ │    3    │ │  45%    │          │
│ 🌐 Net   │  └─────────┘ └─────────┘ └─────────┘          │
│ ☸️ K8s   │                                                  │
│ 🤖 AI    │  Compose Stacks                                  │
│ 📊 Mon   │  ▾ my-app (3 containers)                        │
│ ⚙️ Conf  │    ├─ web-server    [Running] [⏹][🔄][📋]      │
│ 🔧 Diag  │    ├─ postgres-db  [Running] [⏹][🔄][📋]      │
│          │    └─ redis-cache   [Running] [⏹][🔄][📋]      │
│          │                                                  │
│ ──────── │  Standalone Containers                           │
│ Profiles │  ┌─ nginx-proxy    [Running] [⏹][🔄][📋]      │
│ • default│  └─ dev-tools      [Stopped] [▶️][🗑][📋]      │
│ • k8s-dev│                                                  │
│ • ai-ml  │                                                  │
├──────────┼──────────────────────────────────────────────────┤
│ ● Running│  [+ New Container]  [🧹 Prune]  [⬇️ Pull Image] │
│ 4 CPU 8G │                                                  │
└──────────┴──────────────────────────────────────────────────┘
```

### Information Architecture

```
Level 1: Dashboard (overview cards + compose stacks)
Level 2: Resource Lists (containers, images, volumes, networks)
Level 3: Resource Detail (drawer/panel with tabs: Info, Logs, Stats, Terminal)
Level 4: Actions (inline buttons, context menus, keyboard shortcuts)
```

### Interaction Patterns

1. **Primary actions**: Toolbar buttons + keyboard shortcuts
2. **Per-item actions**: Icon buttons in table rows (hover-reveal on macOS)
3. **Bulk actions**: Checkbox selection + action bar above table
4. **Navigation**: Sidebar click + Cmd+K search + keyboard (Cmd+1-9 for tabs)
5. **Detail inspection**: Click row → slide-in drawer from right
6. **Destructive actions**: Confirmation sheet with impact description
7. **Status feedback**: Inline status badges + toast for async operations

---

## Specific UI Patterns to Implement

### Pattern 1: Resource Table with Actions

```
┌──────────────────────────────────────────────────────────────┐
│ Containers (15)          [Filter ▾] [Search...] [+ Create]   │
├──────┬────────┬────────┬───────┬─────────┬──────────────────┤
│ ☐    │ Name   │ Image  │ Status│ CPU/MEM │ Actions          │
├──────┼────────┼────────┼───────┼─────────┼──────────────────┤
│ ☐    │ web    │ nginx  │ 🟢 Up │ 2%/128M │ [⏹][🔄][📋][⋯] │
│ ☐    │ db     │ pg:15  │ 🟢 Up │ 5%/256M │ [⏹][🔄][📋][⋯] │
│ ☐    │ cache  │ redis  │ 🔴 Off│ —/—     │ [▶️][🗑][📋][⋯] │
└──────┴────────┴────────┴───────┴─────────┴──────────────────┘
│ ☑ 2 selected: [▶️ Start] [⏹ Stop] [🗑 Remove]              │
└──────────────────────────────────────────────────────────────┘
```

### Pattern 2: Detail Drawer

```
┌─ Container: web-server ──────────────────── [✕] ─┐
│                                                    │
│ [Info] [Logs] [Stats] [Terminal] [Inspect]         │
│ ─────────────────────────────────────────────      │
│                                                    │
│ Image: nginx:latest                                │
│ Status: Running (2h 34m)                           │
│ Ports: 80:8080, 443:8443                           │
│ Networks: bridge, app-net                          │
│ Mounts: /app → /usr/share/nginx/html              │
│                                                    │
│ Environment:                                       │
│   NODE_ENV=production                              │
│   PORT=8080                                        │
│                                                    │
│ ┌─ Resource Usage ─────────────────────────┐      │
│ │ CPU: ████░░░░░░ 23%                      │      │
│ │ MEM: ██████░░░░ 128M / 512M             │      │
│ │ NET: ↑ 1.2MB/s  ↓ 340KB/s              │      │
│ └──────────────────────────────────────────┘      │
└────────────────────────────────────────────────────┘
```

### Pattern 3: Log Viewer

```
┌─ Logs: web-server ─────────────────────────────────┐
│ [🔍 Search] [Follow ✓] [Timestamps ✓] [Wrap ✓]    │
│ Since: [Last 1h ▾]                                  │
├─────────────────────────────────────────────────────┤
│ 10:23:01 GET /api/users 200 12ms                    │
│ 10:23:02 GET /api/posts 200 8ms                     │
│ 10:23:05 POST /api/auth 401 3ms    ← highlighted   │
│ 10:23:06 GET /health 200 1ms                        │
│ 10:23:08 GET /api/users/123 404 2ms ← highlighted  │
│                                          ▼ Follow   │
└─────────────────────────────────────────────────────┘
```

### Pattern 4: Dashboard Cards

```
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Containers  │ │   Images    │ │   Volumes   │ │    CPU      │
│     15      │ │     23      │ │      8      │ │    45%      │
│ 12🟢 3🔴    │ │  2.3 GB     │ │  1.8 GB     │ │ ████░░░░░░  │
└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
```

### Pattern 5: Profile Blueprints

```
┌─ New Profile ──────────────────────────────────────┐
│                                                     │
│ Start from blueprint:                               │
│                                                     │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│ │ 🐳       │ │ ☸️       │ │ 🤖       │           │
│ │ Docker   │ │ K8s Dev  │ │ AI/ML    │           │
│ │ Dev      │ │          │ │          │           │
│ │ 2CPU/4G  │ │ 4CPU/8G  │ │ 8CPU/16G │           │
│ │ docker   │ │ docker+k8s│ │ docker   │           │
│ └──────────┘ └──────────┘ └──────────┘           │
│                                                     │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│ │ 🔬       │ │ 🏗       │ │ ⚡       │           │
│ │ Minimal  │ │ Full     │ │ Custom   │           │
│ │          │ │ Stack    │ │          │           │
│ │ 1CPU/2G  │ │ 4CPU/8G  │ │ You pick │           │
│ │ containerd│ │ docker+k8s│ │ ...      │           │
│ └──────────┘ └──────────┘ └──────────┘           │
└─────────────────────────────────────────────────────┘
```

### Pattern 6: Cmd+K Command Palette

```
┌─────────────────────────────────────────────┐
│ 🔍 Type a command or search...              │
├─────────────────────────────────────────────┤
│ Recent                                       │
│   📦 web-server — container                 │
│   🖼 nginx:latest — image                   │
│                                              │
│ Actions                                      │
│   ▶️ Start Profile "default"         ⌘⇧S    │
│   ⏹ Stop Profile "default"          ⌘⇧X    │
│   📦 Create Container               ⌘N      │
│   ⬇️ Pull Image                     ⌘⇧P    │
│   🧹 Prune All                      ⌘⇧D    │
│                                              │
│ Navigation                                   │
│   🏠 Dashboard                       ⌘1     │
│   📦 Containers                      ⌘2     │
│   🖼 Images                          ⌘3     │
└─────────────────────────────────────────────┘
```


---

## Unique Differentiators for ColimaUI

These are features that **none** of the analyzed platforms do well (or at all) that ColimaUI should own:

### 1. 🎯 Colima-Native Intelligence

**What it is:** Deep integration with Colima's unique capabilities that no generic Docker GUI provides.

- **Profile-aware everything**: Every view scoped to active profile; switch profiles and entire UI updates
- **VM type advisor**: Recommend qemu vs vz vs krunkit based on workload (e.g., "You're running x86 images on ARM — consider enabling Rosetta")
- **Config diff view**: Show what changed between current running config and saved config (like `colima status` vs `~/.colima/default/colima.yaml`)
- **Mount performance advisor**: Suggest virtiofs over sshfs when on macOS 13+, show mount latency indicators

### 2. 🔋 Resource-Aware Operation

**What it is:** The only container GUI that actively helps you use fewer resources.

- **Battery mode**: Auto-detect battery → suggest reducing CPU/memory, pause non-essential containers
- **Idle detection**: If no container activity for N minutes, offer to stop VM (like Docker Desktop's resource saver, but smarter)
- **Right-sizing recommendations**: "Your VM has 8GB allocated but peak usage was 3.2GB this week — consider reducing to 4GB"
- **Cost of running**: Show estimated battery/energy impact of current configuration
- **Workload-based presets**: "Starting AI workload — temporarily boost to 8CPU/16GB? Revert when done?"

### 3. 🧩 Multi-Runtime Unified View

**What it is:** No other GUI manages Docker + containerd + Incus + Kubernetes in one coherent interface.

- **Unified container view**: See containers from all runtimes in one table with runtime badge
- **Runtime comparison**: Side-by-side feature matrix when choosing runtime
- **Migration assistant**: "Move this Docker workflow to containerd" with step-by-step guidance
- **Socket status dashboard**: Show all active sockets (docker.sock, containerd.sock, etc.) with health

### 4. 📋 Clipboard-First Workflow

**What it is:** Optimized for developers who copy-paste between terminal and GUI.

- **Copy as command**: Every GUI action has "Copy as CLI command" (e.g., right-click Start → copies `colima start --cpu 4 --memory 8`)
- **Paste to create**: Paste a `docker run` command → GUI parses it and creates container with those settings
- **Export compose**: Select multiple containers → "Export as docker-compose.yml"
- **Share profile**: "Copy profile as colima template" → shareable YAML

### 5. 🏥 Health & Diagnostics First-Class

**What it is:** Built-in troubleshooting that other GUIs bolt on as afterthoughts.

- **Health score**: Overall system health indicator (VM responsive, docker socket connected, disk not full, etc.)
- **Common issues detector**: Auto-detect known problems (DNS issues, mount failures, socket permission errors)
- **One-click diagnostics bundle**: Collect all logs, config, versions → zip for bug reports
- **Network connectivity tester**: Verify container→internet, container→container, host→container connectivity
- **Performance baseline**: Track startup time, command latency over time — alert on degradation

### 6. ⌨️ Power User Mode

**What it is:** A mode that transforms the GUI into a keyboard-driven power tool (inspired by Lazydocker).

- **Vim-style navigation**: j/k to move through lists, enter to inspect, q to go back
- **Command mode**: `:` to enter commands (like Vim's command mode)
- **Macro recording**: Record a sequence of actions → replay with one shortcut
- **Custom keybindings**: User-configurable keyboard shortcuts
- **Focus mode**: Hide sidebar, maximize content area, keyboard-only navigation

### 7. 🔄 Workflow Automation

**What it is:** Save and replay common workflows — no other container GUI does this.

- **Saved workflows**: "Morning startup" = start VM → pull latest images → start compose stack
- **Scheduled actions**: "Stop VM at 6pm" / "Start VM at 9am on weekdays"
- **Trigger-based automation**: "When disk > 80% → auto-prune images older than 7 days"
- **Workflow sharing**: Export/import workflows as JSON for team sharing

### 8. 🎨 Native macOS Excellence

**What it is:** The most macOS-native container management experience (vs Electron-based competitors).

- **SwiftUI throughout**: No web views, no Electron — pure native performance
- **Spotlight integration**: Search containers/images from macOS Spotlight
- **Shortcuts app integration**: Expose actions as Shortcuts for automation
- **Widgets**: macOS widgets showing container status, resource usage
- **Handoff**: Start viewing logs on Mac, continue on iPad (future)
- **Menu bar as primary UI**: Full functionality from menu bar without opening main window
- **System notifications**: Native macOS notifications for container events

---

## Implementation Priority Matrix

| Phase | Features | Effort | Impact |
|-------|----------|--------|--------|
| **Phase 1: Foundation** | Cmd+K search, keyboard shortcuts, detail drawer, log viewer, dashboard cards | 2 weeks | High — makes app immediately useful |
| **Phase 2: Intelligence** | Resource advisor, battery mode, health score, diagnostics | 2 weeks | High — unique differentiator |
| **Phase 3: Power** | Compose grouping, bulk actions, profile blueprints, app templates | 3 weeks | Medium — catches up to Docker Desktop |
| **Phase 4: Automation** | Workflows, scheduled actions, clipboard commands, Shortcuts integration | 2 weeks | Medium — power user delight |
| **Phase 5: Polish** | Widgets, Spotlight, sparklines, multi-tab, file browser | 3 weeks | Low — nice to have |

---

## Key Design Principles (Derived from Research)

1. **Tray-first, window-second**: 80% of daily interactions should be possible from the menu bar (Multipass, Parallels)
2. **Progressive disclosure**: Simple by default, powerful on demand (Lazydocker's minimal chrome → Docker Desktop's full UI)
3. **Zero-config useful**: App should be useful immediately after install with no setup (Lazydocker)
4. **Keyboard-navigable**: Every action reachable via keyboard (Lazydocker, Lens)
5. **Context-aware actions**: Only show actions that make sense for current state (Lazydocker's bottom bar)
6. **Native over web**: SwiftUI performance and feel over Electron bloat (UTM)
7. **Information density**: Show maximum useful info without clutter (Lazydocker, Portainer)
8. **Colima-specific value**: Don't just wrap Docker — add value specific to Colima's multi-runtime, multi-profile model

---

## Competitive Positioning

```
                    Simple ←────────────────────→ Complex
                    │                                    │
    Tray/CLI ──────┤  Multipass                         │
                    │  Lazydocker                        │
                    │                                    │
                    │      ★ ColimaUI (target)          │
                    │         Rancher Desktop            │
                    │                                    │
    Full GUI ──────┤  UTM        Docker Desktop         │
                    │  OrbStack   Podman Desktop         │
                    │                                    │
    IDE/Web ───────┤             Portainer    Lens      │
                    │                                    │
                    Simple ←────────────────────→ Complex
```

**ColimaUI's sweet spot**: More capable than Multipass/Rancher, lighter than Docker Desktop/Portainer, more native than Podman Desktop, with unique Colima-specific intelligence that no competitor offers.

---

## Guided Setup & AI-Driven Configuration

### 1. Contextual Tooltips (everywhere)

Every setting/option should have a `?` icon that shows a tooltip explaining:
- **What** this setting does
- **When** to change it from default
- **Impact** of changing it (performance, compatibility, resource usage)

Examples:
```
VM Type: [qemu ▾]  ⓘ
┌─────────────────────────────────────────────────────┐
│ VM Type determines the virtualization technology.    │
│                                                      │
│ • qemu — Works everywhere, supports x86 emulation.  │
│   Best for: compatibility, cross-arch builds.        │
│                                                      │
│ • vz — Apple's native framework. 2-3x faster I/O.   │
│   Best for: daily development on Apple Silicon.      │
│   Requires: macOS 13+                                │
│                                                      │
│ • krunkit — Lightweight with GPU access.             │
│   Best for: AI/ML workloads.                         │
│   Requires: Apple Silicon + macOS 13+                │
│                                                      │
│ 💡 Recommended for you: vz (Apple Silicon detected)  │
└─────────────────────────────────────────────────────┘
```

### 2. Guided Setup Wizard (first-run)

On first launch, a step-by-step wizard that asks questions in plain language:

```
Step 1: What will you use Colima for?
  ○ Docker containers for web development
  ○ Kubernetes local cluster
  ○ AI/ML model development
  ○ Cross-platform builds (x86 on ARM)
  ○ Multiple isolated environments
  ○ All of the above

Step 2: How much resources can you spare?
  ○ Light (2 CPU, 4GB) — laptop on battery
  ○ Moderate (4 CPU, 8GB) — daily development
  ○ Heavy (8 CPU, 16GB) — builds & AI workloads
  ○ Let me choose manually

Step 3: Do you need file sharing with the VM?
  ○ Yes, my projects are in ~/Projects (recommended: virtiofs)
  ○ Yes, but I need inotify for hot-reload (recommended: virtiofs + inotify)
  ○ No, containers are self-contained (recommended: disable mounts)

Step 4: Do you use Docker Compose?
  ○ Yes → (installs docker-compose plugin)
  ○ No

[Configure] → Shows summary of what will be set up and why
```

### 3. Setup Summary & Explanation

After wizard completes, show a clear explanation:

```
┌─────────────────────────────────────────────────────┐
│ ✅ Your Colima environment is configured!            │
│                                                      │
│ Here's what was set up and why:                      │
│                                                      │
│ VM Type: vz                                          │
│ → Apple's native virtualization for best performance │
│   on your M2 MacBook Pro                             │
│                                                      │
│ Mount Type: virtiofs                                 │
│ → Fastest file sharing. Your ~/Projects folder is    │
│   accessible inside containers at the same path.     │
│                                                      │
│ Resources: 4 CPU, 8 GB RAM, 100 GB disk             │
│ → Balanced for web development. You have 12 CPU and  │
│   32 GB total — this leaves plenty for macOS.        │
│                                                      │
│ Runtime: Docker                                      │
│ → Standard container runtime. Compatible with all    │
│   docker-compose files and Docker Hub images.        │
│                                                      │
│ Kubernetes: Disabled                                 │
│ → Can be enabled later from Configuration.           │
│                                                      │
│ [Edit Settings]  [Start Colima]  [Copy as YAML]      │
└─────────────────────────────────────────────────────┘
```

### 4. AI-Driven Guided Setup

An AI assistant (local or API-based) that:

**Conversational setup:**
```
🤖 "Hi! I'll help you set up Colima. What are you building?"

You: "I'm working on a Node.js app with PostgreSQL and Redis,
     and I sometimes need to test on x86"

🤖 "Got it! For a Node.js stack with PostgreSQL and Redis, I recommend:
    
    • VM Type: vz (fastest on your M3 Mac)
    • Memory: 8 GB (PostgreSQL likes memory)
    • Mounts: virtiofs with ~/Projects writable
    • Rosetta: enabled (for x86 testing without full emulation)
    
    I'll also create a docker-compose.yml template for your stack.
    
    Want me to set this up? [Yes] [Customize] [Explain more]"
```

**Ongoing AI assistance:**
- "Your PostgreSQL container is using 2GB RAM. Consider increasing VM memory or adding a memory limit to the container."
- "You're pulling x86 images on ARM. Enable Rosetta for 5x faster execution."
- "Container 'api' restarted 3 times in 5 minutes. Check logs? [View Logs]"
- "Your disk is 85% full. Prune unused images to free 12GB? [Prune]"

**Implementation options:**
1. **Local LLM** (via Colima's own AI workloads feature — dogfooding!)
   - Run a small model (TinyLlama/Phi-3) inside Colima itself
   - Zero API costs, works offline
   - Slower but private

2. **OpenAI/Claude API** (optional, user provides key)
   - Faster, smarter recommendations
   - Can analyze docker-compose files and suggest optimizations
   - Privacy-conscious: only sends config metadata, not code

3. **Rule-based fallback** (no AI needed)
   - Hardcoded recommendations based on hardware detection
   - "Apple Silicon + macOS 13+ → recommend vz + virtiofs"
   - "< 8GB total RAM → recommend light config"
   - Works offline, instant, deterministic

### 5. Smart Defaults Based on Hardware Detection

On first launch, auto-detect and pre-fill:
```swift
// Detect hardware
let cpuCount = ProcessInfo.processInfo.processorCount
let totalRAM = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
let isAppleSilicon = // check arch
let macOSVersion = ProcessInfo.processInfo.operatingSystemVersion

// Smart defaults
if isAppleSilicon && macOSVersion >= 13 {
    vmType = "vz"
    mountType = "virtiofs"
} else {
    vmType = "qemu"
    mountType = "sshfs"
}

cpus = min(cpuCount / 2, 8)  // Half of available, max 8
memory = min(totalRAM / 2, 16)  // Half of available, max 16GB
```

### 6. Inline Setting Recommendations

In the Configuration view, show recommendations inline:

```
CPUs: [4 ▾]  💡 You have 12 cores. 4 is good for development.
              ⚠️ Increase to 8 for faster builds.

Memory: [8 ▾] 💡 32 GB total. 8 GB leaves plenty for macOS.
               ⚠️ AI workloads need 16+ GB.

Mount Type: [virtiofs ▾] ✅ Best choice for your setup (vz + macOS 14)
```

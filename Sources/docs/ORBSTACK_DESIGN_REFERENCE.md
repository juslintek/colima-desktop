# OrbStack Design Reference — Permanent

## Sidebar Structure (exact)
```
Docker
  📦 Containers
  💾 Volumes
  🖼️ Images
  🔗 Networks
Kubernetes
  🟢 Pods
  🔵 Services
Linux
  🖥️ Machines
General
  📊 Activity Monitor
  ⌨️ Commands
```

## Containers View
- **Middle column**: List with "N running" subtitle badge
  - Running section (no header, just listed first)
  - "Stopped" section header
  - Each row: colored icon + name + image subtitle + icon-only actions (stop/start, delete)
  - Actions appear on hover only
- **Right column tabs**: Info | Stats | Logs | Terminal | Files
  - "No Selection" placeholder when nothing selected
  - All tab content renders INSIDE the tab content area (not as sheets/modals)
- **Toolbar**: Sort ↕️, Refresh 🔄, Search 🔍, Add ➕

## Images View
- **Middle column**: List with In Use / Unused sections
- **Right column tabs**: Info | Terminal | Files
- Must be SELECTABLE/CLICKABLE (user reported it's not working)

## Volumes View
- **Middle column**: List with In Use / Unused sections
- **Right column tabs**: Info | Files

## Networks View
- **Middle column**: List
- **Right column**: Info only (no tabs, just info panel)

## All lists have SORTING

## Kubernetes — Pods
- **Right column tabs**: Info | Stats | Logs | Terminal
- "Show System Namespace" toggle → shows kube-system pods
- Each kube-system pod has same 4 tabs

## Kubernetes — Services
- Simple list with info in right column

## Activity Monitor
- **Full-width** (no three-column split)
- Tree view: Containers (expandable) → child containers, Engine
- Columns: Name, CPU%, Memory
- Footer: 4 sparkline cards (Total CPU, Memory, Network, Disk)
- Each sparkline: label + value + mini chart

## Virtual Machines (Machines)
- Will support Linux, macOS, Windows
- Creation dialog: advanced, 5 tabs same as Containers

## User Feedback (Critical Fixes Needed)
1. ❌ "4 running" badge looks bad merged into header — put in separate bubble
2. ❌ Dashboard stat cards look like "AI slop" — REMOVE entirely
3. ❌ Images not clickable/selectable, nothing in 3rd column
4. ❌ Volumes not clickable/selectable, nothing in 3rd column
5. ❌ Networks not clickable/selectable, nothing in 3rd column
6. ✅ Container tabs should show content INSIDE tab area (not sheets)
7. ✅ Hover on list items should look like macOS Spotlight split
8. ✅ All views need sorting

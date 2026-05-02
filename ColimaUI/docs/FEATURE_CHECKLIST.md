# ColimaUI Feature Checklist

Legend: `[ ]` Not started · `[T]` Test written · `[x]` Implemented & tested

---

## 1. Colima VM Lifecycle Commands (15 features)

- [x] 1.1 Start VM with default profile
- [x] 1.2 Stop VM
- [x] 1.3 Restart VM
- [x] 1.4 Delete VM (soft delete, preserve data)
- [x] 1.5 Delete VM (hard delete with --data)
- [x] 1.6 Show VM status
- [x] 1.7 List all profiles
- [x] 1.8 SSH into VM
- [x] 1.9 Show SSH config
- [x] 1.10 Update Colima
- [x] 1.11 Prune unused data
- [x] 1.12 Show version info
- [x] 1.13 Generate config template
- [x] 1.14 Clone profile
- [x] 1.15 Model setup command

## 2. Configuration — VM Resources (4 features)

- [x] 2.1 CPU slider/stepper
- [x] 2.2 Memory slider/stepper
- [x] 2.3 Disk size slider/stepper
- [x] 2.4 Root disk size field

## 3. Configuration — VM Settings (10 features)

- [x] 3.1 Architecture picker (aarch64, x86_64, host)
- [x] 3.2 VM type picker (qemu, vz, krunkit)
- [x] 3.3 CPU type field
- [x] 3.4 Rosetta toggle (VZ only)
- [x] 3.5 Nested virtualization toggle
- [x] 3.6 Hostname field
- [x] 3.7 Disk image path field
- [x] 3.8 Binfmt toggle
- [x] 3.9 Foreground toggle
- [x] 3.10 Port forwarder picker (ssh, grpc, none)

## 4. Configuration — Runtime (5 features)

- [x] 4.1 Runtime picker (docker, containerd, incus)
- [x] 4.2 Auto-activate toggle
- [x] 4.3 Docker daemon config editor (JSON)
- [x] 4.4 Model runner picker (docker, ramalama)
- [x] 4.5 Save/load config YAML

## 5. Configuration — Kubernetes (4 features)

- [x] 5.1 Kubernetes enabled toggle
- [x] 5.2 Kubernetes version field
- [x] 5.3 k3s args list editor
- [x] 5.4 Kubernetes API port field

## 6. Configuration — Network (9 features)

- [x] 6.1 Network address toggle
- [x] 6.2 Network mode picker (shared, bridged)
- [x] 6.3 Network interface field
- [x] 6.4 DNS servers list editor
- [x] 6.5 DNS host mappings editor
- [x] 6.6 Gateway address field
- [x] 6.7 Host addresses toggle
- [x] 6.8 Preferred route toggle
- [x] 6.9 Port forwarder display

## 7. Configuration — Volume Mounts (4 features)

- [x] 7.1 Mounts table (location, writable) with add/remove
- [x] 7.2 Mount type picker (sshfs, 9p, virtiofs)
- [x] 7.3 Mount inotify toggle
- [x] 7.4 Disable all mounts option

## 8. Configuration — SSH (3 features)

- [x] 8.1 SSH port field
- [x] 8.2 Forward agent toggle
- [x] 8.3 SSH config auto-update toggle

## 9. Configuration — Provisioning (2 features)

- [x] 9.1 Provisioning scripts list (mode + script) with add/remove
- [x] 9.2 Script mode picker (system, user)

## 10. Configuration — Environment (3 features)

- [x] 10.1 Environment variables key-value editor with add/remove
- [x] 10.2 Immutable setting detection (lock icons on arch/vmType/runtime/mountType)
- [x] 10.3 Template management (load/save defaults)

## 11. Profiles (12 features)

- [x] 11.1 List all profiles with status
- [x] 11.2 Create new profile (dialog with name/cpus/memory/runtime)
- [x] 11.3 Delete profile (soft)
- [x] 11.4 Delete profile (hard with --data)
- [x] 11.5 Start profile
- [x] 11.6 Stop profile
- [x] 11.7 Restart profile
- [x] 11.8 Clone profile (dialog with source/dest)
- [x] 11.9 Profile switcher in sidebar
- [x] 11.10 Docker context switching per profile
- [x] 11.11 COLIMA_PROFILE env var display
- [x] 11.12 COLIMA_HOME env var display

## 12. Docker Container Management (22 features)

- [x] 12.1 List containers (running + stopped)
- [x] 12.2 Create container (dialog with name + image)
- [x] 12.3 Start container (per-row, state change + toast)
- [x] 12.4 Stop container (per-row, state change + toast)
- [x] 12.5 Kill container (per-row, state change + toast)
- [x] 12.6 Restart container (per-row, state change + toast)
- [x] 12.7 Remove container (per-row, confirmation + row removal + toast)
- [x] 12.8 Pause container (per-row, state change + toast)
- [x] 12.9 Unpause container (per-row, state change + toast)
- [x] 12.10 Rename container (per-row, toast)
- [x] 12.11 Export container (per-row, toast)
- [x] 12.12 View container logs (per-row, toast)
- [x] 12.13 Inspect container (per-row, toast)
- [x] 12.14 Exec into container (per-row, toast)
- [x] 12.15 Show container top processes (per-row, toast)
- [x] 12.16 Show container stats (per-row, toast)
- [x] 12.17 Prune stopped containers (toast)
- [x] 12.18 Show container changes/diff (per-row, toast)
- [x] 12.19 Wait for container (per-row, toast)
- [x] 12.20 Attach to container (per-row, toast)
- [x] 12.21 Update container resources (per-row, toast)
- [x] 12.22 Copy files to/from container (per-row, toast)

## 13. Docker Image Management (11 features)

- [x] 13.1 List images
- [x] 13.2 Pull image (adds row + toast)
- [x] 13.3 Remove image (per-row, removes row + toast)
- [x] 13.4 Inspect image (per-row, toast)
- [x] 13.5 Show image history (per-row, toast)
- [x] 13.6 Tag image (per-row, toast)
- [x] 13.7 Push image (per-row, toast)
- [x] 13.8 Export image/save (per-row, toast)
- [x] 13.9 Import image/load (toast)
- [x] 13.10 Search images (Docker Hub search, toast)
- [x] 13.11 Prune unused images (toast)

## 14. Docker Volume Management (5 features)

- [x] 14.1 List volumes
- [x] 14.2 Create volume (dialog, adds row + toast)
- [x] 14.3 Remove volume (per-row, removes row + toast)
- [x] 14.4 Inspect volume (per-row, toast)
- [x] 14.5 Prune unused volumes (toast)

## 15. Docker Network Management (7 features)

- [x] 15.1 List networks
- [x] 15.2 Create network (dialog, adds row + toast)
- [x] 15.3 Remove network (per-row, removes row + toast)
- [x] 15.4 Inspect network (per-row, toast)
- [x] 15.5 Connect container to network (per-row, toast)
- [x] 15.6 Disconnect container from network (per-row, toast)
- [x] 15.7 Prune unused networks (toast)

## 16. Runtime Controls (6 features)

- [x] 16.1 Docker context management (switch context, toast)
- [x] 16.2 Containerd nerdctl passthrough (command field + run, toast)
- [x] 16.3 Incus command passthrough (command field + run, toast)
- [x] 16.4 Runtime switching (picker + confirmation + toast)
- [x] 16.5 Runtime update command (toast)
- [x] 16.6 Data persistence indicator (per-runtime display)

## 17. AI Workloads (8 features)

- [x] 17.1 Krunkit availability check (status indicator)
- [x] 17.2 Model run interactive (toast)
- [x] 17.3 Model serve web UI (toast)
- [x] 17.4 Registry browser (Docker AI, HuggingFace, Ollama display + browse button)
- [x] 17.5 Runner picker (docker, ramalama)
- [x] 17.6 Model setup command (toast)
- [x] 17.7 Resource recommendations display (table)
- [x] 17.8 AI profile quick-create (toast)

## 18. Monitoring (8 features)

- [x] 18.1 Container stats (CPU, memory, network, disk per container)
- [x] 18.2 VM resource usage (CPU, memory, disk with progress bars)
- [x] 18.3 Process monitoring (process list with PID/User/CPU/MEM/Command/Container)
- [x] 18.4 Memory Governor indicator (tier display with accessibilityValue)
- [x] 18.5 Disk usage breakdown (containers/images/volumes/build cache)
- [x] 18.6 Network I/O stats (per container)
- [x] 18.7 Container count summary (running/stopped/paused)
- [x] 18.8 Auto-refresh toggle

## 19. Community (5 features)

- [x] 19.1 GitHub discussions feed link (toast)
- [x] 19.2 Issue reporting (3-step wizard with repo picker + submit)
- [x] 19.3 FAQ tips display (12 entries covering all FAQ sections)
- [x] 19.4 Release notes link (toast)
- [x] 19.5 Documentation links (toast)

## 20. App Shell & UX (15 features)

- [x] 20.1 Menu bar icon with status (wired to AppState)
- [x] 20.2 Menu bar popover (Start/Stop/Restart wired, live counts)
- [x] 20.3 Sidebar navigation (12 tabs including Runtime Controls)
- [x] 20.4 Activation policy switching (dock ↔ menubar)
- [x] 20.5 Toast notification system (accessibilityIdentifier, auto-dismiss)
- [x] 20.6 Dark mode support (native SwiftUI)
- [x] 20.7 Light mode support (native SwiftUI)
- [x] 20.8 Keyboard navigation (native SwiftUI)
- [x] 20.9 Accessibility identifiers on all elements (209 unique IDs)
- [x] 20.10 NavigationSplitView layout
- [x] 20.11 Status indicator (running/stopped with accessibilityValue)
- [x] 20.12 Loading states (isLoading in AppState)
- [x] 20.13 Error state displays (errorMessage in AppState)
- [x] 20.14 Confirmation dialogs for destructive actions (requestConfirmation)
- [x] 20.15 Window title and toolbar

## 21. Installer & Uninstaller (4 features)

- [ ] 21.1 Homebrew install detection
- [ ] 21.2 Dependency check (docker, kubectl, etc.)
- [ ] 21.3 First-run setup wizard
- [ ] 21.4 Uninstall cleanup

---

## Summary

| Section | Features | Implemented | Tested |
|---------|----------|-------------|--------|
| 1. VM Lifecycle | 15 | 15 | 15 |
| 2. Config Resources | 4 | 4 | 4 |
| 3. Config VM | 10 | 10 | 10 |
| 4. Config Runtime | 5 | 5 | 5 |
| 5. Config K8s | 4 | 4 | 4 |
| 6. Config Network | 9 | 9 | 9 |
| 7. Config Mounts | 4 | 4 | 4 |
| 8. Config SSH | 3 | 3 | 3 |
| 9. Config Provisioning | 2 | 2 | 2 |
| 10. Config Environment | 3 | 3 | 3 |
| 11. Profiles | 12 | 12 | 12 |
| 12. Containers | 22 | 22 | 22 |
| 13. Images | 11 | 11 | 11 |
| 14. Volumes | 5 | 5 | 5 |
| 15. Networks | 7 | 7 | 7 |
| 16. Runtime Controls | 6 | 6 | 6 |
| 17. AI Workloads | 8 | 8 | 8 |
| 18. Monitoring | 8 | 8 | 8 |
| 19. Community | 5 | 5 | 5 |
| 20. App Shell | 15 | 15 | 15 |
| 21. Installer | 4 | 0 | 0 |
| **TOTAL** | **162** | **158** | **158** |

> 4 remaining features (Section 21: Installer) are deferred to the `.pkg` packaging phase.

## Test Coverage

| Metric | Count |
|--------|-------|
| XCUITest files | 13 |
| Total test methods | 170 |
| Behavioral clicks | 135 |
| Toast assertions | 83 |
| Value/label assertions | 90 |
| Predicate expectations | 40 |
| Accessibility IDs | 209 |

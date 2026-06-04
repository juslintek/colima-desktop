# E2E Coverage Audit & Test Plan

**Mode:** mock (`--ui-testing` → `MockServiceProvider`). Verifies UI flows, not real runtime.

---

## 1. Is coverage 100%?

**No.** The suite (297 tests) covers presence/navigation/enable-state/option-availability for
every view, and full lifecycle *flows* for profiles, k8s, and native-perf config. It does
**not** cover: detail-tab content, many config sub-editors, constraint/validity logic between
options, the create-container option matrix, sheets (logs/stats/inspect/changes), the setup
wizard, command palette, menu-bar extra, or dark/light + resize. Operational behavior
(does nginx actually serve?) is **out of scope for mock mode** — see §4.

## 2. Coverage matrix

| View / Flow | Covered | Gaps |
|---|---|---|
| App shell / tabs / navigation | ✅ tabs, status, tables load | keyboard nav, Cmd+K palette |
| Dashboard | ✅ status, terminal panel/field, lifecycle buttons | ResourceAdvisor cards, action cards, copy buttons |
| Containers list | ✅ rows, start/stop/remove, hub search, create dialog open | pause/unpause/kill/rename, prune, **detail tabs** (Info/Stats/Logs/Terminal/Files) |
| Create container (live sheet) | ⚠️ dialog opens | live sheet captures **name + image only** (+ browse/suggestions, local-image hint, name validation). Covered: row appears per popular image, validation, cancel. **No** ports/env/volume/platform/restart fields exist in the live UI |
| Create container (orphaned `CreateContainerView.swift`) | ❌ unreachable | has platform/restart/command/entrypoint/workingDir/flags but is **not wired** to any button — dead code; either wire it up or delete |
| Images | ✅ rows, search, pull, remove | tag, push, history, inspect, prune, In-Use/Unused split, pull progress |
| Volumes | ✅ rows, create, remove | inspect, prune, Info/Files tabs |
| Networks | ✅ rows, create, remove | inspect, connect/disconnect, prune |
| Kubernetes | ✅ enable/disable/reset, quick actions, Pods/Services/Deployments/Nodes/Events tabs, namespace, refresh | resource table content, command-runner output |
| Configuration (resources) | ✅ cpus/memory/disk/rootdisk fields exist | stepper increment/decrement effect, disk increase-only rule |
| Configuration (native perf) | ✅ all vmType/cpuType/mountType, arch/runtime/portForwarder/networkMode/modelRunner options, 5 toggles | **constraint logic** (vz→virtiofs, qemu→9p, rosetta needs vz, nestedVirt needs vz) |
| Configuration (advanced) | ✅ remove mount/provision/env, save/reset/editYAML | DNS presets, gateway validation, SSH port, docker JSON editor, k8s version/k3sArgs, add-mount full flow, provision add, env-var dialog, save persistence |
| Profiles / VM lifecycle | ✅ create/clone/remove/validate, start/stop/restart buttons | switch active profile, per-profile config |
| Monitoring | ✅ table, rows, navigation | sparklines, context-menu actions, scoped stats, kill process |
| AI Workloads | ⚠️ run button, status, model field | setup progress flow, model browser registries, pull progress, serve port |
| Runtime Controls | ✅ context/name/version/socket | update runtime flow, history limit |
| Community | ✅ discussion buttons, issue wizard start | full issue wizard steps |
| Machines | ✅ rows, buttons, running count | create dialog, per-OS flows |
| Setup Wizard | ❌ none | guided setup end-to-end |
| MenuBar extra | ❌ none | menu items, quick actions |

## 3. Configuration combinatorial matrix (to add)

Individual options are covered; the **validity/constraint logic between them is not**. These
are the high-value combos to assert (the UI should recommend/restrict accordingly):

| vmType | mountType | runtime | arch | rosetta | nestedVirt | Valid? | UI should… |
|---|---|---|---|---|---|---|---|
| vz | virtiofs | docker | aarch64 | off | off | ✅ | default-recommend virtiofs |
| vz | 9p | docker | — | — | — | ❌ | 9p not offered/recommended for vz |
| vz | virtiofs | docker | aarch64 | **on** | off | ✅ | rosetta allowed (vz+ARM) |
| qemu | 9p | docker | aarch64 | — | — | ✅ | 9p recommended for qemu |
| qemu | virtiofs | docker | — | on | — | ⚠️ | rosetta only valid with vz |
| krunkit | virtiofs | docker | aarch64 | — | — | ✅ | enables modelRunner/AI |
| vz | virtiofs | docker | aarch64 | off | **on** | ⚠️ | nestedVirt needs M3+ + vz |
| any | — | containerd | — | — | — | ✅ | nerdctl path |
| any | — | incus | — | — | — | ✅ | incus path |

Plus resource ranges: cpu {1,2,4,8}, memory {2,4,8,16} GiB, disk increase-only,
portForwarder {ssh,grpc,none}, networkMode {shared,bridged}, k8s {enabled,version,port}.

## 4. Popular images & their configs

The create-container form captures **image string, platform, name, restart policy, command,
entrypoint, workingDir, privileged/readOnly/init** — but has **no ports/env/volume fields**,
and the mock stores only name+image. So in **mock mode** we can verify the form accepts each
image + options and the row appears; we **cannot** verify the container actually runs/serves.

| Image | Typical real config | Mock-testable here | Needs real backend |
|---|---|---|---|
| `nginx:latest` | `-p 80:80` | image+platform+row appears | serves on :80 |
| `postgres:16` | `-e POSTGRES_PASSWORD=…`, `-v pgdata:/var/lib/postgresql/data` | image+restart=always | accepts connections |
| `redis:7` | `-p 6379:6379` | image+row | PING/PONG |
| `mysql:8` | `-e MYSQL_ROOT_PASSWORD=…` | image | query |
| `mongo:7` | `-p 27017:27017`, volume | image | connect |
| `node:20-alpine` | command, workingDir, `-v .:/app` | image+command+workingDir | build/run |
| `python:3.12-slim` | command, entrypoint | image+entrypoint+command | run script |
| `httpd:2.4` | `-p 8080:80` | image | serves |
| `traefik:v3` | ports, command args | image+command | routes |
| `busybox` / `alpine` | command, `--init` | image+command+init flag | exec |

**Recommendation:** to make "see how they operate" meaningful, either (a) add ports/env/volume
fields to `CreateContainerView` + extend `createContainer` in the provider and assert on the
created container's stored config (mock-verifiable), or (b) cover operation in **real-backend
integration tests** on bare metal (no nested virt in the VM — see FLAKINESS_ANALYSIS.md §Scope).

## 5. Planned new E2E tests (feasible in mock mode now)

1. **ContainerImageConfigUITests** — create container per popular image (`nginx:latest`,
   `postgres:16`, `redis:7`, `node:20-alpine`, `python:3.12-slim`), set platform + restart
   policy + flags, confirm, assert the new row appears with the chosen image.
2. **ContainerLifecycleExtendedUITests** — pause/unpause/kill/rename/prune; detail tab presence.
3. **ConfigConstraintUITests** — vmType↔mountType recommendation logic; rosetta/nestedVirt
   availability vs vmType; resource stepper increment effect.
4. **ImageOpsUITests** — pull popular image → row appears; remove; tag; history/inspect open.

Items requiring app changes (ports/env/volume fields, operational verification) are flagged
for a follow-up and for real-backend integration tests.

# Colima Desktop — Exploration Findings

**Date:** 2026-06-19 · **Build:** v0.1.0 (Debug) · **Backend:** real, against live colima
`default` (Running, 2 CPU / 2 GiB) + Lima · **Host:** macOS 26.5, Apple Silicon (12 cores / 32 GiB),
colima 0.10.1, docker 29.5.2.

## Method & constraints
Each view was launched deep-linked (`--open-tab <name>`, added for deterministic capture),
screenshotted, and quit. Screenshots + per-shot context: `manifest.json` + `screenshots/`.
The full action/outcome space (7,996 rows) is enumerated in `../truth-table.csv` (built first).

**Honest constraint:** XCUITest cannot drive the host (it times out enabling automation mode),
and the host machine can't run nested colima — so literal automated 1000+ click-combinations with a
screenshot each is not feasible. Coverage here = every view against the real backend + the
combinatorial space enumerated in the truth table + representative automation in the XCUITest
suites (~320, mock) and RealBackendTests (35, real service layer).

## Real-data status by view

| # | View | Real data? | Source |
|---|------|-----------|--------|
| 1 | Dashboard | ✅ | vmStatus, real `colima status` in terminal |
| 2 | Containers | ✅ | Docker API listContainers |
| 3 | Images | ✅ | Docker API listImages |
| 4 | Volumes | ✅ | Docker API listVolumes |
| 5 | Networks | ✅ | Docker API listNetworks |
| 6 | Kubernetes | ✅ | real `kubectl get … -o json` (empty unless enabled) |
| 7 | Machines | ✅ **(fixed)** | `limactl list --json` |
| 8 | Profiles | ✅ | `colima list --json` |
| 9 | Configuration | ✅ | reads/writes real `colima.yaml`; steppers show real host capacity |
| 10 | AI Workloads | ❌ **(gap)** | hardcoded model catalog/status |
| 11 | Monitoring | ✅ | containerStats |
| 12 | Runtime Controls | ✅ | docker context / runtime |
| 13 | Community | ❌ **(gap)** | hardcoded discussions |

## Mocks / hardcodes FOUND and FIXED (this pass)

1. **Dashboard › Smart Recommendations (`ResourceAdvisor.swift`)** — was emitting fabricated
   strings regardless of reality: "Current: 4 CPU, 8 GiB", "Peak usage this week: 2.1 CPU,
   3.2 GiB", "2 containers run x86 images", and the buttons only showed a toast.
   **Fixed:** recommendations now derive from real `appState` (vmCPU/vmMemory, running-container
   count, host core count, Low Power Mode); fabricated peak/x86 claims removed; buttons perform
   real actions (Stop VM / open Configuration). *Verified live:* now reads "VM is idle but holding
   2 CPU, 2 GiB" matching the real profile.
2. **Machines (`MachinesView.swift`)** — was a hardcoded global `mockVMs` (fake
   dev-ubuntu/build-fedora/macos-ci/win11-test). **Fixed:** real Lima VMs via
   `limactl list --json` (`DaemonClient.listMachines` → `ServiceProvider.listMachines` →
   `AppState.machines`/`refreshMachines`). *Verified live:* shows the real `default` Lima VM
   (Linux aarch64, 4 CPU / 4 GB). The mock provider still returns the 4 fixtures the XCUITest asserts.
3. **`MockDetailData.swift`** — dead code (0 consumers; detail sheets already use the real Docker
   API). **Deleted.**

## Hardcoded CONTENT still present (flagged, not silently faked)

These are content/catalog data with no trivially-correct real source; documented rather than
faked. Real wiring is feature-level:

- **AI Workloads (`MockK8sData.aiModels`, `dockerAIModels`, `huggingFaceModels`,
  `ollamaModels`)** — model catalog + "Active Models" (e.g. phi4 "serving @ localhost:8080") are
  static. Also the "VM type is qemu" prerequisite badge is hardcoded (the live profile is vz).
  **Real wiring:** `colima model list/pull/run/serve` (requires `vmType=krunkit` + model runner)
  and the real active VM type from `vmStatus`.
- **Community (`MockK8sData.discussions`)** — discussion list is static.
  **Real wiring:** GitHub Discussions API (+ auth) for `juslintek/colima-desktop`.

## Other observations

- **Naming wart (not a bug):** model types are prefixed `Mock*` (`MockContainer`, `MockImage`,
  `MockVM`, `MockK8sResource`, …) but are the *real* models populated from the live backend.
  Recommend renaming (e.g. drop the `Mock` prefix) for clarity; cosmetic only.
- **Backend is genuinely real:** `RealServiceProvider` + `DockerClient` (HTTP over the unix
  socket) + `DaemonClient` (colima/limactl/kubectl via Process) contain **no** mock/hardcoded
  data; proven by `RealBackendTests` (35 live tests) and the live exploration above. The only
  `Mock*` *provider* is `MockServiceProvider`, used solely with `--backend-mock` (tests/CI).
- **Minor warning:** `ConfigurationView.swift:838` uses `@ViewBuilder` + an explicit `return`
  (compiler warning). Cosmetic; safe to clean up.
- **Config steppers** correctly cap at real host capacity (12 cores / 32 GiB) and show free
  headroom — real, not hardcoded.

## Recommended follow-ups (priority)
1. P1 — Wire AI "Active Models" + VM-type badge to real `colima model …` / `vmStatus` (or clearly
   label the catalog as a static registry browser).
2. P2 — Community discussions via GitHub API, or relabel as curated links.
3. P3 — Rename `Mock*` model types; fix the ConfigurationView `@ViewBuilder` warning.

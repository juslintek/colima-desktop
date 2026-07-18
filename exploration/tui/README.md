# TUI Ground-Truth Exploration

## Overview

This directory contains the TUI (Bubble Tea / Go) ground-truth capture for Colima Desktop.
All 11 surfaces were captured using real binary execution in a pseudo-terminal (PTY) plus
deterministic model-direct rendering with `fakeDS`.

## Capture Method

**Hybrid: PTY screenshots + model-direct content**

- **PTY screenshots**: The real `colima-tui` binary was spawned in a pseudo-terminal
  with `TERM=xterm-256color`, `120×40` dimensions. Bubble Tea's initial terminal-capability
  queries (`\x1b]11;?` background colour, `\x1b[6n` cursor position) were responded to
  so the TUI unblocked and rendered. Navigation keys (1-9, 0, →) were sent to traverse
  all 11 tabs. Raw ANSI frames were captured and stored in `screenshots/*.ansi`.

- **Model-direct content**: `go run driver_explore.go` inside `tui/` drives the
  `ui.Model` directly with a deterministic `fakeDS` (no daemon needed), calling `View()`
  at each tab after applying navigation key messages. This produces content-rich frames
  (containers list, images list, config values, etc.) with distinct fingerprints per tab.
  This is the source of `normalized_frame` and `content_fingerprint` in the JSON.

## Surfaces

| # | Surface       | Key | Content Proof                               |
|---|---------------|-----|---------------------------------------------|
| 0 | Dashboard     | `1` | Colima Desktop header, surfaces list        |
| 1 | Containers    | `2` | /web-nginx, /db-postgres, /cache-redis      |
| 2 | Images        | `3` | nginx:latest, postgres:15, redis:7          |
| 3 | Volumes       | `4` | postgres-data (local), redis-cache (local)  |
| 4 | Networks      | `5` | bridge, host, app-network                   |
| 5 | Kubernetes    | `6` | Kubernetes: disabled, Actions: start/stop   |
| 6 | Configuration | `7` | CPU:4, Memory:8.0GiB, Disk:100GiB, vz     |
| 7 | Runtime       | `8` | Runtime: docker, VM type: vz, aarch64      |
| 8 | AI Workloads  | `9` | model setup/run/serve/stop actions          |
| 9 | Profiles      | `0` | default/k8s-dev/production profiles table  |
|10 | Machines      | `→` | colima-default/colima-k8s-dev/lima-rancher  |

## Files

```
ground-truth.json          — Main ground-truth record (11 surfaces, all validated)
screenshots/00_dashboard.*  — Dashboard: .ansi (raw PTY) + .txt (stripped)
screenshots/01_containers.* — Containers view
screenshots/02_images.*     — Images view
screenshots/03_volumes.*    — Volumes view
screenshots/04_networks.*   — Networks view
screenshots/05_kubernetes.* — Kubernetes view
screenshots/06_configuration.* — Configuration view
screenshots/07_runtime.*    — Runtime view
screenshots/08_ai_workloads.* — AI Workloads view
screenshots/09_profiles.*   — Profiles view
screenshots/10_machines.*   — Machines view
```

## Validation

- `total_surfaces`: 11 ✓
- `all_nonempty`: true ✓
- `all_distinct`: true ✓ (all 11 content fingerprints are unique)
- `validation_pass`: true ✓

## Regenerate

```bash
# From repo root:
python3 scripts/tui/explore.py
```

Requires Go (tui builds), Python 3.9+. No daemon needed (model-direct uses fakeDS).

## Notes

- PTY screenshots show "daemon unreachable" in the body for tabs that call gRPC
  (expected — no live daemon during exploration).
- The tab bar and navigation are fully verified via PTY (real rendering).
- Body content is verified via model-direct (deterministic fakeDS).
- The `driver_explore.go` file (in `tui/`) uses `//go:build ignore` and is not
  compiled as part of the normal build.

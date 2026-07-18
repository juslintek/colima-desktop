# Exploration Ground-Truth Artifacts

This directory contains per-platform UI exploration results (M3.9) and the unified
cross-platform analysis (M3.10). Each subdirectory holds an independent runtime capture
produced by a platform-specific accessibility/automation explorer.

## Quick Reference

| File | Contents | Produced by |
|------|----------|-------------|
| `ground-truth.json` | **Unified** — schema v1.0, surface matrix, discrepancies, validation summary | crossplatform-parity-auditor (M3.10) |
| `macos/ground-truth.json` | 13 surfaces, 1,847 AX elements, **live backend** | explore-ax.sh + Peekaboo |
| `windows/ground-truth.json` | 13 surfaces, 699 UIA elements, CI capture | FlaUI/UIA3 (scripts/windows/Program.cs) |
| `linux/ground-truth.json` | 12 surfaces, 887 AT-SPI elements, CI capture | pyatspi + xdotool (scripts/linux/explore_atspi.py) |
| `tui/ground-truth.json` | 12 PTY surfaces, fakeDS stub data, all fingerprints unique | PTY driver (tui/driver_explore.go) |

## Key Facts

- **macOS is the only live-backend capture.** Windows, Linux, and TUI were captured in
  CI environments without a running colima daemon. Element counts on non-macOS platforms
  reflect UI chrome and widget structure, not populated data rows.

- **TUI data is fakeDS.** The TUI explorer uses a `fakeDS` DataSource to inject stub
  rows (mock containers, profiles, etc.) so surfaces render non-empty content. This
  verifies structure, not real data.

- **Linux navigation is xdotool coordinate-based.** AT-SPI doAction/component-extent
  navigation was removed after proving it produced mislabeled captures (pass 8). The
  xdotool positional grid is the authoritative method.

- **12 surfaces are common to all 4 platforms** (runtime-verified): Dashboard,
  Containers, Images, Volumes, Networks, Kubernetes, Configuration, Machines, Profiles,
  AI Workloads, Runtime, Monitoring. Two extras are platform-specific: Community
  (macOS-only), Settings (Windows-only).

## Unified Ground-Truth Schema

`ground-truth.json` follows schema version 1.0:

```
{
  schema_version, generated_at, generator, description,
  source_artifacts: { macos, windows, linux, tui → path, sha256, capture_method, verified_status },
  platform_summaries: { per-platform element counts, limitations, backend_connected },
  canonical_surface_matrix: [ 14 surfaces × {captured per platform, notes} ],
  runtime_only_discrepancies: { active: [DISC-01…07 excl. 03], resolved: [DISC-03] },
  explicit_limitations: [ ... ],
  validation_summary: { overall_status, gaps_requiring_action, ... }
}
```

Raw element arrays (AX, UIA, AT-SPI) are in the per-platform source files only —
the unified file embeds summaries and references, not all elements.

## Platform-Specific Capture Notes

### macOS (`macos/`)
- Method: System Events `entire contents` traversal (12 surfaces); Peekaboo AX
  snapshot fallback for Configuration (448-element tree caused timeout)
- Environment: macOS 26.5.2, aarch64, real colima 0.10.1, AX + screen-recording granted
- Screenshots: 13 PNG files in `macos/screenshots/`

### Windows (`windows/`)
- Method: FlaUI 4.0.0 / UIA3 (UIAutomationClient COM); Click-first navigation;
  mainWindow + navItem re-resolved per iteration to avoid stale COM refs
- Environment: GitHub Actions, Windows NT 10.0.26100.0 x64, unpackaged WinUI 3
- Screenshots: 13 PNG files in `windows/screenshots/`
- Pass history: 6 diagnostic passes documented in `windows/README.md`

### Linux (`linux/`)
- Method: pyatspi DFS (read-only) + xdotool positional grid; GTK_A11Y=atspi;
  colima shimmed via `scripts/linux/colima_shim.sh`
- Environment: GitHub Actions, Ubuntu, Xvfb :99, no live daemon
- Surfaces: 12 (including Monitoring — added after DISC-03 implementation)
- Screenshots: 13 PNG files in `linux/screenshots/`
- Pass history: 8+ diagnostic passes; see `linux/README.md`

### TUI (`tui/`)
- Method: PTY headless driver (tui/driver_explore.go), 120×40 terminal, fakeDS stub data
- Environment: GitHub Actions, linux/amd64, Go 1.25.0, no live daemon
- Surfaces: 12 (including Monitoring — added after DISC-03 implementation)
- Screenshots: ANSI + plaintext files in `tui/screenshots/`
- See `tui/README.md` for capture methodology details

## Related Documents

- `docs/gap-report.md` — evidence-based gap analysis (M3.10)
- `docs/parity/overview.md` — parity model and dimension definitions
- `docs/parity-matrix.md` — per-RPC tracking table
- `.kiro/board/CONTRACT.md` — frozen API contract v1

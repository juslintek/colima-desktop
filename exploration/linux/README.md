# Linux AT-SPI2 Exploration

## Status

**UI-chrome capture: `CI-without-daemon` (succeeded).** After the AT-SPI backend fix
(`GTK_A11Y=atspi`) and xdotool positional-grid navigation, the `explore-linux` workflow
captures all 12 surfaces on the GitHub Actions `ubuntu-latest` Xvfb environment —
`ground-truth.json` records 887 AT-SPI elements across 12 surfaces with 0 errors
(`environment_blocked` = false). The capture runs **without a live colima daemon** (colima is
shimmed so the main window renders instead of onboarding), so backend surfaces show
`✗ Error: transport error` — UI chrome and widget labels are verified, not live data.

**Live AT-SPI vs. a live backend: `environment-blocked`.** Driving these surfaces against a
running daemon requires an interactive Linux desktop + live backend, which does not exist on the
macOS-only verification host. This dimension is honestly labeled `environment-blocked` (see
`EVIDENCE.md` and `docs/windows-linux-parity-evidence.md`). Linux parity is proven via **green CI**
(`frontends.yml` job `linux-gtk4`: native GTK 4 compile + clippy `-D warnings` + `cargo fmt --check`
+ 27 unit tests) — the same evidence model as Windows UIA (see INTENT_LEDGER 2026-07-18T10:40Z).

> Historical note: an earlier revision of this file recorded the whole capture as
> `environment_blocked`. That predates the AT-SPI backend fix; the capture now succeeds on CI (the
> live-**backend** dimension is what remains environment-blocked).

## Running locally

```bash
# Install dependencies (Ubuntu 22.04+)
sudo apt-get install -y \
  libgtk-4-dev libadwaita-1-dev protobuf-compiler \
  xvfb dbus dbus-x11 at-spi2-core python3-pyatspi \
  scrot imagemagick x11-utils gir1.2-atspi-2.0

# Build + explore (from repo root)
bash scripts/linux/run_explore.sh
# Output: exploration/linux/ground-truth.json + screenshots/
```

Or run the explorer against an already-running app:

```bash
DISPLAY=:0 NO_AT_BRIDGE=0 GTK_MODULES=gail:atk-bridge \
  python3 scripts/linux/explore_atspi.py \
    --app linux/target/release/colima-desktop \
    --outdir exploration/linux \
    --timeout 60
```

## Output schema

`ground-truth.json` fields:

| Field | Description |
|-------|-------------|
| `platform` | `"Linux"` |
| `timestamp` | ISO 8601 UTC |
| `environment_blocked` | `true` when headless AT-SPI registration failed |
| `element_count` | Total AT-SPI nodes collected across all surfaces |
| `surfaces` | Array of per-surface captures |
| `surfaces[].surface` | Surface ID (e.g. `"dashboard"`) |
| `surfaces[].elements` | Array of AT-SPI node records |
| `surfaces[].elements[].role` | AT-SPI role string |
| `surfaces[].elements[].name` | Accessible name |
| `surfaces[].elements[].description` | Accessible description |
| `surfaces[].elements[].states` | Array of AT-SPI state names |
| `surfaces[].elements[].actions` | Available actions |
| `surfaces[].elements[].value` | Value interface current value |
| `screenshots` | Array of screenshot paths |
| `errors` | Per-phase error records |

## Surfaces

The app exposes 12 sidebar surfaces (Monitoring added — DISC-03 resolved):
`dashboard` · `containers` · `images` · `volumes` · `networks` ·
`machines` · `kubernetes` · `configuration` · `runtime` · `ai_workloads` · `profiles` ·
`monitoring`

Each GTK4 widget has `widget_name` and `Property::Label` set for AT-SPI
(see `linux/src/main.rs` build_sidebar + all view builders).

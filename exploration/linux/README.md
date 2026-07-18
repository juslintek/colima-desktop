# Linux AT-SPI2 Exploration

## Status

**environment_blocked** — AT-SPI2 runtime capture requires an interactive desktop
session. The GTK4 app builds and runs on Linux (CI green via `frontends.yml`),
but the `at-spi-bus-launcher` + pyatspi registration does not complete inside the
GitHub Actions `ubuntu-latest` Xvfb-only environment.

This is the same constraint documented for Windows UIA capture (see INTENT_LEDGER
entry 2026-07-18T10:40Z).

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

The app exposes 11 sidebar surfaces:
`dashboard` · `containers` · `images` · `volumes` · `networks` ·
`machines` · `kubernetes` · `configuration` · `runtime` · `ai_workloads` · `profiles`

Each GTK4 widget has `widget_name` and `Property::Label` set for AT-SPI
(see `linux/src/main.rs` build_sidebar + all view builders).

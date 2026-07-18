#!/usr/bin/env bash
# scripts/linux/run_explore.sh
#
# Local helper: launches Xvfb + D-Bus session, starts at-spi-bus-launcher,
# then runs the AT-SPI explorer. Mirrors what the CI workflow does.
#
# Usage:
#   bash scripts/linux/run_explore.sh [--skip-build] [--timeout 60]
#
# Requirements (Ubuntu/Debian):
#   sudo apt-get install -y \
#     libgtk-4-dev libadwaita-1-dev protobuf-compiler \
#     xvfb dbus at-spi2-core python3-pyatspi scrot
#
# The script exits 0 only when AT-SPI capture succeeds with nonzero elements.
# On failure it still preserves the diagnostic exploration/linux/ground-truth.json.
#
# GTK4 accessibility setup (critical):
#   GTK_A11Y=1        — enable GTK4's accessibility layer
#   NO_AT_BRIDGE=0    — allow AT-SPI bridge (headless runners set this to 1)
#   Do NOT set GTK_MODULES=gail:atk-bridge — that is GTK2/3 only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LINUX_DIR="$REPO_ROOT/linux"
OUT_DIR="$REPO_ROOT/exploration/linux"
BINARY="$LINUX_DIR/target/release/colima-desktop"
TIMEOUT=60
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1; shift ;;
        --timeout)    TIMEOUT="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ── Build ──────────────────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" -eq 0 ]]; then
    echo "[run_explore] Building linux/ release binary…"
    cd "$LINUX_DIR"
    cargo build --release 2>&1
    cd "$REPO_ROOT"
fi

[[ -x "$BINARY" ]] || { echo "ERROR: binary not found at $BINARY"; exit 1; }

# ── Start Xvfb ────────────────────────────────────────────────────────────
XVFB_DISPLAY=":99"
echo "[run_explore] Starting Xvfb on $XVFB_DISPLAY…"
Xvfb "$XVFB_DISPLAY" -screen 0 1280x800x24 -ac +extension RANDR &
XVFB_PID=$!
export DISPLAY="$XVFB_DISPLAY"
sleep 1

# ── Start D-Bus session bus ───────────────────────────────────────────────
echo "[run_explore] Starting dbus-daemon…"
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
echo "[run_explore] DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"

# ── Enable toolkit-accessibility via gsettings ────────────────────────────
export GSETTINGS_BACKEND=memory
gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null || true
echo "[run_explore] gsettings toolkit-accessibility=true"

# ── Start at-spi-bus-launcher ─────────────────────────────────────────────
# Probe paths for Ubuntu 22.04, 24.04, and generic Linux
echo "[run_explore] Locating at-spi-bus-launcher…"
ATSPI_LAUNCHER=""
for candidate in \
    "/usr/lib/at-spi2-core/at-spi-bus-launcher" \
    "/usr/lib/x86_64-linux-gnu/at-spi2-core/at-spi-bus-launcher" \
    "/usr/libexec/at-spi-bus-launcher" \
    "$(which at-spi-bus-launcher 2>/dev/null || true)"; do
  if [[ -x "$candidate" ]]; then
    ATSPI_LAUNCHER="$candidate"
    break
  fi
done

ATSPI_PID=0
if [[ -n "$ATSPI_LAUNCHER" ]]; then
    echo "[run_explore] Starting $ATSPI_LAUNCHER…"
    "$ATSPI_LAUNCHER" --launch-immediately &
    ATSPI_PID=$!
    echo "[run_explore] at-spi-bus-launcher pid=$ATSPI_PID"
else
    echo "[run_explore] WARNING: at-spi-bus-launcher not found in known paths."
    find /usr/lib -name 'at-spi*' 2>/dev/null | sort || true
fi

sleep 2

# ── AT-SPI env for the app (propagated via explore_atspi.py) ──────────────
export GTK_A11Y=1
export NO_AT_BRIDGE=0

# ── Run explorer ──────────────────────────────────────────────────────────
echo "[run_explore] Running AT-SPI explorer…"
EXIT_CODE=0
python3 "$REPO_ROOT/scripts/linux/explore_atspi.py" \
    --app "$BINARY" \
    --outdir "$OUT_DIR" \
    --timeout "$TIMEOUT" \
    --surface-pause 1.5 || EXIT_CODE=$?

# ── Cleanup ───────────────────────────────────────────────────────────────
[[ "$ATSPI_PID" -gt 0 ]] && kill "$ATSPI_PID" 2>/dev/null || true
kill "$XVFB_PID" 2>/dev/null || true
[[ -n "${DBUS_SESSION_BUS_PID:-}" ]] && kill "$DBUS_SESSION_BUS_PID" 2>/dev/null || true

if [[ "$EXIT_CODE" -ne 0 ]]; then
    echo "[run_explore] Explorer exited with code $EXIT_CODE"
    echo "[run_explore] Diagnostics: $OUT_DIR/ground-truth.json"
    echo "[run_explore] App stderr:  $OUT_DIR/app_stderr.txt"
else
    echo "[run_explore] SUCCESS"
fi

exit "$EXIT_CODE"

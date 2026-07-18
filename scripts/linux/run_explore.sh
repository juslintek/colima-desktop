#!/usr/bin/env bash
# scripts/linux/run_explore.sh
#
# Local helper: launches Xvfb + D-Bus session, builds the app,
# then runs the AT-SPI explorer. Mirrors what the CI workflow does.
#
# Usage:
#   bash scripts/linux/run_explore.sh [--skip-build] [--timeout 60]
#
# Requirements (Ubuntu/Debian):
#   sudo apt-get install -y \
#     libgtk-4-dev libadwaita-1-dev protobuf-compiler \
#     xvfb dbus at-spi2-core python3-pyatspi \
#     scrot  # or imagemagick for screenshots
#
# The script exits 0 only when AT-SPI capture succeeds with nonzero elements.
# On failure it still preserves the diagnostic exploration/linux/ground-truth.json.

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
Xvfb "$XVFB_DISPLAY" -screen 0 1280x800x24 &
XVFB_PID=$!
export DISPLAY="$XVFB_DISPLAY"
sleep 1

# ── Start D-Bus session ───────────────────────────────────────────────────
echo "[run_explore] Starting dbus-daemon…"
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS

# ── Start AT-SPI D-Bus server ─────────────────────────────────────────────
echo "[run_explore] Starting at-spi-bus-launcher…"
/usr/lib/at-spi2-core/at-spi-bus-launcher --launch-immediately &
ATSPI_PID=$!
sleep 1

# ── Run explorer ──────────────────────────────────────────────────────────
echo "[run_explore] Running AT-SPI explorer…"
EXIT_CODE=0
python3 "$REPO_ROOT/scripts/linux/explore_atspi.py" \
    --app "$BINARY" \
    --outdir "$OUT_DIR" \
    --timeout "$TIMEOUT" || EXIT_CODE=$?

# ── Cleanup ───────────────────────────────────────────────────────────────
kill "$XVFB_PID" 2>/dev/null || true
kill "$ATSPI_PID" 2>/dev/null || true
kill "$DBUS_PID" 2>/dev/null || true

if [[ "$EXIT_CODE" -ne 0 ]]; then
    echo "[run_explore] Explorer exited with code $EXIT_CODE (see exploration/linux/ground-truth.json for diagnostics)"
else
    echo "[run_explore] SUCCESS"
fi

exit "$EXIT_CODE"

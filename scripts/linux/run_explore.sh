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
#   GTK_A11Y=atspi    — select the AT-SPI backend explicitly. Valid GTK4 values:
#                       accesskit | atspi | test | none | help
#                       Do NOT use GTK_A11Y=1 — "1" is unrecognized and causes
#                       "Unrecognized accessibility backend '1'" which silently
#                       kills AT-SPI registration.
#   NO_AT_BRIDGE=0    — allow AT-SPI bridge (headless runners set this to 1)
#   Do NOT set GTK_MODULES=gail:atk-bridge — that is GTK2/3 only
#
# colima shim (critical for CI / clean development environments):
#   DependencyManager::is_colima_installed() uses which::which("colima"). If
#   `colima` is not on PATH the app shows the onboarding window instead of the
#   real sidebar UI, causing all AT-SPI captures to be identical onboarding
#   snapshots. We create a temporary bin dir with a CI-only colima shim and
#   prepend it to PATH before launching the explorer so the app enters the
#   real main window.

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

# ── Create colima shim in a temporary bin directory ───────────────────────
# This ensures DependencyManager::is_colima_installed() returns true so the
# app shows the main UI (with sidebar) rather than the onboarding window.
# The shim directory is cleaned up in the EXIT trap below.
SHIM_BIN_DIR="$(mktemp -d /tmp/colima-ci-bin.XXXXXX)"
trap 'rm -rf "$SHIM_BIN_DIR"' EXIT

SHIM_SOURCE="$REPO_ROOT/scripts/linux/colima_shim.sh"
if [[ -f "$SHIM_SOURCE" ]]; then
    cp "$SHIM_SOURCE" "$SHIM_BIN_DIR/colima"
    chmod +x "$SHIM_BIN_DIR/colima"
    echo "[run_explore] colima shim installed at $SHIM_BIN_DIR/colima"
    echo "[run_explore] Shim test: $($SHIM_BIN_DIR/colima --version | head -1)"
else
    echo "[run_explore] WARNING: colima_shim.sh not found at $SHIM_SOURCE"
    echo "[run_explore] Creating inline shim…"
    cat > "$SHIM_BIN_DIR/colima" <<'SHIM'
#!/usr/bin/env bash
cmd="${1:-}"
case "$cmd" in
    --version|version)
        echo "colima version 0.6.99-ci-shim"
        exit 0 ;;
    status)
        echo '{"display_name":"colima","driver":"ci-shim","arch":"x86_64","runtime":"docker","cpu":2,"memory":2147483648,"disk":107374182400}'
        exit 0 ;;
    list)
        echo '{"name":"default","status":"Running","arch":"x86_64","cpus":2,"memory":2147483648,"disk":107374182400,"runtime":"docker","ipAddress":""}'
        exit 0 ;;
    start|stop|restart|delete|update|prune|kubernetes|k8s|model|clone|template|ssh-config)
        exit 0 ;;
    *)
        echo "colima: unknown command \"${cmd}\" (inline ci-shim)" >&2
        exit 1 ;;
esac
SHIM
    chmod +x "$SHIM_BIN_DIR/colima"
fi

# Prepend the shim directory to PATH so which::which("colima") finds it first
export PATH="$SHIM_BIN_DIR:$PATH"
echo "[run_explore] PATH prepended: $SHIM_BIN_DIR is now first on PATH"
echo "[run_explore] which colima: $(which colima)"

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
# GTK_A11Y=atspi is the correct GTK4 AT-SPI backend selector.
# Valid values: accesskit | atspi | test | none | help
# Do NOT use GTK_A11Y=1 — "1" is unrecognized and silently kills AT-SPI registration.
export GTK_A11Y=atspi
export NO_AT_BRIDGE=0

# ── Run explorer ──────────────────────────────────────────────────────────
# PATH with shim is already exported; explore_atspi.py passes it through to
# the app subprocess via build_app_env() which copies os.environ.
echo "[run_explore] Running AT-SPI explorer…"
EXIT_CODE=0
python3 "$REPO_ROOT/scripts/linux/explore_atspi.py" \
    --app "$BINARY" \
    --outdir "$OUT_DIR" \
    --timeout "$TIMEOUT" \
    --surface-pause 1.5 || EXIT_CODE=$?

# ── Cleanup ───────────────────────────────────────────────────────────────
# Note: SHIM_BIN_DIR cleanup is handled by the EXIT trap above.
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

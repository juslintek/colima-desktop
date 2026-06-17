#!/usr/bin/env bash
#
# Generate (or update) appcast.xml for the DMGs in dist/.
# Sparkle's generate_appcast signs each archive with the EdDSA private key from
# your keychain and writes dist/appcast.xml (+ per-version release notes).
#
# Upload BOTH the .dmg and appcast.xml to where SUFeedURL points.
#
# Usage: scripts/sparkle-appcast.sh [dist-dir]   (default: dist/)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"
BIN="$(find "$ROOT/build" -path '*artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"
[[ -n "$BIN" ]] || { echo "ERROR: Sparkle tools not found. Run 'make app' first to resolve Sparkle."; exit 1; }
[[ -d "$DIST" ]] || { echo "ERROR: dist dir '$DIST' not found. Build a release first (make release)."; exit 1; }

# Optional: pass the public download URL prefix so links in the appcast are correct.
ARGS=("$DIST")
[[ -n "${DOWNLOAD_URL_PREFIX:-}" ]] && ARGS=(--download-url-prefix "$DOWNLOAD_URL_PREFIX" "$DIST")

echo "==> Generating appcast in $DIST"
"$BIN/generate_appcast" "${ARGS[@]}"
echo "==> Wrote $DIST/appcast.xml"
echo "    Host appcast.xml + the .dmg at your SUFeedURL, then users auto-update."
ls -1 "$DIST"/*.dmg "$DIST"/appcast.xml 2>/dev/null || true

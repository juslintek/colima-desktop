#!/usr/bin/env bash
#
# Generate the Sparkle EdDSA signing key pair (one-time).
# The PRIVATE key is stored securely in your login keychain; the PUBLIC key is
# printed — paste it into project.yml -> INFOPLIST_KEY_SUPublicEDKey.
#
# Requires Sparkle to be resolved (run `make app` once first).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(find "$ROOT/build" -path '*artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"
[[ -n "$BIN" ]] || { echo "ERROR: Sparkle tools not found. Run 'make app' first to resolve Sparkle."; exit 1; }

echo "==> Generating/locating EdDSA key (private key -> login keychain)"
"$BIN/generate_keys"
echo
echo "==> Paste the public key above into project.yml:"
echo "      INFOPLIST_KEY_SUPublicEDKey: \"<public key>\""
echo "    then \`xcodegen generate\` and rebuild."

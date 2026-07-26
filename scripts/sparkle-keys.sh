#!/usr/bin/env bash
#
# Generate (or locate) the Sparkle EdDSA signing key pair.
# The PRIVATE key is stored securely in your login keychain; the PUBLIC key is
# printed — paste it into packaging/Info.plist -> SUPublicEDKey (the app's config).
#
# IDEMPOTENT: generate_keys never overwrites. If a key already exists in the
# keychain it just prints the existing public key, so re-running is safe and will
# NOT invalidate a previously-published appcast. A real key is already generated
# and wired for this repo (see SIGNING.md); run this only to rotate on a fresh
# machine or to re-read the public key.
#
# Requires Sparkle to be resolved (run `make app` once first).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$(find "$ROOT/build" -path '*artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)"
[[ -n "$BIN" ]] || { echo "ERROR: Sparkle tools not found. Run 'make app' first to resolve Sparkle."; exit 1; }

echo "==> Generating/locating EdDSA key (private key -> login keychain; never committed)"
"$BIN/generate_keys"
echo
echo "==> Paste the public key above into packaging/Info.plist (SUPublicEDKey),"
echo "    then \`xcodegen generate\` and rebuild."
echo
echo "==> For GitHub Actions auto-update, export the PRIVATE key and store it as the"
echo "    repo secret SPARKLE_PRIVATE_KEY:"
echo "      \"$BIN/generate_keys\" -x sparkle_private_key.pem   # then: gh secret set SPARKLE_PRIVATE_KEY < sparkle_private_key.pem"
echo "    (delete the exported file afterwards)."

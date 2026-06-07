#!/usr/bin/env bash
#
# Package Colima Desktop into a distributable .app + .dmg.
#
# Distribution model: Developer ID + notarization (NOT Mac App Store — the app
# spawns colima/docker/brew and uses ~/.colima sockets, which the App Store
# sandbox forbids). See Sources/docs/DISTRIBUTION.md.
#
# Everything is opt-in via env vars, so the script also produces an UNSIGNED dmg
# for local verification when no signing identity is provided.
#
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"  (optional)
#   NOTARY_PROFILE  notarytool keychain profile name               (optional)
#   NOTARIZE        1 to submit for notarization + staple          (optional)
#
# Usage:
#   scripts/package.sh                       # unsigned .app + .dmg (pipeline proof)
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/package.sh
#   SIGN_IDENTITY="..." NOTARY_PROFILE=ColimaDesktopNotary NOTARIZE=1 scripts/package.sh
set -euo pipefail

SCHEME="ColimaDesktop"
APP_NAME="Colima Desktop"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/Release"
DIST_DIR="$ROOT/dist"
ENTITLEMENTS="$ROOT/packaging/ColimaDesktop.entitlements"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

# Version from git tag (override with VERSION=1.2.0). See scripts/version.sh.
eval "$("$ROOT/scripts/version.sh")"
DMG_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION.dmg"
echo "==> Version: $MARKETING_VERSION (build $CURRENT_PROJECT_VERSION)"

echo "==> Generating project + building Release"
cd "$ROOT"
xcodegen generate >/dev/null
BUILD_ARGS=(-scheme "$SCHEME" -configuration Release -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR"
  "MARKETING_VERSION=$MARKETING_VERSION" "CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION")
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing-enabled build as: $SIGN_IDENTITY"
  xcodebuild "${BUILD_ARGS[@]}" clean build \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" -quiet
else
  echo "==> UNSIGNED build (no SIGN_IDENTITY) — pipeline verification only"
  xcodebuild "${BUILD_ARGS[@]}" clean build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
fi

[[ -d "$APP_PATH" ]] || { echo "ERROR: app not found at $APP_PATH"; exit 1; }
mkdir -p "$DIST_DIR"

# Re-sign deeply with hardened runtime + entitlements (covers nested binaries) when signing.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> codesign --deep (hardened runtime, entitlements)"
  codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
  codesign --verify --strict --verbose=2 "$APP_PATH"
fi

echo "==> Building DMG: $DMG_PATH"
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing DMG"
  codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  : "${NOTARY_PROFILE:?NOTARIZE=1 requires NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  echo "==> Notarizing (notarytool) — this can take minutes"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "==> Done: $DMG_PATH"
ls -lh "$DMG_PATH"
[[ -n "${SIGN_IDENTITY:-}" ]] && spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" 2>&1 || \
  echo "NOTE: unsigned DMG — Gatekeeper will block until signed + notarized."

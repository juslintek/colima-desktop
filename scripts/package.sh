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
# Both dirs are overridable so a verification/CI build can isolate its
# derivedDataPath + output (e.g. DERIVED_DATA=/tmp/... DIST_DIR=/tmp/... package.sh).
BUILD_DIR="${DERIVED_DATA:-$ROOT/build/Release}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
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
else
  # No Developer ID: ad-hoc sign so the bundle has a VALID (self) signature.
  # Sparkle's generate_appcast rejects apps with no signature at all (errSecCSUnsigned);
  # ad-hoc passes that check. Gatekeeper still flags it as unidentified (right-click → Open).
  echo "==> Ad-hoc signing (no Developer ID)"
  codesign --force --deep --sign - "$APP_PATH"
  codesign --verify --deep "$APP_PATH" || true
fi

echo "==> Building DMG: $DMG_PATH"
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# Give the DMG volume itself the app icon (best-effort): build RW, set icon, convert.
[[ -f "$ROOT/packaging/AppIcon.icns" ]] && cp "$ROOT/packaging/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
TMPDMG="$(mktemp -u).dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$TMPDMG" >/dev/null
MNT="$(hdiutil attach "$TMPDMG" -nobrowse -noverify -noautoopen 2>/dev/null | grep -Eo '/Volumes/.*$' | head -1 || true)"
if [[ -n "${MNT:-}" && -f "$MNT/.VolumeIcon.icns" ]]; then
  ( /usr/bin/SetFile -a C "$MNT" 2>/dev/null || xcrun SetFile -a C "$MNT" 2>/dev/null || true )
fi
[[ -n "${MNT:-}" ]] && hdiutil detach "$MNT" -quiet 2>/dev/null || true
hdiutil convert "$TMPDMG" -format UDZO -ov -o "$DMG_PATH" >/dev/null
rm -f "$TMPDMG"
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

# ── Honest signing-status sidecar for the DMG (consumed by checksums.sh) ──
# Credential-gated: SIGNED only when a Developer ID identity was supplied; when
# absent we emit the exact "UNSIGNED — signing credential <NAME> absent" label
# and list the credential names a fully-signed release needs. Never faked.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  if [[ "${NOTARIZE:-0}" == "1" ]]; then
    DMG_SIGNED=true
    DMG_STATUS="SIGNED + NOTARIZED (Developer ID: ${SIGN_IDENTITY})"
    DMG_REQ='[]'
  else
    DMG_SIGNED=true
    DMG_STATUS="SIGNED (Developer ID: ${SIGN_IDENTITY}) — NOT notarized (set NOTARIZE=1 + NOTARY_PROFILE)"
    DMG_REQ='["NOTARY_APPLE_ID","NOTARY_TEAM_ID","NOTARY_PASSWORD"]'
  fi
else
  DMG_SIGNED=false
  DMG_STATUS="UNSIGNED — signing credential MACOS_SIGN_IDENTITY absent (ad-hoc signed only; Gatekeeper will block)"
  DMG_REQ='["MACOS_SIGN_IDENTITY","MACOS_CERTIFICATE_P12","MACOS_CERTIFICATE_PASSWORD","KEYCHAIN_PASSWORD","NOTARY_APPLE_ID","NOTARY_TEAM_ID","NOTARY_PASSWORD"]'
fi
cat > "$DMG_PATH.meta.json" <<META
{
  "component": "macos-app",
  "os": "darwin",
  "arch": "universal",
  "version": "${MARKETING_VERSION}",
  "signed": ${DMG_SIGNED},
  "signing_status": "${DMG_STATUS}",
  "required_credentials": ${DMG_REQ}
}
META

# ── Ship the Go daemon + TUI binaries alongside the macOS app (versioned) ──
# Skippable via PACKAGE_GO=0. Uses package-go.sh so the version stamp + signing
# gate are identical to the CI path.
if [[ "${PACKAGE_GO:-1}" == "1" ]] && command -v go >/dev/null 2>&1; then
  echo "==> Building versioned Go binaries (daemon + tui)"
  DIST_DIR="$DIST_DIR" MACOS_SIGN_IDENTITY="${SIGN_IDENTITY:-}" "$ROOT/scripts/package-go.sh" daemon --universal || echo "WARN: daemon package failed"
  DIST_DIR="$DIST_DIR" MACOS_SIGN_IDENTITY="${SIGN_IDENTITY:-}" "$ROOT/scripts/package-go.sh" tui --universal || echo "WARN: tui package failed"
fi

# ── SHA-256 checksums manifest for every artifact in DIST_DIR ──
if [[ "${SKIP_MANIFEST:-0}" != "1" ]]; then
  echo "==> Generating SHA-256 checksums manifest"
  "$ROOT/scripts/release/checksums.sh" --dir "$DIST_DIR" --version "$MARKETING_VERSION" || echo "WARN: manifest generation failed"
fi

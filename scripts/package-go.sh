#!/usr/bin/env bash
#
# package-go.sh — build a versioned Go component binary (daemon | tui) for the
# release (R8 / task 13.1). The version is STAMPED at build time via -ldflags so
# no Go source is edited (build-time injection, not a committed constant):
#
#   -X main.version=<marketing>  -X main.commit=<sha>  -X main.date=<iso8601>
#
# These target the conventional `main.version` symbol. Go's linker silently
# ignores an -X for a symbol that does not yet exist, so the build is correct
# TODAY and the stamped `--version` output goes live the moment the daemon/tui
# owner adds `var version string` + a `--version` printer (a one-line, minimal
# coordination point — this script does NOT edit their source).
#
# On macOS the binary is code-signed with Developer ID when MACOS_SIGN_IDENTITY
# is set (credential-gated); otherwise it is ad-hoc signed and honestly labelled
# UNSIGNED in its manifest sidecar. Nothing here fakes a Developer ID signature.
#
# USAGE
#   scripts/package-go.sh daemon                 # host os/arch
#   scripts/package-go.sh daemon --universal     # macOS universal (arm64+amd64 via lipo)
#   scripts/package-go.sh tui --os linux --arch amd64
#   scripts/package-go.sh daemon --os windows --arch amd64   # -> .exe
#
# ENV: DIST_DIR (default dist/), MACOS_SIGN_IDENTITY (optional Developer ID)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)/.."
ROOT="$(cd "$ROOT" && pwd)"

COMPONENT="${1:-}"; shift || true
[ -n "$COMPONENT" ] || { echo "usage: package-go.sh <daemon|tui> [--os X --arch Y | --universal]" >&2; exit 2; }
case "$COMPONENT" in daemon|tui) ;; *) echo "package-go.sh: component must be daemon|tui" >&2; exit 2 ;; esac

GOOS_ARG=""
GOARCH_ARG=""
UNIVERSAL=0
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
while [ $# -gt 0 ]; do
  case "$1" in
    --os) GOOS_ARG="$2"; shift 2 ;;
    --arch) GOARCH_ARG="$2"; shift 2 ;;
    --universal) UNIVERSAL=1; shift ;;
    --out) DIST_DIR="$2"; shift 2 ;;
    *) echo "package-go.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v go >/dev/null 2>&1 || { echo "package-go.sh: go not installed" >&2; exit 1; }

MARKETING="$(bash "$ROOT/scripts/version.sh" marketing)"
COMMIT="$(bash "$ROOT/scripts/version.sh" commit)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LDFLAGS="-s -w -X main.version=${MARKETING} -X main.commit=${COMMIT} -X main.date=${DATE}"

SRC_DIR="$ROOT/$COMPONENT"
# The daemon's main package is ./cmd; the TUI's main package is the module root.
if [ "$COMPONENT" = "daemon" ]; then PKG="./cmd"; else PKG="."; fi

mkdir -p "$DIST_DIR"

HOST_OS="$(go env GOOS)"
GOOS_EFF="${GOOS_ARG:-$HOST_OS}"
EXT=""
[ "$GOOS_EFF" = "windows" ] && EXT=".exe"

build_one() { # build_one <goos> <goarch> <outfile>
  local goos="$1" goarch="$2" out="$3"
  echo "==> go build $COMPONENT ($goos/$goarch) v$MARKETING"
  ( cd "$SRC_DIR" && CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
      go build -trimpath -ldflags "$LDFLAGS" -o "$out" "$PKG" )
}

OUTBASE="colima-${COMPONENT}"
[ "$COMPONENT" = "daemon" ] && OUTBASE="colima-daemon"
[ "$COMPONENT" = "tui" ] && OUTBASE="colima-tui"

if [ "$UNIVERSAL" = "1" ]; then
  [ "$HOST_OS" = "darwin" ] || { echo "package-go.sh: --universal requires a macOS host (lipo)" >&2; exit 1; }
  TMP="$(mktemp -d)"
  build_one darwin arm64 "$TMP/arm64"
  build_one darwin amd64 "$TMP/amd64"
  OUT="$DIST_DIR/${OUTBASE}-${MARKETING}-macos-universal"
  lipo -create "$TMP/arm64" "$TMP/amd64" -output "$OUT"
  rm -rf "$TMP"
  GOOS_EFF="darwin"; ARCH_LABEL="universal"
else
  GOARCH_EFF="${GOARCH_ARG:-$(go env GOARCH)}"
  OUT="$DIST_DIR/${OUTBASE}-${MARKETING}-${GOOS_EFF}-${GOARCH_EFF}${EXT}"
  build_one "$GOOS_EFF" "$GOARCH_EFF" "$OUT"
  ARCH_LABEL="$GOARCH_EFF"
fi

# Credential-gated signing (macOS only; Go binaries elsewhere ship unsigned here).
SIGNED=false
SIGNING_STATUS="UNSIGNED — Go binaries are shipped unsigned (verify via SHA256SUMS)"
REQ_CREDS='[]'
if [ "$GOOS_EFF" = "darwin" ] && [ "$HOST_OS" = "darwin" ]; then
  if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    echo "==> codesign (Developer ID) $OUT"
    codesign --force --timestamp --options runtime --sign "$MACOS_SIGN_IDENTITY" "$OUT"
    SIGNED=true
    SIGNING_STATUS="SIGNED (Developer ID: ${MACOS_SIGN_IDENTITY})"
  else
    echo "==> ad-hoc sign (no MACOS_SIGN_IDENTITY) $OUT"
    codesign --force --sign - "$OUT" 2>/dev/null || true
    SIGNING_STATUS="UNSIGNED — signing credential MACOS_SIGN_IDENTITY absent (ad-hoc signed only)"
    REQ_CREDS='["MACOS_SIGN_IDENTITY","MACOS_CERTIFICATE_P12","MACOS_CERTIFICATE_PASSWORD","KEYCHAIN_PASSWORD"]'
  fi
fi

# Manifest sidecar consumed by scripts/release/checksums.sh.
OUT_NAME="$(basename "$OUT")"
cat > "$OUT.meta.json" <<META
{
  "component": "${COMPONENT}",
  "os": "${GOOS_EFF}",
  "arch": "${ARCH_LABEL}",
  "version": "${MARKETING}",
  "signed": ${SIGNED},
  "signing_status": "${SIGNING_STATUS}",
  "required_credentials": ${REQ_CREDS}
}
META

BYTES="$(wc -c < "$OUT" | tr -d ' ')"
echo "==> built ${OUT_NAME} (${BYTES} bytes) — ${SIGNING_STATUS}"

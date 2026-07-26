#!/usr/bin/env bash
#
# package-linux.sh — build versioned, packaged Linux (GTK 4) deliverables for the
# release (R8 / tasks 13.1 + 13.3). The native `cargo build` runs on the
# `linux-gtk4` CI runner (GTK 4 cannot build on the macOS verification host);
# the PACKAGING logic (staging, tar.gz/.deb assembly, signing, checksums,
# manifest sidecar) is host-agnostic and can be exercised locally in a degraded
# `--dry-run` form.
#
# DELIVERABLES (Requirement 12.3 — "package the Linux deliverable"):
#   * <name>.tar.gz               a versioned, relocatable tarball (always)
#   * <name>.deb                  a Debian package (opt-in: --deb; needs dpkg-deb)
# plus, per artifact, a `.meta.json` sidecar consumed by
# scripts/release/checksums.sh, and (credential-gated) a detached `.asc`.
#
# VERSION STAMPING (single source of truth = scripts/version.sh): the PACKAGE
# version (artifact filename + bundled VERSION file + .desktop `Version=` +
# .deb control `Version:` + manifest sidecar) is set from the git tag. No
# `linux/**` source is edited — the Rust crate's Cargo.toml is consumed
# unchanged (build-time package stamping, not a committed source edit).
#
# SIGNING is CREDENTIAL-GATED and honest (task 13.3):
#   * When LINUX_GPG_PRIVATE_KEY (+ LINUX_GPG_PASSPHRASE) is present, each
#     artifact gets a detached, armored GPG signature (`<artifact>.asc`) which is
#     then VERIFIED (`gpg --verify`) before the run is accepted.
#   * When the key is ABSENT the artifact is UNSIGNED and labelled exactly
#     "UNSIGNED - signing credential LINUX_GPG_PRIVATE_KEY absent" in the sidecar,
#     and the required credential names are reported.
# Nothing here fakes a signature or commits a key.
#
# USAGE
#   scripts/linux/package-linux.sh [--version X.Y.Z] [--dist dir]
#                                  [--deb] [--no-tgz]
#                                  [--binary path] [--skip-build] [--dry-run]
#
# ENV: LINUX_GPG_PRIVATE_KEY (armored, optional), LINUX_GPG_PASSPHRASE,
#      LINUX_GPG_KEY_ID (optional)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

VERSION=""
DIST_DIR="$ROOT/dist"
WANT_DEB=0
WANT_TGZ=1
BINARY=""
SKIP_BUILD=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --dist) DIST_DIR="$2"; shift 2 ;;
    --deb) WANT_DEB=1; shift ;;
    --no-tgz) WANT_TGZ=0; shift ;;
    --binary) BINARY="$2"; SKIP_BUILD=1; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --dry-run) DRY_RUN=1; SKIP_BUILD=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "package-linux.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -z "$VERSION" ] && VERSION="$(bash "$ROOT/scripts/version.sh" marketing)"
mkdir -p "$DIST_DIR"

ARCH="$(uname -m)"            # x86_64 / aarch64
case "$ARCH" in               # Debian architecture names for the .deb
  x86_64) DEB_ARCH="amd64" ;;
  aarch64|arm64) DEB_ARCH="arm64" ;;
  *) DEB_ARCH="$ARCH" ;;
esac

# ── Portable SHA-256 (macOS `shasum` / Linux `sha256sum`) ──
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  else echo "unavailable"; fi
}

# ── Resolve the binary to package (real build, provided, or dry placeholder) ──
DEFAULT_BIN="$ROOT/linux/target/release/colima-desktop"
if [ "$SKIP_BUILD" -eq 0 ]; then
  command -v cargo >/dev/null 2>&1 || { echo "package-linux.sh: cargo not installed (use --dry-run/--binary to package without building)" >&2; exit 1; }
  echo "==> cargo build --release (colima-desktop v$VERSION, $ARCH)"
  ( cd "$ROOT/linux" && cargo build --release )
  BINARY="$DEFAULT_BIN"
elif [ -n "$BINARY" ]; then
  :                                   # explicit --binary path
elif [ -x "$DEFAULT_BIN" ]; then
  BINARY="$DEFAULT_BIN"               # a prior build's output
elif [ "$DRY_RUN" -eq 1 ]; then
  # Degraded exercise: synthesize a placeholder so the packaging logic runs on a
  # non-Linux host. Clearly marked dry_run in every sidecar; never a real build.
  BINARY="$(mktemp -d)/colima-desktop"
  printf '#!/bin/sh\necho "colima-desktop %s (dry-run placeholder — not a real build)"\n' "$VERSION" > "$BINARY"
  chmod +x "$BINARY"
  echo "==> DRY RUN: packaging a placeholder binary (no cargo build)"
else
  echo "package-linux.sh: no binary at $DEFAULT_BIN; pass --binary <path> or --dry-run" >&2; exit 1
fi
[ -f "$BINARY" ] || { echo "package-linux.sh: binary not found at $BINARY" >&2; exit 1; }

# ── Credential-gated GPG signing (imported once, reused, verified) ──
GPG_READY=0
GPGHOME=""
if [ -n "${LINUX_GPG_PRIVATE_KEY:-}" ] && command -v gpg >/dev/null 2>&1; then
  GPGHOME="$(mktemp -d)"
  if printf '%s' "$LINUX_GPG_PRIVATE_KEY" | GNUPGHOME="$GPGHOME" gpg --batch --import >/dev/null 2>&1; then
    GPG_READY=1
  else
    echo "==> WARNING: LINUX_GPG_PRIVATE_KEY present but import failed — treating as UNSIGNED" >&2
    rm -rf "$GPGHOME"; GPGHOME=""
  fi
fi
cleanup() { [ -n "${GPGHOME:-}" ] && rm -rf "$GPGHOME"; return 0; }
trap cleanup EXIT

# sign_and_verify <artifact> ; echoes "signed" or "unsigned" on stdout.
sign_and_verify() {
  local art="$1"
  if [ "$GPG_READY" -eq 1 ]; then
    local args=(--batch --yes --armor --detach-sign)
    [ -n "${LINUX_GPG_PASSPHRASE:-}" ] && args+=(--pinentry-mode loopback --passphrase "$LINUX_GPG_PASSPHRASE")
    [ -n "${LINUX_GPG_KEY_ID:-}" ] && args+=(--local-user "$LINUX_GPG_KEY_ID")
    if GNUPGHOME="$GPGHOME" gpg "${args[@]}" --output "$art.asc" "$art" 2>/dev/null \
       && GNUPGHOME="$GPGHOME" gpg --batch --verify "$art.asc" "$art" >/dev/null 2>&1; then
      echo "signed"; return 0
    fi
    echo "==> WARNING: GPG sign/verify failed for $(basename "$art") — leaving UNSIGNED" >&2
    rm -f "$art.asc"
  fi
  echo "unsigned"
}

# write_meta <artifact> <signed|unsigned>
write_meta() {
  local art="$1" state="$2" signed status req sha
  sha="$(sha256_of "$art")"
  if [ "$state" = "signed" ]; then
    signed=true;  status="SIGNED (GPG detached $(basename "$art").asc, verified)"; req='[]'
  else
    signed=false; status="UNSIGNED - signing credential LINUX_GPG_PRIVATE_KEY absent"
    req='["LINUX_GPG_PRIVATE_KEY","LINUX_GPG_PASSPHRASE"]'
  fi
  cat > "$art.meta.json" <<META
{
  "component": "linux",
  "os": "linux",
  "arch": "${ARCH}",
  "version": "${VERSION}",
  "format": "$(echo "$art" | sed 's/.*\.//')",
  "signed": ${signed},
  "signing_status": "${status}",
  "required_credentials": ${req},
  "sha256": "${sha}",
  "dry_run": $( [ "$DRY_RUN" -eq 1 ] && echo true || echo false )
}
META
  echo "==> $(basename "$art"): sha256 ${sha} — ${status}"
}

# ── tar.gz (relocatable tree: binary + VERSION + .desktop + README) ──
if [ "$WANT_TGZ" -eq 1 ]; then
  STAGE_NAME="colima-desktop-${VERSION}-linux-${ARCH}"
  STAGE_PARENT="$(mktemp -d)"
  STAGE="$STAGE_PARENT/$STAGE_NAME"
  mkdir -p "$STAGE"
  cp "$BINARY" "$STAGE/colima-desktop"
  chmod +x "$STAGE/colima-desktop"
  printf '%s\n' "$VERSION" > "$STAGE/VERSION"
  [ -f "$ROOT/linux/README.md" ] && cp "$ROOT/linux/README.md" "$STAGE/README.md"
  cat > "$STAGE/colima-desktop.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Colima Desktop
Comment=Native GTK4 GUI for the Colima container runtime
Exec=colima-desktop
Icon=colima-desktop
Categories=Development;Utility;
Version=${VERSION}
DESKTOP
  TGZ="$DIST_DIR/${STAGE_NAME}.tar.gz"
  rm -f "$TGZ"
  tar -C "$STAGE_PARENT" -czf "$TGZ" "$STAGE_NAME"
  rm -rf "$STAGE_PARENT"
  echo "==> packaged $(basename "$TGZ")"
  write_meta "$TGZ" "$(sign_and_verify "$TGZ")"
fi

# ── .deb (opt-in; FHS layout via dpkg-deb) ──
if [ "$WANT_DEB" -eq 1 ]; then
  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "==> SKIP .deb: dpkg-deb not available on this host (built on the linux-gtk4 CI runner)" >&2
  else
    DEB_NAME="colima-desktop_${VERSION}_${DEB_ARCH}"
    DROOT="$(mktemp -d)/$DEB_NAME"
    mkdir -p "$DROOT/DEBIAN" "$DROOT/usr/bin" "$DROOT/usr/share/applications" "$DROOT/usr/share/doc/colima-desktop"
    cp "$BINARY" "$DROOT/usr/bin/colima-desktop"
    chmod 0755 "$DROOT/usr/bin/colima-desktop"
    cat > "$DROOT/usr/share/applications/colima-desktop.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Colima Desktop
Comment=Native GTK4 GUI for the Colima container runtime
Exec=colima-desktop
Icon=colima-desktop
Categories=Development;Utility;
Version=${VERSION}
DESKTOP
    printf '%s\n' "$VERSION" > "$DROOT/usr/share/doc/colima-desktop/VERSION"
    cat > "$DROOT/DEBIAN/control" <<CONTROL
Package: colima-desktop
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${DEB_ARCH}
Depends: libgtk-4-1, libadwaita-1-0
Maintainer: Colima Desktop <jusys.linas@gmail.com>
Description: Native GTK4 GUI for the Colima container runtime
 Colima Desktop is a native desktop client for managing Colima virtual
 machines, containers, images, volumes, networks, and Kubernetes over the
 shared gRPC daemon.
CONTROL
    DEB="$DIST_DIR/${DEB_NAME}.deb"
    rm -f "$DEB"
    # Reproducible-ish, root-owned tree regardless of the build user.
    dpkg-deb --root-owner-group --build "$DROOT" "$DEB" >/dev/null
    rm -rf "$(dirname "$DROOT")"
    echo "==> packaged $(basename "$DEB")"
    write_meta "$DEB" "$(sign_and_verify "$DEB")"
  fi
fi

echo "==> done (version ${VERSION}, arch ${ARCH}$( [ "$DRY_RUN" -eq 1 ] && echo ', DRY RUN' ))"

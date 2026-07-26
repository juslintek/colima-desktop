#!/usr/bin/env bash
# sbom.sh — generate CycloneDX SBOMs for every Colima Desktop component (R7 / Requirement 11.3).
#
# Covers all five shipped components' dependency graphs:
#   - Go daemon    (daemon/go.mod)
#   - Go TUI       (tui/go.mod)
#   - Rust Linux   (linux/Cargo.lock)
#   - .NET Windows (windows/ColimaDesktop.Windows.csproj [+ transitive via dotnet list])
#   - Swift macOS  (Package.resolved)
#
# Tooling: uses `syft` when installed (rich CycloneDX/SPDX). When syft is absent
# (the default on this host) it falls back to scripts/sbom_gen.py, which emits a
# valid, byte-stable CycloneDX 1.5 SBOM directly from the committed lockfiles —
# no network required. Output lands in a COMMITTED docs path (docs/sbom/), never
# the git-ignored artifacts/live/.
#
# Usage: scripts/sbom.sh [--out-dir docs/sbom] [--dotnet-json <file>] [--timestamp <iso8601>]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:$PATH"

OUT_DIR="docs/sbom"
DOTNET_JSON=""
TIMESTAMP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --dotnet-json) DOTNET_JSON="$2"; shift 2 ;;
    --timestamp) TIMESTAMP="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

ABS_OUT="$ROOT/$OUT_DIR"
CDX_DIR="$ABS_OUT/cyclonedx"
mkdir -p "$CDX_DIR"

echo "== Colima Desktop SBOM =="

if command -v syft >/dev/null 2>&1; then
  echo "-- syft found ($(syft version 2>/dev/null | head -1)); generating CycloneDX per component --"
  gen() { # gen <key> <target>
    local key="$1" target="$2"
    syft "$target" -o "cyclonedx-json=$CDX_DIR/$key.cdx.json" >/dev/null 2>&1 \
      && echo "  syft $key <- $target" || echo "  syft $key FAILED <- $target"
  }
  gen daemon  "dir:$ROOT/daemon"
  gen tui     "dir:$ROOT/tui"
  gen linux   "dir:$ROOT/linux"
  gen windows "dir:$ROOT/windows"
  gen macos   "dir:$ROOT"
  # Aggregate + inventory still come from the deterministic generator so the
  # summary/report shape is stable regardless of which tool produced the BOMs.
  python3 "$ROOT/scripts/sbom_gen.py" --root "$ROOT" --out-dir "$OUT_DIR" \
    ${DOTNET_JSON:+--dotnet-json "$DOTNET_JSON"} ${TIMESTAMP:+--timestamp "$TIMESTAMP"}
else
  echo "-- syft not installed; using deterministic lockfile generator (scripts/sbom_gen.py) --"
  python3 "$ROOT/scripts/sbom_gen.py" --root "$ROOT" --out-dir "$OUT_DIR" \
    ${DOTNET_JSON:+--dotnet-json "$DOTNET_JSON"} ${TIMESTAMP:+--timestamp "$TIMESTAMP"}
fi
rc=$?

echo "-- SBOM artifacts in $OUT_DIR/ --"
exit $rc

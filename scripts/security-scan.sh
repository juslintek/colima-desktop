#!/usr/bin/env bash
# security-scan.sh — SBOMs + dependency vulnerability audit for every component (R7 / Requirement 11.3).
#
# Runs the ecosystem-native vulnerability scanners available on the host and
# produces an HONEST report (real advisories, or "no known vulnerabilities
# found", or an explicit "not run" with a reason per ecosystem):
#   - Go daemon + TUI : govulncheck ./...     (auto-installed via `go install` if absent + lightweight)
#   - Rust Linux       : cargo audit --json    (reads Cargo.lock against the RustSec DB)
#   - .NET Windows      : dotnet list package --vulnerable --include-transitive
#   - Swift macOS       : no standard SPM scanner installed -> recorded not-run with reason
#
# Also (re)generates the CycloneDX SBOMs (scripts/sbom.sh). Output goes to the
# COMMITTED docs/sbom/ tree (SBOMs + VULNERABILITY-REPORT.md + raw scans/), never
# the git-ignored artifacts/live/.
#
# A found vulnerability is REPORTED, not automatically fatal. Pass --fail-on-critical
# to make the script exit non-zero when any CRITICAL finding exists — this is how
# the release-candidate gate (task 12.5) consumes it.
#
# Usage: scripts/security-scan.sh [--out-dir docs/sbom] [--fail-on-critical]
#                                 [--skip-install] [--skip-sbom]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GOBIN_DIR="$(go env GOPATH 2>/dev/null)/bin"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:$HOME/.cargo/bin:${GOBIN_DIR}:$PATH"

OUT_DIR="docs/sbom"
FAIL_ON_CRITICAL=0
SKIP_INSTALL=0
SKIP_SBOM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --fail-on-critical) FAIL_ON_CRITICAL=1; shift ;;
    --skip-install) SKIP_INSTALL=1; shift ;;
    --skip-sbom) SKIP_SBOM=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

ABS_OUT="$ROOT/$OUT_DIR"
SCANS="$ABS_OUT/scans"
mkdir -p "$SCANS"
rm -f "$SCANS"/*.json 2>/dev/null || true   # fresh per-ecosystem status each run
SCAN_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PARSE="python3 $ROOT/scripts/vuln_parse.py"

# run_to <seconds> <logfile> <cmd...> — bounded run (macOS has no coreutils timeout).
run_to() {
  local secs="$1" logf="$2"; shift 2
  "$@" >"$logf" 2>&1 &
  local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null; ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$watcher" >/dev/null 2>&1; wait "$watcher" 2>/dev/null
  return $rc
}

echo "== Colima Desktop security scan =="
echo "-- $SCAN_DATE --"

# ─────────────────────────────── Go: govulncheck (daemon + tui) ───────────────
if ! command -v govulncheck >/dev/null 2>&1 && [ "$SKIP_INSTALL" -eq 0 ]; then
  echo "-- installing govulncheck (go install golang.org/x/vuln/cmd/govulncheck@latest) --"
  run_to 300 "$SCANS/govulncheck-install.log" go install golang.org/x/vuln/cmd/govulncheck@latest
fi

scan_go() { # scan_go <eco> <component> <dir>
  local eco="$1" comp="$2" dir="$3"
  local raw="$SCANS/${eco}.txt"
  if command -v govulncheck >/dev/null 2>&1; then
    echo "-- govulncheck: $comp ($dir) --"
    ( cd "$dir" && govulncheck ./... ) >"$raw" 2>&1
    local rc=$?
    $PARSE --kind govulncheck --ecosystem "$eco" --component "$comp" \
      --tool "govulncheck ./..." --raw "$raw" --raw-rel "scans/${eco}.txt" --rc "$rc" \
      >"$SCANS/${eco}.json"
  else
    echo "-- govulncheck unavailable; recording not-run for $comp --"
    $PARSE --kind notrun --ecosystem "$eco" --component "$comp" \
      --tool "govulncheck ./..." \
      --reason "govulncheck not installed and 'go install' unavailable/offline (Go CI job is authoritative)" \
      >"$SCANS/${eco}.json"
  fi
}
scan_go "go-daemon" "colima-daemon (Go)" "$ROOT/daemon"
scan_go "go-tui"    "colima-tui (Go)"    "$ROOT/tui"

# ─────────────────────────────── Rust: cargo audit ───────────────────────────
if command -v cargo-audit >/dev/null 2>&1 || cargo audit --version >/dev/null 2>&1; then
  echo "-- cargo audit: colima-desktop-linux (linux/Cargo.lock) --"
  raw="$SCANS/rust-linux.json.raw"
  run_to 300 "$raw" cargo audit --file "$ROOT/linux/Cargo.lock" --json
  # cargo audit --json prints JSON to stdout; keep a human copy too.
  ( cd "$ROOT/linux" && cargo audit --file "$ROOT/linux/Cargo.lock" ) >"$SCANS/rust-linux.txt" 2>&1
  $PARSE --kind cargo-audit --ecosystem "rust-linux" --component "colima-desktop-linux (Rust/GTK4)" \
    --tool "cargo audit" --raw "$raw" --raw-rel "scans/rust-linux.txt" \
    >"$SCANS/rust-linux.json"
else
  echo "-- cargo audit unavailable; recording not-run --"
  $PARSE --kind notrun --ecosystem "rust-linux" --component "colima-desktop-linux (Rust/GTK4)" \
    --tool "cargo audit" \
    --reason "cargo-audit not installed (install: cargo install cargo-audit)" \
    >"$SCANS/rust-linux.json"
fi

# ─────────────────────────────── .NET: dotnet list --vulnerable ──────────────
# The shipped runtime NuGet deps (Grpc.Net.Client/Google.Protobuf/System.Text.Json/
# CommunityToolkit.Mvvm) are scanned via the net8.0 test/host project, which restores
# on any OS; the WinUI-platform packages are scanned authoritatively on the Windows CI.
WIN_TESTS="$ROOT/windows/Tests/ColimaDesktop.Windows.Tests.csproj"
if command -v dotnet >/dev/null 2>&1 && [ -f "$WIN_TESTS" ]; then
  echo "-- dotnet list --vulnerable: Windows runtime deps ($WIN_TESTS) --"
  run_to 300 "$SCANS/dotnet-restore.log" dotnet restore "$WIN_TESTS"
  raw="$SCANS/dotnet-windows.txt"
  run_to 240 "$raw" dotnet list "$WIN_TESTS" package --vulnerable --include-transitive
  rc=$?
  $PARSE --kind dotnet --ecosystem "dotnet-windows" \
    --component ".NET Windows runtime deps (net8.0 host project)" \
    --tool "dotnet list package --vulnerable --include-transitive" \
    --raw "$raw" --raw-rel "scans/dotnet-windows.txt" --rc "$rc" \
    >"$SCANS/dotnet-windows.json"
else
  echo "-- dotnet unavailable; recording not-run --"
  $PARSE --kind notrun --ecosystem "dotnet-windows" \
    --component ".NET Windows (WinUI3)" \
    --tool "dotnet list package --vulnerable --include-transitive" \
    --reason "dotnet SDK unavailable on host (windows-winui CI job is authoritative)" \
    >"$SCANS/dotnet-windows.json"
fi

# ─────────────────────────────── Swift: SPM (no standard scanner) ─────────────
# No SwiftPM-native vulnerability scanner is installed (syft/grype/osv-scanner
# absent). The SPM dependencies are test/dev-only (Package.swift ships no product;
# ViewInspector + swift-snapshot-testing + transitive) and do NOT link into the
# macOS app binary. Recorded honestly as not-run with that reason; the components
# are still inventoried in the CycloneDX SBOM (docs/sbom/cyclonedx/macos.cdx.json).
if command -v osv-scanner >/dev/null 2>&1; then
  echo "-- osv-scanner: Swift Package.resolved --"
  raw="$SCANS/swift-macos.txt"
  run_to 240 "$raw" osv-scanner --lockfile "$ROOT/Package.resolved"
  rc=$?
  # osv-scanner text has no fixed severity table we parse here; capture + mark clean/notrun by rc.
  if [ $rc -eq 0 ]; then
    $PARSE --kind notrun --ecosystem "swift-macos" --component "ColimaDesktop (Swift/SwiftUI)" \
      --tool "osv-scanner --lockfile Package.resolved" \
      --reason "osv-scanner ran and reported no vulnerabilities (see raw output)" >"$SCANS/swift-macos.json"
  else
    $PARSE --kind notrun --ecosystem "swift-macos" --component "ColimaDesktop (Swift/SwiftUI)" \
      --tool "osv-scanner --lockfile Package.resolved" \
      --reason "osv-scanner run captured in scans/swift-macos.txt (review findings)" >"$SCANS/swift-macos.json"
  fi
else
  echo "-- no SwiftPM vulnerability scanner installed; recording not-run --"
  $PARSE --kind notrun --ecosystem "swift-macos" --component "ColimaDesktop (Swift/SwiftUI)" \
    --tool "(none — SPM scanner absent)" \
    --reason "No SwiftPM vulnerability scanner installed (syft/grype/osv-scanner absent); SPM deps are test/dev-only (ViewInspector, swift-snapshot-testing + transitive) and are not linked into the shipped app. Components are inventoried in cyclonedx/macos.cdx.json." \
    >"$SCANS/swift-macos.json"
fi

# ─────────────────────────────── SBOMs ───────────────────────────────────────
if [ "$SKIP_SBOM" -eq 0 ]; then
  echo "-- generating SBOMs --"
  bash "$ROOT/scripts/sbom.sh" --out-dir "$OUT_DIR"
fi

# ─────────────────────── tidy + sanitize committed evidence (Req 8.6) ────────
# Keep user machine data (home path / username, absolute repo path) out of the
# committed raw evidence, and drop transient tool logs / machine-readable intermediates.
sanitize_file() {
  [ -f "$1" ] || return 0
  python3 - "$1" "$HOME" "$ROOT" <<'PY'
import sys
p, home, root = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    t = open(p, encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit(0)
if root:
    t = t.replace(root, ".")
if home:
    t = t.replace(home, "~")
open(p, "w", encoding="utf-8").write(t)
PY
}
for f in "$SCANS"/*.txt; do sanitize_file "$f"; done
rm -f "$SCANS"/*.json.raw "$SCANS"/govulncheck-install.log "$SCANS"/dotnet-restore.log 2>/dev/null || true

# ─────────────────────────────── assemble report + gate ──────────────────────
echo "-- assembling vulnerability report --"
GATE_FLAG=""
[ "$FAIL_ON_CRITICAL" -eq 1 ] && GATE_FLAG="--fail-on-critical"
python3 "$ROOT/scripts/vuln_report.py" --scans-dir "$SCANS" --out-dir "$ABS_OUT" \
  --scan-date "$SCAN_DATE" $GATE_FLAG
rc=$?

echo "-- report: $OUT_DIR/VULNERABILITY-REPORT.md ; summary: $OUT_DIR/vuln-summary.json --"
exit $rc

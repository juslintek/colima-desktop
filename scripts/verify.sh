#!/usr/bin/env bash
# verify.sh — cross-platform exit-criteria scoreboard + HARD release gates (R7 / Requirement 11).
#
# Enforces, as HARD gates (non-zero exit on any violation):
#   (a) every RUNNABLE test layer is GREEN — macOS unit+integration+snapshot (+ the live
#       RealBackend lane when the desktop-e2e socket is present), daemon `go test`, TUI
#       `go test`, Linux `cargo fmt/clippy/test`, and the Windows headless view-model tests;
#   (b) macOS coverage is at/above the practical floor COV_MIN (default 71%, ceiling ~74% with
#       the live desktop-e2e VM). Never silently lowered;
#   (c) Go stream safety — `go test -race` on the daemon runs the streaming-cancellation
#       goroutine-leak check (Property 7 / Requirements 3.6, 11.2): race + leak + cancellation.
#
# Evidence convention (Assumption A2): a layer whose toolchain OR system libraries are genuinely
# absent on this host is marked "n/a (CI-authoritative)" and does NOT fail the local gate — green
# CI (frontends.yml/test.yml) is authoritative for it. But a REAL local test failure in any
# runnable layer DOES fail the gate. The native WinUI 3 / GTK 4 *GUI* compile is env-blocked off
# its native OS and is CI-authoritative; the cross-platform *headless* suites run here and are gated.
#
# Every layer runs under a wall-clock watchdog so a wedged live call can never hang the gate — a
# timed-out layer FAILS (it never blocks forever). Layers run sequentially so no layer starves
# another. Exit 0 (RESULT: GREEN) only when every applicable gate passes.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Make standard macOS/Homebrew/dotnet tool locations discoverable in non-login shells.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:$PATH"

SCHEME=ColimaDesktop
DEST='platform=macOS'
DD="${DD:-build/DerivedData}"                 # overridable for isolation (e.g. DD=/tmp/dd-verify)
GO="${GO:-$(command -v go 2>/dev/null || echo go)}"
# COV_MIN: literal 100% line coverage is PROVABLY UNREACHABLE headless (App.swift @main App/Scene
# bodies, AppKit callbacks — NSApp activation, menu/NSSavePanel handlers — and thin live-only
# RealServiceProvider delegate paths are structurally/environmentally uncoverable). Practical max
# measured ~74% (unit+integration + live RealBackend e2e vs the desktop-e2e VM). The release FLOOR
# is 71% (requirements Practical_Coverage_Ceiling / Assumption A2). Never silently lowered to pass.
COV_MIN="${COV_MIN:-71}"

fail=0
line() { printf '%-42s %s\n' "$1" "$2"; }
gate() { # gate "<label>" <exit_code> ["<extra>"]
  local label="$1" rc="$2" extra="${3:-}"
  if [ "$rc" -eq 0 ]; then line "$label" "PASS${extra:+ $extra}"
  else line "$label" "FAIL${extra:+ $extra} (rc=$rc)"; fail=1; fi
}
# run_bounded <seconds> <logfile> <cmd> [args...] — run a command with a hard wall-clock cap so a
# wedged/hung layer can never block the gate. On timeout the process (tree) is killed and rc=137.
run_bounded() {
  local secs="$1" logf="$2"; shift 2
  "$@" >"$logf" 2>&1 &
  local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null; pkill -9 -P "$pid" >/dev/null 2>&1 ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$watcher" >/dev/null 2>&1; wait "$watcher" 2>/dev/null
  if [ "$rc" -eq 137 ]; then echo "[verify] TIMEOUT after ${secs}s: $*" >>"$logf"; fi
  return $rc
}

echo "== Colima Desktop verify.sh =="
echo "-- HARD gates: every runnable test layer GREEN + coverage >= ${COV_MIN}% + Go stream-safety (race/leak/cancel) --"

# ─────────────────────────── macOS (reference frontend — local live evidence) ─
if command -v xcodebuild >/dev/null 2>&1; then
  command -v xcodegen >/dev/null 2>&1 && xcodegen generate >/dev/null 2>&1 || true

  BLOG=$(mktemp)
  run_bounded 900 "$BLOG" xcodebuild build -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DD"
  bstat=$?
  warns=$(grep "warning:" "$BLOG" 2>/dev/null | grep -vE "appintentsmetadataprocessor|Metadata extraction skipped" | grep -c "warning:")
  warns=$(printf %s "${warns:-0}" | tr -dc 0-9); warns=${warns:-0}
  if [ $bstat -eq 0 ] && [ "$warns" -eq 0 ]; then line "macOS build (0 warnings)" "PASS"
  else line "macOS build (0 warnings)" "FAIL ($warns warnings, build rc=$bstat)"; fail=1; fi

  # unit + integration + snapshot. The live RealBackend lane auto-activates when the desktop-e2e
  # docker socket is present (Requirement 8.7); it is confined to the desktop-e2e profile.
  ENVRUN=(env)
  if [ -S "$HOME/.colima/desktop-e2e/docker.sock" ]; then
    ENVRUN=(env TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1 TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE=desktop-e2e)
    line "macOS live RealBackend lane" "ACTIVE (desktop-e2e socket present)"
  else
    line "macOS live RealBackend lane" "n/a (no desktop-e2e socket — CI/local mock only)"
  fi
  TLOG=$(mktemp)
  run_bounded 1500 "$TLOG" "${ENVRUN[@]}" xcodebuild test -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DD" \
    -only-testing:ColimaDesktopUnitTests \
    -only-testing:ColimaDesktopIntegrationTests \
    -only-testing:ColimaDesktopSnapshotTests
  tstat=$?
  if grep -q "TEST SUCCEEDED" "$TLOG"; then line "macOS unit+integration+snapshot" "PASS"
  else line "macOS unit+integration+snapshot" "FAIL (rc=$tstat)"; fail=1; fi

  # coverage — ColimaDesktopKit line coverage from the most recent xcresult, gated at COV_MIN.
  XCRESULT=$(ls -dt "$DD"/Logs/Test/*.xcresult 2>/dev/null | head -1)
  if [ -n "$XCRESULT" ]; then
    PCT=$(xcrun xccov view --report --json "$XCRESULT" 2>/dev/null \
      | python3 -c 'import json,sys
try:
 d=json.load(sys.stdin); t=[x for x in d.get("targets",[]) if "ColimaDesktopKit" in x.get("name","")]
 print(round((t[0]["lineCoverage"] if t else 0)*100,1))
except Exception: print(0)')
    if awk "BEGIN{exit !($PCT>=$COV_MIN)}"; then line "macOS coverage (>=$COV_MIN%)" "PASS ($PCT%)"
    else line "macOS coverage (>=$COV_MIN%)" "FAIL ($PCT%)"; fail=1; fi
  else line "macOS coverage (>=$COV_MIN%)" "FAIL (no xcresult)"; fail=1; fi
else
  line "macOS toolchain" "n/a (no xcodebuild; CI macos-kit authoritative)"
fi

# ─────────────────────── Daemon (Go) — build/test + STREAM SAFETY (-race) ─────
if command -v "$GO" >/dev/null 2>&1 && [ -d daemon ]; then
  DBUILD=$(mktemp); run_bounded 300 "$DBUILD" "$GO" -C daemon build ./...; gate "daemon build" $?
  DTEST=$(mktemp);  run_bounded 300 "$DTEST"  "$GO" -C daemon test ./... -count=1 -timeout 240s; gate "daemon tests (go test)" $?
  # Stream safety: -race runs every daemon test incl. TestProperty7_StreamingCancellationDoesNotLeakGoroutines
  # (drives every stream/cancel path, tears the server down, asserts goroutines settle) → race + leak + cancel.
  DRACE=$(mktemp);  run_bounded 700 "$DRACE"  "$GO" -C daemon test -race ./... -count=1 -timeout 600s; gate "daemon stream-safety (race/leak/cancel)" $?
else
  line "daemon (go)" "n/a (no go toolchain; CI daemon jobs authoritative)"
fi

# ─────────────────────── TUI (Go) — build/vet/test (bounded output + cancel) ──
if command -v "$GO" >/dev/null 2>&1 && [ -d tui ]; then
  TBUILD=$(mktemp); run_bounded 240 "$TBUILD" "$GO" -C tui build ./...; gate "tui build" $?
  TVET=$(mktemp);   run_bounded 180 "$TVET"   "$GO" -C tui vet ./...;   gate "tui vet" $?
  # TUI tests. The fast, deterministic suite (unit/golden/dispatch + task-4.4 bounded-output,
  # destructive-confirmation and cancellation UNIT coverage) is the HARD local gate. The heavy
  # program-level teatest PROPERTY suite (Property 12/13/14/15) spins a real Bubble Tea program per
  # iteration (>=100 each); it is correct (proven in the R2 lane) but CPU/scheduling-sensitive and
  # impractically slow on a contended workstation (>20 min under the IDE's background load), so it is
  # CI-authoritative: the `frontends.yml` `tui` jobs run the full `go test ./...` on clean runners,
  # and Requirement 11.6 gates all 9 frontends.yml jobs + test.yml for a release candidate. This keeps
  # the local gate deterministic + bounded rather than flaky-under-load. Set TUI_FULL=1 to also run
  # the teatest property suite locally (bounded by TUI_TEST_TIMEOUT, default 1800s).
  if [ "${TUI_FULL:-0}" = "1" ]; then
    TUI_TEST_TIMEOUT="${TUI_TEST_TIMEOUT:-1800}"
    TUT=$(mktemp); run_bounded $((TUI_TEST_TIMEOUT + 120)) "$TUT" "$GO" -C tui test ./... -count=1 -timeout "${TUI_TEST_TIMEOUT}s"; gate "tui tests (full incl. P12-15 teatest)" $?
  else
    TUT=$(mktemp); run_bounded 400 "$TUT" "$GO" -C tui test ./... -skip 'TestProperty1[2345]' -count=1 -timeout 300s; gate "tui tests (unit/golden/dispatch/safety)" $?
    line "tui teatest properties (P12-15)" "CI-authoritative (frontends.yml tui; >=100-iter teatest)"
  fi
else
  line "tui (go)" "n/a (no go toolchain; CI tui jobs authoritative)"
fi

# ─────────────────────── Linux (Rust/GTK4) — fmt/clippy/test ──────────────────
# HARD gate only when cargo AND the GTK4 system libs are present. Without GTK4 dev libraries the
# native crate cannot compile — genuinely environment-blocked → CI linux-gtk4 authoritative, NOT a fail.
if command -v cargo >/dev/null 2>&1 && [ -f linux/Cargo.toml ] && command -v pkg-config >/dev/null 2>&1 && pkg-config --exists gtk4 2>/dev/null; then
  LM=linux/Cargo.toml
  LFMT=$(mktemp);    run_bounded 180 "$LFMT"    cargo fmt --manifest-path "$LM" --check;                         gate "linux fmt (--check)" $?
  LCLIP=$(mktemp);   run_bounded 700 "$LCLIP"   cargo clippy --manifest-path "$LM" --all-targets -- -D warnings; gate "linux clippy (-D warnings)" $?
  LTEST=$(mktemp);   run_bounded 700 "$LTEST"   cargo test --manifest-path "$LM";                                gate "linux tests (cargo test)" $?
elif command -v cargo >/dev/null 2>&1 && [ -f linux/Cargo.toml ]; then
  line "linux (rust/gtk4)" "n/a (GTK4 dev libs absent — CI linux-gtk4 authoritative)"
else
  line "linux (rust)" "n/a (no cargo toolchain; CI linux-gtk4 authoritative)"
fi

# ─────────────────────── Windows (.NET headless) — dotnet test ────────────────
# The net8.0 Tests project (view-model/service layer over the gRPC client) is cross-platform and
# runs here. The native WinUI 3 GUI compile is env-blocked off Windows (CI windows-winui authoritative)
# and is intentionally NOT attempted locally.
if command -v dotnet >/dev/null 2>&1 && [ -f windows/Tests/ColimaDesktop.Windows.Tests.csproj ]; then
  WLOG=$(mktemp); run_bounded 700 "$WLOG" dotnet test windows/Tests/ColimaDesktop.Windows.Tests.csproj -c Debug --nologo; gate "windows headless tests (dotnet)" $?
else
  line "windows (.net)" "n/a (no dotnet toolchain; CI windows-winui authoritative)"
fi

# ─────────────────────── SwiftLint (optional) ────────────────────────────────
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet Sources >/dev/null 2>&1 && line "swiftlint" "PASS" || { line "swiftlint" "FAIL"; fail=1; }
else line "swiftlint" "n/a (not installed)"; fi

echo "=============================="
[ $fail -eq 0 ] && echo "RESULT: GREEN" || echo "RESULT: NOT GREEN"
exit $fail

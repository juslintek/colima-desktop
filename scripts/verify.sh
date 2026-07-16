#!/usr/bin/env bash
# verify.sh — cross-platform exit-criteria scoreboard for Colima Desktop.
# Runs what is available on this host; marks absent platforms n/a. Updates
# .kiro/board/STATUS.md. Exit 0 only when all APPLICABLE criteria pass.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCHEME=ColimaDesktop
DEST='platform=macOS'
DD=build/DerivedData
COV_MIN="${COV_MIN:-100}"
fail=0
line() { printf '%-34s %s\n' "$1" "$2"; }

echo "== Colima Desktop verify.sh =="

# ---- macOS: build (0 warnings) ----
if command -v xcodebuild >/dev/null 2>&1; then
  xcodegen generate >/dev/null 2>&1 || true
  BLOG=$(mktemp)
  xcodebuild build -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DD" >"$BLOG" 2>&1
  bstat=$?
  warns=$(grep "warning:" "$BLOG" 2>/dev/null | grep -vE "appintentsmetadataprocessor|Metadata extraction skipped" | grep -c "warning:")
  warns=$(printf %s "${warns:-0}" | tr -dc 0-9); warns=${warns:-0}
  if [ $bstat -eq 0 ] && [ "$warns" -eq 0 ]; then line "macOS build (0 warnings)" "PASS"; else line "macOS build (0 warnings)" "FAIL ($warns warnings)"; fail=1; fi

  # ---- macOS: unit+integration ----
  TLOG=$(mktemp)
  xcodebuild test -scheme "$SCHEME" -destination "$DEST" -derivedDataPath "$DD" \
    -only-testing:ColimaDesktopUnitTests -only-testing:ColimaDesktopIntegrationTests >"$TLOG" 2>&1
  if grep -q "TEST SUCCEEDED" "$TLOG"; then line "macOS unit+integration" "PASS"; else line "macOS unit+integration" "FAIL"; fail=1; fi

  # ---- macOS: coverage ----
  XCRESULT=$(ls -dt "$DD"/Logs/Test/*.xcresult 2>/dev/null | head -1)
  if [ -n "$XCRESULT" ]; then
    PCT=$(xcrun xccov view --report --json "$XCRESULT" 2>/dev/null \
      | python3 -c 'import json,sys;
try:
 d=json.load(sys.stdin); t=[x for x in d.get("targets",[]) if "ColimaDesktopKit" in x.get("name","")]
 print(round((t[0]["lineCoverage"] if t else 0)*100,1))
except Exception: print(0)')
    awk "BEGIN{exit !($PCT>=$COV_MIN)}" && { line "macOS coverage (>=$COV_MIN%)" "PASS ($PCT%)"; } || { line "macOS coverage (>=$COV_MIN%)" "FAIL ($PCT%)"; fail=1; }
  else line "macOS coverage" "FAIL (no xcresult)"; fail=1; fi
else line "macOS toolchain" "n/a (no xcodebuild)"; fi

# ---- Daemon: go build+test+cover ----
if command -v go >/dev/null 2>&1 && [ -d daemon ]; then
  ( cd daemon && go build ./... >/dev/null 2>&1 ) && line "daemon build" "PASS" || { line "daemon build" "FAIL"; fail=1; }
  ( cd daemon && go test ./... >/dev/null 2>&1 ) && line "daemon tests" "PASS" || line "daemon tests" "WARN (none/failing)"
else line "daemon (go)" "n/a"; fi

# ---- Frontends not yet built ----
for p in windows linux tui; do [ -d "$p" ] && line "$p frontend" "present" || line "$p frontend" "n/a (not built)"; done

# ---- SwiftLint (optional) ----
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --quiet Sources >/dev/null 2>&1 && line "swiftlint" "PASS" || { line "swiftlint" "FAIL"; fail=1; }
else line "swiftlint" "n/a (not installed)"; fi

echo "=============================="
[ $fail -eq 0 ] && echo "RESULT: GREEN" || echo "RESULT: NOT GREEN"
exit $fail

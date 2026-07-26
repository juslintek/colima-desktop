#!/usr/bin/env bash
# rc-gate.sh — the single RELEASE-CANDIDATE gate aggregator (R7 / task 12.5, Requirement 11.6).
#
# One reproducible command that composes EVERY R7 hardening sub-gate into a single pass/fail
# verdict that a release candidate (task 13 / R8) MUST clear before it can proceed. It INVOKES the
# sub-gate scripts owned by tasks 12.1–12.4 (it never reimplements them):
#
#   [verify]    scripts/verify.sh                           (12.1) — every runnable test layer GREEN
#                                                                     + macOS coverage >= COV_MIN (71%)
#                                                                     + Go stream-safety (race/leak/cancel)
#   [security]  scripts/security-scan.sh --fail-on-critical (12.2) — SBOMs + zero known CRITICAL vuln
#   [perf]      scripts/perf-budgets.sh --check             (12.3) — startup / idle-resource / large-list
#   [a11y]      scripts/check-a11y-ids.py                   (12.4) — cross-frontend a11y-id totality+uniqueness
#
# ...plus the CI-authoritative layers that CANNOT be exercised on a macOS-only host and are proven
# by their CI jobs instead (Assumption A2 evidence convention — see docs/release-candidate-gate.md):
#
#   [frontends] .github/workflows/frontends.yml — 9 jobs (daemon x3, tui x3, windows-winui,
#                                                 linux-gtk4, macos-kit). The native WinUI 3 XAML
#                                                 and GTK 4 compiles are env-blocked locally →
#                                                 CI-authoritative (never faked green here).
#   [tests]     .github/workflows/test.yml      — macOS build + unit + integration on a clean runner.
#
# The IDENTICAL aggregation runs in CI as .github/workflows/release-candidate.yml, which re-invokes
# frontends.yml + test.yml + security-scan.yml as reusable workflows and runs verify.sh + the
# perf/a11y gates — so the RC verdict is reproducible both locally and in CI.
#
# OWNERSHIP: this script lives in the devops `scripts/**` lane and only INVOKES the 12.1–12.4
# scripts; it does not edit them, nor any daemon/frontend/proto/Tests source.
#
# EXIT CODE: 0 only when every gate that RAN passed. A gate that is genuinely CI-authoritative on
# this host (deferred) is labelled and does NOT fail the local verdict, but is reported honestly as
# "n/a (CI-authoritative)" rather than a pass — so a local GREEN is an honestly-labelled partial
# whenever a native-only layer is deferred to CI.
#
# USAGE
#   scripts/rc-gate.sh                 # thorough: verify.sh (watchdog) + security + perf + a11y
#   scripts/rc-gate.sh --fast          # quick local lane: defer verify.sh to CI/`make verify`,
#                                      #   consume the committed security summary, run perf + a11y live
#   scripts/rc-gate.sh --full-security # re-run the vulnerability scanners locally (needs network)
#   scripts/rc-gate.sh --skip-verify   # (also --skip-security | --skip-perf | --skip-a11y)
#   scripts/rc-gate.sh --list          # print the gate plan + CI mapping and exit 0 (no gates run)
#   scripts/rc-gate.sh --selftest      # prove the pass/fail aggregation is correct, exit 0/1
#   scripts/rc-gate.sh -h | --help
#
# macOS bash 3.2 compatible. No `set -e` (gates intentionally return non-zero).
set -uo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Make standard macOS/Homebrew/dotnet/cargo tool locations discoverable in non-login shells.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/share/dotnet:$HOME/.cargo/bin:$PATH"

# ── Gate commands (defaults invoke the task 12.1–12.4 scripts; overridable for the selftest/tests) ─
: "${RC_VERIFY_CMD:=bash $ROOT/scripts/verify.sh}"
: "${RC_SECURITY_CMD:=bash $ROOT/scripts/security-scan.sh --fail-on-critical}"
: "${RC_PERF_CMD:=bash $ROOT/scripts/perf-budgets.sh --check}"
: "${RC_A11Y_CMD:=python3 $ROOT/scripts/check-a11y-ids.py}"
SECURITY_SUMMARY="${RC_SECURITY_SUMMARY:-$ROOT/docs/sbom/vuln-summary.json}"

# ── Per-gate wall-clock watchdog caps (seconds) — a wedged gate can never hang the aggregate ──
VERIFY_TIMEOUT="${RC_VERIFY_TIMEOUT:-2400}"
SECURITY_TIMEOUT="${RC_SECURITY_TIMEOUT:-1200}"
PERF_TIMEOUT="${RC_PERF_TIMEOUT:-180}"
A11Y_TIMEOUT="${RC_A11Y_TIMEOUT:-180}"

FAST=0
FULL_SECURITY=0
RUN_VERIFY=1; RUN_SECURITY=1; RUN_PERF=1; RUN_A11Y=1
MODE="run"
LOGDIR="${RC_GATE_LOGDIR:-${TMPDIR:-/tmp}/rc-gate-logs}"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --fast)          FAST=1; shift ;;
    --full-security) FULL_SECURITY=1; shift ;;
    --skip-verify)   RUN_VERIFY=0; shift ;;
    --skip-security) RUN_SECURITY=0; shift ;;
    --skip-perf)     RUN_PERF=0; shift ;;
    --skip-a11y)     RUN_A11Y=0; shift ;;
    --list|--dry-run) MODE="list"; shift ;;
    --selftest)      MODE="selftest"; shift ;;
    --log-dir)       LOGDIR="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "rc-gate: unknown arg: $1 (see --help)" >&2; exit 2 ;;
  esac
done

mkdir -p "$LOGDIR"

# run_bounded <seconds> <logfile> <cmd...> — hard wall-clock cap; kills the process tree on timeout
# (rc 137) so a wedged gate cannot block the RC verdict. Mirrors the pattern in verify.sh.
run_bounded() {
  local secs="$1" logf="$2"; shift 2
  "$@" >"$logf" 2>&1 &
  local pid=$!
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null; pkill -9 -P "$pid" >/dev/null 2>&1 ) >/dev/null 2>&1 &
  local watcher=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$watcher" >/dev/null 2>&1; wait "$watcher" 2>/dev/null
  if [ "$rc" -eq 137 ]; then echo "[rc-gate] TIMEOUT after ${secs}s: $*" >>"$logf"; fi
  return $rc
}

# ── Scoreboard state ──────────────────────────────────────────────────────────
SUMMARY_LABELS=(); SUMMARY_STATUS=(); SUMMARY_DETAIL=()
fail=0
deferred=0
ran=0
record() { SUMMARY_LABELS+=("$1"); SUMMARY_STATUS+=("$2"); SUMMARY_DETAIL+=("${3:-}"); }

# Consume the committed vulnerability summary (real scan output from task 12.2) as the security
# verdict without re-running the network/install-heavy scanners. Zero known CRITICAL => pass.
security_from_summary() {
  [ -f "$SECURITY_SUMMARY" ] || return 3
  python3 - "$SECURITY_SUMMARY" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("security summary: unreadable (%s)" % e); sys.exit(2)
crit = int(d.get("severity_totals", {}).get("critical", 0))
verdict = d.get("verdict", "?")
print("verdict=%s critical=%d (committed %s)" % (verdict, crit, "docs/sbom/vuln-summary.json"))
sys.exit(0 if crit == 0 else 1)
PY
}

# ── --list : print the plan and exit (nothing runs) ────────────────────────────
if [ "$MODE" = "list" ]; then
  echo "== release-candidate gate plan (task 12.5 / Requirement 11.6) =="
  echo "Local gates (this host):"
  echo "  verify   -> $RC_VERIFY_CMD        $([ "$FAST" -eq 1 ] && echo '[--fast: DEFERRED to CI/make verify]')"
  echo "  security -> $([ "$FULL_SECURITY" -eq 1 ] && echo "$RC_SECURITY_CMD" || echo "read $SECURITY_SUMMARY (--full-security to re-scan)")"
  echo "  perf     -> $RC_PERF_CMD"
  echo "  a11y     -> $RC_A11Y_CMD"
  echo "CI-authoritative layers (proven by their CI jobs; env-blocked locally):"
  echo "  frontends-> .github/workflows/frontends.yml (9 jobs: daemon x3, tui x3, windows-winui, linux-gtk4, macos-kit)"
  echo "  tests    -> .github/workflows/test.yml (macOS build + unit + integration)"
  echo "Aggregated in CI by .github/workflows/release-candidate.yml. Task 13 (release) is gated on GREEN."
  exit 0
fi

# ── --selftest : prove the aggregation flips pass/fail correctly ────────────────
if [ "$MODE" = "selftest" ]; then
  echo "== rc-gate --selftest (aggregation logic) =="
  env RC_VERIFY_CMD=true  RC_SECURITY_CMD=true RC_PERF_CMD=true RC_A11Y_CMD=true \
      RC_SECURITY_SUMMARY=/nonexistent RC_GATE_LOGDIR="$LOGDIR/selftest-pass" \
      bash "$SELF" --full-security >/dev/null 2>&1; a=$?
  env RC_VERIFY_CMD=true  RC_SECURITY_CMD=true RC_PERF_CMD=true RC_A11Y_CMD=false \
      RC_SECURITY_SUMMARY=/nonexistent RC_GATE_LOGDIR="$LOGDIR/selftest-fail" \
      bash "$SELF" --full-security >/dev/null 2>&1; b=$?
  echo "  all-gates-pass  -> exit $a (expect 0)"
  echo "  one-gate-fails  -> exit $b (expect non-zero)"
  if [ "$a" -eq 0 ] && [ "$b" -ne 0 ]; then echo "RESULT: selftest PASS"; exit 0; fi
  echo "RESULT: selftest FAIL (aggregation did not flip: pass=$a fail=$b)"; exit 1
fi

# ── run the gates ───────────────────────────────────────────────────────────────
echo "== Colima Desktop release-candidate gate (task 12.5 / Requirement 11.6) =="
echo "-- aggregates: verify(12.1) + security(12.2) + perf(12.3) + a11y(12.4) + CI frontends.yml/test.yml --"
[ "$FAST" -eq 1 ] && echo "-- MODE: --fast (verify deferred to CI/'make verify'; security from committed summary) --"

# verify (12.1) — heavy macOS/Go gate. In --fast it is CI-authoritative (macos-kit + test.yml + the
# daemon/tui CI jobs run the same layers on clean runners) and deferred locally.
if [ "$RUN_VERIFY" -eq 1 ]; then
  if [ "$FAST" -eq 1 ]; then
    record "verify (12.1)" "n/a (CI-authoritative)" "deferred to 'make verify' + CI macos-kit/test.yml"
    deferred=$((deferred + 1))
  else
    run_bounded "$VERIFY_TIMEOUT" "$LOGDIR/verify.log" $RC_VERIFY_CMD; rc=$?
    ran=$((ran + 1))
    if [ "$rc" -eq 0 ]; then record "verify (12.1)" "PASS" "GREEN + coverage + stream-safety ($LOGDIR/verify.log)"
    else record "verify (12.1)" "FAIL (rc=$rc)" "$LOGDIR/verify.log"; fail=1; fi
  fi
else
  record "verify (12.1)" "SKIP (user)" "--skip-verify"
fi

# security (12.2) — zero known CRITICAL vulnerability. Default consumes the committed real scan
# summary; --full-security re-runs the scanners (needs network/install).
if [ "$RUN_SECURITY" -eq 1 ]; then
  if [ "$FULL_SECURITY" -eq 1 ]; then
    run_bounded "$SECURITY_TIMEOUT" "$LOGDIR/security.log" $RC_SECURITY_CMD; rc=$?
    ran=$((ran + 1))
    if [ "$rc" -eq 0 ]; then record "security (12.2)" "PASS" "scan re-run, zero critical ($LOGDIR/security.log)"
    else record "security (12.2)" "FAIL (rc=$rc)" "$LOGDIR/security.log"; fail=1; fi
  else
    detail="$(security_from_summary)"; rc=$?
    if [ "$rc" -eq 0 ]; then record "security (12.2)" "PASS" "$detail"; ran=$((ran + 1))
    elif [ "$rc" -eq 3 ]; then record "security (12.2)" "n/a (no summary)" "run 'make security-scan' or --full-security"; deferred=$((deferred + 1))
    else record "security (12.2)" "FAIL" "$detail"; fail=1; fi
  fi
else
  record "security (12.2)" "SKIP (user)" "--skip-security"
fi

# perf (12.3) — startup / idle-resource / large-list budgets. --check reads the committed JSON.
if [ "$RUN_PERF" -eq 1 ]; then
  run_bounded "$PERF_TIMEOUT" "$LOGDIR/perf.log" $RC_PERF_CMD; rc=$?
  ran=$((ran + 1))
  if [ "$rc" -eq 0 ]; then record "perf (12.3)" "PASS" "budgets OK ($LOGDIR/perf.log)"
  else record "perf (12.3)" "FAIL (rc=$rc)" "$LOGDIR/perf.log"; fail=1; fi
else
  record "perf (12.3)" "SKIP (user)" "--skip-perf"
fi

# a11y (12.4) — cross-frontend accessibility-identifier totality + uniqueness.
if [ "$RUN_A11Y" -eq 1 ]; then
  run_bounded "$A11Y_TIMEOUT" "$LOGDIR/a11y.log" $RC_A11Y_CMD; rc=$?
  ran=$((ran + 1))
  if [ "$rc" -eq 0 ]; then record "a11y (12.4)" "PASS" "cross-frontend a11y-id gate ($LOGDIR/a11y.log)"
  else record "a11y (12.4)" "FAIL (rc=$rc)" "$LOGDIR/a11y.log"; fail=1; fi
else
  record "a11y (12.4)" "SKIP (user)" "--skip-a11y"
fi

# CI-authoritative layers (never run locally; recorded so the verdict is honest about coverage).
record "frontends (CI)" "n/a (CI-authoritative)" ".github/workflows/frontends.yml — 9 jobs"
record "tests (CI)" "n/a (CI-authoritative)" ".github/workflows/test.yml"

# ── scoreboard ──────────────────────────────────────────────────────────────────
echo "------------------------------------------------------------------------------"
i=0
while [ "$i" -lt "${#SUMMARY_LABELS[@]}" ]; do
  printf '%-18s %-24s %s\n' "${SUMMARY_LABELS[$i]}" "${SUMMARY_STATUS[$i]}" "${SUMMARY_DETAIL[$i]}"
  i=$((i + 1))
done
echo "------------------------------------------------------------------------------"
echo "local gates run: $ran | deferred to CI: $deferred"

if [ "$fail" -eq 0 ]; then
  if [ "$deferred" -gt 0 ]; then
    echo "RESULT: RC-GATE GREEN (partial — $deferred layer(s) CI-authoritative; verify in CI: .github/workflows/release-candidate.yml)"
  else
    echo "RESULT: RC-GATE GREEN"
  fi
  echo "Task 13 (R8 release) MAY proceed once CI release-candidate.yml is GREEN on the tag."
  exit 0
fi
echo "RESULT: RC-GATE NOT GREEN — a required gate failed above. Task 13 (release) is BLOCKED."
exit 1

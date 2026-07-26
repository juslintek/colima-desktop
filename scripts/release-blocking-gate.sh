#!/usr/bin/env bash
# release-blocking-gate.sh -- the P0/P1 RELEASE-BLOCKING gate (R8 / task 13.4, Requirement 12.5).
#
# Thin shell entry point (mirrors scripts/sbom.sh -> scripts/sbom_gen.py) so the release flow, CI,
# and `make` invoke this gate the same way they invoke verify.sh / rc-gate.sh / security-scan.sh.
# All logic lives in scripts/release_blocking_gate.py (pure + importable, so task 13.5 can
# property-test it directly).
#
# Requirement 12.5: block the v1.0.0 tag IFF any OPEN defect carries priority P0 or P1
# (design Property 22). Defect source = docs/release-defects.json (+ auto-ingest of the task-12.2
# docs/sbom/vuln-summary.json: critical->P0, high->P1). This gate is COMPLEMENTARY to the
# release-candidate gate (scripts/rc-gate.sh, task 12.5): BOTH must pass to ship (task 13.6).
#
# EXIT: 0 = no open P0/P1 (release may proceed, defect-gate-wise); 1 = blocked (open P0/P1 present);
#       2 = usage error / defect source unreadable (FAIL-CLOSED -- never counts as pass).
#
# USAGE
#   scripts/release-blocking-gate.sh                 # check docs/release-defects.json (+ vuln summary)
#   scripts/release-blocking-gate.sh --list          # print every defect + classification, exit 0
#   scripts/release-blocking-gate.sh --format json   # machine-readable verdict
#   scripts/release-blocking-gate.sh --no-vuln       # registry only
#   scripts/release-blocking-gate.sh --selftest      # prove the block-iff-P0/P1 logic, exit 0/1
#   scripts/release-blocking-gate.sh --registry PATH # check an explicit registry
#   scripts/release-blocking-gate.sh -h | --help
#
# macOS bash 3.2 compatible.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
PY="${PYTHON:-python3}"
exec "$PY" "$ROOT/scripts/release_blocking_gate.py" "$@"

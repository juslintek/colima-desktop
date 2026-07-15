#!/usr/bin/env bash
# changelog.sh — generate a Keep-a-Changelog-style markdown from conventional commits.
# Usage: scripts/changelog.sh [<git-range>]  (default: all history)
# Prints markdown to stdout.
set -euo pipefail
RANGE="${1:-}"
range_args=()
[ -n "$RANGE" ] && range_args=("$RANGE")

section() { # <type-regex> <title>
  local pat="$1" title="$2" body
  body=$(git log --no-merges --pretty=format:'%s|%h' "${range_args[@]}" 2>/dev/null \
    | grep -iE "^($pat)(\([^)]*\))?!?:" || true)
  [ -z "$body" ] && return 0
  echo "### $title"
  echo
  while IFS='|' read -r subj hash; do
    subj="${subj#*: }"
    echo "- ${subj} (\`${hash}\`)"
  done <<< "$body"
  echo
}

VERSION="${VERSION:-Unreleased}"
echo "## ${VERSION} — $(date +%Y-%m-%d)"
echo
section "feat" "Features"
section "fix" "Fixes"
section "perf" "Performance"
section "refactor" "Refactoring"
section "test" "Tests"
section "docs" "Documentation"
section "chore|build|ci" "Chores & CI"

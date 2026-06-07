#!/usr/bin/env bash
#
# Derive the app version from git tags for tagged releases.
#
#   MARKETING_VERSION       -> CFBundleShortVersionString (e.g. 1.2.0)
#                              from the latest `vX.Y.Z` tag (the leading `v` is stripped).
#   CURRENT_PROJECT_VERSION -> CFBundleVersion (monotonic build number)
#                              = total commit count, always increasing.
#
# Override the marketing version explicitly with VERSION=1.4.0.
# Prints two `KEY=VALUE` lines; eval it or parse it.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${VERSION:-}" ]]; then
  MARKETING="${VERSION#v}"
else
  TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)"
  MARKETING="${TAG#v}"
fi

# Build number must be a monotonically increasing integer for Gatekeeper/updates.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

echo "MARKETING_VERSION=${MARKETING}"
echo "CURRENT_PROJECT_VERSION=${BUILD}"

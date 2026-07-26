#!/usr/bin/env bash
#
# Single source of version truth for EVERY shipped component (R8 / task 13.1).
#
# The version is derived from the git tag so a `vX.Y.Z` tag stamps the same
# X.Y.Z into the macOS app, the Go daemon + TUI, the Windows package, and the
# Linux package. Every packaging script (any language) reads THIS script so the
# version can never drift between components.
#
#   MARKETING_VERSION       -> CFBundleShortVersionString (e.g. 1.2.0)
#                              from the latest `vX.Y.Z` tag (the leading `v` is stripped).
#   CURRENT_PROJECT_VERSION -> CFBundleVersion (monotonic build number)
#                              = total commit count, always increasing.
#
# Override the marketing version explicitly with VERSION=1.4.0 (a leading `v` is
# stripped). Useful in CI where the tag ref is passed as `v1.0.0`.
#
# USAGE
#   scripts/version.sh              # two KEY=VALUE lines (eval it) — default, back-compat
#   eval "$(scripts/version.sh)"    # sets MARKETING_VERSION + CURRENT_PROJECT_VERSION
#   scripts/version.sh marketing    # just the marketing version   -> 1.2.0
#   scripts/version.sh build        # just the build number        -> 143
#   scripts/version.sh tag          # the vX.Y.Z tag form           -> v1.2.0
#   scripts/version.sh commit       # short commit sha              -> a1b2c3d
#   scripts/version.sh json         # machine-readable, for any consumer
#
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
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

case "${1:-env}" in
  env|"")
    # Default: KEY=VALUE lines for `eval` (package.sh / github-release.sh depend on this).
    echo "MARKETING_VERSION=${MARKETING}"
    echo "CURRENT_PROJECT_VERSION=${BUILD}"
    ;;
  marketing|version) echo "${MARKETING}" ;;
  build) echo "${BUILD}" ;;
  tag) echo "v${MARKETING}" ;;
  commit) echo "${COMMIT}" ;;
  json)
    printf '{"marketing":"%s","build":"%s","tag":"v%s","commit":"%s"}\n' \
      "${MARKETING}" "${BUILD}" "${MARKETING}" "${COMMIT}"
    ;;
  *)
    echo "version.sh: unknown mode '$1' (env|marketing|build|tag|commit|json)" >&2
    exit 2
    ;;
esac

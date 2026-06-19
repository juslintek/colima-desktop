#!/usr/bin/env bash
#
# Cut a GitHub release for Colima Desktop and publish the Sparkle appcast.
#
#   1. builds the DMG for the current git tag (scripts/package.sh; unsigned unless
#      SIGN_IDENTITY/NOTARIZE are set — see DISTRIBUTION.md),
#   2. creates/uploads a GitHub Release with the DMG (gh),
#   3. regenerates appcast.xml with enclosure URLs pointing at the release assets,
#      preserving prior entries, and commits it to main so SUFeedURL serves it.
#
# Prereqs: `gh auth login`, a git tag checked out (e.g. `git tag v1.0.0`), and
# Sparkle EdDSA keys (`make sparkle-keys`, or SPARKLE_PRIVATE_KEY env for CI).
#
# Usage: git tag v1.0.0 && scripts/github-release.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "juslintek/colima-desktop")"
TAG="${TAG:-$(git describe --tags --exact-match 2>/dev/null || true)}"
[[ -n "$TAG" ]] || { echo "ERROR: no exact git tag on HEAD. Run: git tag vX.Y.Z"; exit 1; }
VERSION="${TAG#v}"
DMG="dist/Colima Desktop-$VERSION.dmg"

echo "==> Building DMG for $TAG"
VERSION="$VERSION" scripts/package.sh
[[ -f "$DMG" ]] || { echo "ERROR: $DMG not produced"; exit 1; }

echo "==> Creating GitHub release $TAG on $REPO"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --clobber
else
  gh release create "$TAG" "$DMG" --title "$TAG" --generate-notes
fi

echo "==> Generating appcast (enclosures -> release assets), preserving history"
# Seed dist/ with the currently-published appcast so prior versions are preserved.
[[ -f appcast.xml ]] && cp appcast.xml dist/appcast.xml
DOWNLOAD_URL_PREFIX="https://github.com/$REPO/releases/download/$TAG/" \
  scripts/sparkle-appcast.sh

echo "==> Publishing appcast.xml to main (served at SUFeedURL)"
cp dist/appcast.xml appcast.xml
git add appcast.xml
if ! git diff --cached --quiet -- appcast.xml; then
  git commit -m "chore(release): appcast for $TAG"
  git push origin HEAD:main
else
  echo "   (appcast unchanged)"
fi
echo "==> Released $TAG: $DMG + appcast.xml"

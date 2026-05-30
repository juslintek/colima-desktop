#!/bin/bash
set -e
SCHEME="ColimaDesktop"

xcodebuild build-for-testing -scheme $SCHEME -destination 'platform=macOS' -quiet 2>&1 | grep -E 'error:' | head -5
xcodebuild test -scheme $SCHEME -destination 'platform=macOS' \
  -only-testing:ColimaDesktopUITests \
  -resultBundlePath TestResults.xcresult

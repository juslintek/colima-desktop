#!/bin/bash
set -e
cd /project

echo "=== Installing xcodegen ==="
which xcodegen || brew install xcodegen

echo "=== Generating Xcode project ==="
xcodegen generate

echo "=== Building ==="
xcodebuild build-for-testing -scheme ColimaUI -destination 'platform=macOS' -quiet 2>&1 | grep -E 'error:' | head -5

echo "=== Running UI Tests ==="
xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
  -only-testing:ColimaUIUITests \
  2>&1 | tee /project/test_output.txt | grep -E 'Executed|Test Case.*failed'

echo ""
echo "=== RESULTS ==="
grep 'Executed.*tests' /project/test_output.txt | tail -1
echo "Failures:"
grep -c 'Test Case.*failed' /project/test_output.txt || echo "0"

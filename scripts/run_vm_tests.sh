#!/bin/bash
set -e

# Run tests inside Tart VM via SSH (uses ~/.ssh/config Host tart-vm)
# VM: colima-test-vnc with project mounted at /Volumes/My Shared Files/project

VM_NAME="colima-test-vnc"
SSH_HOST="tart-vm"
PROJECT_PATH="/Volumes/My Shared Files/project"
SCHEME="ColimaDesktop"

# Verify VM is running
if ! tart ip "$VM_NAME" &>/dev/null; then
    echo "ERROR: VM '$VM_NAME' not running."
    echo "Start with: tart run $VM_NAME --dir=project:/Volumes/Projects/colima-desktop --vnc &"
    exit 1
fi

# Run requested test target (default: unit)
TARGET="${1:-ColimaDesktopUnitTests}"

echo "=== Running $TARGET in VM ($SSH_HOST) ==="

ssh "$SSH_HOST" "cd '$PROJECT_PATH' && xcodebuild test -scheme $SCHEME -destination 'platform=macOS' -derivedDataPath /tmp/DD -only-testing:$TARGET 2>&1" | tee /tmp/vm-test-output.txt

if grep -q "TEST SUCCEEDED" /tmp/vm-test-output.txt; then
    echo "=== ✅ PASSED ==="
else
    echo "=== ❌ FAILED ==="
    exit 1
fi

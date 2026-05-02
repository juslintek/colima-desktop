#!/bin/bash
set -e
cd /project

echo "=== Installing dependencies ==="
which xcodegen || brew install xcodegen
which colima || brew install colima docker

echo "=== Starting Colima ==="
colima start --vm-type vz --mount-type virtiofs --cpus 4 --memory 8 || true

echo "=== Creating test fixtures ==="
docker pull nginx:latest
docker pull redis:7-alpine
docker pull postgres:16
docker pull node:20-slim
docker pull python:3.12

docker run -d --name web-server -p 8080:80 nginx:latest || true
docker run -d --name postgres-db postgres:16 -e POSTGRES_PASSWORD=test || true
docker create --name redis-cache redis:7-alpine || true
docker run -d --name api-service node:20-slim sleep infinity || true
docker run -d --name worker python:3.12 sleep infinity || true
docker pause worker || true

docker volume create postgres_data || true
docker volume create redis_data || true
docker volume create app_uploads || true
docker network create app-network || true

echo "=== Generating Xcode project ==="
xcodegen generate

echo "=== Granting TCC permissions ==="
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified, pid, pid_version, boot_uuid, last_reminded) VALUES ('kTCCServiceAccessibility', 'com.apple.dt.Xcode', 0, 2, 0, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $(date +%s), NULL, NULL, 'UNUSED', 0);"
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity, flags, last_modified, pid, pid_version, boot_uuid, last_reminded) VALUES ('kTCCServiceAccessibility', 'com.colima.ColimaUI', 0, 2, 0, 1, NULL, NULL, 0, 'UNUSED', NULL, 0, $(date +%s), NULL, NULL, 'UNUSED', 0);"

echo "=== Running tests ==="
xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
  -only-testing:ColimaUIUITests \
  -resultBundlePath /project/TestResults.xcresult 2>&1 | tee /project/test_output.txt

PASSED=$(grep -c 'passed' /project/test_output.txt || echo 0)
FAILED=$(grep -c 'Test Case.*failed' /project/test_output.txt || echo 0)
echo ""
echo "=== RESULTS: $PASSED passed, $FAILED failed ==="

echo "=== Cleanup ==="
docker rm -f web-server postgres-db redis-cache api-service worker 2>/dev/null
docker volume rm postgres_data redis_data app_uploads 2>/dev/null
docker network rm app-network 2>/dev/null
colima stop

exit $( [ "$FAILED" -eq 0 ] && echo 0 || echo 1 )

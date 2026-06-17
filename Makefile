.PHONY: all build daemon app test test-unit test-integration test-snapshots test-real-e2e test-smoke test-vm test-local clean

DAEMON_BIN = build/colima-daemon
APP_BUNDLE = build/Colima\ Desktop.app
TART_IMAGE = ghcr.io/cirruslabs/macos-sequoia-base:latest
VM_NAME = colima-test-$(shell date +%s)
SCHEME = ColimaDesktop
DEST = 'platform=macOS'
DD = -derivedDataPath build/DerivedData
E2E_PROFILE = desktop-e2e

all: build

build: daemon app

daemon:
	cd daemon && go build -o ../$(DAEMON_BIN) ./cmd

app:
	xcodegen generate
	xcodebuild build -scheme $(SCHEME) -destination $(DEST) $(DD) -quiet

# === Fast test pyramid (no VM needed) ===

test: test-unit test-integration

test-unit:
	xcodegen generate
	xcodebuild test -scheme $(SCHEME) -destination $(DEST) $(DD) \
		-only-testing:ColimaDesktopUnitTests -quiet

test-integration:
	xcodegen generate
	xcodebuild test -scheme $(SCHEME) -destination $(DEST) $(DD) \
		-only-testing:ColimaDesktopIntegrationTests -quiet

test-snapshots:
	xcodegen generate
	xcodebuild test -scheme $(SCHEME) -destination $(DEST) $(DD) \
		-only-testing:ColimaDesktopSnapshotTests -quiet

# === Real-backend E2E (host with a dedicated colima profile) ===
# Requires: `colima start colima-desktop-e2e --vm-type vz` (colima stores it as `desktop-e2e`).
# Opt-in is mandatory; env is forwarded to the test runner via the TEST_RUNNER_ prefix.
test-real-e2e:
	xcodegen generate
	TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1 TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE=$(E2E_PROFILE) \
		xcodebuild test -scheme $(SCHEME) -destination $(DEST) $(DD) \
		-only-testing:ColimaDesktopUnitTests/RealBackendTests

# === Slow E2E smoke tests (Tart VM only) ===

test-smoke: test-vm

test-vm:
	./scripts/run_vm_tests.sh ColimaDesktopUITests

test-local:
	xcodegen generate
	xcodebuild test -scheme $(SCHEME) -destination $(DEST) \
		-only-testing:ColimaDesktopUITests

# === Utilities ===

proto:
	protoc --go_out=daemon --go-grpc_out=daemon proto/colima_ui.proto

clean:
	rm -rf build/ ColimaDesktop.xcodeproj TestResults.xcresult
	cd daemon && go clean

install: build
	cp -R $(APP_BUNDLE) /Applications/
	cp $(DAEMON_BIN) /usr/local/bin/

run: build
	open $(APP_BUNDLE)

setup-tart:
	brew install cirruslabs/cli/tart
	tart pull $(TART_IMAGE)

# === Distribution (Developer ID + notarization; NOT App Store — see docs/DISTRIBUTION.md) ===
.PHONY: package-dmg release

# Unsigned DMG (pipeline proof): make package-dmg
# Signed+notarized: SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=Name NOTARIZE=1 make release
package-dmg:
	scripts/package.sh

release:
	NOTARIZE=$(NOTARIZE) scripts/package.sh

# === Sparkle auto-update tooling ===
.PHONY: sparkle-keys appcast
sparkle-keys:   # one-time: generate EdDSA keys (private -> keychain, public -> stdout)
	scripts/sparkle-keys.sh

appcast:        # sign dist/*.dmg and (re)generate dist/appcast.xml
	scripts/sparkle-appcast.sh

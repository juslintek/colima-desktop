.PHONY: all build daemon app test test-unit test-integration test-snapshots test-real-e2e test-ui clean

DAEMON_BIN = build/colima-daemon
APP_BUNDLE = build/Colima\ Desktop.app
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

# === Fast test pyramid ===

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
test-real-e2e:
	xcodegen generate
	TEST_RUNNER_COLIMA_DESKTOP_REAL_E2E=1 TEST_RUNNER_COLIMA_DESKTOP_TEST_PROFILE=$(E2E_PROFILE) \
		xcodebuild test -scheme $(SCHEME) -destination $(DEST) $(DD) \
		-only-testing:ColimaDesktopUnitTests/RealBackendTests

# === XCUITest (runs on host) ===

test-ui:
	xcodegen generate
	xcodebuild test -scheme $(SCHEME) -destination $(DEST) $(DD) \
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

# === Distribution ===
.PHONY: package-dmg release

package-dmg:
	scripts/package.sh

release:
	NOTARIZE=$(NOTARIZE) scripts/package.sh

# === Sparkle auto-update tooling ===
.PHONY: sparkle-keys appcast
sparkle-keys:
	scripts/sparkle-keys.sh

appcast:
	scripts/sparkle-appcast.sh

# === Verification scoreboard (exit criteria) ===
.PHONY: verify coverage
verify:
	bash scripts/verify.sh

coverage:
	COV_MIN=0 bash scripts/verify.sh

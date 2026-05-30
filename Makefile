.PHONY: all build daemon app test test-unit test-integration test-snapshots test-smoke test-vm test-local clean

DAEMON_BIN = build/colima-daemon
APP_BUNDLE = build/Colima\ Desktop.app
TART_IMAGE = ghcr.io/cirruslabs/macos-sequoia-base:latest
VM_NAME = colima-test-$(shell date +%s)
SCHEME = ColimaDesktop
DEST = 'platform=macOS'
DD = -derivedDataPath build/DerivedData

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

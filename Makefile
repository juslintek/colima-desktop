.PHONY: all build daemon app test test-vm test-local clean

DAEMON_BIN = build/colima-daemon
APP_BUNDLE = build/ColimaUI.app
TART_IMAGE = ghcr.io/cirruslabs/macos-sequoia-base:latest
VM_NAME = colima-test-$(shell date +%s)

all: build

# Build everything
build: daemon app

# Build Go daemon
daemon:
	cd daemon && go build -o ../$(DAEMON_BIN) ./cmd

# Build Swift app
app:
	xcodegen generate
	xcodebuild build -scheme ColimaUI -destination 'platform=macOS' \
		-derivedDataPath build/DerivedData -quiet

# Run tests in isolated Tart VM (no desktop interference)
test: test-vm

test-vm:
	@echo "=== Running tests in isolated Tart VM ==="
	tart clone $(TART_IMAGE) $(VM_NAME)
	tart run $(VM_NAME) --dir=.:/project "/project/scripts/run_tests.sh" || true
	@echo "=== Cleaning up VM ==="
	tart delete $(VM_NAME)

# Run tests locally (requires Colima running + TCC permissions)
test-local:
	xcodegen generate
	xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
		-only-testing:ColimaUIUITests

# Run unit tests only (no GUI needed)
test-unit:
	xcodegen generate
	xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
		-only-testing:ColimaUITests

# Generate proto (requires protoc + plugins)
proto:
	protoc --go_out=daemon --go-grpc_out=daemon proto/colima_ui.proto

# Clean
clean:
	rm -rf build/ ColimaUI.xcodeproj TestResults.xcresult
	cd daemon && go clean

# Install
install: build
	cp -R $(APP_BUNDLE) /Applications/
	cp $(DAEMON_BIN) /usr/local/bin/

# Run app
run: build
	open $(APP_BUNDLE)

# Pull Tart base image (one-time setup)
setup-tart:
	brew install cirruslabs/cli/tart
	tart pull $(TART_IMAGE)

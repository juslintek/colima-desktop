.PHONY: all build daemon app test clean

DAEMON_BIN = build/colima-daemon
APP_BUNDLE = build/ColimaUI.app

all: build

# Build everything
build: daemon app

# Build Go daemon
daemon:
	cd daemon && go build -o ../$(DAEMON_BIN) ./cmd

# Build Swift app (includes daemon in bundle)
app: daemon
	xcodegen generate
	xcodebuild build -scheme ColimaUI -destination 'platform=macOS' \
		-derivedDataPath build/DerivedData \
		CONFIGURATION_BUILD_DIR=$(PWD)/build
	@# Copy daemon into app bundle
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(DAEMON_BIN) $(APP_BUNDLE)/Contents/MacOS/

# Run UI tests (mock mode, no Colima needed)
test:
	xcodegen generate
	xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
		-only-testing:ColimaUIUITests 2>&1 | tail -20

# Run unit tests
test-unit:
	xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
		-only-testing:ColimaUITests

# Generate proto (requires protoc + plugins)
proto:
	protoc --go_out=daemon --go-grpc_out=daemon proto/colima_ui.proto

# Clean build artifacts
clean:
	rm -rf build/ ColimaUI.xcodeproj
	cd daemon && go clean

# Install (copy to /Applications)
install: build
	cp -R $(APP_BUNDLE) /Applications/
	cp $(DAEMON_BIN) /usr/local/bin/

# Development: build and run
run: build
	open $(APP_BUNDLE)

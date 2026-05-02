# Integration Test Harness

## Prerequisites

- macOS 13+
- Colima installed (`brew install colima`)
- Docker CLI installed (`brew install docker`)
- Colima running (`colima start --vm-type vz --mount-type virtiofs --cpus 4 --memory 8`)

## Running UI Tests (Mock Mode)

Tests run with `--ui-testing` flag, using mock data. No Colima needed.

```bash
xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
  -only-testing:ColimaUIUITests
```

## Running Integration Tests (Real Mode)

Requires Colima + Docker running. Tests create/destroy real containers.

```bash
# 1. Ensure Colima is running
colima status || colima start

# 2. Create test fixtures
docker pull nginx:latest
docker pull redis:7-alpine
docker pull postgres:16

# 3. Run integration tests (without --ui-testing flag)
xcodebuild test -scheme ColimaUI -destination 'platform=macOS' \
  -only-testing:ColimaUIIntegrationTests
```

## Test Fixture Setup

For integration tests, a separate test target `ColimaUIIntegrationTests` would:

```swift
class IntegrationTestBase: XCTestCase {
    let app = XCUIApplication()
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        // NO --ui-testing flag = real mode
        app.launch()
        
        // Create test containers
        shell("docker run -d --name test-web nginx:latest")
        shell("docker run -d --name test-redis redis:7-alpine")
        shell("docker create --name test-stopped alpine:latest")
    }
    
    override func tearDownWithError() throws {
        // Cleanup
        shell("docker rm -f test-web test-redis test-stopped 2>/dev/null")
        shell("docker volume rm test-vol 2>/dev/null")
        shell("docker network rm test-net 2>/dev/null")
    }
    
    func shell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try? process.run()
        process.waitUntilExit()
    }
}
```

## Architecture Summary

```
┌─────────────────────────────────────────────────┐
│                  Test Modes                       │
├─────────────────────────────────────────────────┤
│                                                  │
│  UI Tests (--ui-testing)     Integration Tests   │
│  ┌─────────────────────┐    ┌────────────────┐  │
│  │ Mock data in memory  │    │ Real Colima    │  │
│  │ No network calls     │    │ Real Docker    │  │
│  │ Deterministic        │    │ Real containers│  │
│  │ Fast (< 30s)         │    │ Slow (2-5min)  │  │
│  └─────────────────────┘    └────────────────┘  │
│           │                         │            │
│           ▼                         ▼            │
│  ┌─────────────────────────────────────────┐    │
│  │           AppState                       │    │
│  │  useMocks=true  │  useMocks=false        │    │
│  │  (mock arrays)  │  (ServiceProvider)     │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

## Current Status

- ✅ UI Tests (279 tests) — run with mock data, no Colima needed
- ✅ AppState dual-mode — useMocks flag switches between mock and real
- ✅ DockerClient — HTTP over Unix socket, all endpoints implemented
- ✅ DaemonClient — CLI bridge to Colima commands
- ✅ ServiceProvider — protocol + RealServiceProvider implementation
- ✅ Go daemon — gRPC server wrapping Colima app.App (for future gRPC migration)
- ⏳ Integration tests — require Colima installed on test machine

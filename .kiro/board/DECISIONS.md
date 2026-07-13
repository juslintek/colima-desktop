# Program Board — DECISIONS (ADR log)

## ADR-001: Shared Go/gRPC core + native per-platform frontends
- **Context:** Need macOS/Windows/Linux/TUI parity as a free OrbStack alternative, native & fast.
- **Decision:** One Go daemon exposing `colima_ui.proto` gRPC is the single backend brain.
  Frontends are fully native: SwiftUI (mac), WinUI 3 (Windows), GTK4 (Linux), Bubble Tea (TUI).
  Each implements a thin native client mirroring the SwiftUI `ServiceProvider` pattern.
- **Status:** Accepted.

## ADR-002: Windows manages remote + local WSL2/Docker (2=c)
- **Decision:** Windows client supports both a remote colima/Lima host (SSH/gRPC) and local
  WSL2/Docker. Linux drives local colima directly.
- **Status:** Accepted.

## ADR-003: Sequencing — build all frontends, then harden to unified v1 (3=b)
- **Decision:** Build all frontends first, then run the explore→gap→test→fix→parity→auto-update
  loop across all platforms, then a single unified v1. Minimal README+LICENSE seeded up front;
  full OSS docs at v1 tag.
- **Status:** Accepted.

## ADR-004: Fix Xcode-26 test hang via ColimaDesktopKit framework extraction
- **Context:** `xcodebuild test` hangs (~704s "test runner hung before establishing connection")
  hosting the `@main` SwiftUI app.
- **Decision:** Extract app logic into a `ColimaDesktopKit` framework; logic tests link the module
  (no app-host injection). XCUITest keeps a minimal host guarded by `XCTestConfigurationFilePath`.
- **Status:** Accepted (implement in M0.2).

## ADR-005: Coverage target = 100%
- **Decision:** 100% on logic + backend command construction; view layers via ViewInspector/explorer
  where feasible; any unreachable line must be explicitly justified in code + gap report.
- **Status:** Accepted.

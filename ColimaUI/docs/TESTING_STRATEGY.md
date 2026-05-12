# ColimaUI — Testing Strategy & Progress Summary

**Date:** May 12, 2026
**Status:** GUI feature-complete with mocks. Test infrastructure exists but e2e tests are flaky.

---

## What Was Done

### 1. Complete GUI Implementation (mock-driven)

**Views completed:**
- Dashboard (VM status, resources, inline terminal, ResourceAdvisor, rich action cards)
- Containers (list + Info/Stats/Logs/Terminal/Files tabs, sorting, create dialog)
- Images (In Use/Unused, pull progress, Info/Terminal/Files tabs)
- Volumes (selectable list, Info/Files tabs)
- Networks (selectable list, info panel)
- Kubernetes (toolbar-style top bar, selectable Services/Deployments/Nodes with detail panels)
- AI Workloads (Setup progress, Model Browser with registry picker, Pull progress)
- Machines (Linux/macOS/Windows VM management, create dialog)
- Monitoring (tree view, sparklines, context menu actions, scoped stats)
- Configuration (fully visual: CPU Type cards, Mount Type cards with star ratings, Docker JSON editor with schema autocomplete, K8s version picker, DNS presets with descriptions, Gateway validation, SSH Port picker with suggestions, Mount dialog, Provisioning cards, Environment variable dialog with presets/bulk add)
- Runtime Controls (Docker Context picker, Update Runtime card, history dropdown with limit)
- Community, Profiles, MenuBarExtra

**Smart features added:**
- Pull progress with layer breakdown (Images + AI Models)
- AI Setup multi-step progress flow
- Model Browser with 3 registries and search
- Migration flow (Docker Desktop/Podman/Another Profile)
- Backup/export with file path confirmation
- Resource Advisor (battery, idle, right-sizing, Rosetta recommendations)
- Inline terminal in Dashboard (dark/light theme adaptive)
- Cmd+K command palette
- Guided Setup Wizard

### 2. Test Infrastructure

**247 XCUITests written** covering:
- AppShell, Lifecycle, Containers, Images, Volumes, Networks
- Kubernetes, Configuration, Monitoring, AI, Community
- Profiles, Runtime Controls, Machines (new)

**7 unit tests** (AppState init, mock mode)

**Tart VM testing:**
- `macos-tahoe-xcode:latest` image pre-baked with Xcode 26.4
- VNC accessible for monitoring
- `make test-vm` runs tests in isolation
- Successfully achieved 238/238 passing once (classes run individually)

### 3. Backend Scaffolding

- Go daemon compiles and runs (18MB binary)
- Swift DockerClient (HTTP over Unix socket, API v1.46)
- Streaming methods: events, logs, stats
- DaemonClient (CLI bridge to colima commands)
- ServiceProvider protocol with Mock and Real implementations

---

## The E2E Testing Problem

### Why XCUITests are Unreliable on macOS

After extensive investigation:

1. **Focus stealing** — Tests require foreground focus; macOS security model fights this
2. **Button click failures** — SwiftUI buttons inside ScrollView often don't receive synthetic clicks
3. **Toast detection impossible** — Overlay views with conditional rendering aren't reliably in the accessibility tree
4. **Parallel execution breaks** — Xcode 26.1 introduced regressions (Apple Dev Forums thread #812307)
5. **VNC + XCUITest** — Tests need active desktop session, VNC counts as background
6. **25 min per full suite** — Even when it works, it's too slow for iteration

**Current pass rate:** ~55% (137/247 fail due to flakiness, not bugs)

### What We Tried (all have issues)

| Approach | Result |
|----------|--------|
| Running all tests together | 55% pass (focus issues) |
| Running one class at a time | 100% pass but 25+ min |
| Tart VM with VNC | Same focus issues |
| `accessibilityLabel` workarounds | Helped some, not all |
| Naming conflict fixes | Fixed a few edge cases |

---

## Proposed New Testing Strategy

### Drop E2E, Use 3-Layer Pyramid

```
┌─────────────────────────────────────────┐
│   Snapshot Tests (20% — visual regression)│  ~3 sec total
├─────────────────────────────────────────┤
│   Integration Tests (30% — view + state)  │  ~10 sec total
├─────────────────────────────────────────┤
│   Unit Tests (50% — logic, models, API) │  ~1 sec total
└─────────────────────────────────────────┘
Total runtime: ~15 seconds for entire suite
```

### Layer 1: Unit Tests (Swift Testing framework, Xcode 26+)

**Target: 150+ tests, <1 second total runtime**

Test pure logic without UI:
- `AppState` mutations (start/stop/restart container, pull image, switch profile)
- `DockerClient` request/response parsing
- `DaemonClient` CLI parsing
- Mock data factories
- Computed properties (filtering, sorting, status subtitles)
- Validation logic (gateway IP, SSH port, K8s version regex, DNS format)
- Sparkline data generation
- YAML template formatting

**New Swift Testing API** (Xcode 26+):
```swift
@Test("AppState starts container and updates list")
func startContainer() async {
    let state = AppState(useMocks: true)
    await state.startContainer(name: "web-server")
    #expect(state.containers.first { $0.name == "web-server" }?.state == "running")
    #expect(state.toastMessage?.contains("started") == true)
}
```

**Advantages:**
- No focus issues, no VM needed
- Runs in parallel by default (Xcode 26+)
- Clear failure messages with captured expression values
- 100x faster than XCUITests

### Layer 2: Integration Tests (ViewInspector)

**Target: 50+ tests, ~10 seconds total**

Test SwiftUI views without rendering by walking the view tree:

```swift
import ViewInspector
import Testing

@Test("ContainersView shows running count")
func runningCount() throws {
    let state = AppState(useMocks: true)
    let view = ContainersView().environmentObject(state)
    let subtitle = try view.inspect().find(text: "4 running · 1 stopped")
    #expect(try subtitle.string() == "4 running · 1 stopped")
}

@Test("Clicking container row selects it")
func containerSelection() throws {
    let state = AppState(useMocks: true)
    let view = ContainersView().environmentObject(state)
    try view.inspect().find(button: "web-server").tap()
    #expect(state.selectedContainerName == "web-server")
}
```

**Advantages:**
- Tests actual SwiftUI views without rendering
- No focus/window issues (runs in-process)
- Can assert on computed view state
- Validates bindings and state updates

### Layer 3: Snapshot Tests (pointfreeco/swift-snapshot-testing)

**Target: 30 snapshots, ~3 seconds total**

Catch visual regressions using reference images:

```swift
@Test
func dashboardLightMode() {
    let view = DashboardView()
        .environmentObject(AppState(useMocks: true))
        .environment(\.colorScheme, .light)
    assertSnapshot(of: view, as: .image(layout: .fixed(width: 1200, height: 800)))
}

@Test
func dashboardDarkMode() {
    let view = DashboardView()
        .environmentObject(AppState(useMocks: true))
        .environment(\.colorScheme, .dark)
    assertSnapshot(of: view, as: .image(layout: .fixed(width: 1200, height: 800)))
}
```

**Advantages:**
- One snapshot covers entire view tree
- Catches CSS-like visual bugs (wrong colors, spacing, alignment)
- Commits PNG references to git for review
- Fast — renders once, compares pixels

**Coverage plan:**
- Each main view in light + dark mode (20 snapshots)
- Key interactions: selected item, expanded menu, dialog open (10 snapshots)

### Keep Minimal E2E (Smoke Tests Only)

**Target: 5 XCUITests, ~1 minute total**

Only test things that genuinely require the full app stack:
1. App launches without crash
2. Main window appears
3. Sidebar tabs exist
4. Menu bar extra appears
5. Cmd+K palette opens

Run these in Tart VM on CI only, not per-commit.

---

## Implementation Plan

### Phase 1: Foundation (1-2 days)

1. Add Swift Testing framework target (built into Xcode 26)
2. Add `swift-snapshot-testing` + `ViewInspector` as SPM dependencies
3. Create new test targets: `ColimaUITests` (unit), `ColimaUIIntegrationTests`, `ColimaUISnapshotTests`
4. Remove redundant XCUITests (keep only 5 smoke tests)
5. Update `Makefile`: `make test-unit` (fast), `make test-integration` (ViewInspector), `make test-snapshots` (regression), `make test-smoke` (e2e in Tart)

### Phase 2: Unit Test Migration (3-5 days)

Port ~150 behaviors to unit tests:
- AppState actions (60 tests)
- Service layer (30 tests)
- Validation logic (25 tests)
- Data formatting (20 tests)
- Mock factories (15 tests)

### Phase 3: Integration Tests (2-3 days)

Write ViewInspector tests for each view:
- Assert navigation routes correctly
- Assert selection state updates
- Assert computed properties render
- Assert bindings flow between views

### Phase 4: Snapshot Baseline (1 day)

Generate snapshots for all views in light/dark mode.
Review and commit PNG references.

### Phase 5: CI Integration (1 day)

- Unit tests run on every PR (fast, blocks merge)
- Integration tests run on every PR (medium speed)
- Snapshot tests run on every PR (medium speed, flag on diff)
- E2E smoke run nightly in Tart VM

---

## Benefits vs Current XCUITest Approach

| Metric | Current XCUITest | Proposed 3-Layer |
|--------|------------------|------------------|
| Full suite time | 25 min | 15 sec |
| Pass rate | 55% (flaky) | 99%+ (deterministic) |
| Debug difficulty | Hard (focus, timing) | Easy (in-process) |
| CI cost | 25 min per PR | 15 sec per PR |
| Maintenance burden | High (IDs, timing) | Low (direct assertions) |
| Visual regression catching | None | Yes (snapshots) |
| Coverage signal quality | Low | High |

---

## Research References

- **Apple Swift Testing:** https://developer.apple.com/xcode/swift-testing/
- **ViewInspector:** https://github.com/nalexn/ViewInspector
- **swift-snapshot-testing:** https://github.com/pointfreeco/swift-snapshot-testing
- **WWDC 2025 UI Automation:** https://developer.apple.com/videos/play/wwdc2025/344/
- **XCUITest in Xcode 26.1 issues:** Apple Dev Forums thread #812307
- **Kiwi.com Snapshot Testing with Macros:** https://code.kiwi.com/articles/generating-swiftui-snapshot-tests-with-swift-macros/

---

## Recommendation

**Stop investing time in XCUITest reliability.** It's fundamentally broken for SwiftUI on macOS in 2026.

**Adopt the 3-layer pyramid:**
1. Unit tests (Swift Testing) — fast, deterministic, most coverage
2. Integration tests (ViewInspector) — test view logic without rendering
3. Snapshot tests — catch visual regressions

**Keep only 5 smoke E2E tests** that verify the app launches and main navigation works.

This gets us from 55% flaky pass rate in 25 minutes to 99%+ deterministic in 15 seconds, while improving the quality of failures (actual bugs vs flakiness).

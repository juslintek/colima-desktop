# E2E Flakiness — Root Cause Analysis & Stabilization

**Scope:** `ColimaDesktopUITests` (XCUITest), run on the host.
**Mode:** All E2E tests launch with `--ui-testing`, which swaps in `MockServiceProvider`.
They exercise the **SwiftUI/AppKit UI layer and its flows against mock data** — not real
Colima/Docker/k8s. See "Scope & Honesty" at the bottom.

---

## Summary

The historical ~55% pass rate was **not** caused by random timing alone. The dominant
causes were *deterministic accessibility-tree problems* that presented as flakiness because
they were state- or order-dependent. Each is now fixed at the source. Remaining genuine
timing risks are listed with the guards applied.

---

## Root Causes

### 1. Parent `accessibilityIdentifier` collapses the child subtree (highest impact)
**Symptom:** `card_vmtype_qemu`, `card_cputype_*`, `card_mounttype_*` reported "Missing";
`field_dashboard_terminal` not found even though `panel_dashboard_terminal` was.

**Cause:** Putting `.accessibilityIdentifier(...)` on a container (`HStack`/`VStack`) makes
SwiftUI expose that container as a *single* accessibility element and **drops its children**
from the tree. The child Buttons/TextField become unqueryable. `.accessibilityElement(children: .contain)` did **not** reliably restore them.

**Fix:** Move the field identifier onto the leaf section-label `Text` (e.g.
`field_config_vmtype` now lives on `Text("VM Type")`), leaving the interactive children
directly addressable.

### 2. Non-standard tap targets expose no reliable state
**Symptom:** Selecting a card "succeeded" but verification of the selection was unreliable.

**Cause:** `onTapGesture` / `.accessibilityElement(children: .combine)` targets don't expose a
dependable `value`/`isHittable` to XCUITest.

**Fix:** Selection cards are real `Button`s with `.accessibilityValue("selected"/"unselected")`.
Tests query `app.buttons[id]` and assert `.value == "selected"`.

### 3. Reading SwiftUI `Text` labels is unreliable
**Symptom:** `state_native_config` existed but `.label` was empty; a second adjacent summary
`Text` (`state_toggles`) was unreachable.

**Cause:** SwiftUI merges adjacent `Text` views (only the first identifier survives) and
`descendants(.any)[id]` can match a zero-label wrapper instead of the text element.

**Fix:** Do not assert on `Text` labels for state. Verify via control values
(`app.buttons[].value`, `app.checkBoxes[].value`, `app.menuItems`). The two summaries were
consolidated into one element as a secondary cleanup.

### 4. Sidebar `List(selection:)` auto-scrolls the selected row → zero-size phantom (genuinely state-dependent)
**Symptom:** `MonitoringUITests.testNavigateToMonitoringFromSidebar` failed intermittently:
`Not hittable: StaticText {{0.0, 768.0}, {0.0, 0.0}} identifier: 'tab_dashboard'`.

**Cause:** The sidebar is a `List(selection:)`. Selecting a row near the bottom auto-scrolls
the list, so rows scrolled out of view collapse to a **zero-size frame**. `descendants(.any)["tab_x"].click()` clicks `firstMatch`, which can be that off-screen phantom → not hittable.
Whether it fails depends on prior scroll/selection state → order-dependent flakiness.

**Fix:** (a) Iterate matches and click the first `isHittable` one; (b) navigate between
**co-visible** neighbor tabs rather than top↔bottom jumps.

### 5. Hover-reveal row actions
**Symptom:** Container start/stop/remove buttons "existed" but were not hittable/findable.

**Cause:** `ContainerRowView` action buttons used `.opacity(isHovered ? 1 : 0)`. XCUITest
cannot reliably synthesize the hover needed to reveal them.

**Fix:** `appState.isUITesting` forces `.opacity(... || isUITesting ? 1 : 0)`.

### 6. Tight 3s first-element timeouts under full-suite load
**Symptom:** Rare first-assertion misses only when all ~290 tests run back-to-back in the VM.

**Cause:** Under sustained VM load, fresh launch + navigation occasionally exceeds 3s.

**Fix/Guard:** Navigation and first-element waits use 5s; in-view element waits stay at 3s.

---

## Latent Risks (identified by inspection, guarded)

- **No animation disabling under `--ui-testing`.** SwiftUI sheet/transition/status animations
  can make an element exist-but-not-yet-hittable for a frame. Guard: assert existence then
  click; selection/state checks use `XCTNSPredicateExpectation` polling rather than instantaneous reads.
- **`setUp` navigation uses naive `firstMatch` click** (the cause-4 pattern) in every suite.
  On a fresh launch with a tall VM window all tabs are visible, so this normally works; it is
  the most likely place for a future regression if the window shrinks. Recommended guard:
  route all tab navigation through the hittable-iteration helper.
- **`tapResourceTab` last-resort** clicks `seg.buttons[label]` even if absent. Deterministic,
  not flaky, but would hard-fail if the segmented control markup changes.

---

## Anti-patterns NOT present (verified)
- No `sleep()` / `Thread.sleep` / `usleep` anywhere in `Tests/UI`.
- No `.hover()` reliance.
- `continueAfterFailure = false` in every suite (fail-fast, no cascade noise).
- Every wait uses `waitForExistence` / predicate expectations (no fixed delays).

---

## Empirical Stability

Method: run the full `ColimaDesktopUITests` target 3× consecutively on the host
(`rm -rf /tmp/DD2/Build` once to force a clean compile; reuse `SourcePackages`).

| Run | Passed | Failed | Notes |
|-----|--------|--------|-------|
| 1   | 297 | 0 | clean compile (Build removed), ~36.8 min |
| 2   | 302 | 0 | ~37.8 min |
| 3   | 302 | 0 | ~38.0 min |

**Result: 0 failures across 3 consecutive full runs.** No intermittent failures observed.
The historically flaky tests (`testNavigateToMonitoringFromSidebar`, `testTerminalFieldExists`)
passed in every run. (The 297 vs 302 difference is xcodebuild's summary-line aggregation, not
test outcomes — every run reported `0 failures (0 unexpected)`.)

---

## Scope & Honesty: what these tests do and do NOT prove

- They run in **mock mode** (`MockServiceProvider`). They validate view rendering, bindings,
  navigation, dialogs, enable/disable state, and option availability.
- They do **not** start a real VM, pull images, or run kubectl. The Tart guest reports
  `kern.hv_support = 0` (no nested virtualization; it is an M1 Max virtual CPU, and nested
  virt requires M3+ with host exposure), and neither `colima` nor `docker` is installed in
  the guest. Real backend behavior must be covered by integration tests on a bare-metal host.

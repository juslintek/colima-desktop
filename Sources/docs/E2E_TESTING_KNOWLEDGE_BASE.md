# E2E Testing Knowledge Base — Colima Desktop

> Historical reference for the XCUITest end-to-end suite: what broke, why, and how it was
> fixed. Read this before touching `Tests/UI/`, the Tart VM workflow, or any
> `accessibilityIdentifier`. Companion docs:
> `FLAKINESS_ANALYSIS.md` (root-cause deep dive) and `E2E_COVERAGE_AND_TEST_PLAN.md` (coverage + plan).

---

## TL;DR

- E2E tests run **only in the Tart VM**, **mock mode** (`--ui-testing` → `MockServiceProvider`).
  They validate the SwiftUI UI layer and flows, **not** real Colima/Docker/k8s.
- Real Colima/nested VMs **cannot** run in the Tart guest: `kern.hv_support = 0`, the CPU is
  "Apple M1 Max (Virtual)" (nested virt needs M3+ with host exposure), and neither `colima`
  nor `docker` is installed. This is by design — see "Nested virtualization" below.
- The suite went from ~55% flaky to **317 tests, 0 failures** (4 consecutive full runs: three
  at 297, plus a final 317-test run after adding the new suites). Almost every "flake" was a
  deterministic **accessibility-tree** problem, not random timing.

---

## How to run the suite (the only reliable recipe)

```bash
# From the host. The VM mounts the project at "/Volumes/My Shared Files/project".
ssh tart-vm "rm -rf /tmp/DD2/Build; cd '/Volumes/My Shared Files/project' && \
  xcodebuild test -scheme ColimaDesktop -destination 'platform=macOS' \
  -derivedDataPath /tmp/DD2 -only-testing:ColimaDesktopUITests 2>&1"
```

Single suite/test: append `-only-testing:ColimaDesktopUITests/<Suite>[/<testMethod>]`.

### Why `rm -rf /tmp/DD2/Build` every time (VirtioFS staleness)
Incremental builds over the Tart VirtioFS share **do not detect source changes** — mtimes
don't propagate, so the VM compiles **stale** binaries/test bundles. Symptom: old assertion
text shows up in failures, or edits "have no effect."
- **Fix:** delete only `/tmp/DD2/Build` (forces full recompile) but **keep**
  `/tmp/DD2/SourcePackages` (reused resolved SPM packages).
- **Do NOT** `rm -rf /tmp/DD2` entirely — package re-resolution over the network can leave a
  corrupted swift-syntax checkout. If it ever breaks, recover with a **fresh** `/tmp/DD2` dir.

### Adding/removing test files → regenerate the project IN the VM
`project.yml` globs `Tests/UI`, so a new test file needs `xcodegen generate`. Regenerate
**inside the VM**, never on the host (host regeneration corrupts the VM's VirtioFS view of the
`.xcodeproj` bundle):
```bash
ssh tart-vm "cd '/Volumes/My Shared Files/project' && /opt/homebrew/bin/xcodegen generate"
```
Host can still `xcodebuild build-for-testing ... -derivedDataPath build/DerivedData` to
compile-check Swift changes (do not run XCUITests on the host — see below).

### Never run XCUITests on the host
Host XCUITest fails with "Timed out while enabling automation mode" and steals focus. The Tart
VM is the only supported runner.

---

## The SwiftUI ↔ XCUITest accessibility gotchas (the real causes of "flakiness")

### 1. A parent `accessibilityIdentifier` collapses its children out of the tree
Putting `.accessibilityIdentifier(...)` on an `HStack`/`VStack` makes SwiftUI expose that
container as **one** element and **drops the children**. The child Buttons/TextFields become
unqueryable → "Missing card_vmtype_qemu", "field_dashboard_terminal not found".
`.accessibilityElement(children: .contain)` did **not** reliably fix it.
- **Fix:** put the field identifier on the leaf section-label `Text` (e.g. `field_config_vmtype`
  on `Text("VM Type")`, `panel_dashboard_terminal` on the `Text("Terminal")` header), leaving
  the interactive children directly addressable.

### 2. Verify state via control VALUES, not Text labels
- `descendants(.any)["id"]` can match a zero-label wrapper → `.label` is empty.
- SwiftUI merges adjacent `Text` views; only the first `accessibilityIdentifier` survives.
- **Fix:** make selection targets real `Button`s with `.accessibilityValue("selected"/"unselected")`
  and assert `app.buttons[id].value`. Toggles: assert `app.checkBoxes[id].value`. Pickers:
  open and assert `app.menuItems[option]`. These are read reliably; `Text` labels are not.

### 3. `List(selection:)` auto-scrolls the selected row → zero-size phantom
The sidebar is a `List(selection:)`. Selecting a row near the bottom auto-scrolls the list, so
off-screen rows collapse to a **zero frame** (`{0,768}{0,0}`). `descendants(.any)["tab_x"].click()`
hits `firstMatch`, which may be that phantom → "Not hittable", **order-dependent** flake.
- **Fix:** iterate matches and click the first `isHittable` one; prefer navigating between
  **co-visible** neighbor tabs over top↔bottom jumps. Reusable helper:
  ```swift
  func clickHittable(_ id: String) {
      let q = app.descendants(matching: .any).matching(identifier: id)
      XCTAssertTrue(q.firstMatch.waitForExistence(timeout: 8), "Missing \(id)")
      for i in 0..<q.count where q.element(boundBy: i).isHittable { q.element(boundBy: i).click(); return }
      q.firstMatch.click()
  }
  ```

### 4. Hover-reveal buttons can't be hovered reliably
`ContainerRowView` action buttons used `.opacity(isHovered ? 1 : 0)`. XCUITest can't synthesize
the hover. **Fix:** `appState.isUITesting` (set from `--ui-testing`) forces
`.opacity(... || isUITesting ? 1 : 0)`.

### 5. Duplicate/orphaned views with conflicting identifiers
There are **two** create-container UIs: the **live** `ContainersView.createSheet`
(ids `field_create_container_name`, `field_create_container_image`, `btn_confirm_container_create`,
captures **name + image only**) and an **orphaned** `CreateContainerView.swift`
(ids `*_full`, with platform/restart/payload/flags) that is **not wired to any button**.
Tests must target the live sheet. The `_full` view is dead code — wire it up or delete it.
- **Lesson:** confirm which view actually renders (grep the `.sheet { ... }` wiring) before
  writing identifiers into a test. This cost a full failing run when the new image tests were
  first written against the orphaned view's `*_full` ids.

### 6. Timeouts
No `sleep()` anywhere — all waits are `waitForExistence`/`XCTNSPredicateExpectation`. Use **5s**
for navigation/first-element-after-launch (VM under full-suite load), **3s** for in-view
elements. `continueAfterFailure = false` in every suite.

---

## Nested virtualization / real Colima — the honest answer

**No — real Colima and nested VMs do not (and cannot) run inside the Tart VM.** Evidence
gathered in the guest:
- `sysctl kern.hv_support` → `0` (no Hypervisor.framework; the guest cannot create VMs).
- No `hw.optional.arm.FEAT_NV` (nested-virt feature absent).
- CPU: `Apple M1 Max (Virtual)`. Colima nested virt needs **M3+** *and* the host to expose it.
- `colima` and `docker` are **not installed** in the guest.

That is exactly why the E2E suite runs in **mock mode**. The tests prove the UI renders,
navigates, binds, validates, and reflects state correctly against `MockServiceProvider`. They
**do not** prove that a real container runs or that a real VM boots. Real backend behavior must
be covered by **integration tests on a bare-metal Apple-Silicon host** (or a host with working
virtualization), not in the VM.

`MockServiceProvider` is stateful in-memory CRUD: start/stop/delete VM, profile create/clone/
delete, k8s start/stop/reset, container create/start/stop/kill/remove/rename, image pull/remove,
volume/network CRUD, `readConfig` returns sample mounts/provisions/env. `createContainer` stores
**name + image only** (no ports/env) — so "image configuration" coverage is bounded accordingly.

---

## What is and isn't covered (summary)

Covered: every view's presence/navigation, lifecycle flows (profiles=VMs, k8s enable/disable/
reset, native-perf config — all vmType/cpuType/mountType/arch/runtime/portForwarder/networkMode/
modelRunner options + 5 toggles + valid combos), container create from popular images, list CRUD
for containers/images/volumes/networks. Not covered: detail-tab content, several config
sub-editors (DNS/gateway/SSH/docker-json/k8s-version), setup wizard, command palette, menu-bar
extra, dark/light + resize, and all **operational** behavior (needs real backend). Full matrix in
`E2E_COVERAGE_AND_TEST_PLAN.md`.

---

## Commit history of this effort (for archaeology)
- `fix 15 failing E2E tests + add VM/k8s/native-perf config E2E coverage`
- `make native-perf config E2E reliable via control values`
- `fix terminal field + monitoring nav E2E flakiness`
- `docs: E2E suite green — 297/297`
- `add popular-image create-flow + config-combo E2E + flakiness/coverage/KB docs`

.PHONY: all build daemon app test test-unit test-integration test-snapshots test-real-e2e test-ui clean

DAEMON_BIN = build/colima-daemon
APP_BUNDLE = build/Colima\ Desktop.app
SCHEME = ColimaDesktop
DEST = 'platform=macOS'
DD = -derivedDataPath build/DerivedData
# Single source of truth: the allowed live profile is defined once in the shared
# safety guard (scripts/live/guard.sh) and read here so it can never drift.
E2E_PROFILE := $(shell bash scripts/live/guard.sh profile 2>/dev/null || echo desktop-e2e)

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

# === Distribution (R8 / task 13.1) ===
# Single source of version truth = scripts/version.sh (git tag -> version).
# scripts/package.sh builds the versioned macOS .app/.dmg (+ the Go daemon & TUI
# universal binaries) and emits a SHA-256 checksums manifest (SHA256SUMS.txt +
# release-manifest.json). Signing is credential-gated: with no Developer ID the
# artifacts are built UNSIGNED and labelled honestly in the manifest.
.PHONY: version package package-dmg checksums release

version:
	@bash scripts/version.sh json

# Build every locally-buildable artifact (macOS .app/.dmg + daemon + tui) with a
# SHA-256 checksums manifest. Set SIGN_IDENTITY / NOTARIZE=1 to sign+notarize.
package: package-dmg

package-dmg:
	scripts/package.sh

# (Re)generate the SHA-256 checksums manifest over dist/ without rebuilding.
checksums:
	bash scripts/release/checksums.sh --dir dist

release:
	NOTARIZE=$(NOTARIZE) scripts/package.sh

# === Sparkle auto-update tooling ===
.PHONY: sparkle-keys appcast
sparkle-keys:
	scripts/sparkle-keys.sh

appcast:
	scripts/sparkle-appcast.sh

# === Verification scoreboard (exit criteria) ===
.PHONY: verify coverage check-a11y
verify:
	bash scripts/verify.sh

coverage:
	COV_MIN=0 bash scripts/verify.sh

# Cross-frontend accessibility-identifier hardening gate (R7 / task 12.4, Property 17):
# totality + within-surface uniqueness + cross-frontend canonical-surface consistency +
# shared-id non-collision across macOS/Windows/Linux/TUI. Exits non-zero on any violation
# so verify.sh / the release-candidate gate can invoke it as a hard check.
check-a11y:
	python3 scripts/check-a11y-ids.py --report

# === Live E2E environment (disposable desktop-e2e colima profile) ===
# Managed by scripts/live/e2e-env.sh — NEVER touches any profile but $(E2E_PROFILE).
# The profile safety guard (scripts/live/guard.sh) is the single enforced
# invariant keeping every destructive live action inside $(E2E_PROFILE).
.PHONY: live-e2e-up live-e2e-status live-e2e-down live-e2e-teardown live-e2e-restore-orbstack live-e2e-selftest live-e2e-exercise
live-e2e-selftest:
	bash scripts/live/guard.sh selftest

# Full-functionality live exercise (R9 / task 10.6): drives EVERY functional area
# of the macOS app against the running $(E2E_PROFILE) backend with REAL data,
# creates+removes e2e- resources, and writes evidence to artifacts/live/full-exercise/.
# Requires the profile up first: `make live-e2e-up`.
live-e2e-exercise:
	bash scripts/live/full-exercise.sh

live-e2e-up:
	bash scripts/live/e2e-env.sh up

live-e2e-status:
	bash scripts/live/e2e-env.sh status

live-e2e-down:
	bash scripts/live/e2e-env.sh down

live-e2e-teardown:
	bash scripts/live/e2e-env.sh teardown

live-e2e-restore-orbstack:
	bash scripts/live/e2e-env.sh restore-orbstack

# === Supply chain: SBOM + vulnerability audit (R7 / Requirement 11.3) ===
# scripts/sbom.sh generates CycloneDX 1.5 SBOMs for every component (Go daemon+TUI,
# Rust Linux, .NET Windows, Swift macOS) into the COMMITTED docs/sbom/ tree.
# scripts/security-scan.sh additionally runs the ecosystem vulnerability scanners
# (govulncheck / cargo audit / dotnet list --vulnerable) and writes an honest,
# severity-summarised VULNERABILITY-REPORT.md. `security-gate` exits non-zero on
# any CRITICAL finding (Requirement 11.3) and is what the release-candidate gate consumes.
.PHONY: sbom security-scan security-gate
sbom:
	bash scripts/sbom.sh

security-scan:
	bash scripts/security-scan.sh

security-gate:
	bash scripts/security-scan.sh --fail-on-critical

# === Performance budgets (R7 / Requirement 11.5) ===
# scripts/perf-budgets.sh records the app's key performance budgets and MEASURES real
# values READ-ONLY against a running desktop-e2e profile (every docker/colima call is
# routed through scripts/live/guard.sh — desktop-e2e only, status/list/stats only, no
# resource create/destroy). It writes the machine-readable docs/performance-budgets.json
# (source of truth) + the human-readable docs/performance-budgets.md. `perf-check` lets
# the release-candidate gate consume the JSON: a NON-load over-budget fails; an
# over-budget attributable to host load is reported as a warning (Requirement 11.5 intent).
.PHONY: perf-budgets perf-check
perf-budgets:
	bash scripts/perf-budgets.sh

perf-check:
	bash scripts/perf-budgets.sh --check

# === Release-candidate gate (R7 / task 12.5, Requirement 11.6) ===
# scripts/rc-gate.sh is the SINGLE aggregator that composes every R7 hardening sub-gate into one
# pass/fail verdict a release candidate (task 13 / R8) must clear: it INVOKES verify.sh (12.1),
# security-scan.sh --fail-on-critical (12.2), perf-budgets.sh --check (12.3) and check-a11y-ids.py
# (12.4), and documents that the 9 frontends.yml jobs + test.yml are CI-authoritative for the
# native-only layers (WinUI 3 / GTK 4 compiles are env-blocked on a macOS-only host — Assumption A2).
# The same aggregation runs in CI as .github/workflows/release-candidate.yml. See
# docs/release-candidate-gate.md. Task 13 (release) is gated on a GREEN RC verdict.
#   make rc-gate        thorough: verify.sh (watchdog) + security + perf + a11y
#   make rc-gate-fast   quick local lane: defer verify.sh to CI/`make verify`, security from the
#                       committed summary, perf + a11y run live (honestly-labelled partial)
.PHONY: rc-gate rc-gate-fast
rc-gate:
	bash scripts/rc-gate.sh

rc-gate-fast:
	bash scripts/rc-gate.sh --fast

# === Release-blocking P0/P1 defect gate (R8 / task 13.4, Requirement 12.5) ===
# scripts/release-blocking-gate.sh (-> scripts/release_blocking_gate.py) blocks the v1.0.0 tag IFF
# any OPEN defect in the machine-readable registry docs/release-defects.json carries priority P0 or
# P1 (it also auto-ingests the task-12.2 docs/sbom/vuln-summary.json: critical->P0, high->P1). It is
# COMPLEMENTARY to `make rc-gate` (task 12.5): BOTH must pass to ship (task 13.6). Exit 0 = no open
# P0/P1; exit 1 = blocked (prints which defects block); exit 2 = source unreadable (fail-closed).
#   make release-gate       P0/P1 defect gate (release publish + RC/release flow consume this)
#   make release-defects    list the registry + each entry's block classification
.PHONY: release-gate release-defects
release-gate:
	bash scripts/release-blocking-gate.sh

release-defects:
	bash scripts/release-blocking-gate.sh --list

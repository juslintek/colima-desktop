# Requirements Document

## Introduction

The Cross-Platform Live Verification program takes the Colima Desktop repository from its current
partially-verified state to a shipped, signed `v1.0.0` release. The program has four obligations,
in this order:

1. **Audit** the `.kiro/board` planning documents against real source code, tests, and CI evidence,
   and correct every stale or overstated claim.
2. **Complete** the remaining partial roadmap items — shared daemon completion, per-action parity on
   macOS, Windows, Linux, and the TUI, DependencyManager live verification, and roadmap items
   R0 through R7.
3. **Verify** the product against a live Colima backend from an isolated disposable profile, with
   the desktop application exercising every functional surface (all 31 `ColimaService` RPCs and 34
   `DockerService` RPCs), including creation of new containers, images, volumes, networks, and VMs,
   to the depth defined for each platform.
4. **Ship** the cross-platform `v1.0.0` release with signing and the signed tag (roadmap R8), then
   send a completion notification.

The frozen v1 gRPC contract (31 `ColimaService` RPCs plus 34 `DockerService` RPCs) and the
disjoint-path multi-agent ownership model are fixed constraints. The program consumes and preserves
both; the program does not redesign either. The one exception is the additive, pre-v1
request-shape correction already recorded in `INTENT_LEDGER.md` (profile/host/WSL2 scope fields on
`Update`, `Prune`, `Rename`, `Tag`, `Search`, and `NetworkContainer`), which the audit must
reconcile into `CONTRACT.md`.

## Glossary

- **Verification_Program**: The overall audit, completion, verification, release, and notification
  effort defined by this document.
- **Board**: The planning documents in `.kiro/board/` — `PLAN.md`, `STATUS.md`, `CONTRACT.md`,
  `INTENT_LEDGER.md`, `OWNERSHIP.md`, and `DECISIONS.md`.
- **Board_Audit**: The reconciliation activity that compares Board claims against real source,
  tests, and CI evidence.
- **Frozen_Contract**: The v1 gRPC surface — 31 `ColimaService` RPCs and 34 `DockerService` RPCs
  (65 total) defined by `proto/colima_ui.proto` and `CONTRACT.md`.
- **ColimaService**: The 31-RPC gRPC service covering VM lifecycle, SSH, profiles, config/template,
  Kubernetes, AI models, runtime, monitoring, and machine listing.
- **DockerService**: The 34-RPC gRPC service covering container, image, volume, and network
  operations plus event/log/stat streams.
- **Colima_Daemon**: The shared Go gRPC server in `daemon/` that implements the Frozen_Contract.
- **Desktop_Frontend**: A native client that implements the Frozen_Contract — one of
  macOS_Frontend, Windows_Frontend, Linux_Frontend, or TUI_Frontend.
- **macOS_Frontend**: The SwiftUI application under `Sources/`.
- **Windows_Frontend**: The WinUI 3 application under `windows/`.
- **Linux_Frontend**: The GTK4 application under `linux/`.
- **TUI_Frontend**: The Bubble Tea terminal application under `tui/`.
- **Canonical_Surface**: One of the 12 functional screens present on every Desktop_Frontend.
- **Path_Owner_Agent**: An agent that owns a single disjoint path prefix per `OWNERSHIP.md` and is
  the only writer to that prefix.
- **Integration_Agent**: The single agent authorized to merge branches to `main`.
- **INTENT_LEDGER**: The append-only coordination log at `.kiro/board/INTENT_LEDGER.md`.
- **E2E_Profile**: The disposable, safety-prefixed Colima profile named `desktop-e2e` used for all
  destructive live tests.
- **Verify_Script**: The scoreboard script `scripts/verify.sh`.
- **CI_Gate**: The GitHub Actions workflows `frontends.yml` (9 jobs) and `test.yml`.
- **Release_Pipeline**: The GitHub Actions workflow `release.yml`.
- **Notification_Service**: The component that sends the completion summary by email, SMS, and any
  configured optional messaging channel.
- **DependencyManager**: The component that tracks and installs `colima`, `lima`, `qemu`,
  `krunkit`, `docker-cli`, and `kubectl`.
- **Ground_Truth_Artifact**: A recorded exploration result under `exploration/` describing observed
  runtime behavior and its evidence level.
- **Practical_Coverage_Ceiling**: The configured minimum coverage gate `COV_MIN` in the
  Verify_Script — default 71%, approximately 74% when the E2E_Profile socket is present.
- **Live_Backend_Evidence**: Evidence produced by running against a live Colima daemon, as distinct
  from source-only, deterministic-fake-data, or CI-without-daemon evidence.

## Requirements

### Requirement 1: Board-vs-Reality Completion Audit (roadmap R0)

**User Story:** As the program orchestrator, I want the Board reconciled against real code, tests,
and CI evidence, so that planning documents state verifiable truth before completion work proceeds.

#### Acceptance Criteria

1. WHEN the Board_Audit runs, THE Verification_Program SHALL compare each of the 31 `ColimaService`
   RPCs and 34 `DockerService` RPCs against the concrete daemon server method, the generated client
   method, and the frontend handler for each Desktop_Frontend.
2. WHEN the Board_Audit evaluates an RPC, THE Verification_Program SHALL assign one evidence level
   among implemented, UI-wired, runtime-tested, and live-tested for each Desktop_Frontend.
3. IF a Board statement conflicts with the audited source, tests, or CI evidence, THEN THE
   Verification_Program SHALL correct the statement in the owning Board file.
4. THE Verification_Program SHALL replace the `STATUS.md` baseline with the current build, test,
   explorer, and coverage results from the latest Verify_Script and CI_Gate runs.
5. THE Verification_Program SHALL update `CONTRACT.md` to describe the approved pre-v1 additive
   request-shape revision recorded in `INTENT_LEDGER.md`.
6. WHEN the Board_Audit completes, THE Verification_Program SHALL regenerate `docs/gap-report.md`
   and `docs/parity-matrix.md` from the current proto, server, and frontend source.
7. WHEN the Board_Audit finds a legacy planning document that contradicts `PLAN.md`, THE
   Verification_Program SHALL close, migrate, or delete the legacy document.
8. THE Verification_Program SHALL label every capability claim with the evidence level that
   supports the claim: source-only, deterministic-fake-data, CI-without-daemon, or
   Live_Backend_Evidence.

### Requirement 2: Multi-Agent Execution Protocol and Path Ownership

**User Story:** As the program orchestrator, I want all completion work executed through the
existing disjoint-path multi-agent protocol, so that parallel work merges without conflict and every
change stays traceable.

#### Acceptance Criteria

1. THE Verification_Program SHALL preserve the Frozen_Contract RPC names, RPC counts (31
   `ColimaService` and 34 `DockerService`), and proto field numbers.
2. THE Verification_Program SHALL preserve the disjoint path-ownership assignments defined in
   `OWNERSHIP.md`.
3. WHERE two tasks run in parallel, THE Verification_Program SHALL assign each task a disjoint owned
   path prefix.
4. WHEN a Path_Owner_Agent begins a task, THE Path_Owner_Agent SHALL append an entry to
   `INTENT_LEDGER.md` containing the intent, the plan, and the files-to-touch.
5. WHEN a Path_Owner_Agent finishes a task, THE Path_Owner_Agent SHALL append an outcome entry to
   `INTENT_LEDGER.md` containing the evidence and the contract-impact.
6. THE Verification_Program SHALL restrict merges to `main` to the Integration_Agent.
7. IF a change modifies a path outside the acting agent's owned prefix, THEN THE Integration_Agent
   SHALL reject the change.
8. WHILE integrating a completed branch, THE Integration_Agent SHALL require the Verify_Script to
   pass for the touched platform and require the touched platform to hold or improve every other
   platform's `STATUS.md` scoreboard value.

### Requirement 3: Shared Daemon and Provider Completion (roadmap R1)

**User Story:** As a cross-platform user, I want the shared daemon to implement every contract RPC
with real behavior, so that every frontend receives identical backend capability.

#### Acceptance Criteria

1. THE Colima_Daemon SHALL provide a concrete server method for each of the 31 `ColimaService` RPCs
   and 34 `DockerService` RPCs.
2. WHEN a client invokes `DockerService.PullImage` or `DockerService.PushImage`, THE Colima_Daemon
   SHALL stream real progress and propagate cancellation and errors to the client.
3. THE Colima_Daemon SHALL expose a configurable Unix-socket listener and a configurable
   loopback-TCP listener, each with graceful shutdown.
4. WHEN a client invokes a profile-scoped command, THE Colima_Daemon SHALL target the profile named
   in the request.
5. WHERE a request lacks a profile or provider field that safe scoping requires, THE Colima_Daemon
   SHALL reject the request with a contextual error.
6. WHEN the daemon concurrency test suite runs, THE Colima_Daemon SHALL pass `go test -race` with no
   leaked goroutines.
7. THE Colima_Daemon SHALL compile for macOS, Linux, and Windows build targets.

### Requirement 4: TUI Per-Action Parity (roadmap R2)

**User Story:** As a terminal user, I want every advertised TUI action to invoke a real profile-scoped
RPC, so that the TUI performs work rather than only displaying data.

#### Acceptance Criteria

1. THE TUI_Frontend SHALL bind VM start, stop, restart, delete, update, prune, and SSH-config
   actions to the matching `ColimaService` RPC for the active profile.
2. THE TUI_Frontend SHALL bind container, image, volume, and network actions to the matching
   `DockerService` RPC for the active profile.
3. THE TUI_Frontend SHALL bind Kubernetes, runtime, profile, config, template, and AI-model actions
   to the matching `ColimaService` RPC.
4. WHEN a user triggers a destructive action, THE TUI_Frontend SHALL require an explicit
   confirmation before invoking the RPC.
5. WHILE a streamed action runs, THE TUI_Frontend SHALL support cancellation and SHALL bound the
   displayed output.
6. WHEN an action returns an error, THE TUI_Frontend SHALL display the error with context.
7. WHEN the TUI action suite runs, THE Verification_Program SHALL confirm each action maps to the
   exact RPC and profile through deterministic dispatch tests.

### Requirement 5: Windows Per-Action Parity (roadmap R3)

**User Story:** As a Windows user, I want every command surface to invoke a real, cancellable RPC
against the daemon, so that the Windows application delivers full contract capability.

#### Acceptance Criteria

1. WHEN the Windows binding audit runs, THE Verification_Program SHALL produce an exact list mapping
   each of the 65 Frozen_Contract RPCs to a Windows_Frontend command handler.
2. THE Windows_Frontend SHALL invoke real gRPC calls for VM lifecycle, profile, SSH, update, and
   prune commands.
3. THE Windows_Frontend SHALL invoke real gRPC calls for container, image, volume, and network
   mutations and for event, log, and stat streams.
4. THE Windows_Frontend SHALL invoke real gRPC calls for Kubernetes, AI, runtime, config, template,
   and monitoring actions.
5. WHEN a user triggers a destructive command, THE Windows_Frontend SHALL require an accessible
   confirmation before invoking the RPC.
6. WHILE a command runs, THE Windows_Frontend SHALL maintain non-reentrant busy state, honor
   cancellation, and surface errors.
7. THE Windows_Frontend SHALL assign a stable accessibility identifier to each interactive control.
8. WHEN the Windows service and view-model test suite runs on a native Windows runner, THE
   Verification_Program SHALL confirm the suite passes.

### Requirement 6: Linux Per-Action Parity (roadmap R4)

**User Story:** As a Linux user, I want every GTK callback to invoke a real, cancellable RPC on the
GLib main context, so that the Linux application delivers full contract capability safely.

#### Acceptance Criteria

1. WHEN the Linux callback audit runs, THE Verification_Program SHALL produce an exact matrix
   mapping each of the 65 Frozen_Contract RPCs to a Linux_Frontend callback.
2. THE Linux_Frontend SHALL invoke real gRPC calls for VM lifecycle, profile, SSH, update, and
   prune callbacks.
3. THE Linux_Frontend SHALL invoke real gRPC calls for container, image, volume, and network
   mutations and streams.
4. THE Linux_Frontend SHALL invoke real gRPC calls for Kubernetes, AI, runtime, config, template,
   and monitoring actions.
5. WHILE performing asynchronous work, THE Linux_Frontend SHALL apply GTK widget mutations on the
   GLib main context.
6. WHEN a user triggers a destructive action, THE Linux_Frontend SHALL require a confirmation before
   invoking the RPC.
7. WHEN the Linux test suite runs, THE Verification_Program SHALL confirm the format check, unit
   tests, and lint pass with warnings denied.

### Requirement 7: macOS Product-Gap Closure (roadmap R5)

**User Story:** As a macOS user, I want the remaining macOS product gaps closed with truthful
runtime behavior, so that the reference frontend has no fake-success flows.

#### Acceptance Criteria

1. THE macOS_Frontend SHALL provide a template read, edit, and save interface over the implemented
   `GetTemplate` and `SetTemplate` RPCs.
2. WHEN a user triggers a destructive Docker mutation, THE macOS_Frontend SHALL require a
   confirmation before invoking the RPC.
3. WHILE an image pull runs, THE macOS_Frontend SHALL display observed progress rather than
   synthesized progress.
4. WHEN the macOS_Frontend loads configuration, THE macOS_Frontend SHALL populate fields from the
   real profile YAML and SHALL preserve unknown keys on save.
5. THE macOS_Frontend SHALL resolve the orphaned create-container view by wiring the view into
   navigation or removing the view.
6. WHEN accessibility inspection runs on the Runtime Controls surface, THE macOS_Frontend SHALL
   expose the surface without breaking traversal.

### Requirement 8: Isolated Live-Backend Test Environment (roadmap R6.1)

**User Story:** As a QA engineer, I want live real-backend testing confined to a disposable Colima
profile with OrbStack stopped, so that real workflows are verified without risk to existing user
data.

#### Acceptance Criteria

1. WHEN live-backend testing begins, THE Verification_Program SHALL stop OrbStack and start the
   E2E_Profile.
2. THE Verification_Program SHALL confine create, start, stop, and delete lifecycle tests to the
   E2E_Profile.
3. THE Verification_Program SHALL locate the live test project under `/Volumes/Projects/`.
4. WHEN a live test suite finishes, THE Verification_Program SHALL tear down the resources created
   in the E2E_Profile.
5. IF a test action would target a Colima profile other than the E2E_Profile, THEN THE
   Verification_Program SHALL reject the action.
6. THE Verification_Program SHALL keep secrets and user machine data out of every committed evidence
   artifact.
7. WHILE the E2E_Profile Docker socket is present, THE Verify_Script SHALL run the live RealBackend
   end-to-end tests.

### Requirement 9: Full-Functionality Exercise Across All Surfaces (roadmap R6.2)

**User Story:** As a release manager, I want the desktop application to exercise every functional
surface — including resource creation — on each platform to the defined depth, so that v1 ships
proven capability rather than only visible surfaces.

#### Acceptance Criteria

1. WHEN full-functionality verification runs on macOS, THE macOS_Frontend SHALL invoke all 12
   Canonical_Surfaces against the live E2E_Profile backend.
2. WHEN full-functionality verification runs on macOS, THE macOS_Frontend SHALL create a new
   container, pull an image, create a volume, and create a network against the E2E_Profile.
3. WHEN full-functionality verification runs on macOS, THE macOS_Frontend SHALL exercise VM
   lifecycle, profile, config, template, Kubernetes, AI-model, runtime, and monitoring actions
   against the E2E_Profile.
4. WHILE exercising the live workflows, THE macOS_Frontend SHALL return real backend data and SHALL
   remain running without crashing.
5. WHERE the verification host runs macOS only, THE Windows_Frontend and THE Linux_Frontend SHALL
   demonstrate functional parity through green `frontends.yml` and `test.yml` CI_Gate runs.
6. WHEN a frontend completes an exercised action, THE Verification_Program SHALL record a
   Ground_Truth_Artifact labeled with the evidence level of the action.
7. WHERE live UIA capture or AT-SPI capture is environment-blocked, THE Verification_Program SHALL
   label the affected evidence as environment-blocked.

### Requirement 10: DependencyManager Live Verification (roadmap R6.3)

**User Story:** As a new user, I want the DependencyManager to verify install, update, and
onboarding paths on each platform, so that turnkey setup works on a clean machine.

#### Acceptance Criteria

1. WHEN a dependency check runs, THE DependencyManager SHALL report installed, missing, and outdated
   states for `colima`, `lima`, `qemu`, `krunkit`, `docker-cli`, and `kubectl`.
2. WHEN a required dependency is missing, THE DependencyManager SHALL offer an install path through
   the platform package manager or a signed direct download.
3. IF a dependency install is cancelled, THEN THE DependencyManager SHALL return to a safe state and
   report the cancellation.
4. IF the host is offline during a dependency check, THEN THE DependencyManager SHALL report the
   offline condition.
5. IF a dependency install is denied permission, THEN THE DependencyManager SHALL report a
   permission error with remediation context.

### Requirement 11: Quality, Security, and Release Hardening (roadmap R7)

**User Story:** As a maintainer, I want quality, security, performance, and accessibility gates
enforced, so that v1 is safe to ship.

#### Acceptance Criteria

1. WHEN the Verify_Script runs, THE Verification_Program SHALL report GREEN with a coverage value at
   or above the Practical_Coverage_Ceiling.
2. WHEN Go streams and long-running UI operations are tested, THE Verification_Program SHALL pass
   race, leak, and cancellation checks.
3. WHEN the dependency and license audit runs, THE Verification_Program SHALL produce SBOMs and a
   vulnerability report containing zero known critical vulnerabilities.
4. THE Verification_Program SHALL provide a keyboard-accessible, uniquely named identifier for each
   interactive control across the Desktop_Frontends.
5. WHEN performance tests run, THE Verification_Program SHALL record startup-time, idle-resource, and
   large-list budgets.
6. WHEN a release candidate is prepared, THE Verification_Program SHALL require the Verify_Script,
   all 9 `frontends.yml` jobs, and `test.yml` to pass.

### Requirement 12: Cross-Platform v1 Release (roadmap R8)

**User Story:** As a release manager, I want signed cross-platform artifacts and a `v1.0.0` tag, so
that users on every platform can install and update the product.

#### Acceptance Criteria

1. WHEN a `vX.Y.Z` tag is pushed, THE Release_Pipeline SHALL build versioned artifacts for macOS,
   Windows, Linux, the Colima_Daemon, and the TUI_Frontend with checksums and SBOMs.
2. THE Release_Pipeline SHALL configure macOS Developer ID signing, notarization, and a
   non-placeholder Sparkle Ed25519 appcast key.
3. THE Release_Pipeline SHALL sign and package the Windows and Linux deliverables and SHALL document
   the install and trust behavior for each.
4. WHEN all v1 release gates pass, THE Release_Pipeline SHALL publish the signed `v1.0.0` tag with
   release notes, assets, checksums, and the appcast.
5. IF an open defect carries priority P0 or P1, THEN THE Release_Pipeline SHALL block the `v1.0.0`
   tag.
6. WHEN v1 documentation is published, THE Verification_Program SHALL align the installation,
   troubleshooting, architecture, security, privacy, and limitations documents with the shipped
   artifacts.

### Requirement 13: Completion Notification (blocking Assumption A1)

**User Story:** As the program sponsor, I want an email and SMS summary when the program completes,
so that I learn the outcome without monitoring the run.

#### Acceptance Criteria

1. WHEN the `v1.0.0` release completes, THE Notification_Service SHALL send an email to
   `jusys.linas@gmail.com` containing the released version, the completed roadmap item identifiers,
   and the final verification result.
2. WHEN the `v1.0.0` release completes, THE Notification_Service SHALL send an SMS to
   `+37060891909` containing the released version and the final verification result.
3. THE Notification_Service SHALL read the email and SMS credentials from environment variables.
4. IF an email or SMS credential is absent, THEN THE Notification_Service SHALL write the drafted
   message content to a file and SHALL provide a send script for later delivery.
5. WHERE an optional messaging channel among Viber, WhatsApp, and Telegram is configured, THE
   Notification_Service SHALL send the same summary through the configured channel.
6. THE Notification_Service SHALL exclude credentials and secrets from the message content and from
   logs.

## Assumptions

These assumptions were selected as documented defaults because the corresponding clarifying
questions were skipped. The Review phase should surface each assumption for confirmation.

### Assumption A1 — Notification channels, credentials, and fallback (blocking)

- Email is sent to `jusys.linas@gmail.com`; SMS is sent to `+37060891909`; Viber, WhatsApp, and
  Telegram are optional additional channels.
- No mail or SMS gateway credentials exist in the repository. The Notification_Service assumes
  credentials are supplied through environment variables (for example, SMTP or SendGrid for email,
  and Twilio or an equivalent provider for SMS and WhatsApp).
- When credentials are absent, the graceful fallback is to write the drafted message content to a
  file and provide a send script, rather than fail the release.
- This assumption is blocking for the notification acceptance criteria in Requirement 13.

### Assumption A2 — Cross-platform testing depth on a macOS-only host

- macOS receives full real-backend live testing locally against the E2E_Profile.
- Windows and Linux parity is proven through green CI (build plus tests in `frontends.yml` and
  `test.yml`) rather than live UI testing on this host, because live UIA and AT-SPI explorers are
  environment-blocked on a macOS-only host.
- Literal 100% line coverage is unreachable on a headless host; the measured practical ceiling is
  approximately 74% with the live E2E_Profile VM, and the Verify_Script gate `COV_MIN` defaults to
  71%. The phrase "works on mac, Windows, and Linux" is measured against this reality: macOS via
  live evidence, Windows and Linux via green CI.

### Assumption A3 — Destructive and real-data test blast radius

- All create, start, stop, and delete lifecycle tests use the isolated disposable `desktop-e2e`
  Colima profile, with teardown after each suite.
- Testing does not touch the user's existing or default Colima profiles or data.
- Stopping OrbStack and starting the `desktop-e2e` Colima profile is an environment-preparation
  task that precedes live testing.

## Constraints and Preserved Invariants

The following are fixed inputs. The Verification_Program consumes and preserves each; the program
does not redesign any of them.

- The Frozen_Contract keeps its 31 `ColimaService` RPCs, 34 `DockerService` RPCs, RPC names, and
  proto field numbers. Only the already-approved additive request-shape correction recorded in
  `INTENT_LEDGER.md` is reflected, and the audit reconciles it into `CONTRACT.md`.
- The disjoint-path multi-agent ownership model in `OWNERSHIP.md` remains the coordination
  mechanism, including the append-only `INTENT_LEDGER.md` and the single Integration_Agent merge
  policy.
- The native-frontend architecture (SwiftUI, WinUI 3, GTK4, Bubble Tea) remains; no Electron or
  frontend replacement is introduced.
- fakeDS-based deterministic rendering tests remain valid as regression tests but do not by
  themselves close Live_Backend_Evidence obligations.

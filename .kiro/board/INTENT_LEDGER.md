# Program Board — INTENT LEDGER (append-only)

> Protocol: BEFORE acting, append an entry with `intent`, `plan`, `files-to-touch`.
> AFTER acting, append an `outcome` + any `contract-impact`. Never rewrite prior entries.

---

### 2026-07-13T23:18Z · orchestrator · M0.1
- **intent:** Stand up the coordination substrate + seed OSS docs so parallel agents can start conflict-free.
- **plan:** Create `.kiro/board/{PLAN,INTENT_LEDGER,CONTRACT,OWNERSHIP,STATUS,DECISIONS}.md`; seed `README.md`, `LICENSE`.
- **files-to-touch:** `.kiro/board/*`, `README.md`, `LICENSE`.
- **outcome:** DONE. Created `.kiro/board/{PLAN,INTENT_LEDGER,CONTRACT,OWNERSHIP,STATUS,DECISIONS}.md`, seeded `README.md` + MIT `LICENSE`. CONTRACT v1 drafted from existing `proto/colima_ui.proto` (comprehensive: lifecycle/ssh/profiles/config/k8s/AI/runtime/monitoring). Board ready for parallel agents.
- **contract-impact:** none (proto unchanged; freeze deferred to M0.4).

---

### 2026-07-13T23:20Z · swiftui-dev · M0.2
- **intent:** Fix the Xcode-26 test-runner hang by extracting `ColimaDesktopKit` framework so logic tests link the module instead of hosting the `@main` app.
- **plan:** Add framework target in `project.yml`; move App/Models/Services/Views into the framework (app target becomes a thin `@main` shell + `main.swift`); unit/integration tests depend on the framework with `@testable import ColimaDesktopKit` and NO TEST_HOST; XCUITest keeps minimal host.
- **files-to-touch:** `project.yml`, `Sources/**` (module boundary only), `Tests/**` imports.
- **outcome:** (pending)
- **contract-impact:** none.

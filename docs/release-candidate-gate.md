# Release-Candidate Gate (R7 / task 12.5)

> Validates **Requirement 11.6**: *"WHEN a release candidate is prepared, THE Verification_Program
> SHALL require the Verify_Script, all 9 `frontends.yml` jobs, and `test.yml` to pass."*

The release-candidate (RC) gate is the single checkpoint a v1 release (**task 13 / R8**) must clear.
It composes every R7 hardening sub-gate (tasks 12.1–12.4) plus the frontend CI matrix and the macOS
test workflow into one pass/fail verdict. Nothing ships unless the RC gate is GREEN.

## What the gate aggregates

| # | Gate | Runner / command | Owner task | Requirement |
|---|------|------------------|-----------|-------------|
| 1 | **Verify_Script** — every runnable test layer GREEN + macOS coverage ≥ `COV_MIN` (71%) + Go stream-safety (race / leak / cancellation) | `scripts/verify.sh` | 12.1 | 11.1, 11.2, 11.6 |
| 2 | **Supply-chain** — CycloneDX SBOMs + **zero known CRITICAL** vulnerabilities | `scripts/security-scan.sh --fail-on-critical` | 12.2 | 11.3 |
| 3 | **Performance budgets** — startup-time / idle-resource / large-list within budget | `scripts/perf-budgets.sh --check` | 12.3 | 11.5 |
| 4 | **Accessibility identifiers** — cross-frontend totality + within-surface uniqueness + canonical-surface consistency + shared-id non-collision | `scripts/check-a11y-ids.py` | 12.4 | 11.4 |
| 5 | **Frontend matrix** — 9 jobs: `daemon`×3, `tui`×3, `windows-winui`, `linux-gtk4`, `macos-kit` | `.github/workflows/frontends.yml` | — | 11.6 |
| 6 | **macOS tests** — build + unit + integration | `.github/workflows/test.yml` | — | 11.6 |

The RC gate does **not** re-implement any sub-gate; it only invokes the scripts and workflows owned
by tasks 12.1–12.4. Those files are unchanged by this task.

## Two reproducible entry points

The identical set of gates runs both locally and in CI, so the verdict is reproducible.

### CI — `.github/workflows/release-candidate.yml`

Triggered when a version tag `v*` is pushed (i.e. a release candidate is *prepared*) or on
`workflow_dispatch`. It invokes `frontends.yml`, `test.yml`, and `security-scan.yml` as **reusable
workflows** (each exposes a `workflow_call` trigger), runs `verify.sh` on a macOS runner, and runs
the perf + a11y gates on a Linux runner. The final `rc-gate` job succeeds only when every upstream
job reports `success`; otherwise the release candidate is blocked.

```
release-candidate.yml
├── frontends        → .github/workflows/frontends.yml   (9 jobs)
├── tests            → .github/workflows/test.yml
├── security         → .github/workflows/security-scan.yml (--fail-on-critical)
├── verify-script    → macos-latest: bash scripts/verify.sh
├── hardening-gates  → ubuntu-latest: check-a11y-ids.py + perf-budgets.sh --check
└── rc-gate          → needs: all of the above → GREEN iff every result == success
```

### Local — `make rc-gate` (`scripts/rc-gate.sh`)

```bash
make rc-gate        # thorough: verify.sh (watchdog-bounded) + security + perf + a11y
make rc-gate-fast   # quick lane: defer verify.sh to CI/`make verify`, security from the committed
                    #             summary, perf + a11y run live
scripts/rc-gate.sh --list       # print the gate plan + CI mapping (nothing runs)
scripts/rc-gate.sh --selftest   # prove the pass/fail aggregation is correct
```

Every gate runs under a wall-clock watchdog, so a wedged sub-gate can never hang the verdict. The
aggregator exits non-zero if any gate that ran failed.

## Evidence convention (Assumption A2 — macOS-only host)

The native **WinUI 3** (Windows) and **GTK 4** (Linux) GUI compiles are environment-blocked on a
macOS-only verification host. They are **not** faked green locally: the local aggregator labels them
`n/a (CI-authoritative)` and the real compile + headless tests run in the `windows-winui` and
`linux-gtk4` jobs of `frontends.yml`. A local `make rc-gate-fast` therefore reports an **honestly
labelled partial GREEN** — the fast, host-runnable gates (perf, a11y, security-from-summary) pass
locally, and the heavy macOS `verify.sh` plus the native-compile layers are covered by CI
`release-candidate.yml`. Only a CI run of `release-candidate.yml` exercises all six gates end to end.

## Relationship to the release (task 13 / R8)

Task 13 (`release.yml`, signed artifacts, notarization, appcast, the `v1.0.0` tag) is **gated on a
GREEN RC verdict**. The release pipeline should require `release-candidate.yml` to pass before
publishing; a red RC gate blocks the release. This is separate from — and complementary to — the
P0/P1 defect-blocking gate (task 13.4, Requirement 12.5): both must be satisfied to ship.

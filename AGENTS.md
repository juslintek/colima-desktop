# Agent guidance

## Start here

- Read `docs/ARCHITECTURE.md` and `docs/DEVELOPMENT.md` for changes that cross components; read the touched component's README and nearby implementation for focused work.
- `proto/colima_ui.proto` is the source of truth for the shared gRPC API. Read the frozen-contract notes in `docs/ARCHITECTURE.md` and `docs/DEVELOPMENT.md` before changing that API.
- Keep changes small and within the requested scope. Reuse existing libraries and project patterns; do not add dependencies or abstractions without a concrete need.

## Changes and checks

- Follow `CONTRIBUTING.md`: use a short-lived branch and a focused pull request; commit messages use Conventional Commits.
- Run the narrowest real check for the changed component, using the commands in `CONTRIBUTING.md` or its existing CI workflow. For Go changes, run `go test ./...` in `daemon/` or `tui/`; for native frontends, use their documented platform build and tests. Report checks that could not run and why.
- For UI changes, preserve semantic controls, keyboard access, visible focus, and reduced-motion behavior; render and inspect the affected UI when its platform is available.
- Never skip or weaken a check to get a green result. Do not claim a build, test, platform review, or live-backend check that did not run.

## Safety and privacy

- Treat user data and machine state carefully. Read the live-test safeguards in `scripts/live/guard.sh` before running live E2E or teardown commands; keep destructive actions confined to the dedicated `desktop-e2e` profile.
- Do not expose credentials, private keys, local paths, host details, or private infrastructure in source, logs, prompts, or public documentation. Never fabricate product or verification claims.

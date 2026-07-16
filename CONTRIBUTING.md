# Contributing to Colima Desktop

Thank you for your interest in contributing! Colima Desktop is a multi-platform native
GUI and TUI for [Colima](https://github.com/abiosoft/colima). We welcome bug reports,
feature requests, documentation improvements, and code contributions.

## Code of Conduct

Be respectful and constructive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## Getting Started

1. Fork the repository and clone your fork
2. Read the [Architecture](docs/ARCHITECTURE.md) and [Development](docs/DEVELOPMENT.md) guides
3. Set up your environment following [docs/INSTALL.md](docs/INSTALL.md)
4. Create a short-lived branch from `main`
5. Make your changes, commit, and open a pull request

## Development Workflow

We follow **trunk-based development**:

- `main` is always deployable
- Short-lived feature branches (1–2 days max)
- No long-lived branches — use feature flags for incomplete work
- Rebase on `main` before opening a PR

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): short description

Types: feat | fix | refactor | test | docs | chore | perf
Scopes: daemon | macos | windows | linux | tui | proto | ci
```

Examples:
```
feat(tui): add container start/stop keybindings
fix(daemon): handle nil config in SetConfig RPC
docs: update ARCHITECTURE.md with streaming details
test(macos): add snapshot tests for DashboardView
```

## Project Structure

```
daemon/         Go gRPC daemon (shared backend)
Sources/        macOS SwiftUI frontend (+ ColimaDesktopKit framework)
windows/        Windows WinUI 3 frontend (C#/.NET 8)
linux/          Linux GTK4 frontend (Rust/tonic)
tui/            Terminal UI (Go/Bubble Tea)
proto/          Protobuf definitions (source of truth)
docs/           Documentation
Tests/          macOS test suites (unit/integration/snapshot/UI)
```

## Building

### macOS (required: Xcode 15+, Go 1.21+)
```bash
make build        # builds daemon + app
make test         # runs unit + integration tests
```

### Daemon only (any platform with Go 1.21+)
```bash
cd daemon && go build ./cmd
cd daemon && go test ./...
```

### TUI (any platform with Go 1.21+)
```bash
cd tui && go build .
```

### Windows (requires .NET 8 SDK + Windows App SDK)
```bash
cd windows && dotnet build
```

### Linux (requires Rust + GTK4 dev libs)
```bash
cd linux && cargo build
```

## Testing

### macOS test pyramid
| Target | Framework | Command |
|--------|-----------|---------|
| Unit | Swift Testing | `make test-unit` |
| Integration | ViewInspector | `make test-integration` |
| Snapshot | swift-snapshot-testing | `make test-snapshots` |
| UI (E2E) | XCUITest | `make test-ui` |

### Daemon
```bash
cd daemon && go test ./...
```

### TUI
```bash
cd tui && go test ./...
```

### Before submitting a PR
- All tests must pass for the component you changed
- Run `make verify` for the macOS component (coverage scoreboard)
- Ensure your code compiles without warnings

## Pull Request Guidelines

1. **One concern per PR** — keep changes focused
2. **Describe what and why** — link to issues if applicable
3. **Add tests** — new features need tests; bug fixes need a regression test
4. **Update docs** — if your change affects user-facing behavior
5. **Keep it small** — prefer multiple small PRs over one large one

## What to Work On

Check the [parity matrix](docs/parity-matrix.md) for features that need implementation.
The [gap report](docs/gap-report.md) identifies specific missing functionality per
frontend. Issues labeled `good first issue` are suitable for newcomers.

### Priority areas
- **TUI**: Adding action keybindings (start/stop VM, container lifecycle)
- **Windows/Linux**: Building out UI views backed by the gRPC client
- **Daemon**: Implementing GetConfig/SetConfig/Template RPCs
- **Documentation**: Improving guides, adding examples

## Architecture Decisions

Major design decisions are documented in `.kiro/board/`. The CONTRACT
(`.kiro/board/CONTRACT.md`) defines the frozen API surface — any changes to it
require a version bump and multi-team acknowledgment.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE).

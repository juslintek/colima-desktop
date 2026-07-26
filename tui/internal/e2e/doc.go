// Package e2e holds the TUI's gated live end-to-end verification lane.
//
// The live lane drives the compiled TUI binary through a real pseudo-terminal
// (PTY) against a real colima-desktop daemon bound to the disposable
// `desktop-e2e` colima profile, exercising actual key input -> real gRPC ->
// real rendered output. It is the "live-backend" evidence complement to the
// deterministic teatest dispatch tests in internal/ui.
//
// The lane lives entirely behind the `live_e2e` build tag (see
// live_pty_test.go). Without that tag this package compiles to nothing but this
// doc file, so the default `go build ./...` / `go vet ./...` / `go test ./...`
// runs never touch the PTY harness and stay green with the lane absent. Even
// with the tag, the single test skips cleanly (t.Skip, never fail, never hang)
// unless the live environment is explicitly available:
//
//   - env gate:    COLIMA_DESKTOP_E2E=1
//   - profile:     COLIMA_DESKTOP_E2E_PROFILE (default "desktop-e2e")
//   - live socket: ~/.colima/<profile>/docker.sock must exist
//
// The disposable `desktop-e2e` profile is provisioned later by task 10.1
// (scripts/live/e2e-env.sh); task 10.x drives this lane live once it is up.
package e2e

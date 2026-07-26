//go:build live_e2e

// live_pty_test.go — GATED live end-to-end PTY lane for the Bubble Tea TUI.
//
// This lane drives the *compiled* TUI binary through a real pseudo-terminal
// against a real colima-desktop daemon bound to the disposable `desktop-e2e`
// colima profile: actual key input -> real gRPC -> real rendered output. It is
// the "live-backend" evidence complement to the deterministic teatest dispatch
// tests in internal/ui (which prove action->RPC mapping against a fake source).
//
// Gating (never fail, never hang when the live env is absent):
//   - Build tag `live_e2e`: without it this file is not compiled at all, so the
//     default `go build ./...` / `go vet ./...` / `go test ./...` never touch
//     the PTY harness. Run the lane with:  go test -tags live_e2e ./internal/e2e
//   - Runtime skip: even with the tag, the test t.Skips cleanly unless
//       COLIMA_DESKTOP_E2E=1  AND  ~/.colima/<profile>/docker.sock exists.
//
// Daemon wiring (task 10.x drives this live once desktop-e2e is provisioned by
// task 10.1 / scripts/live/e2e-env.sh):
//   - If COLIMA_DESKTOP_ENDPOINT is set, the lane connects to that already
//     running daemon (task 10.x owns the daemon lifecycle).
//   - Otherwise the lane builds and starts the daemon itself on a private Unix
//     socket, so the lane is self-contained against the live profile.
package e2e

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/creack/pty"
)

// Timeouts are generous: this host is heavily loaded and the live backend does
// real work. They bound a genuinely stuck run, not a healthy one — every wait
// returns as soon as its marker renders.
const (
	buildTimeout      = 3 * time.Minute
	daemonReadyWait   = 30 * time.Second
	renderWait        = 25 * time.Second
	actionWait        = 45 * time.Second
	quitWait          = 15 * time.Second
	keySettle         = 200 * time.Millisecond
	ptyRows, ptyCols  = 40, 120
	pollEvery         = 50 * time.Millisecond
	recentOutputBytes = 4000
)

// liveConfig is the resolved live-lane environment.
type liveConfig struct {
	profile   string
	endpoint  string // non-empty => connect to this external daemon
	tuiDir    string
	daemonDir string
}

// requireLiveEnv enforces the runtime gate. It SKIPS (never fails) whenever the
// live desktop-e2e environment is not explicitly available, so the lane is safe
// to run on any host — including this macOS host before task 10.1 provisions the
// profile.
func requireLiveEnv(t *testing.T) liveConfig {
	t.Helper()

	if os.Getenv("COLIMA_DESKTOP_E2E") != "1" {
		t.Skip("live PTY lane disabled: set COLIMA_DESKTOP_E2E=1 with the desktop-e2e profile running to enable")
	}

	profile := envOr("COLIMA_DESKTOP_E2E_PROFILE", "desktop-e2e")

	home, err := os.UserHomeDir()
	if err != nil {
		t.Skipf("live PTY lane skipped: cannot resolve home dir: %v", err)
	}
	sock := filepath.Join(home, ".colima", profile, "docker.sock")
	info, err := os.Stat(sock)
	if err != nil {
		t.Skipf("live PTY lane skipped: %q profile socket %s not present (task 10.1 provisions it): %v", profile, sock, err)
	}
	if info.Mode()&os.ModeSocket == 0 {
		t.Skipf("live PTY lane skipped: %s exists but is not a socket", sock)
	}

	if _, err := exec.LookPath("go"); err != nil {
		t.Skipf("live PTY lane skipped: go toolchain not found on PATH: %v", err)
	}

	tuiDir, daemonDir := moduleDirs(t)

	return liveConfig{
		profile:   profile,
		endpoint:  os.Getenv("COLIMA_DESKTOP_ENDPOINT"),
		tuiDir:    tuiDir,
		daemonDir: daemonDir,
	}
}

// moduleDirs resolves the tui/ and daemon/ module directories relative to this
// test file, so the lane works regardless of the checkout location.
func moduleDirs(t *testing.T) (tuiDir, daemonDir string) {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("live PTY lane: cannot resolve caller path")
	}
	// thisFile = <repo>/tui/internal/e2e/live_pty_test.go
	e2eDir := filepath.Dir(thisFile)
	tuiDir = filepath.Dir(filepath.Dir(e2eDir)) // e2e -> internal -> tui
	repoRoot := filepath.Dir(tuiDir)
	daemonDir = filepath.Join(repoRoot, "daemon")
	return tuiDir, daemonDir
}

// TestLivePTYEndToEnd is the single live lane. It: launches the TUI in a PTY
// against a real daemon+profile, observes the real dashboard/status render,
// navigates to a resource tab and observes the real list render, runs one
// non-destructive action (SSH configuration) end-to-end, then tears down
// cleanly by quitting the TUI.
func TestLivePTYEndToEnd(t *testing.T) {
	cfg := requireLiveEnv(t)

	// Binaries live under the standard temp dir (regular files, no path-length
	// limit). The daemon Unix socket lives under a SHORT /tmp dir because macOS
	// caps Unix socket paths at ~104 bytes and t.TempDir() paths are long.
	binDir := t.TempDir()
	tuiBin := filepath.Join(binDir, "colima-tui")
	buildBinary(t, cfg.tuiDir, tuiBin, ".")

	endpoint := cfg.endpoint
	if endpoint == "" {
		sockDir, err := os.MkdirTemp("/tmp", "cde2e")
		if err != nil {
			t.Fatalf("live PTY lane: create short socket dir: %v", err)
		}
		t.Cleanup(func() { _ = os.RemoveAll(sockDir) })

		daemonBin := filepath.Join(binDir, "colima-daemon")
		buildBinary(t, cfg.daemonDir, daemonBin, "./cmd")
		endpoint = startDaemon(t, daemonBin, filepath.Join(sockDir, "d.sock"))
	} else {
		t.Logf("live PTY lane: using external daemon endpoint %q", endpoint)
	}

	// Launch the TUI attached to a real PTY, sized deterministically.
	cmd := exec.Command(tuiBin, "-endpoint", endpoint, "-profile", cfg.profile)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")
	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{Rows: ptyRows, Cols: ptyCols})
	if err != nil {
		t.Fatalf("live PTY lane: start TUI under PTY: %v", err)
	}

	waitCh := make(chan error, 1)
	go func() { waitCh <- cmd.Wait() }()
	tail := newPtyTail(ptmx)

	// Force teardown if the test bails before the graceful quit below.
	t.Cleanup(func() {
		_ = ptmx.Close()
		if cmd.Process != nil {
			_ = cmd.Process.Signal(syscall.SIGKILL)
		}
		select {
		case <-waitCh:
		case <-time.After(3 * time.Second):
		}
	})

	// 1. Launch -> the dashboard tab bar and body render.
	requireContains(t, tail, "Dashboard", renderWait,
		"TUI dashboard did not render under PTY")

	// Observe REAL backend data: the footer status line is populated from a live
	// ColimaService.Status RPC scoped to the active profile.
	requireContains(t, tail, "profile="+cfg.profile, renderWait,
		"live status line (real Status RPC) did not render")

	// 2. Navigate to the Containers tab (key '2') and observe the REAL list
	// render. The container-specific action hints are appended only after a
	// successful ListContainers RPC replaces the "Loading…" placeholder.
	writeKey(t, ptmx, "2")
	requireContains(t, tail, "start/stop/restart", renderWait,
		"Containers tab did not render its real list (ListContainers RPC)")

	// 3. Run one NON-DESTRUCTIVE action end-to-end: SSH configuration on the
	// Dashboard. Key input -> real ColimaService.SSHConfig RPC -> rendered
	// success output. SSH config is read-only and always available while the
	// desktop-e2e VM is running.
	writeKey(t, ptmx, "1")
	requireContains(t, tail, "Colima Desktop", renderWait,
		"Dashboard did not re-render after navigating back")
	writeKey(t, ptmx, "H")
	requireContains(t, tail, "SSH configuration", actionWait,
		"SSH-config action did not launch")
	requireContains(t, tail, "Success:", actionWait,
		"SSH-config action did not complete successfully end-to-end")

	// 4. Clean teardown: quit the TUI and confirm the process exits promptly
	// without hanging or crashing.
	writeKey(t, ptmx, "q")
	select {
	case err := <-waitCh:
		if err != nil {
			t.Fatalf("TUI did not exit cleanly after quit: %v\n--- recent PTY output ---\n%s",
				err, recentOutput(tail))
		}
	case <-time.After(quitWait):
		t.Fatalf("TUI did not exit within %s after quit key", quitWait)
	}
}

// ─── daemon + build helpers ──────────────────────────────────────────────────

// buildBinary compiles pkg (relative to dir) to out. Building the sibling
// daemon module compiles its source into a temp binary; it never writes into
// the daemon source tree.
func buildBinary(t *testing.T, dir, out, pkg string) {
	t.Helper()
	cmd := exec.Command("go", "build", "-o", out, pkg)
	cmd.Dir = dir
	cmd.Env = os.Environ()

	done := make(chan error, 1)
	var combined []byte
	go func() {
		var err error
		combined, err = cmd.CombinedOutput()
		done <- err
	}()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("live PTY lane: build %s in %s failed: %v\n%s", pkg, dir, err, combined)
		}
	case <-time.After(buildTimeout):
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		t.Fatalf("live PTY lane: build %s in %s timed out after %s", pkg, dir, buildTimeout)
	}
}

// startDaemon builds nothing; it launches the already-built daemon binary on a
// private Unix socket and waits for the socket to appear. It returns the TUI
// endpoint string and registers graceful teardown.
func startDaemon(t *testing.T, daemonBin, sockPath string) string {
	t.Helper()
	endpoint := "unix:" + sockPath

	logPath := sockPath + ".log"
	logFile, err := os.Create(logPath)
	if err != nil {
		t.Fatalf("live PTY lane: create daemon log: %v", err)
	}

	cmd := exec.Command(daemonBin, "--listen", endpoint)
	cmd.Env = os.Environ()
	cmd.Stdout = logFile
	cmd.Stderr = logFile
	if err := cmd.Start(); err != nil {
		_ = logFile.Close()
		t.Fatalf("live PTY lane: start daemon: %v", err)
	}

	daemonDone := make(chan error, 1)
	go func() { daemonDone <- cmd.Wait() }()

	t.Cleanup(func() {
		if cmd.Process != nil {
			_ = cmd.Process.Signal(syscall.SIGTERM)
			select {
			case <-daemonDone:
			case <-time.After(5 * time.Second):
				_ = cmd.Process.Signal(syscall.SIGKILL)
				<-daemonDone
			}
		}
		_ = logFile.Close()
		if t.Failed() {
			if data, readErr := os.ReadFile(logPath); readErr == nil && len(data) > 0 {
				t.Logf("--- daemon log (%s) ---\n%s", logPath, data)
			}
		}
	})

	deadline := time.Now().Add(daemonReadyWait)
	for time.Now().Before(deadline) {
		select {
		case err := <-daemonDone:
			data, _ := os.ReadFile(logPath)
			t.Fatalf("live PTY lane: daemon exited before becoming ready: %v\n%s", err, data)
		default:
		}
		if info, statErr := os.Stat(sockPath); statErr == nil && info.Mode()&os.ModeSocket != 0 {
			t.Logf("live PTY lane: daemon ready on %s", endpoint)
			return endpoint
		}
		time.Sleep(pollEvery)
	}
	data, _ := os.ReadFile(logPath)
	t.Fatalf("live PTY lane: daemon socket %s did not appear within %s\n%s", sockPath, daemonReadyWait, data)
	return endpoint // unreachable
}

// ─── PTY I/O helpers ─────────────────────────────────────────────────────────

// ptyTail accumulates the full cumulative PTY output in a background goroutine
// so sequential markers can each be matched without consuming the stream.
type ptyTail struct {
	mu  sync.Mutex
	buf []byte
}

func newPtyTail(r io.Reader) *ptyTail {
	tail := &ptyTail{}
	go func() {
		chunk := make([]byte, 4096)
		for {
			n, err := r.Read(chunk)
			if n > 0 {
				tail.mu.Lock()
				tail.buf = append(tail.buf, chunk[:n]...)
				tail.mu.Unlock()
			}
			if err != nil {
				return // EOF on TUI exit / PTY close
			}
		}
	}()
	return tail
}

func (tail *ptyTail) contains(substr string) bool {
	tail.mu.Lock()
	defer tail.mu.Unlock()
	return bytes.Contains(tail.buf, []byte(substr))
}

func (tail *ptyTail) snapshot() string {
	tail.mu.Lock()
	defer tail.mu.Unlock()
	return string(tail.buf)
}

// writeKey sends literal key bytes to the TUI and lets it process them. Number
// and letter keys map directly to bytes; the model reads them as tea.KeyRunes.
func writeKey(t *testing.T, w io.Writer, keys string) {
	t.Helper()
	if _, err := io.WriteString(w, keys); err != nil {
		t.Fatalf("live PTY lane: write key %q to PTY: %v", keys, err)
	}
	time.Sleep(keySettle)
}

// requireContains polls the cumulative output until substr appears or the cap
// elapses; on timeout it fails with the most recent output for diagnosis.
func requireContains(t *testing.T, tail *ptyTail, substr string, within time.Duration, msg string) {
	t.Helper()
	deadline := time.Now().Add(within)
	for {
		if tail.contains(substr) {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("%s: never observed %q within %s\n--- recent PTY output ---\n%s",
				msg, substr, within, recentOutput(tail))
		}
		time.Sleep(pollEvery)
	}
}

// recentOutput returns a printable tail of the PTY stream for failure messages,
// with the noisiest ANSI control bytes stripped so logs stay readable.
func recentOutput(tail *ptyTail) string {
	out := tail.snapshot()
	if len(out) > recentOutputBytes {
		out = out[len(out)-recentOutputBytes:]
	}
	return sanitize(out)
}

func sanitize(s string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '\n' || r == '\t':
			b.WriteRune(r)
		case r == '\x1b':
			b.WriteString("\\e")
		case r < 0x20:
			// drop other control bytes
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

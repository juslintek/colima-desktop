package ui

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/colima-desktop/tui/internal/action"
)

// ─── bounded output (Requirement 4.5 / design Property 14) ───────────────────

func TestBoundOutputCapsLinesDropOldest(t *testing.T) {
	var b strings.Builder
	for i := 0; i < maxOutputLines+500; i++ {
		fmt.Fprintf(&b, "line-%05d\n", i)
	}
	out := boundOutput(b.String())
	if lines := strings.Split(out, "\n"); len(lines) > maxOutputLines {
		t.Fatalf("line count %d exceeds cap %d", len(lines), maxOutputLines)
	}
	if !strings.Contains(out, fmt.Sprintf("line-%05d", maxOutputLines+499)) {
		t.Fatal("newest line was dropped by the ring buffer")
	}
	if strings.Contains(out, "line-00000") {
		t.Fatal("oldest line was not dropped by the ring buffer")
	}
}

func TestBoundOutputCapsBytesKeepingNewest(t *testing.T) {
	huge := "HEAD_MARKER" + strings.Repeat("x", maxOutputBytes*2) + "TAIL_MARKER"
	out := boundOutput(huge)
	if len(out) > maxOutputBytes {
		t.Fatalf("byte length %d exceeds cap %d", len(out), maxOutputBytes)
	}
	if !strings.Contains(out, "TAIL_MARKER") {
		t.Fatal("newest bytes (tail) were dropped")
	}
	if strings.Contains(out, "HEAD_MARKER") {
		t.Fatal("oldest bytes (head) were not dropped")
	}
}

func TestBoundOutputAlwaysReturnsValidUTF8(t *testing.T) {
	// A byte-level trim must not split a multi-byte rune.
	huge := strings.Repeat("é", maxOutputBytes) // 2 bytes per rune → exceeds the byte cap
	out := boundOutput(huge)
	if len(out) > maxOutputBytes {
		t.Fatalf("byte length %d exceeds cap %d", len(out), maxOutputBytes)
	}
	if !strings.ContainsRune(out, 'é') {
		t.Fatal("expected retained content")
	}
	if strings.ContainsRune(out, '\uFFFD') {
		t.Fatal("byte trim produced an invalid/replacement rune")
	}
}

func TestStreamingAppendOutputStaysBounded(t *testing.T) {
	state := &actionState{}
	for i := 0; i < maxOutputLines+1000; i++ {
		state.appendOutput(fmt.Sprintf("event-%05d", i))
	}
	if lines := strings.Split(state.output, "\n"); len(lines) > maxOutputLines {
		t.Fatalf("streaming output not line-bounded: %d > %d", len(lines), maxOutputLines)
	}
	if len(state.output) > maxOutputBytes {
		t.Fatalf("streaming output not byte-bounded: %d > %d", len(state.output), maxOutputBytes)
	}
	if !strings.Contains(state.output, fmt.Sprintf("event-%05d", maxOutputLines+999)) {
		t.Fatal("newest streamed event was dropped")
	}
	if strings.Contains(state.output, "event-00000") {
		t.Fatal("oldest streamed event was not dropped")
	}
	if state.outputLine != 1<<30 {
		t.Fatalf("streaming outputLine sentinel = %d, want %d", state.outputLine, 1<<30)
	}
}

// TestUnaryResultOutputIsBounded proves the real gap closed by task 4.4: a large
// UNARY result (e.g. a chatty container's logs fetched via ContainerLogs) is
// bounded in the model buffer instead of being retained in full.
func TestUnaryResultOutputIsBounded(t *testing.T) {
	var b strings.Builder
	for i := 0; i < maxOutputLines+3000; i++ {
		fmt.Fprintf(&b, "log-line-%05d: chatty container output\n", i)
	}
	source := &actionRecordingSource{result: action.Result{Text: b.String()}}
	m := New(source, "desktop-e2e")
	m.tab = TabContainers
	m.resources = []resourceItem{{ID: "ctr-chatty", Name: "chatty"}}

	m, cmd := updateKey(t, m, runeKey("g")) // container logs — unary, non-destructive
	if m.action.phase != actionBusy {
		t.Fatalf("phase = %v, want busy", m.action.phase)
	}
	m, _ = executeCommand(t, m, cmd)
	if m.action.phase != actionSuccess {
		t.Fatalf("phase = %v, want success", m.action.phase)
	}
	if len(m.action.output) > maxOutputBytes {
		t.Fatalf("unary output not byte-bounded: %d > %d", len(m.action.output), maxOutputBytes)
	}
	if lines := strings.Split(m.action.output, "\n"); len(lines) > maxOutputLines {
		t.Fatalf("unary output not line-bounded: %d > %d", len(lines), maxOutputLines)
	}
	if !strings.Contains(m.action.output, fmt.Sprintf("log-line-%05d", maxOutputLines+2999)) {
		t.Fatal("newest unary output line was dropped")
	}
	if strings.Contains(m.action.output, "log-line-00000") {
		t.Fatal("oldest unary output line was not dropped (buffer is unbounded)")
	}
}

// ─── streamed cancellation teardown (Requirement 4.5) ────────────────────────

// TestEscapeCancelsBusyStreamAndTearsDownContext proves that cancelling an
// in-flight stream with Esc cancels the context so the blocked recv goroutine
// unwinds (no leaked goroutine / orphaned stream) and the cancel func is cleared.
func TestEscapeCancelsBusyStreamAndTearsDownContext(t *testing.T) {
	started := make(chan struct{})
	stream := &contextProgressStream{block: true, started: started}
	source := &actionRecordingSource{stream: stream}
	m := New(source, "desktop-e2e")
	m.tab = TabDashboard

	m, openCmd := updateKey(t, m, runeKey("s")) // Start VM — streaming action
	m, recvCmd := executeCommand(t, m, openCmd)
	done := make(chan tea.Msg, 1)
	go func() { done <- recvCmd() }()

	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("stream Recv did not start")
	}

	m, _ = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEsc})
	if m.action.phase != actionCanceled {
		t.Fatalf("phase = %v, want canceled", m.action.phase)
	}
	if m.action.cancel != nil {
		t.Fatal("cancel func must be cleared after teardown")
	}

	select {
	case message := <-done:
		progress, ok := message.(actionProgressMsg)
		if !ok {
			t.Fatalf("recv returned %T, want actionProgressMsg", message)
		}
		if !errors.Is(progress.err, context.Canceled) {
			t.Fatalf("Recv error = %v, want context.Canceled", progress.err)
		}
	case <-time.After(time.Second):
		t.Fatal("Esc did not tear down the stream context (goroutine leak)")
	}
}

// ─── destructive confirmation gate (Requirement 4.4 / design Property 13) ────

// TestDismissedConfirmationFiresNoDestructiveRPC covers the destructive
// operations the task enumerates: no RPC may fire without confirmed intent, and
// dismissing the confirmation must issue nothing.
func TestDismissedConfirmationFiresNoDestructiveRPC(t *testing.T) {
	cases := []struct {
		name string
		tab  int
		key  string
	}{
		{"container remove", TabContainers, "d"},
		{"image remove", TabImages, "d"},
		{"volume remove", TabVolumes, "d"},
		{"vm delete", TabDashboard, "D"},
		{"kubernetes reset", TabKubernetes, "R"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			source := &actionRecordingSource{}
			m := New(source, "desktop-e2e")
			m.tab = tc.tab
			m.resources = []resourceItem{{ID: "res-id", Name: "res-name"}}

			m, cmd := updateKey(t, m, runeKey(tc.key))
			if cmd != nil || m.action.phase != actionConfirm {
				t.Fatalf("%s did not open a confirmation gate: phase=%v hasCmd=%v", tc.name, m.action.phase, cmd != nil)
			}
			if len(source.requests) != 0 {
				t.Fatalf("%s issued an RPC before confirmation", tc.name)
			}

			m, _ = updateKey(t, m, runeKey("n")) // dismiss
			if len(source.requests) != 0 {
				t.Fatalf("%s issued an RPC after dismissal: %#v", tc.name, source.requests)
			}
			if m.action.phase != actionIdle {
				t.Fatalf("%s: dismissed confirmation left phase=%v, want idle", tc.name, m.action.phase)
			}
		})
	}
}

// ─── error rendering with context (Requirement 4.6 / design Property 15) ─────

func TestBackendErrorRendersOperationNameAndUnderlyingError(t *testing.T) {
	source := &actionRecordingSource{unaryErr: errors.New("connection refused: daemon unreachable")}
	m := New(source, "desktop-e2e")
	m.tab = TabImages
	m.resources = []resourceItem{{ID: "sha256:abc", Name: "nginx:latest"}}

	m, _ = updateKey(t, m, runeKey("d")) // image remove — destructive
	m, cmd := updateKey(t, m, runeKey("y"))
	m, _ = executeCommand(t, m, cmd)

	if m.action.phase != actionFailure {
		t.Fatalf("phase = %v, want failure", m.action.phase)
	}
	view := m.View()
	if !strings.Contains(view, "Remove image") {
		t.Fatalf("failure view is missing the operation name (context):\n%s", view)
	}
	if !strings.Contains(view, "connection refused: daemon unreachable") {
		t.Fatalf("failure view is missing the underlying error:\n%s", view)
	}
}

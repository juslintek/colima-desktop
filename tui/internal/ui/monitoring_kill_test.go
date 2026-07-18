package ui

import (
	"bytes"
	"errors"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/exp/teatest"
	pb "github.com/colima-desktop/daemon/proto"
)

// killRecordingSource wraps fakeSource to record KillProcess invocations.
type killRecordingSource struct {
	fakeSource
	killCalls []killCall
	killErr   error // if non-nil, KillProcess returns this error
}

type killCall struct {
	profile string
	pid     int32
	signal  int32
}

func (k *killRecordingSource) KillProcess(profile string, pid int32, signal int32) error {
	k.killCalls = append(k.killCalls, killCall{profile, pid, signal})
	return k.killErr
}

// ─── Unit tests: process selection state ─────────────────────────────────────

func TestMonitoringCursorInitiallyZero(t *testing.T) {
	m := New(fakeSource{}, "default")
	if m.monCursor != 0 {
		t.Errorf("monCursor should start at 0, got %d", m.monCursor)
	}
}

func TestMonitoringMsgSetsProcesses(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring

	procs := []*pb.ProcessInfo{
		{Pid: 100, User: "root", Command: "init"},
		{Pid: 200, User: "user", Command: "bash"},
	}
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: procs},
		stats:     &pb.VMStatsEvent{CpuPercent: 10},
	}
	nm, _ := m.Update(monitoringMsg{data: md, processes: procs})
	m2 := nm.(Model)

	if len(m2.monProcesses) != 2 {
		t.Fatalf("monProcesses len = %d, want 2", len(m2.monProcesses))
	}
	if m2.monProcesses[0].Pid != 100 {
		t.Errorf("first process PID = %d, want 100", m2.monProcesses[0].Pid)
	}
}

func TestMonitoringSelectionMarkerInBody(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring

	procs := []*pb.ProcessInfo{
		{Pid: 111, User: "root", Command: "dockerd"},
		{Pid: 222, User: "user", Command: "nginx"},
	}
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: procs},
		stats:     &pb.VMStatsEvent{CpuPercent: 50, MemoryUsed: 1024, MemoryTotal: 2048},
	}
	nm, _ := m.Update(monitoringMsg{data: md, processes: procs})
	m2 := nm.(Model)

	// First process (cursor=0) should be marked with "> "
	if !strings.Contains(m2.body, "> 111") {
		t.Errorf("body should contain '> 111' (selected marker):\n%s", m2.body)
	}
	// Second process should NOT have marker
	lines := strings.Split(m2.body, "\n")
	for _, line := range lines {
		if strings.Contains(line, "222") && strings.HasPrefix(line, "> ") {
			t.Errorf("process 222 should not be selected:\n%s", line)
		}
	}
}

func TestMonitoringDownKeyMovesSelection(t *testing.T) {
	src := &killRecordingSource{}
	m := New(src, "default")
	m.tab = TabMonitoring
	m.monProcesses = []*pb.ProcessInfo{
		{Pid: 1, User: "root", Command: "a"},
		{Pid: 2, User: "user", Command: "b"},
		{Pid: 3, User: "root", Command: "c"},
	}
	m.monCursor = 0
	// Set a body that has the right structure for rerenderMonitoringSelection.
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: m.monProcesses},
		stats:     &pb.VMStatsEvent{CpuPercent: 10, MemoryUsed: 100, MemoryTotal: 200},
	}
	m.body = renderMonitoringWithSelection(md, m.monProcesses, 0)

	// Press down
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyDown})
	m2 := nm.(Model)
	if m2.monCursor != 1 {
		t.Errorf("after down: cursor = %d, want 1", m2.monCursor)
	}

	// Press j (also moves down)
	nm, _ = m2.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'j'}})
	m3 := nm.(Model)
	if m3.monCursor != 2 {
		t.Errorf("after j: cursor = %d, want 2", m3.monCursor)
	}

	// Wraps around
	nm, _ = m3.Update(tea.KeyMsg{Type: tea.KeyDown})
	m4 := nm.(Model)
	if m4.monCursor != 0 {
		t.Errorf("after wrap: cursor = %d, want 0", m4.monCursor)
	}
}

func TestMonitoringUpKeyMovesSelection(t *testing.T) {
	src := &killRecordingSource{}
	m := New(src, "default")
	m.tab = TabMonitoring
	m.monProcesses = []*pb.ProcessInfo{
		{Pid: 1, User: "root", Command: "a"},
		{Pid: 2, User: "user", Command: "b"},
	}
	m.monCursor = 0
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: m.monProcesses},
		stats:     &pb.VMStatsEvent{CpuPercent: 10, MemoryUsed: 100, MemoryTotal: 200},
	}
	m.body = renderMonitoringWithSelection(md, m.monProcesses, 0)

	// Press up from 0 wraps to last
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyUp})
	m2 := nm.(Model)
	if m2.monCursor != 1 {
		t.Errorf("up from 0: cursor = %d, want 1", m2.monCursor)
	}
}

// ─── Unit tests: kill invocation ─────────────────────────────────────────────

func TestKillKeyInvokesKillProcess(t *testing.T) {
	src := &killRecordingSource{}
	m := New(src, "default")
	m.tab = TabMonitoring
	m.monProcesses = []*pb.ProcessInfo{
		{Pid: 1001, User: "root", Command: "dockerd"},
		{Pid: 2042, User: "user", Command: "nginx"},
	}
	m.monCursor = 1 // select nginx (PID 2042)
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: m.monProcesses},
		stats:     &pb.VMStatsEvent{CpuPercent: 10, MemoryUsed: 100, MemoryTotal: 200},
	}
	m.body = renderMonitoringWithSelection(md, m.monProcesses, 1)

	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'k'}})
	if cmd == nil {
		t.Fatal("pressing k should return a command")
	}

	// Execute the command synchronously to trigger the KillProcess call.
	msg := cmd()
	kr, ok := msg.(killResultMsg)
	if !ok {
		t.Fatalf("cmd returned %T, want killResultMsg", msg)
	}
	if kr.pid != 2042 {
		t.Errorf("kill pid = %d, want 2042", kr.pid)
	}
	if kr.err != nil {
		t.Errorf("unexpected error: %v", kr.err)
	}

	// Verify the DataSource was called with correct args.
	if len(src.killCalls) != 1 {
		t.Fatalf("expected 1 kill call, got %d", len(src.killCalls))
	}
	call := src.killCalls[0]
	if call.profile != "default" {
		t.Errorf("kill profile = %q, want 'default'", call.profile)
	}
	if call.pid != 2042 {
		t.Errorf("kill pid = %d, want 2042", call.pid)
	}
	if call.signal != 9 {
		t.Errorf("kill signal = %d, want 9 (SIGKILL)", call.signal)
	}
}

func TestKillResultSuccessShowsFeedback(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring
	m.body = "some monitoring body"

	nm, _ := m.Update(killResultMsg{pid: 2042, err: nil})
	m2 := nm.(Model)

	if !strings.Contains(m2.monFeedback, "Killed PID 2042") {
		t.Errorf("feedback should mention success: %q", m2.monFeedback)
	}
	if !strings.Contains(m2.body, "Killed PID 2042") {
		t.Errorf("body should contain kill feedback: %q", m2.body)
	}
}

func TestKillResultErrorShowsFeedback(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring
	m.body = "some monitoring body"

	nm, _ := m.Update(killResultMsg{pid: 999, err: errors.New("permission denied")})
	m2 := nm.(Model)

	if !strings.Contains(m2.monFeedback, "failed") {
		t.Errorf("feedback should mention failure: %q", m2.monFeedback)
	}
	if !strings.Contains(m2.monFeedback, "permission denied") {
		t.Errorf("feedback should contain error message: %q", m2.monFeedback)
	}
}

func TestKillResultTriggersRefresh(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring
	m.body = "body"

	_, cmd := m.Update(killResultMsg{pid: 100, err: nil})
	if cmd == nil {
		t.Fatal("killResultMsg should return a refresh command")
	}
}

func TestKillKeyWithErrorSource(t *testing.T) {
	src := &killRecordingSource{killErr: errors.New("no such process")}
	m := New(src, "default")
	m.tab = TabMonitoring
	m.monProcesses = []*pb.ProcessInfo{
		{Pid: 9999, User: "root", Command: "zombie"},
	}
	m.monCursor = 0
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: m.monProcesses},
		stats:     &pb.VMStatsEvent{CpuPercent: 5, MemoryUsed: 50, MemoryTotal: 100},
	}
	m.body = renderMonitoringWithSelection(md, m.monProcesses, 0)

	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'k'}})
	msg := cmd()
	kr := msg.(killResultMsg)
	if kr.err == nil {
		t.Fatal("expected error from kill")
	}
	if kr.pid != 9999 {
		t.Errorf("pid = %d, want 9999", kr.pid)
	}
}

// ─── Unit tests: k key does NOT trigger on non-Monitoring tabs ───────────────

func TestKKeyIgnoredOnOtherTabs(t *testing.T) {
	src := &killRecordingSource{}
	m := New(src, "default")
	m.tab = TabDashboard // not Monitoring

	nm, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'k'}})
	m2 := nm.(Model)
	_ = m2
	// Should not produce a command (k is not a valid action on Dashboard)
	if cmd != nil {
		t.Error("k key on non-Monitoring tab should not produce a command")
	}
	if len(src.killCalls) > 0 {
		t.Error("KillProcess should not be called from Dashboard tab")
	}
}

func TestKKeyIgnoredWhenNoProcesses(t *testing.T) {
	src := &killRecordingSource{}
	m := New(src, "default")
	m.tab = TabMonitoring
	m.monProcesses = nil // empty

	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'k'}})
	if cmd != nil {
		t.Error("k key with no processes should not produce a command")
	}
}

// ─── Unit tests: cursor clamping on refresh ──────────────────────────────────

func TestMonitoringCursorClampedOnRefresh(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring
	m.monCursor = 5 // was at index 5

	// Refresh delivers only 2 processes → cursor must clamp.
	procs := []*pb.ProcessInfo{
		{Pid: 1, User: "a", Command: "x"},
		{Pid: 2, User: "b", Command: "y"},
	}
	md := monitoringData{
		processes: &pb.ProcessListResponse{Processes: procs},
		stats:     &pb.VMStatsEvent{CpuPercent: 10, MemoryUsed: 100, MemoryTotal: 200},
	}
	nm, _ := m.Update(monitoringMsg{data: md, processes: procs})
	m2 := nm.(Model)
	if m2.monCursor != 1 {
		t.Errorf("cursor should clamp to last valid index (1), got %d", m2.monCursor)
	}
}

// ─── Unit tests: left/right still work on Monitoring tab ─────────────────────

func TestLeftRightStillNavigateFromMonitoring(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = TabMonitoring
	m.monProcesses = []*pb.ProcessInfo{
		{Pid: 1, User: "root", Command: "init"},
	}

	// Right from Monitoring (11) wraps to Dashboard (0)
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m2 := nm.(Model)
	if m2.tab != TabDashboard {
		t.Errorf("right from Monitoring: tab = %d, want 0 (Dashboard)", m2.tab)
	}

	// Go back to Monitoring via left
	nm, _ = m2.Update(tea.KeyMsg{Type: tea.KeyLeft})
	m3 := nm.(Model)
	if m3.tab != TabMonitoring {
		t.Errorf("left from Dashboard: tab = %d, want %d (Monitoring)", m3.tab, TabMonitoring)
	}
}

// ─── teatest: kill process flow end-to-end ───────────────────────────────────

func TestTeatestMonitoringKillFlow(t *testing.T) {
	src := &killRecordingSource{}
	m := New(src, "default")
	tm := teatest.NewTestModel(
		t, m,
		teatest.WithInitialTermSize(120, 40),
	)
	t.Cleanup(func() { _ = tm.Quit() })

	// Navigate to Monitoring tab (index 11): press 0 → right → right
	tm.Type("0")                            // tab 9 Profiles
	tm.Send(tea.KeyMsg{Type: tea.KeyRight}) // tab 10 Machines
	tm.Send(tea.KeyMsg{Type: tea.KeyRight}) // tab 11 Monitoring

	// Wait for monitoring content to load (should show process data)
	teatest.WaitFor(t, tm.Output(), func(out []byte) bool {
		return bytes.Contains(out, []byte("dockerd"))
	}, teatest.WithDuration(5*time.Second))

	// Move selection down once (select nginx PID 2042)
	tm.Send(tea.KeyMsg{Type: tea.KeyDown})
	time.Sleep(100 * time.Millisecond)

	// Kill selected process
	tm.Type("k")

	// Wait for kill feedback
	teatest.WaitFor(t, tm.Output(), func(out []byte) bool {
		return bytes.Contains(out, []byte("Killed PID 2042"))
	}, teatest.WithDuration(5*time.Second))

	_ = tm.Quit()
	fm := tm.FinalModel(t, teatest.WithFinalTimeout(3*time.Second))
	final, ok := fm.(Model)
	if !ok {
		t.Fatalf("final model is %T, want Model", fm)
	}
	if final.tab != TabMonitoring {
		t.Errorf("should still be on Monitoring tab, got %d", final.tab)
	}

	// Verify KillProcess was called with correct args.
	if len(src.killCalls) != 1 {
		t.Fatalf("expected 1 kill call, got %d", len(src.killCalls))
	}
	if src.killCalls[0].pid != 2042 {
		t.Errorf("kill pid = %d, want 2042", src.killCalls[0].pid)
	}
	if src.killCalls[0].signal != 9 {
		t.Errorf("kill signal = %d, want 9", src.killCalls[0].signal)
	}
}

func TestTeatestMonitoringKillError(t *testing.T) {
	src := &killRecordingSource{killErr: errors.New("operation not permitted")}
	m := New(src, "default")
	tm := teatest.NewTestModel(
		t, m,
		teatest.WithInitialTermSize(120, 40),
	)
	t.Cleanup(func() { _ = tm.Quit() })

	// Navigate to Monitoring
	tm.Type("0")
	tm.Send(tea.KeyMsg{Type: tea.KeyRight})
	tm.Send(tea.KeyMsg{Type: tea.KeyRight})

	// Wait for process list
	teatest.WaitFor(t, tm.Output(), func(out []byte) bool {
		return bytes.Contains(out, []byte("dockerd"))
	}, teatest.WithDuration(5*time.Second))

	// Kill first process (cursor is at 0, PID 1001)
	tm.Type("k")

	// Wait for error feedback
	teatest.WaitFor(t, tm.Output(), func(out []byte) bool {
		return bytes.Contains(out, []byte("failed")) ||
			bytes.Contains(out, []byte("operation not permitted"))
	}, teatest.WithDuration(5*time.Second))

	_ = tm.Quit()
	fm := tm.FinalModel(t, teatest.WithFinalTimeout(3*time.Second))
	final := fm.(Model)
	if !strings.Contains(final.monFeedback, "operation not permitted") {
		t.Errorf("feedback should contain error: %q", final.monFeedback)
	}
}

func TestTeatestMonitoringSelectionVisible(t *testing.T) {
	m := New(fakeSource{}, "default")
	tm := teatest.NewTestModel(
		t, m,
		teatest.WithInitialTermSize(120, 40),
	)
	t.Cleanup(func() { _ = tm.Quit() })

	// Navigate to Monitoring
	tm.Type("0")
	tm.Send(tea.KeyMsg{Type: tea.KeyRight})
	tm.Send(tea.KeyMsg{Type: tea.KeyRight})

	// Wait for the selection marker to appear ("> " prefix on first process)
	teatest.WaitFor(t, tm.Output(), func(out []byte) bool {
		return bytes.Contains(out, []byte("> 1001"))
	}, teatest.WithDuration(5*time.Second))

	_ = tm.Quit()
}

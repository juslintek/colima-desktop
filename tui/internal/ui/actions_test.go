package ui

import (
	"context"
	"errors"
	"io"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/action"
)

type actionRecordingSource struct {
	fakeSource
	mu          sync.Mutex
	requests    []action.Request
	unaryErr    error
	result      action.Result
	openRequest []action.Request
	stream      action.ProgressStream
	openErr     error
}

func (s *actionRecordingSource) RunAction(_ context.Context, request action.Request) (action.Result, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.requests = append(s.requests, request)
	if s.unaryErr != nil {
		return action.Result{}, s.unaryErr
	}
	return s.result, nil
}

func (s *actionRecordingSource) OpenProgress(cx context.Context, request action.Request) (action.ProgressStream, error) {
	s.mu.Lock()
	s.openRequest = append(s.openRequest, request)
	stream := s.stream
	err := s.openErr
	s.mu.Unlock()
	if stream == nil {
		stream = &contextProgressStream{context: cx, events: []*pb.ProgressEvent{{Message: "done", Progress: 1, Done: true}}}
	}
	if contextual, ok := stream.(*contextProgressStream); ok {
		contextual.context = cx
	}
	return stream, err
}

type contextProgressStream struct {
	context context.Context
	events  []*pb.ProgressEvent
	block   bool
	started chan struct{}
	once    sync.Once
}

func (s *contextProgressStream) Recv() (*pb.ProgressEvent, error) {
	if s.started != nil {
		s.once.Do(func() { close(s.started) })
	}
	if s.block {
		<-s.context.Done()
		return nil, s.context.Err()
	}
	if len(s.events) == 0 {
		return nil, io.EOF
	}
	event := s.events[0]
	s.events = s.events[1:]
	return event, nil
}

func updateKey(t *testing.T, m Model, key tea.KeyMsg) (Model, tea.Cmd) {
	t.Helper()
	next, cmd := m.Update(key)
	return next.(Model), cmd
}

func runeKey(value string) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(value)}
}

func typeRunes(t *testing.T, m Model, value string) Model {
	t.Helper()
	for _, r := range value {
		m, _ = updateKey(t, m, runeKey(string(r)))
	}
	return m
}

func executeCommand(t *testing.T, m Model, cmd tea.Cmd) (Model, tea.Cmd) {
	t.Helper()
	if cmd == nil {
		t.Fatal("expected command")
	}
	next, follow := m.Update(cmd())
	return next.(Model), follow
}

func TestContainerActionUsesSelectedIDAndActiveProfile(t *testing.T) {
	source := &actionRecordingSource{result: action.Result{Text: "started"}}
	m := New(source, "desktop-e2e")
	m.tab = TabContainers
	m.resources = []resourceItem{{ID: "ctr-one", Name: "one"}, {ID: "ctr-two", Name: "two"}}
	m.cursor = 1

	var cmd tea.Cmd
	m, cmd = updateKey(t, m, runeKey("s"))
	if m.action.phase != actionBusy {
		t.Fatalf("phase = %v, want busy", m.action.phase)
	}
	m, _ = executeCommand(t, m, cmd)
	if m.action.phase != actionSuccess {
		t.Fatalf("phase = %v, want success", m.action.phase)
	}
	if len(source.requests) != 1 {
		t.Fatalf("requests = %d", len(source.requests))
	}
	want := source.requests[0]
	if want.Kind != action.ContainerDo || want.Action != "start" || want.Profile != "desktop-e2e" || want.ID != "ctr-two" {
		t.Fatalf("unexpected request: %#v", want)
	}
}

func TestDestructiveContainerRemoveRequiresExplicitConfirmation(t *testing.T) {
	source := &actionRecordingSource{}
	m := New(source, "desktop-e2e")
	m.tab = TabContainers
	m.resources = []resourceItem{{ID: "ctr-doomed", Name: "doomed"}}

	var cmd tea.Cmd
	m, cmd = updateKey(t, m, runeKey("d"))
	if cmd != nil || m.action.phase != actionConfirm || len(source.requests) != 0 {
		t.Fatalf("remove must wait for confirmation: phase=%v calls=%d", m.action.phase, len(source.requests))
	}
	// Any key other than y/Y cannot confirm.
	m, cmd = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnter})
	if cmd != nil || len(source.requests) != 0 {
		t.Fatal("Enter must not confirm a destructive action")
	}
	m, cmd = updateKey(t, m, runeKey("y"))
	m, _ = executeCommand(t, m, cmd)
	if len(source.requests) != 1 || source.requests[0].ID != "ctr-doomed" || source.requests[0].Action != "remove" {
		t.Fatalf("unexpected remove request: %#v", source.requests)
	}
}

func TestCreateContainerPromptValidatesAndBuildsExactRequest(t *testing.T) {
	source := &actionRecordingSource{}
	m := New(source, "desktop-e2e")
	m.tab = TabContainers

	m, _ = updateKey(t, m, runeKey("n"))
	if m.action.phase != actionPrompt {
		t.Fatalf("phase = %v, want prompt", m.action.phase)
	}
	m, _ = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnter})
	if !strings.Contains(m.action.fieldError, "required") {
		t.Fatalf("empty name should fail validation: %q", m.action.fieldError)
	}
	m = typeRunes(t, m, "web")
	m, _ = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnter})
	m = typeRunes(t, m, "nginx:latest")
	var cmd tea.Cmd
	m, cmd = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnter})
	if m.action.phase != actionBusy {
		t.Fatalf("phase = %v, want busy", m.action.phase)
	}
	m, _ = executeCommand(t, m, cmd)
	request := source.requests[0]
	if request.Kind != action.ContainerNew || request.Profile != "desktop-e2e" || request.Name != "web" || request.Target != "nginx:latest" {
		t.Fatalf("unexpected create request: %#v", request)
	}
}

func TestUnaryErrorIsVisibleAndNotSuccess(t *testing.T) {
	source := &actionRecordingSource{unaryErr: errors.New("permission denied")}
	m := New(source, "desktop-e2e")
	m.tab = TabKubernetes
	m, cmd := updateKey(t, m, runeKey("s"))
	m, _ = executeCommand(t, m, cmd)
	if m.action.phase != actionFailure || !strings.Contains(m.View(), "permission denied") {
		t.Fatalf("daemon error not visible: phase=%v view=%s", m.action.phase, m.View())
	}
}

func TestStreamingActionShowsProgressAndCompletion(t *testing.T) {
	source := &actionRecordingSource{stream: &contextProgressStream{events: []*pb.ProgressEvent{
		{Stage: "download", Message: "half", Progress: .5},
		{Stage: "ready", Message: "pulled", Progress: 1, Done: true},
	}}}
	m := New(source, "desktop-e2e")
	m.tab = TabImages
	m, _ = updateKey(t, m, runeKey("p"))
	m = typeRunes(t, m, "alpine:latest")
	m, openCmd := updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnter})
	m, recvCmd := executeCommand(t, m, openCmd)
	m, recvCmd = executeCommand(t, m, recvCmd)
	if m.action.phase != actionBusy || m.action.progress != .5 || !strings.Contains(m.View(), "half") {
		t.Fatalf("intermediate progress not rendered: phase=%v progress=%v", m.action.phase, m.action.progress)
	}
	m, _ = executeCommand(t, m, recvCmd)
	if m.action.phase != actionSuccess || len(source.openRequest) != 1 || source.openRequest[0].Name != "alpine:latest" {
		t.Fatalf("stream did not complete with exact request: phase=%v requests=%#v", m.action.phase, source.openRequest)
	}
	if !strings.Contains(m.action.output, "half") || !strings.Contains(m.action.output, "pulled") {
		t.Fatalf("streamed output was not retained: %q", m.action.output)
	}
}

func TestTerminalProgressErrorIsNeverSuccess(t *testing.T) {
	source := &actionRecordingSource{stream: &contextProgressStream{events: []*pb.ProgressEvent{{Done: true, Progress: 1, Error: "registry denied"}}}}
	m := New(source, "desktop-e2e")
	m.tab = TabDashboard
	m, openCmd := updateKey(t, m, runeKey("s"))
	m, recvCmd := executeCommand(t, m, openCmd)
	m, _ = executeCommand(t, m, recvCmd)
	if m.action.phase != actionFailure || !strings.Contains(m.action.message, "registry denied") {
		t.Fatalf("terminal progress error became success: phase=%v message=%q", m.action.phase, m.action.message)
	}
}

func TestEscapeCancelsPromptWithoutRPC(t *testing.T) {
	source := &actionRecordingSource{}
	m := New(source, "desktop-e2e")
	m.tab = TabContainers
	m, _ = updateKey(t, m, runeKey("n"))
	m = typeRunes(t, m, "temporary")
	m, _ = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEsc})
	if m.action.phase != actionIdle || len(source.requests) != 0 {
		t.Fatalf("Esc did not cancel prompt safely: phase=%v requests=%d", m.action.phase, len(source.requests))
	}
}

func TestLargeActionOutputIsBoundedAndScrollable(t *testing.T) {
	m := New(fakeSource{}, "desktop-e2e")
	m.height = 20
	lines := make([]string, 30)
	for i := range lines {
		lines[i] = "line-" + strconv.Itoa(i+1)
	}
	m.action = actionState{phase: actionSuccess, spec: actionSpec{title: "Inspect"}, message: "Completed", output: strings.Join(lines, "\n")}
	view := m.View()
	if !strings.Contains(view, "line-1") || strings.Contains(view, "line-30") {
		t.Fatalf("initial output viewport is not bounded at the beginning:\n%s", view)
	}
	m, _ = updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnd})
	view = m.View()
	if !strings.Contains(view, "line-30") || strings.Contains(view, "line-1\n") {
		t.Fatalf("End did not scroll to bounded output tail:\n%s", view)
	}
}

func TestNavigationCancelsBusyStreamContext(t *testing.T) {
	started := make(chan struct{})
	stream := &contextProgressStream{block: true, started: started}
	source := &actionRecordingSource{stream: stream}
	m := New(source, "desktop-e2e")
	m.tab = TabDashboard
	m, openCmd := updateKey(t, m, runeKey("s"))
	m, recvCmd := executeCommand(t, m, openCmd)
	done := make(chan tea.Msg, 1)
	go func() { done <- recvCmd() }()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("stream Recv did not start")
	}
	m, _ = updateKey(t, m, tea.KeyMsg{Type: tea.KeyRight})
	if m.tab != TabContainers || m.action.phase != actionIdle {
		t.Fatalf("navigation did not leave busy action: tab=%d phase=%v", m.tab, m.action.phase)
	}
	select {
	case message := <-done:
		progress := message.(actionProgressMsg)
		if !errors.Is(progress.err, context.Canceled) {
			t.Fatalf("Recv error = %v, want context canceled", progress.err)
		}
	case <-time.After(time.Second):
		t.Fatal("navigation did not cancel streaming context")
	}
}

func TestProfileSelectChangesScopeAndRefreshes(t *testing.T) {
	source := &actionRecordingSource{}
	m := New(source, "default")
	m.tab = TabProfiles
	m.resources = []resourceItem{{ID: "default", Name: "default"}, {ID: "desktop-e2e", Name: "desktop-e2e"}}
	m.cursor = 1
	m.config = &pb.ColimaConfig{Cpu: 99}
	m.monProcesses = []*pb.ProcessInfo{{Pid: 999}}
	m, cmd := updateKey(t, m, tea.KeyMsg{Type: tea.KeyEnter})
	if cmd == nil || m.profile != "desktop-e2e" || m.action.phase != actionSuccess {
		t.Fatalf("profile was not selected and refreshed: profile=%q phase=%v", m.profile, m.action.phase)
	}
	if m.config != nil || len(m.monProcesses) != 0 {
		t.Fatal("profile switch retained stale profile-scoped config or process data")
	}
	status := m.loadStatus().(statusMsg)
	if !strings.Contains(status.text, "profile=desktop-e2e") {
		t.Fatalf("status did not use active profile: %q", status.text)
	}
}

func TestConfigFormUsesTypedValuesAndPreservesUneditedFields(t *testing.T) {
	base := &pb.ColimaConfig{
		Cpu: 4, Memory: 8, Disk: 100, Arch: "aarch64", VmType: "vz", Runtime: "docker", MountType: "virtiofs",
		Env: map[string]string{"TOKEN_SOURCE": "environment"}, Mounts: []*pb.Mount{{Location: "/Volumes/Projects", MountPoint: "/projects", Writable: true}},
		Kubernetes: &pb.KubernetesConfig{Enabled: false, Version: "v1.30", Port: 0},
	}
	spec := configSpec("Edit", action.ConfigSet, "desktop-e2e", base)
	values := make(map[string]string)
	for _, field := range spec.fields {
		values[field.name] = field.value
	}
	values["cpu"] = "6"
	values["memory"] = "12.5"
	values["runtime"] = "containerd"
	values["kube_enabled"] = "true"
	request, err := spec.build(values)
	if err != nil {
		t.Fatal(err)
	}
	if request.Config.GetCpu() != 6 || request.Config.GetMemory() != 12.5 || request.Config.GetRuntime() != "containerd" || !request.Config.GetKubernetes().GetEnabled() {
		t.Fatalf("typed edits were not applied: %v", request.Config)
	}
	if request.Config.GetEnv()["TOKEN_SOURCE"] != "environment" || len(request.Config.GetMounts()) != 1 {
		t.Fatalf("uneditable typed fields were not preserved: %v", request.Config)
	}
	if base.GetCpu() != 4 || base.GetRuntime() != "docker" {
		t.Fatal("editing mutated the loaded config before save")
	}
}

func TestConfigViewToggleHasARealHandler(t *testing.T) {
	m := New(fakeSource{}, "desktop-e2e")
	m.tab = TabConfig
	m.config = &pb.ColimaConfig{Cpu: 2, Runtime: "docker"}
	m.template = &pb.ColimaConfig{Cpu: 8, Runtime: "containerd"}
	m.body = renderSelectedConfig(m.config, m.template, false)
	m, cmd := updateKey(t, m, runeKey("v"))
	if cmd != nil || !m.showTemplate || !strings.Contains(m.body, "Global configuration template") || !strings.Contains(m.body, "CPU=8") {
		t.Fatalf("v hint has no working toggle: showTemplate=%v body=%q", m.showTemplate, m.body)
	}
}

func TestEveryDisplayedActionKeyHasHandler(t *testing.T) {
	m := New(fakeSource{}, "desktop-e2e")
	m.resources = []resourceItem{{ID: "resource-id", Name: "resource-name"}}
	m.config = &pb.ColimaConfig{Cpu: 4, Memory: 8, Disk: 100, Arch: "aarch64", VmType: "vz", Runtime: "docker", MountType: "virtiofs", Kubernetes: &pb.KubernetesConfig{}}
	m.template = cloneConfig(m.config)
	m.monProcesses = []*pb.ProcessInfo{{Pid: 99, Command: "worker"}}
	tests := map[int][]string{
		TabDashboard:  {"s", "x", "R", "D", "U", "P", "H"},
		TabContainers: {"n", "s", "x", "R", "k", "p", "u", "d", "e", "g", "i", "t", "a", "c", "P"},
		TabImages:     {"p", "u", "d", "t", "s", "H", "i", "P"},
		TabVolumes:    {"n", "d", "i", "P"},
		TabNetworks:   {"n", "d", "i", "c", "x", "P"},
		TabKubernetes: {"s", "x", "R", "e"},
		TabConfig:     {"e", "t"},
		TabRuntime:    {"d", "c", "i", "u"},
		TabAI:         {"s", "n", "v", "x"},
		TabProfiles:   {"n", "d", "c"},
		TabMonitoring: {"k"},
	}
	for tab, keys := range tests {
		m.tab = tab
		for _, key := range keys {
			if _, err, handled := m.actionForKey(key); !handled || err != nil {
				t.Errorf("tab %s displayed key %q has no usable handler: handled=%v err=%v", Tabs[tab], key, handled, err)
			}
		}
	}
}

func TestEveryDestructiveActionSpecRequiresConfirmation(t *testing.T) {
	m := New(fakeSource{}, "desktop-e2e")
	m.resources = []resourceItem{{ID: "resource-id", Name: "resource-name"}}
	m.monProcesses = []*pb.ProcessInfo{{Pid: 99, Command: "worker"}}
	tests := []struct {
		tab int
		key string
	}{
		{TabDashboard, "D"}, {TabDashboard, "P"},
		{TabContainers, "k"}, {TabContainers, "d"}, {TabContainers, "P"},
		{TabImages, "d"}, {TabImages, "P"},
		{TabVolumes, "d"}, {TabVolumes, "P"},
		{TabNetworks, "d"}, {TabNetworks, "x"}, {TabNetworks, "P"},
		{TabKubernetes, "R"}, {TabProfiles, "d"},
		{TabRuntime, "d"}, {TabRuntime, "c"}, {TabRuntime, "i"},
		{TabMonitoring, "k"},
	}
	for _, test := range tests {
		m.tab = test.tab
		spec, err, handled := m.actionForKey(test.key)
		if err != nil || !handled {
			t.Errorf("%s %q unavailable: handled=%v err=%v", Tabs[test.tab], test.key, handled, err)
			continue
		}
		if !spec.destructive || strings.TrimSpace(spec.confirm) == "" {
			t.Errorf("%s %q lacks explicit confirmation", Tabs[test.tab], test.key)
		}
	}
}

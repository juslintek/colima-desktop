// dispatch_property_test.go — teatest-driven DETERMINISTIC end-to-end dispatch
// property tests for the Bubble Tea TUI (task 4.5).
//
// These tests drive a real tea.Program loop (via teatest, no live daemon) with
// simulated key input and assert on rendered output / final model state. They
// cover the design's TUI dispatch properties:
//
//   Property 12 — Action-to-RPC dispatch mapping: each advertised action invokes
//                 exactly its mapped RPC, scoped to the active profile.
//   Property 13 — Destructive-action confirmation gate: no RPC unless confirmed;
//                 a dismissed confirmation issues none.
//   Property 14 — Bounded streamed output: displayed lines never exceed the
//                 configured bound.
//   Property 15 — Error rendering with context: an errored RPC yields rendered
//                 state containing the contextual (operation-named) error.
//
// Every property runs a meaningful number of randomized-but-seeded (deterministic)
// iterations (>=100). There is no wall-clock/network flakiness: a fully in-memory
// fake source is used, gating is condition-based (teatest.WaitFor), and no
// time.Sleep is used for correctness.
//
// This is the program-level harness ON TOP of the task-4.4 unit tests
// (action_safety_test.go) and the client-level exact-RPC tests
// (internal/client/actions_test.go); it does not duplicate them.
package ui

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"strings"
	"sync"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/x/exp/teatest"
	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/action"
)

// Iteration counts — each property runs the required minimum of 100 randomized
// iterations (kept tight so the teatest suite stays fast on a loaded host).
const (
	p12Iterations = 100
	p13Iterations = 100
	p14Iterations = 100
	p15Iterations = 100
)

// ─── synchronized recording data source ──────────────────────────────────────

// dispatchSource is a fully deterministic DataSource: it embeds fakeSource for
// the read/list methods and records the exact action.Request the model
// dispatches through RunAction (unary) and OpenProgress (stream). The recorded
// logs are read only AFTER FinalModel returns (program goroutine dead), so reads
// are race-free; the mutex additionally guarantees memory visibility.
type dispatchSource struct {
	fakeSource
	mu            sync.Mutex
	unary         []action.Request
	streamReqs    []action.Request
	unaryErr      error
	unaryText     string
	openErr       error
	streamEvents  []*pb.ProgressEvent
	streamRecvErr error
}

func newDispatchSource() *dispatchSource {
	return &dispatchSource{
		unaryText:    "dispatched-ok",
		streamEvents: []*pb.ProgressEvent{{Stage: "done", Message: "completed", Progress: 1, Done: true}},
	}
}

func (s *dispatchSource) RunAction(_ context.Context, req action.Request) (action.Result, error) {
	s.mu.Lock()
	s.unary = append(s.unary, req)
	err := s.unaryErr
	text := s.unaryText
	s.mu.Unlock()
	if err != nil {
		return action.Result{}, err
	}
	return action.Result{Text: text}, nil
}

func (s *dispatchSource) OpenProgress(_ context.Context, req action.Request) (action.ProgressStream, error) {
	s.mu.Lock()
	s.streamReqs = append(s.streamReqs, req)
	err := s.openErr
	events := s.streamEvents
	recvErr := s.streamRecvErr
	s.mu.Unlock()
	if err != nil {
		return nil, err
	}
	return &sliceProgressStream{events: events, recvErr: recvErr}, nil
}

func (s *dispatchSource) unarySnapshot() []action.Request {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]action.Request(nil), s.unary...)
}

func (s *dispatchSource) streamSnapshot() []action.Request {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]action.Request(nil), s.streamReqs...)
}

// sliceProgressStream replays a fixed event slice then returns recvErr (or io.EOF).
// The model consumes it single-threaded (one Recv per cmd), so it needs no lock.
type sliceProgressStream struct {
	events  []*pb.ProgressEvent
	index   int
	recvErr error
}

func (s *sliceProgressStream) Recv() (*pb.ProgressEvent, error) {
	if s.index < len(s.events) {
		event := s.events[s.index]
		s.index++
		return event, nil
	}
	if s.recvErr != nil {
		return nil, s.recvErr
	}
	return nil, io.EOF
}

// ─── teatest helpers ─────────────────────────────────────────────────────────

func sendRuneKey(tm *teatest.TestModel, s string) {
	tm.Send(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)})
}

func sendEnterKey(tm *teatest.TestModel) { tm.Send(tea.KeyMsg{Type: tea.KeyEnter}) }
func sendEscKey(tm *teatest.TestModel)   { tm.Send(tea.KeyMsg{Type: tea.KeyEsc}) }

// waitTimeout is a safety cap, not a correctness knob: waits return as soon as
// the marker appears, so nothing depends on wall-clock timing. A healthy
// in-process program renders in well under this; the cap only bounds a
// genuinely stuck/killed program, which the per-iteration retry re-attempts
// with a fresh program. It is kept modest so a transient miss recovers quickly.
const waitTimeout = 8 * time.Second

// outputTail accumulates the full cumulative terminal output of one teatest
// program (drained by a single background goroutine) so sequential markers can
// each be found without consuming the stream.
type outputTail struct {
	mu  sync.Mutex
	buf []byte
}

func (o *outputTail) contains(substr string) bool {
	o.mu.Lock()
	defer o.mu.Unlock()
	return bytes.Contains(o.buf, []byte(substr))
}

func drainOutput(tm *teatest.TestModel) *outputTail {
	o := &outputTail{}
	go func() {
		reader := tm.Output()
		chunk := make([]byte, 4096)
		for {
			n, err := reader.Read(chunk)
			if n > 0 {
				o.mu.Lock()
				o.buf = append(o.buf, chunk[:n]...)
				o.mu.Unlock()
			}
			if err != nil {
				return // program ended (EOF) or output closed on Quit
			}
		}
	}()
	return o
}

// awaitContains polls the cumulative output until substr appears or the cap
// elapses. It NEVER fails the test (returns a bool), so the caller can retry a
// transient render hiccup with a fresh program.
func awaitContains(o *outputTail, substr string) bool {
	deadline := time.Now().Add(waitTimeout)
	for {
		if o.contains(substr) {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(15 * time.Millisecond)
	}
}

func dispatchFinalModel(t *testing.T, tm *teatest.TestModel) Model {
	t.Helper()
	_ = tm.Quit()
	fm := tm.FinalModel(t, teatest.WithFinalTimeout(waitTimeout))
	m, ok := fm.(Model)
	if !ok {
		t.Fatalf("final model is %T, want ui.Model", fm)
	}
	return m
}

// withRetry runs one iteration's driver up to maxAttempts times. A returned
// error is treated as a transient (host-starved) teatest render hiccup and
// retried with a fresh program; a genuine logic failure inside the driver uses
// t.Fatalf directly (aborting immediately, no bogus retry). Only if every
// attempt hits a transient render failure does the iteration fail.
func withRetry(t *testing.T, name string, drive func() error) {
	t.Helper()
	const maxAttempts = 3
	var lastErr error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		if lastErr = drive(); lastErr == nil {
			return
		}
	}
	t.Fatalf("[%s] teatest program did not render after %d attempts: %v", name, maxAttempts, lastErr)
}

// tabReadyMarker is a stable substring proving the given tab's content (and, for
// selectable tabs, its resources) has been loaded and rendered by the fake source.
func tabReadyMarker(tab int) string {
	switch tab {
	case TabDashboard:
		return "Colima Desktop"
	case TabContainers:
		return "container-web"
	case TabImages:
		return "nginx:latest"
	case TabVolumes:
		return "mydata"
	case TabNetworks:
		return "bridge"
	case TabKubernetes:
		return "Kubernetes:"
	case TabConfig:
		return "Profile configuration"
	case TabRuntime:
		return "Runtime:"
	case TabAI:
		return "Backend: colima model"
	case TabProfiles:
		return "default"
	case TabMonitoring:
		return "dockerd"
	default:
		return ""
	}
}

// randomProfile generates a seeded, non-empty, whitespace-free profile name that
// is never "default" (the fake Profiles resource), so profile-scope assertions
// are unambiguous.
func randomProfile(rng *rand.Rand) string {
	const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
	n := 4 + rng.Intn(6)
	var b strings.Builder
	b.WriteString("e2e-")
	for i := 0; i < n; i++ {
		b.WriteByte(alphabet[rng.Intn(len(alphabet))])
	}
	return b.String()
}

// ─── Property 12: action-to-RPC dispatch mapping ─────────────────────────────

type dispatchCase struct {
	name     string
	tab      int
	trigger  string   // the key that triggers the action
	fields   []string // prompt inputs in order; "" = accept the prefilled value (Enter only); nil = not a prompt
	confirm  bool     // destructive → an explicit "y" confirmation is required
	stream   bool     // recorded via OpenProgress (vs RunAction)
	wantKind action.Kind
	verify   func(t *testing.T, name string, r action.Request)
}

func fieldCheck(check func(action.Request) string) func(*testing.T, string, action.Request) {
	return func(t *testing.T, name string, r action.Request) {
		t.Helper()
		if msg := check(r); msg != "" {
			t.Fatalf("[%s] %s (req=%#v)", name, msg, r)
		}
	}
}

// dispatchCases enumerates essentially every advertised TUI action (all tabs,
// direct + destructive + prompt-based) except the multi-field config/template
// forms and profile-select (which issues no RPC). The fake source loads exactly
// one resource per selectable tab (container "container-web"/"web", image
// "nginx:latest"/"sha256:abc", volume "mydata", network "bridge", profile
// "default") and two monitoring processes (dockerd pid 1001, nginx pid 2042).
func dispatchCases() []dispatchCase {
	containerDo := func(act string) func(*testing.T, string, action.Request) {
		return fieldCheck(func(r action.Request) string {
			if r.Action != act {
				return fmt.Sprintf("Action=%q want %q", r.Action, act)
			}
			if r.ID != "container-web" {
				return fmt.Sprintf("ID=%q want container-web", r.ID)
			}
			return ""
		})
	}
	wantID := func(id string) func(*testing.T, string, action.Request) {
		return fieldCheck(func(r action.Request) string {
			if r.ID != id {
				return fmt.Sprintf("ID=%q want %q", r.ID, id)
			}
			return ""
		})
	}
	wantName := func(name string) func(*testing.T, string, action.Request) {
		return fieldCheck(func(r action.Request) string {
			if r.Name != name {
				return fmt.Sprintf("Name=%q want %q", r.Name, name)
			}
			return ""
		})
	}

	return []dispatchCase{
		// ── VM lifecycle (Dashboard) ──
		{name: "vm start", tab: TabDashboard, trigger: "s", stream: true, wantKind: action.VMStart},
		{name: "vm stop", tab: TabDashboard, trigger: "x", wantKind: action.VMStop},
		{name: "vm restart", tab: TabDashboard, trigger: "R", stream: true, wantKind: action.VMRestart},
		{name: "vm delete", tab: TabDashboard, trigger: "D", confirm: true, wantKind: action.VMDelete,
			verify: fieldCheck(func(r action.Request) string {
				if !r.Data {
					return "Data=false want true"
				}
				return ""
			})},
		{name: "vm update", tab: TabDashboard, trigger: "U", wantKind: action.VMUpdate},
		{name: "vm prune", tab: TabDashboard, trigger: "P", confirm: true, wantKind: action.VMPrune,
			verify: fieldCheck(func(r action.Request) string {
				if !r.All {
					return "All=false want true"
				}
				return ""
			})},
		{name: "vm ssh-config", tab: TabDashboard, trigger: "H", wantKind: action.VMSSHConfig},

		// ── Containers ──
		{name: "container create", tab: TabContainers, trigger: "n", fields: []string{"e2e-web", "nginx:latest"}, wantKind: action.ContainerNew,
			verify: fieldCheck(func(r action.Request) string {
				if r.Name != "e2e-web" {
					return fmt.Sprintf("Name=%q want e2e-web", r.Name)
				}
				if r.Target != "nginx:latest" {
					return fmt.Sprintf("Target=%q want nginx:latest", r.Target)
				}
				return ""
			})},
		{name: "container start", tab: TabContainers, trigger: "s", wantKind: action.ContainerDo, verify: containerDo("start")},
		{name: "container stop", tab: TabContainers, trigger: "x", wantKind: action.ContainerDo, verify: containerDo("stop")},
		{name: "container restart", tab: TabContainers, trigger: "R", wantKind: action.ContainerDo, verify: containerDo("restart")},
		{name: "container kill", tab: TabContainers, trigger: "k", confirm: true, wantKind: action.ContainerDo, verify: containerDo("kill")},
		{name: "container pause", tab: TabContainers, trigger: "p", wantKind: action.ContainerDo, verify: containerDo("pause")},
		{name: "container unpause", tab: TabContainers, trigger: "u", wantKind: action.ContainerDo, verify: containerDo("unpause")},
		{name: "container remove", tab: TabContainers, trigger: "d", confirm: true, wantKind: action.ContainerDo, verify: containerDo("remove")},
		{name: "container rename", tab: TabContainers, trigger: "e", fields: []string{""}, wantKind: action.ContainerName,
			verify: fieldCheck(func(r action.Request) string {
				if r.ID != "container-web" {
					return fmt.Sprintf("ID=%q want container-web", r.ID)
				}
				if r.NewName != "web" {
					return fmt.Sprintf("NewName=%q want web (prefilled)", r.NewName)
				}
				return ""
			})},
		{name: "container logs", tab: TabContainers, trigger: "g", wantKind: action.ContainerLogs, verify: wantID("container-web")},
		{name: "container inspect", tab: TabContainers, trigger: "i", wantKind: action.ContainerInfo, verify: wantID("container-web")},
		{name: "container top", tab: TabContainers, trigger: "t", wantKind: action.ContainerTop, verify: wantID("container-web")},
		{name: "container stats", tab: TabContainers, trigger: "a", wantKind: action.ContainerStat, verify: wantID("container-web")},
		{name: "container changes", tab: TabContainers, trigger: "c", wantKind: action.ContainerDiff, verify: wantID("container-web")},
		{name: "container prune", tab: TabContainers, trigger: "P", confirm: true, wantKind: action.ContainerPrune},

		// ── Images ──
		{name: "image pull", tab: TabImages, trigger: "p", fields: []string{"alpine:latest"}, stream: true, wantKind: action.ImagePull, verify: wantName("alpine:latest")},
		{name: "image push", tab: TabImages, trigger: "u", stream: true, wantKind: action.ImagePush, verify: wantName("nginx:latest")},
		{name: "image remove", tab: TabImages, trigger: "d", confirm: true, wantKind: action.ImageRemove, verify: wantID("sha256:abc")},
		{name: "image tag", tab: TabImages, trigger: "t", fields: []string{"registry/app", ""}, wantKind: action.ImageTag,
			verify: fieldCheck(func(r action.Request) string {
				if r.Name != "nginx:latest" {
					return fmt.Sprintf("Name=%q want nginx:latest", r.Name)
				}
				if r.Repository != "registry/app" {
					return fmt.Sprintf("Repository=%q want registry/app", r.Repository)
				}
				if r.Tag != "latest" {
					return fmt.Sprintf("Tag=%q want latest (prefilled)", r.Tag)
				}
				return ""
			})},
		{name: "image search", tab: TabImages, trigger: "s", fields: []string{"alpine"}, wantKind: action.ImageSearch,
			verify: fieldCheck(func(r action.Request) string {
				if r.Term != "alpine" {
					return fmt.Sprintf("Term=%q want alpine", r.Term)
				}
				return ""
			})},
		{name: "image history", tab: TabImages, trigger: "H", wantKind: action.ImageHistory, verify: wantName("nginx:latest")},
		{name: "image inspect", tab: TabImages, trigger: "i", wantKind: action.ImageInspect, verify: wantName("nginx:latest")},
		{name: "image prune", tab: TabImages, trigger: "P", confirm: true, wantKind: action.ImagePrune},

		// ── Volumes ──
		{name: "volume create", tab: TabVolumes, trigger: "n", fields: []string{"e2e-vol"}, wantKind: action.VolumeCreate, verify: wantName("e2e-vol")},
		{name: "volume remove", tab: TabVolumes, trigger: "d", confirm: true, wantKind: action.VolumeRemove, verify: wantName("mydata")},
		{name: "volume inspect", tab: TabVolumes, trigger: "i", wantKind: action.VolumeInspect, verify: wantName("mydata")},
		{name: "volume prune", tab: TabVolumes, trigger: "P", confirm: true, wantKind: action.VolumePrune},

		// ── Networks ──
		{name: "network create", tab: TabNetworks, trigger: "n", fields: []string{"e2e-net"}, wantKind: action.NetworkCreate, verify: wantName("e2e-net")},
		{name: "network remove", tab: TabNetworks, trigger: "d", confirm: true, wantKind: action.NetworkRemove, verify: wantID("bridge")},
		{name: "network inspect", tab: TabNetworks, trigger: "i", wantKind: action.NetworkInspect, verify: wantID("bridge")},
		{name: "network connect", tab: TabNetworks, trigger: "c", fields: []string{"ctr-x"}, wantKind: action.NetworkConnect,
			verify: fieldCheck(func(r action.Request) string {
				if r.ID != "bridge" {
					return fmt.Sprintf("ID=%q want bridge", r.ID)
				}
				if r.ContainerID != "ctr-x" {
					return fmt.Sprintf("ContainerID=%q want ctr-x", r.ContainerID)
				}
				return ""
			})},
		{name: "network disconnect", tab: TabNetworks, trigger: "x", fields: []string{"ctr-x"}, confirm: true, wantKind: action.NetworkDisconnect,
			verify: fieldCheck(func(r action.Request) string {
				if r.ID != "bridge" {
					return fmt.Sprintf("ID=%q want bridge", r.ID)
				}
				if r.ContainerID != "ctr-x" {
					return fmt.Sprintf("ContainerID=%q want ctr-x", r.ContainerID)
				}
				return ""
			})},
		{name: "network prune", tab: TabNetworks, trigger: "P", confirm: true, wantKind: action.NetworkPrune},

		// ── Kubernetes ──
		{name: "kubernetes start", tab: TabKubernetes, trigger: "s", wantKind: action.KubeStart},
		{name: "kubernetes stop", tab: TabKubernetes, trigger: "x", wantKind: action.KubeStop},
		{name: "kubernetes reset", tab: TabKubernetes, trigger: "R", confirm: true, wantKind: action.KubeReset},
		{name: "kubernetes exec", tab: TabKubernetes, trigger: "e", fields: []string{""}, wantKind: action.KubeExec,
			verify: fieldCheck(func(r action.Request) string {
				if r.Command != "get pods -A" {
					return fmt.Sprintf("Command=%q want 'get pods -A' (prefilled)", r.Command)
				}
				return ""
			})},

		// ── Runtime ──
		{name: "runtime update", tab: TabRuntime, trigger: "u", wantKind: action.RuntimeUpdate},
		{name: "runtime switch docker", tab: TabRuntime, trigger: "d", confirm: true, wantKind: action.RuntimeSwitch,
			verify: fieldCheck(func(r action.Request) string {
				if r.Runtime != "docker" {
					return fmt.Sprintf("Runtime=%q want docker", r.Runtime)
				}
				return ""
			})},
		{name: "runtime switch containerd", tab: TabRuntime, trigger: "c", confirm: true, wantKind: action.RuntimeSwitch,
			verify: fieldCheck(func(r action.Request) string {
				if r.Runtime != "containerd" {
					return fmt.Sprintf("Runtime=%q want containerd", r.Runtime)
				}
				return ""
			})},
		{name: "runtime switch incus", tab: TabRuntime, trigger: "i", confirm: true, wantKind: action.RuntimeSwitch,
			verify: fieldCheck(func(r action.Request) string {
				if r.Runtime != "incus" {
					return fmt.Sprintf("Runtime=%q want incus", r.Runtime)
				}
				return ""
			})},

		// ── AI models ──
		{name: "model setup", tab: TabAI, trigger: "s", fields: []string{""}, stream: true, wantKind: action.ModelSetup,
			verify: fieldCheck(func(r action.Request) string {
				if r.Runner != "docker" {
					return fmt.Sprintf("Runner=%q want docker (prefilled)", r.Runner)
				}
				return ""
			})},
		{name: "model run", tab: TabAI, trigger: "n", fields: []string{"llama", "", ""}, stream: true, wantKind: action.ModelRun,
			verify: fieldCheck(func(r action.Request) string {
				if r.Model != "llama" {
					return fmt.Sprintf("Model=%q want llama", r.Model)
				}
				if r.Runner != "docker" {
					return fmt.Sprintf("Runner=%q want docker (prefilled)", r.Runner)
				}
				return ""
			})},
		{name: "model serve", tab: TabAI, trigger: "v", fields: []string{"llama", "", ""}, wantKind: action.ModelServe,
			verify: fieldCheck(func(r action.Request) string {
				if r.Model != "llama" {
					return fmt.Sprintf("Model=%q want llama", r.Model)
				}
				if r.Port != 8080 {
					return fmt.Sprintf("Port=%d want 8080 (prefilled)", r.Port)
				}
				return ""
			})},
		{name: "model stop", tab: TabAI, trigger: "x", wantKind: action.ModelStop},

		// ── Profiles ──
		{name: "profile create", tab: TabProfiles, trigger: "n", fields: []string{"e2e-prof"}, wantKind: action.ProfileCreate, verify: wantName("e2e-prof")},
		{name: "profile delete", tab: TabProfiles, trigger: "d", confirm: true, wantKind: action.ProfileDelete,
			verify: fieldCheck(func(r action.Request) string {
				if r.Name != "default" {
					return fmt.Sprintf("Name=%q want default (selected)", r.Name)
				}
				if !r.Data {
					return "Data=false want true"
				}
				return ""
			})},
		{name: "profile clone", tab: TabProfiles, trigger: "c", fields: []string{"e2e-clone"}, wantKind: action.ProfileClone,
			verify: fieldCheck(func(r action.Request) string {
				if r.Source != "default" {
					return fmt.Sprintf("Source=%q want default (selected)", r.Source)
				}
				if r.Target != "e2e-clone" {
					return fmt.Sprintf("Target=%q want e2e-clone", r.Target)
				}
				return ""
			})},

		// ── Monitoring ──
		{name: "process kill", tab: TabMonitoring, trigger: "k", confirm: true, wantKind: action.ProcessKill,
			verify: fieldCheck(func(r action.Request) string {
				if r.PID != 1001 {
					return fmt.Sprintf("PID=%d want 1001 (selected dockerd)", r.PID)
				}
				if r.Signal != 9 {
					return fmt.Sprintf("Signal=%d want 9", r.Signal)
				}
				return ""
			})},
	}
}

// driveDispatch drives one action end-to-end. It returns an error for a
// transient render failure (retryable) and uses t.Fatalf for a genuine
// dispatch-mapping mismatch (deterministic — not retried).
func driveDispatch(t *testing.T, c dispatchCase, profile string) error {
	src := newDispatchSource()
	m := New(src, profile)
	m.tab = c.tab
	tm := teatest.NewTestModel(t, m, teatest.WithInitialTermSize(200, 50))
	out := drainOutput(tm)

	if !awaitContains(out, tabReadyMarker(c.tab)) {
		_ = tm.Quit()
		return fmt.Errorf("tab %d content did not render", c.tab)
	}
	sendRuneKey(tm, c.trigger)

	if c.fields != nil {
		if !awaitContains(out, "Step 1/") {
			_ = tm.Quit()
			return errors.New("prompt did not render")
		}
		for _, f := range c.fields {
			if f != "" {
				sendRuneKey(tm, f)
			}
			sendEnterKey(tm)
		}
	}
	if c.confirm {
		if !awaitContains(out, "Confirmation required") {
			_ = tm.Quit()
			return errors.New("confirmation gate did not render")
		}
		sendRuneKey(tm, "y")
	}

	if !awaitContains(out, "Success:") {
		_ = tm.Quit()
		return errors.New("success state did not render")
	}
	fm := dispatchFinalModel(t, tm)

	if fm.action.phase != actionSuccess {
		t.Fatalf("[%s] final phase = %v, want success", c.name, fm.action.phase)
	}

	var reqs []action.Request
	var otherChannel int
	if c.stream {
		reqs = src.streamSnapshot()
		otherChannel = len(src.unarySnapshot())
	} else {
		reqs = src.unarySnapshot()
		otherChannel = len(src.streamSnapshot())
	}
	if len(reqs) != 1 {
		t.Fatalf("[%s] dispatched %d matching requests, want exactly 1 (stream=%v profile=%q)", c.name, len(reqs), c.stream, profile)
	}
	if otherChannel != 0 {
		t.Fatalf("[%s] dispatched %d requests on the wrong RPC channel (stream=%v)", c.name, otherChannel, c.stream)
	}
	r := reqs[0]
	if r.Kind != c.wantKind {
		t.Fatalf("[%s] dispatched Kind=%q, want %q", c.name, r.Kind, c.wantKind)
	}
	if r.Profile != profile {
		t.Fatalf("[%s] dispatched Profile=%q, want active profile %q", c.name, r.Profile, profile)
	}
	if c.verify != nil {
		c.verify(t, c.name, r)
	}
	return nil
}

func TestProperty12ActionDispatchMapping(t *testing.T) {
	// Feature: cross-platform-live-verification, Property 12: Action-to-RPC dispatch mapping
	const seed = 0xC012
	rng := rand.New(rand.NewSource(seed))
	cases := dispatchCases()
	t.Logf("Feature: cross-platform-live-verification, Property 12 — seed=%#x cases=%d iterations=%d", seed, len(cases), p12Iterations)
	// Each iteration runs in its own subtest so teatest tears the program down
	// immediately (bounding live programs per iteration). Subtests are
	// sequential, so the shared seeded RNG stays deterministic.
	for i := 0; i < p12Iterations; i++ {
		c := cases[rng.Intn(len(cases))]
		profile := randomProfile(rng)
		t.Run(fmt.Sprintf("iter%03d-%s", i, c.name), func(t *testing.T) {
			withRetry(t, c.name, func() error { return driveDispatch(t, c, profile) })
		})
	}
}

// ─── Property 13: destructive-action confirmation gate ───────────────────────

// destructiveCases are the direct (non-prompt) destructive actions. Reaching the
// "Confirmation required" render proves launchAction has NOT run (the confirm
// phase issues no cmd), so no RPC was fired before confirmation. All are unary.
func destructiveCases() []dispatchCase {
	return []dispatchCase{
		{name: "vm delete", tab: TabDashboard, trigger: "D", wantKind: action.VMDelete},
		{name: "vm prune", tab: TabDashboard, trigger: "P", wantKind: action.VMPrune},
		{name: "container kill", tab: TabContainers, trigger: "k", wantKind: action.ContainerDo},
		{name: "container remove", tab: TabContainers, trigger: "d", wantKind: action.ContainerDo},
		{name: "container prune", tab: TabContainers, trigger: "P", wantKind: action.ContainerPrune},
		{name: "image remove", tab: TabImages, trigger: "d", wantKind: action.ImageRemove},
		{name: "image prune", tab: TabImages, trigger: "P", wantKind: action.ImagePrune},
		{name: "volume remove", tab: TabVolumes, trigger: "d", wantKind: action.VolumeRemove},
		{name: "volume prune", tab: TabVolumes, trigger: "P", wantKind: action.VolumePrune},
		{name: "network remove", tab: TabNetworks, trigger: "d", wantKind: action.NetworkRemove},
		{name: "network prune", tab: TabNetworks, trigger: "P", wantKind: action.NetworkPrune},
		{name: "kubernetes reset", tab: TabKubernetes, trigger: "R", wantKind: action.KubeReset},
		{name: "profile delete", tab: TabProfiles, trigger: "d", wantKind: action.ProfileDelete},
		{name: "runtime switch docker", tab: TabRuntime, trigger: "d", wantKind: action.RuntimeSwitch},
		{name: "runtime switch containerd", tab: TabRuntime, trigger: "c", wantKind: action.RuntimeSwitch},
		{name: "runtime switch incus", tab: TabRuntime, trigger: "i", wantKind: action.RuntimeSwitch},
		{name: "process kill", tab: TabMonitoring, trigger: "k", wantKind: action.ProcessKill},
	}
}

// driveConfirmationGate returns an error for a transient render failure
// (retryable) and uses t.Fatalf for a genuine gate violation (deterministic).
func driveConfirmationGate(t *testing.T, c dispatchCase, profile string, confirm bool, dismissChoice int) error {
	src := newDispatchSource()
	m := New(src, profile)
	m.tab = c.tab
	tm := teatest.NewTestModel(t, m, teatest.WithInitialTermSize(200, 50))
	out := drainOutput(tm)

	if !awaitContains(out, tabReadyMarker(c.tab)) {
		_ = tm.Quit()
		return fmt.Errorf("tab %d content did not render", c.tab)
	}
	sendRuneKey(tm, c.trigger)
	// Reaching the confirmation render proves the destructive RPC did NOT fire.
	if !awaitContains(out, "Confirmation required") {
		_ = tm.Quit()
		return errors.New("confirmation gate did not render")
	}

	if confirm {
		sendRuneKey(tm, "y")
		if !awaitContains(out, "Success:") {
			_ = tm.Quit()
			return errors.New("success state did not render after confirm")
		}
		fm := dispatchFinalModel(t, tm)
		if fm.action.phase != actionSuccess {
			t.Fatalf("[%s] confirmed phase = %v, want success", c.name, fm.action.phase)
		}
		reqs := src.unarySnapshot()
		if len(reqs) != 1 || reqs[0].Kind != c.wantKind || reqs[0].Profile != profile {
			t.Fatalf("[%s] confirmed dispatched %#v, want exactly one %q for profile %q", c.name, reqs, c.wantKind, profile)
		}
		return nil
	}

	// Dismiss with a (seeded) chosen dismissal key: n / N / Esc. This and the
	// FinalModel below are synchronous (no RPC cmd), so no render wait is needed.
	switch dismissChoice {
	case 0:
		sendRuneKey(tm, "n")
	case 1:
		sendRuneKey(tm, "N")
	default:
		sendEscKey(tm)
	}
	fm := dispatchFinalModel(t, tm)
	if n := len(src.unarySnapshot()); n != 0 {
		t.Fatalf("[%s] dismissed confirmation issued %d unary RPCs, want 0", c.name, n)
	}
	if n := len(src.streamSnapshot()); n != 0 {
		t.Fatalf("[%s] dismissed confirmation issued %d stream RPCs, want 0", c.name, n)
	}
	if fm.action.phase != actionIdle {
		t.Fatalf("[%s] dismissed confirmation left phase = %v, want idle", c.name, fm.action.phase)
	}
	return nil
}

func TestProperty13DestructiveConfirmationGate(t *testing.T) {
	// Feature: cross-platform-live-verification, Property 13: Destructive-action confirmation gate
	const seed = 0xC013
	rng := rand.New(rand.NewSource(seed))
	cases := destructiveCases()
	t.Logf("Feature: cross-platform-live-verification, Property 13 — seed=%#x cases=%d iterations=%d", seed, len(cases), p13Iterations)
	for i := 0; i < p13Iterations; i++ {
		c := cases[rng.Intn(len(cases))]
		profile := randomProfile(rng)
		confirm := rng.Intn(2) == 0
		dismissChoice := rng.Intn(3)
		t.Run(fmt.Sprintf("iter%03d-%s", i, c.name), func(t *testing.T) {
			withRetry(t, c.name, func() error {
				return driveConfirmationGate(t, c, profile, confirm, dismissChoice)
			})
		})
	}
}

// ─── Property 14: bounded streamed output ────────────────────────────────────

// buildBoundedOutputEvents produces a seeded stream whose cumulative output
// deliberately exceeds a bound: line-heavy (many short lines > maxOutputLines) or
// byte-heavy (fewer long lines whose bytes > maxOutputBytes). Lines are globally
// numbered "L%07d-" so the newest can be asserted present and the oldest absent.
func buildBoundedOutputEvents(rng *rand.Rand) (events []*pb.ProgressEvent, total int, byteHeavy bool) {
	byteHeavy = rng.Intn(100) < 35
	var lineLen, target int
	if byteHeavy {
		lineLen = 900 + rng.Intn(400) // ~0.9–1.3 KB per line
		target = maxOutputBytes/lineLen + 300 + rng.Intn(400)
	} else {
		lineLen = 8 + rng.Intn(20)
		target = maxOutputLines + 50 + rng.Intn(1500)
	}

	lines := make([]string, target)
	for i := range lines {
		prefix := fmt.Sprintf("L%07d-", i)
		pad := lineLen - len(prefix)
		if pad < 0 {
			pad = 0
		}
		lines[i] = prefix + strings.Repeat("x", pad)
	}

	blocks := 2 + rng.Intn(7) // 2–8 stream events
	per := (target + blocks - 1) / blocks
	for start := 0; start < target; start += per {
		end := start + per
		if end > target {
			end = target
		}
		events = append(events, &pb.ProgressEvent{
			Message:  strings.Join(lines[start:end], "\n"),
			Progress: float32(end) / float32(target),
		})
	}
	return events, target, byteHeavy
}

func TestProperty14BoundedStreamedOutput(t *testing.T) {
	// Feature: cross-platform-live-verification, Property 14: Bounded streamed output
	const seed = 0xC014
	rng := rand.New(rand.NewSource(seed))
	t.Logf("Feature: cross-platform-live-verification, Property 14 — seed=%#x iterations=%d maxLines=%d maxBytes=%d", seed, p14Iterations, maxOutputLines, maxOutputBytes)

	for i := 0; i < p14Iterations; i++ {
		profile := randomProfile(rng)
		events, total, byteHeavy := buildBoundedOutputEvents(rng)
		t.Run(fmt.Sprintf("iter%03d", i), func(t *testing.T) {
			withRetry(t, fmt.Sprintf("iter%03d", i), func() error {
				return driveBoundedOutput(t, profile, events, total, byteHeavy)
			})
		})
	}
}

// driveBoundedOutput streams a large seeded output and asserts the bound holds.
// It returns an error for a transient render failure (retryable); a bound
// violation uses t.Fatalf (deterministic — a real bug, not retried).
func driveBoundedOutput(t *testing.T, profile string, events []*pb.ProgressEvent, total int, byteHeavy bool) error {
	src := newDispatchSource()
	src.streamEvents = events // no Done → terminated by io.EOF → success

	m := New(src, profile)
	m.tab = TabDashboard
	tm := teatest.NewTestModel(t, m, teatest.WithInitialTermSize(200, 50))
	out := drainOutput(tm)

	if !awaitContains(out, tabReadyMarker(TabDashboard)) {
		_ = tm.Quit()
		return errors.New("dashboard content did not render")
	}
	sendRuneKey(tm, "s") // VM start — streaming
	if !awaitContains(out, "Success:") {
		_ = tm.Quit()
		return errors.New("stream did not reach success")
	}
	fm := dispatchFinalModel(t, tm)

	buffered := fm.action.output
	lines := strings.Split(buffered, "\n")
	if len(lines) > maxOutputLines {
		t.Fatalf("bounded output has %d lines > cap %d (byteHeavy=%v total=%d)", len(lines), maxOutputLines, byteHeavy, total)
	}
	if len(buffered) > maxOutputBytes {
		t.Fatalf("bounded output has %d bytes > cap %d (byteHeavy=%v total=%d)", len(buffered), maxOutputBytes, byteHeavy, total)
	}
	newest := fmt.Sprintf("L%07d-", total-1)
	if !strings.Contains(buffered, newest) {
		t.Fatalf("newest line %q was dropped from bounded output (byteHeavy=%v)", newest, byteHeavy)
	}
	if strings.Contains(buffered, "L0000000-") {
		t.Fatalf("oldest line survived — the bound was not actually enforced (byteHeavy=%v total=%d lines=%d bytes=%d)", byteHeavy, total, len(lines), len(buffered))
	}

	// The rendered success viewport never displays more than the configured rows.
	rows := fm.actionOutputRows()
	view, _, _, _ := outputViewport(buffered, fm.action.outputLine, rows)
	if shown := len(strings.Split(view, "\n")); shown > rows {
		t.Fatalf("displayed %d output lines > viewport bound %d", shown, rows)
	}
	return nil
}

// ─── Property 15: error rendering with operation-name context ────────────────

type errorCase struct {
	name    string
	tab     int
	trigger string
	stream  bool
	title   string // the operation name rendered as the action title
}

func errorCases() []errorCase {
	return []errorCase{
		{"vm ssh-config", TabDashboard, "H", false, "SSH configuration"},
		{"vm update", TabDashboard, "U", false, "Update Colima"},
		{"kubernetes start", TabKubernetes, "s", false, "Start Kubernetes"},
		{"kubernetes stop", TabKubernetes, "x", false, "Stop Kubernetes"},
		{"runtime update", TabRuntime, "u", false, "Update runtime"},
		{"model stop", TabAI, "x", false, "Stop model service"},
		{"vm start (stream)", TabDashboard, "s", true, "Start VM"},
		{"vm restart (stream)", TabDashboard, "R", true, "Restart VM"},
	}
}

// driveErrorRendering returns an error for a transient render failure
// (retryable) and uses t.Fatalf for a genuine missing-context assertion.
func driveErrorRendering(t *testing.T, c errorCase, profile, errText string, variant int) error {
	src := newDispatchSource()
	if c.stream {
		switch variant {
		case 0: // stream open fails
			src.openErr = errors.New(errText)
		case 1: // terminal error event mid-stream
			src.streamEvents = []*pb.ProgressEvent{{Message: "starting", Progress: 0.2}, {Error: errText, Done: true}}
		default: // stream Recv fails after one event
			src.streamEvents = []*pb.ProgressEvent{{Message: "starting", Progress: 0.2}}
			src.streamRecvErr = errors.New(errText)
		}
	} else {
		src.unaryErr = errors.New(errText)
	}

	m := New(src, profile)
	m.tab = c.tab
	tm := teatest.NewTestModel(t, m, teatest.WithInitialTermSize(200, 50))
	out := drainOutput(tm)

	if !awaitContains(out, tabReadyMarker(c.tab)) {
		_ = tm.Quit()
		return fmt.Errorf("tab %d content did not render", c.tab)
	}
	sendRuneKey(tm, c.trigger)
	if !awaitContains(out, "Error:") {
		_ = tm.Quit()
		return errors.New("failure state did not render")
	}
	fm := dispatchFinalModel(t, tm)

	if fm.action.phase != actionFailure {
		t.Fatalf("[%s] final phase = %v, want failure", c.name, fm.action.phase)
	}
	view := fm.View()
	if !strings.Contains(view, c.title) {
		t.Fatalf("[%s] failure render is missing the operation name %q:\n%s", c.name, c.title, view)
	}
	if !strings.Contains(view, errText) {
		t.Fatalf("[%s] failure render is missing the underlying error %q:\n%s", c.name, errText, view)
	}
	return nil
}

func TestProperty15ErrorRenderingWithContext(t *testing.T) {
	// Feature: cross-platform-live-verification, Property 15: Error rendering with context
	const seed = 0xC015
	rng := rand.New(rand.NewSource(seed))
	cases := errorCases()
	t.Logf("Feature: cross-platform-live-verification, Property 15 — seed=%#x cases=%d iterations=%d", seed, len(cases), p15Iterations)
	for i := 0; i < p15Iterations; i++ {
		c := cases[rng.Intn(len(cases))]
		profile := randomProfile(rng)
		errText := fmt.Sprintf("backend-failure-%d", rng.Intn(1_000_000))
		variant := rng.Intn(3) // used only for streaming cases
		t.Run(fmt.Sprintf("iter%03d-%s", i, c.name), func(t *testing.T) {
			withRetry(t, c.name, func() error {
				return driveErrorRendering(t, c, profile, errText, variant)
			})
		})
	}
}

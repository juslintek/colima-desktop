package ui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	pb "github.com/colima-desktop/daemon/proto"
)

// fakeSource is a fully deterministic DataSource used in unit tests.
type fakeSource struct{}

func (fakeSource) Status(string) (*pb.VMStatus, error) {
	return &pb.VMStatus{
		Running: true, Runtime: "docker", Cpu: 2,
		Memory: 2 * 1024 * 1024 * 1024, Driver: "QEMU", Arch: "aarch64",
		Kubernetes: false,
	}, nil
}
func (fakeSource) Profiles() (*pb.ProfileList, error) {
	return &pb.ProfileList{Profiles: []*pb.ProfileInfo{
		{Name: "default", Status: "Running", Arch: "aarch64", Cpus: 2},
	}}, nil
}
func (fakeSource) Machines() (*pb.MachineList, error) {
	return &pb.MachineList{Machines: []*pb.MachineInfo{
		{Name: "default", Status: "Running", Arch: "aarch64", Cpus: 4},
	}}, nil
}
func (fakeSource) GetConfig(string) (*pb.ColimaConfig, error) {
	return &pb.ColimaConfig{
		Cpu:     2,
		Memory:  2.0,
		Disk:    60,
		Arch:    "aarch64",
		VmType:  "vz",
		Runtime: "docker",
		Kubernetes: &pb.KubernetesConfig{
			Enabled: false, Version: "v1.30.0+k3s1",
		},
	}, nil
}
func (fakeSource) KubernetesStatus(string) (*pb.VMStatus, error) {
	return &pb.VMStatus{Running: true, Kubernetes: false, Runtime: "docker"}, nil
}
func (fakeSource) Containers(string) (string, error) {
	return `[{"Names":["/web"],"Image":"nginx","State":"running","Status":"Up 2h"}]`, nil
}
func (fakeSource) Images(string) (string, error) {
	return `[{"RepoTags":["nginx:latest"],"Id":"sha256:abc","Size":142000000}]`, nil
}
func (fakeSource) Volumes(string) (string, error) {
	return `[{"Name":"mydata","Driver":"local","Mountpoint":"/var/lib/docker/volumes/mydata/_data"}]`, nil
}
func (fakeSource) Networks(string) (string, error) {
	return `[{"Name":"bridge","Driver":"bridge","Scope":"local"}]`, nil
}

// newModel is a test helper.
func newModel() Model { return New(fakeSource{}, "default") }

// ─── view / render tests ─────────────────────────────────────────────────────

func TestViewRendersAllTabs(t *testing.T) {
	m := newModel()
	view := m.View()
	for _, tab := range Tabs {
		if !strings.Contains(view, tab) {
			t.Errorf("view missing tab label %q", tab)
		}
	}
}

func TestTabCountIs11(t *testing.T) {
	if len(Tabs) != 11 {
		t.Errorf("expected 11 tabs, got %d: %v", len(Tabs), Tabs)
	}
}

func TestTabConstantsMatchSlice(t *testing.T) {
	cases := []struct {
		idx  int
		name string
	}{
		{TabDashboard, "Dashboard"},
		{TabContainers, "Containers"},
		{TabImages, "Images"},
		{TabVolumes, "Volumes"},
		{TabNetworks, "Networks"},
		{TabKubernetes, "Kubernetes"},
		{TabConfig, "Configuration"},
		{TabRuntime, "Runtime"},
		{TabAI, "AI Workloads"},
		{TabProfiles, "Profiles"},
		{TabMachines, "Machines"},
	}
	for _, c := range cases {
		if Tabs[c.idx] != c.name {
			t.Errorf("Tabs[%d] = %q, want %q", c.idx, Tabs[c.idx], c.name)
		}
	}
}

// ─── navigation tests ────────────────────────────────────────────────────────

func TestTabNavigationWraps(t *testing.T) {
	m := newModel()
	if m.tab != 0 {
		t.Fatalf("initial tab = %d, want 0", m.tab)
	}
	// left from 0 wraps to last
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyLeft})
	m = nm.(Model)
	if m.tab != len(Tabs)-1 {
		t.Errorf("left-wrap tab = %d, want %d", m.tab, len(Tabs)-1)
	}
	// right wraps back to 0
	nm, _ = m.Update(tea.KeyMsg{Type: tea.KeyRight})
	m = nm.(Model)
	if m.tab != 0 {
		t.Errorf("right-wrap tab = %d, want 0", m.tab)
	}
}

func TestRightNavAdvances(t *testing.T) {
	m := newModel()
	for i := 0; i < len(Tabs); i++ {
		if m.tab != i {
			t.Errorf("iteration %d: tab = %d, want %d", i, m.tab, i)
		}
		nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRight})
		m = nm.(Model)
	}
	// After full cycle we're back at 0
	if m.tab != 0 {
		t.Errorf("after full cycle tab = %d, want 0", m.tab)
	}
}

func TestHKeyNavigatesLeft(t *testing.T) {
	m := newModel()
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'l'}})
	m = nm.(Model)
	if m.tab != 1 {
		t.Errorf("l key → tab %d, want 1", m.tab)
	}
	nm, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'h'}})
	m = nm.(Model)
	if m.tab != 0 {
		t.Errorf("h key → tab %d, want 0", m.tab)
	}
}

func TestNumberKeySelectsTab(t *testing.T) {
	cases := []struct {
		key  rune
		want int
	}{
		{'1', 0}, {'2', 1}, {'3', 2}, {'4', 3}, {'5', 4},
		{'6', 5}, {'7', 6}, {'8', 7}, {'9', 8}, {'0', 9},
	}
	for _, c := range cases {
		m := newModel()
		nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{c.key}})
		m = nm.(Model)
		if m.tab != c.want {
			t.Errorf("key %q → tab %d, want %d", string(c.key), m.tab, c.want)
		}
	}
}

func TestQuitKey(t *testing.T) {
	m := newModel()
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})
	if cmd == nil {
		t.Fatal("q should return a quit command")
	}
}

func TestCtrlCQuits(t *testing.T) {
	m := newModel()
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyCtrlC})
	if cmd == nil {
		t.Fatal("ctrl+c should return a quit command")
	}
}

func TestHelpToggle(t *testing.T) {
	m := newModel()
	if m.showHelp {
		t.Fatal("showHelp should start false")
	}
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	m = nm.(Model)
	if !m.showHelp {
		t.Error("? should toggle showHelp to true")
	}
	// View should contain help text
	v := m.View()
	if !strings.Contains(v, "Keybindings") {
		t.Error("help view should contain 'Keybindings'")
	}
	// Toggle off
	nm, _ = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	m = nm.(Model)
	if m.showHelp {
		t.Error("second ? should toggle showHelp back to false")
	}
}

// ─── body message handling ───────────────────────────────────────────────────

func TestBodyMsgUpdatesActiveTab(t *testing.T) {
	m := newModel()
	nm, _ := m.Update(bodyMsg{tab: 0, text: "hello-dashboard"})
	m = nm.(Model)
	if !strings.Contains(m.View(), "hello-dashboard") {
		t.Error("body for active tab not rendered in view")
	}
}

func TestBodyMsgForInactiveTabIgnored(t *testing.T) {
	m := newModel()
	// Set body for active tab (tab 0)
	nm, _ := m.Update(bodyMsg{tab: 0, text: "initial"})
	m = nm.(Model)
	// Send body for a different tab (tab 3, not active)
	nm, _ = m.Update(bodyMsg{tab: 3, text: "should-be-ignored"})
	m = nm.(Model)
	if strings.Contains(m.body, "should-be-ignored") {
		t.Error("body from inactive tab should not update current body")
	}
}

func TestStatusMsgUpdatesFooter(t *testing.T) {
	m := newModel()
	nm, _ := m.Update(statusMsg{text: "profile=test status=running"})
	m = nm.(Model)
	if !strings.Contains(m.View(), "profile=test") {
		t.Error("status message not reflected in view footer")
	}
}

func TestWindowSizeMsg(t *testing.T) {
	m := newModel()
	nm, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 40})
	m = nm.(Model)
	if m.width != 120 || m.height != 40 {
		t.Errorf("window size not stored: got %dx%d", m.width, m.height)
	}
}

// ─── per-tab body loaders ─────────────────────────────────────────────────────

func TestLoadTabDashboard(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabDashboard)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.tab != TabDashboard {
		t.Errorf("tab = %d, want %d", bm.tab, TabDashboard)
	}
	if !strings.Contains(bm.text, "Colima Desktop") {
		t.Errorf("dashboard body missing 'Colima Desktop': %q", bm.text)
	}
}

func TestLoadTabContainers(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabContainers)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "web") && !strings.Contains(bm.text, "nginx") {
		t.Errorf("containers body should mention container name or image: %q", bm.text)
	}
}

func TestLoadTabImages(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabImages)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "nginx") {
		t.Errorf("images body should mention 'nginx': %q", bm.text)
	}
}

func TestLoadTabVolumes(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabVolumes)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "mydata") {
		t.Errorf("volumes body should mention 'mydata': %q", bm.text)
	}
}

func TestLoadTabNetworks(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabNetworks)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "bridge") {
		t.Errorf("networks body should mention 'bridge': %q", bm.text)
	}
}

func TestLoadTabKubernetes(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabKubernetes)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "Kubernetes") {
		t.Errorf("kubernetes body should mention 'Kubernetes': %q", bm.text)
	}
}

func TestLoadTabConfig(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabConfig)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "CPU") {
		t.Errorf("config body should mention 'CPU': %q", bm.text)
	}
	if !strings.Contains(bm.text, "aarch64") {
		t.Errorf("config body should mention arch 'aarch64': %q", bm.text)
	}
}

func TestLoadTabRuntime(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabRuntime)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "Runtime") {
		t.Errorf("runtime body should mention 'Runtime': %q", bm.text)
	}
	if !strings.Contains(bm.text, "docker") {
		t.Errorf("runtime body should mention 'docker': %q", bm.text)
	}
}

func TestLoadTabAI(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabAI)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "AI Workloads") {
		t.Errorf("AI tab body should mention 'AI Workloads': %q", bm.text)
	}
}

func TestLoadTabProfiles(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabProfiles)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "default") {
		t.Errorf("profiles body missing 'default': %q", bm.text)
	}
}

func TestLoadTabMachines(t *testing.T) {
	m := newModel()
	msg := m.loadTab(TabMachines)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.err != "" {
		t.Errorf("unexpected error: %s", bm.err)
	}
	if !strings.Contains(bm.text, "default") {
		t.Errorf("machines body missing 'default': %q", bm.text)
	}
}

// ─── onboarding model tests ──────────────────────────────────────────────────

func TestOnboardingViewWhileChecking(t *testing.T) {
	ob := NewOnboardingModel()
	view := ob.View()
	if !strings.Contains(view, "Dependency Check") {
		t.Errorf("onboarding view should show 'Dependency Check': %q", view)
	}
}

func TestOnboardingAllOKSignalsDone(t *testing.T) {
	ob := NewOnboardingModel()
	// Inject all-OK result
	nm, cmd := ob.Update(depsCheckedMsg{deps: []Dependency{
		{Name: "colima", OK: true, Version: "0.8.0"},
	}})
	ob2 := nm.(OnboardingModel)
	if !ob2.allOK {
		t.Error("allOK should be true when all deps pass")
	}
	if cmd == nil {
		t.Error("should have returned a cmd (OnboardingDoneMsg)")
	}
}

func TestOnboardingMissingDepNoAutoComplete(t *testing.T) {
	ob := NewOnboardingModel()
	nm, cmd := ob.Update(depsCheckedMsg{deps: []Dependency{
		{Name: "colima", OK: false},
	}})
	ob2 := nm.(OnboardingModel)
	if ob2.allOK {
		t.Error("allOK should be false when a dep is missing")
	}
	if cmd != nil {
		t.Error("should NOT auto-complete when deps are missing")
	}
}

func TestOnboardingSkipKeySendsDoneMsg(t *testing.T) {
	ob := NewOnboardingModel()
	// Set up checked state with missing dep
	ob.checked = true
	ob.deps = []Dependency{{Name: "colima", OK: false}}
	nm, cmd := ob.Update(tea.KeyMsg{Type: tea.KeyEnter})
	_ = nm
	if cmd == nil {
		t.Error("enter key should return a cmd (OnboardingDoneMsg)")
	}
}

func TestOnboardingViewShowsMissingDep(t *testing.T) {
	ob := NewOnboardingModel()
	ob.checked = true
	ob.deps = []Dependency{
		{Name: "colima", OK: false},
		{Name: "docker (CLI)", OK: true, Version: "24.0.0"},
	}
	view := ob.View()
	if !strings.Contains(view, "colima") {
		t.Errorf("view should mention 'colima': %q", view)
	}
	if !strings.Contains(view, "not found") {
		t.Errorf("view should mention 'not found' for missing dep: %q", view)
	}
}

func TestOnboardingViewShowsInstallGuide(t *testing.T) {
	ob := NewOnboardingModel()
	ob.checked = true
	ob.allOK = false
	ob.deps = []Dependency{{Name: "colima", OK: false}}
	view := ob.View()
	// Should contain some install instruction
	if !strings.Contains(view, "Install") && !strings.Contains(view, "install") &&
		!strings.Contains(view, "brew") && !strings.Contains(view, "apt") &&
		!strings.Contains(view, "winget") {
		t.Errorf("view should contain install instructions: %q", view)
	}
}

func TestOnboardingCursorNavigation(t *testing.T) {
	ob := NewOnboardingModel()
	ob.checked = true
	ob.deps = []Dependency{
		{Name: "colima", OK: true},
		{Name: "docker (CLI)", OK: true},
	}
	nm, _ := ob.Update(tea.KeyMsg{Type: tea.KeyDown})
	ob2 := nm.(OnboardingModel)
	if ob2.cursor != 1 {
		t.Errorf("down key: cursor = %d, want 1", ob2.cursor)
	}
	nm, _ = ob2.Update(tea.KeyMsg{Type: tea.KeyUp})
	ob3 := nm.(OnboardingModel)
	if ob3.cursor != 0 {
		t.Errorf("up key: cursor = %d, want 0", ob3.cursor)
	}
}

// ─── model with onboarding integration ───────────────────────────────────────

func TestModelWithOnboardingDelegates(t *testing.T) {
	ob := NewOnboardingModel()
	m := NewWithOnboarding(fakeSource{}, "default", ob)
	view := m.View()
	if !strings.Contains(view, "Dependency Check") {
		t.Errorf("model with onboarding should show dependency check view: %q", view)
	}
}

func TestModelOnboardingDoneSwitchesToNormal(t *testing.T) {
	ob := NewOnboardingModel()
	m := NewWithOnboarding(fakeSource{}, "default", ob)
	nm, _ := m.Update(OnboardingDoneMsg{})
	m2 := nm.(Model)
	if m2.onboarding != nil {
		t.Error("onboarding should be cleared after OnboardingDoneMsg")
	}
	// Normal view should show tab bar
	view := m2.View()
	if !strings.Contains(view, "Dashboard") {
		t.Errorf("normal view after onboarding should show 'Dashboard': %q", view)
	}
}

// ─── renderer helpers ─────────────────────────────────────────────────────────

func TestRenderJSONListEmpty(t *testing.T) {
	msg := renderJSONList(0, "", "Name")
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.text != "(empty)" {
		t.Errorf("empty raw → %q, want '(empty)'", bm.text)
	}
}

func TestRenderJSONListNone(t *testing.T) {
	msg := renderJSONList(0, "[]", "Name")
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if bm.text != "(none)" {
		t.Errorf("empty array → %q, want '(none)'", bm.text)
	}
}

func TestRenderJSONListParsesItems(t *testing.T) {
	raw := `[{"Name":"alpha"},{"Name":"beta"}]`
	msg := renderJSONList(2, raw, "Name")
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if !strings.Contains(bm.text, "alpha") || !strings.Contains(bm.text, "beta") {
		t.Errorf("rendered list missing items: %q", bm.text)
	}
}

func TestRenderConfigNil(t *testing.T) {
	out := renderConfig(nil)
	if !strings.Contains(out, "No configuration") {
		t.Errorf("nil config → %q, want 'No configuration'", out)
	}
}

func TestRenderConfigFields(t *testing.T) {
	cfg := &pb.ColimaConfig{
		Cpu: 4, Memory: 8.0, Disk: 100, Arch: "x86_64", VmType: "qemu", Runtime: "containerd",
	}
	out := renderConfig(cfg)
	for _, want := range []string{"4", "8.0", "100", "x86_64", "qemu", "containerd"} {
		if !strings.Contains(out, want) {
			t.Errorf("renderConfig missing %q: %q", want, out)
		}
	}
}

func TestOrEmpty(t *testing.T) {
	if orEmpty("", "fallback") != "fallback" {
		t.Error("empty string should return fallback")
	}
	if orEmpty("  ", "fallback") != "fallback" {
		t.Error("whitespace string should return fallback")
	}
	if orEmpty("hello", "fallback") != "hello" {
		t.Error("non-empty string should return itself")
	}
}

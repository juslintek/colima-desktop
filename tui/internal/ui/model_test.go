package ui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	pb "github.com/colima-desktop/daemon/proto"
)

type fakeSource struct{}

func (fakeSource) Status(string) (*pb.VMStatus, error) {
	return &pb.VMStatus{Running: true, Runtime: "docker", Cpu: 2, Memory: 2 * 1024 * 1024 * 1024}, nil
}
func (fakeSource) Profiles() (*pb.ProfileList, error) {
	return &pb.ProfileList{Profiles: []*pb.ProfileInfo{{Name: "default", Status: "Running", Arch: "aarch64", Cpus: 2}}}, nil
}
func (fakeSource) Machines() (*pb.MachineList, error) {
	return &pb.MachineList{Machines: []*pb.MachineInfo{{Name: "default", Status: "Running", Arch: "aarch64", Cpus: 4}}}, nil
}
func (fakeSource) Containers(string) (string, error) {
	return `[{"Names":["/web"],"Image":"nginx","State":"running"}]`, nil
}
func (fakeSource) Images(string) (string, error) {
	return `[{"RepoTags":["nginx:latest"],"Id":"sha256:abc"}]`, nil
}

func TestViewRendersAllTabs(t *testing.T) {
	m := New(fakeSource{}, "default")
	view := m.View()
	for _, tab := range Tabs {
		if !strings.Contains(view, tab) {
			t.Errorf("view missing tab %q", tab)
		}
	}
}

func TestTabNavigationWraps(t *testing.T) {
	m := New(fakeSource{}, "default")
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

func TestNumberKeySelectsTab(t *testing.T) {
	m := New(fakeSource{}, "default")
	nm, _ := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'5'}})
	m = nm.(Model)
	if m.tab != 4 {
		t.Errorf("key '5' → tab %d, want 4", m.tab)
	}
}

func TestQuitKey(t *testing.T) {
	m := New(fakeSource{}, "default")
	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'q'}})
	if cmd == nil {
		t.Fatal("q should return a quit command")
	}
}

func TestBodyMsgUpdatesActiveTab(t *testing.T) {
	m := New(fakeSource{}, "default")
	nm, _ := m.Update(bodyMsg{tab: 0, text: "hello-dashboard"})
	m = nm.(Model)
	if !strings.Contains(m.View(), "hello-dashboard") {
		t.Error("body for active tab not rendered")
	}
}

func TestLoadTabProfilesProducesBody(t *testing.T) {
	m := New(fakeSource{}, "default")
	m.tab = 5 // Profiles
	msg := m.loadTab(5)()
	bm, ok := msg.(bodyMsg)
	if !ok {
		t.Fatalf("expected bodyMsg, got %T", msg)
	}
	if !strings.Contains(bm.text, "default") {
		t.Errorf("profiles body missing 'default': %q", bm.text)
	}
}

//go:build ignore
// +build ignore

// driver_explore.go — Model-direct ground-truth capture driver.
// Run with: go run driver_explore.go
// (must be invoked from within the tui/ directory)
//
// Outputs 11 View() frames as a JSON array to stdout.
// Uses a deterministic fakeDS (no daemon needed).
package main

import (
	"encoding/json"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/ui"
)

type fakeDS struct{}

func (fakeDS) Status(string) (*pb.VMStatus, error) {
	return &pb.VMStatus{
		Running: true, Runtime: "docker", Cpu: 4,
		Memory: 8 * 1024 * 1024 * 1024, Driver: "vz", Arch: "aarch64",
		Kubernetes: false,
	}, nil
}
func (fakeDS) Profiles() (*pb.ProfileList, error) {
	return &pb.ProfileList{Profiles: []*pb.ProfileInfo{
		{Name: "default", Status: "Running", Arch: "aarch64", Cpus: 4},
		{Name: "k8s-dev", Status: "Stopped", Arch: "aarch64", Cpus: 2},
		{Name: "production", Status: "Stopped", Arch: "x86_64", Cpus: 8},
	}}, nil
}
func (fakeDS) Machines() (*pb.MachineList, error) {
	return &pb.MachineList{Machines: []*pb.MachineInfo{
		{Name: "colima-default", Status: "Running", Arch: "aarch64", Cpus: 4},
		{Name: "colima-k8s-dev", Status: "Stopped", Arch: "aarch64", Cpus: 2},
		{Name: "lima-rancher", Status: "Stopped", Arch: "aarch64", Cpus: 4},
	}}, nil
}
func (fakeDS) GetConfig(string) (*pb.ColimaConfig, error) {
	return &pb.ColimaConfig{
		Cpu: 4, Memory: 8.0, Disk: 100,
		Arch: "aarch64", VmType: "vz", Runtime: "docker", MountType: "virtiofs",
		Kubernetes: &pb.KubernetesConfig{Enabled: false, Version: "v1.35.0+k3s1"},
	}, nil
}
func (fakeDS) KubernetesStatus(string) (*pb.VMStatus, error) {
	return &pb.VMStatus{Running: true, Kubernetes: false, Runtime: "docker", Arch: "aarch64"}, nil
}
func (fakeDS) Containers(string) (string, error) {
	return `[{"Names":["/web-nginx"],"Image":"nginx:latest","State":"running","Status":"Up 2h"},{"Names":["/db-postgres"],"Image":"postgres:15","State":"running","Status":"Up 5h"},{"Names":["/cache-redis"],"Image":"redis:7","State":"exited","Status":"Exited 1h"}]`, nil
}
func (fakeDS) Images(string) (string, error) {
	return `[{"RepoTags":["nginx:latest"],"Id":"sha256:abc123","Size":142000000},{"RepoTags":["postgres:15"],"Id":"sha256:def456","Size":379000000},{"RepoTags":["redis:7"],"Id":"sha256:ghi789","Size":117000000}]`, nil
}
func (fakeDS) Volumes(string) (string, error) {
	return `[{"Name":"postgres-data","Driver":"local","Mountpoint":"/var/lib/docker/volumes/postgres-data/_data"},{"Name":"redis-cache","Driver":"local","Mountpoint":"/var/lib/docker/volumes/redis-cache/_data"}]`, nil
}
func (fakeDS) Networks(string) (string, error) {
	return `[{"Name":"bridge","Driver":"bridge","Scope":"local"},{"Name":"host","Driver":"host","Scope":"local"},{"Name":"app-network","Driver":"bridge","Scope":"local"}]`, nil
}

func applyCmd(m ui.Model, cmd tea.Cmd) ui.Model {
	if cmd == nil {
		return m
	}
	msg := cmd()
	if msg == nil {
		return m
	}
	m2, _ := m.Update(msg)
	return m2.(ui.Model)
}

func main() {
	const w, h = 120, 40

	m := ui.New(fakeDS{}, "default")
	m2, _ := m.Update(tea.WindowSizeMsg{Width: w, Height: h})
	m = m2.(ui.Model)

	// Bootstrap Init() — loads dashboard + status
	m = applyCmd(m, m.Init())

	frames := make([]string, len(ui.Tabs))

	for i := range ui.Tabs {
		var key tea.KeyMsg
		switch {
		case i == 0:
			key = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'1'}}
		case i < 9:
			key = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{rune('1' + i)}}
		case i == 9:
			key = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'0'}}
		default:
			// Tab 10 (Machines): '0' → tab 9, then right-arrow → tab 10
			k0 := tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'0'}}
			m3, c3 := m.Update(k0)
			m = m3.(ui.Model)
			m = applyCmd(m, c3)
			key = tea.KeyMsg{Type: tea.KeyRight}
		}

		m3, cmd3 := m.Update(key)
		m = m3.(ui.Model)
		m = applyCmd(m, cmd3)
		frames[i] = m.View()
	}

	out, _ := json.Marshal(frames)
	os.Stdout.Write(out)
}

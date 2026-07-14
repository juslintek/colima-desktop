// Package ui implements the Bubble Tea TUI for colima-desktop.
package ui

import (
	"encoding/json"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/colima-desktop/tui/internal/client"
)

// Tabs mirror the desktop app surfaces.
var Tabs = []string{"Dashboard", "Containers", "Images", "Volumes", "Networks", "Profiles", "Machines"}

type Model struct {
	cli     *client.Client
	profile string
	tab     int
	width   int
	height  int
	status  string
	body    string
	err     string
}

func New(cli *client.Client, profile string) Model {
	return Model{cli: cli, profile: profile, status: "connecting…", body: "Loading…"}
}

// messages
type statusMsg struct{ text string }
type bodyMsg struct {
	tab  int
	text string
	err  string
}

func (m Model) Init() tea.Cmd { return tea.Batch(m.loadStatus, m.loadTab(m.tab)) }

func (m Model) loadStatus() tea.Msg {
	st, err := m.cli.Status(m.profile)
	if err != nil {
		return statusMsg{"daemon unreachable: " + err.Error()}
	}
	state := "stopped"
	if st.Running {
		state = "running"
	}
	return statusMsg{fmt.Sprintf("profile=%s  status=%s  runtime=%s  cpu=%d  mem=%dGi",
		m.profile, state, st.Runtime, st.Cpu, st.Memory/(1024*1024*1024))}
}

func (m Model) loadTab(tab int) tea.Cmd {
	return func() tea.Msg {
		switch Tabs[tab] {
		case "Containers":
			raw, err := m.cli.Containers(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return renderJSON(tab, raw, []string{"Names", "Image", "State", "Status"})
		case "Images":
			raw, err := m.cli.Images(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return renderJSON(tab, raw, []string{"RepoTags", "Id", "Size"})
		case "Profiles":
			pl, err := m.cli.Profiles()
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			var b strings.Builder
			for _, p := range pl.Profiles {
				fmt.Fprintf(&b, "• %-16s %-10s %s cpu=%d\n", p.Name, p.Status, p.Arch, p.Cpus)
			}
			return bodyMsg{tab, orEmpty(b.String(), "No profiles"), ""}
		case "Machines":
			ml, err := m.cli.Machines()
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			var b strings.Builder
			for _, x := range ml.Machines {
				fmt.Fprintf(&b, "• %-16s %-10s %s cpu=%d\n", x.Name, x.Status, x.Arch, x.Cpus)
			}
			return bodyMsg{tab, orEmpty(b.String(), "No machines"), ""}
		case "Dashboard":
			return bodyMsg{tab, "Colima Desktop — TUI\n\nUse ←/→ or 1-7 to switch tabs, q to quit.\n\nBacked live by the colima-desktop daemon (gRPC).", ""}
		default:
			return bodyMsg{tab, Tabs[tab] + ": (wired via daemon DockerService)", ""}
		}
	}
}

func renderJSON(tab int, raw string, _ []string) tea.Msg {
	if raw == "" {
		return bodyMsg{tab, "(empty)", ""}
	}
	var arr []map[string]any
	if err := json.Unmarshal([]byte(raw), &arr); err != nil {
		return bodyMsg{tab, raw, ""}
	}
	var b strings.Builder
	for _, it := range arr {
		name := firstString(it, "Names", "RepoTags", "Name", "Id")
		fmt.Fprintf(&b, "• %s\n", name)
	}
	return bodyMsg{tab, orEmpty(b.String(), "(none)"), ""}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
	case statusMsg:
		m.status = msg.text
	case bodyMsg:
		if msg.tab == m.tab {
			m.body, m.err = msg.text, msg.err
		}
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "right", "l":
			m.tab = (m.tab + 1) % len(Tabs)
			return m, m.loadTab(m.tab)
		case "left", "h":
			m.tab = (m.tab - 1 + len(Tabs)) % len(Tabs)
			return m, m.loadTab(m.tab)
		case "r":
			return m, tea.Batch(m.loadStatus, m.loadTab(m.tab))
		}
		if len(msg.String()) == 1 && msg.String() >= "1" && msg.String() <= "7" {
			m.tab = int(msg.String()[0] - '1')
			return m, m.loadTab(m.tab)
		}
	}
	return m, nil
}

var (
	activeTab = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212")).Padding(0, 1)
	dimTab    = lipgloss.NewStyle().Foreground(lipgloss.Color("240")).Padding(0, 1)
	bar       = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	errStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
)

func (m Model) View() string {
	var tabs []string
	for i, t := range Tabs {
		if i == m.tab {
			tabs = append(tabs, activeTab.Render(fmt.Sprintf("%d %s", i+1, t)))
		} else {
			tabs = append(tabs, dimTab.Render(fmt.Sprintf("%d %s", i+1, t)))
		}
	}
	header := strings.Join(tabs, " ")
	body := m.body
	if m.err != "" {
		body = errStyle.Render("error: " + m.err)
	}
	return fmt.Sprintf("%s\n%s\n\n%s\n\n%s",
		header, bar.Render(strings.Repeat("─", 60)), body,
		bar.Render(m.status+"   [←/→ tabs · r refresh · q quit]"))
}

func orEmpty(s, fallback string) string {
	if strings.TrimSpace(s) == "" {
		return fallback
	}
	return s
}

func firstString(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k]; ok {
			switch t := v.(type) {
			case string:
				if t != "" {
					return t
				}
			case []any:
				if len(t) > 0 {
					return fmt.Sprintf("%v", t[0])
				}
			}
		}
	}
	return "(unnamed)"
}

// Package ui — dependency onboarding view (CONTRACT Part C: M4.13).
// Checks whether colima is installed and guides the user through installation.
package ui

import (
	"fmt"
	"os/exec"
	"runtime"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Dependency represents a required tool.
type Dependency struct {
	Name    string
	Cmd     string // command to probe (empty = skip check)
	OK      bool
	Version string
}

// OnboardingDoneMsg is sent when onboarding is complete (all deps OK or user skipped).
type OnboardingDoneMsg struct{}

// depsCheckedMsg carries the result of the dependency probe.
type depsCheckedMsg struct{ deps []Dependency }

// OnboardingModel is a Bubble Tea model for the dependency onboarding screen.
type OnboardingModel struct {
	deps     []Dependency
	checked  bool
	allOK    bool
	cursor   int // which dep is highlighted
	quitting bool
}

// NewOnboardingModel returns a model that checks the given deps (or default colima deps).
func NewOnboardingModel() *OnboardingModel {
	return &OnboardingModel{}
}

var defaultDeps = []Dependency{
	{Name: "colima", Cmd: "colima"},
	{Name: "docker (CLI)", Cmd: "docker"},
	{Name: "kubectl", Cmd: "kubectl"},
	{Name: "lima (limactl)", Cmd: "limactl"},
}

func (ob OnboardingModel) Init() tea.Cmd {
	return checkDepsCmd(defaultDeps)
}

func checkDepsCmd(deps []Dependency) tea.Cmd {
	return func() tea.Msg {
		results := make([]Dependency, len(deps))
		for i, d := range deps {
			results[i] = d
			if d.Cmd == "" {
				results[i].OK = true
				continue
			}
			path, err := exec.LookPath(d.Cmd)
			if err != nil {
				results[i].OK = false
				continue
			}
			results[i].OK = true
			// Try to get version
			out, err2 := exec.Command(path, "version", "--short").Output()
			if err2 != nil {
				out, _ = exec.Command(path, "--version").Output()
			}
			v := strings.TrimSpace(string(out))
			if len(v) > 40 {
				v = v[:40] + "…"
			}
			results[i].Version = v
		}
		return depsCheckedMsg{deps: results}
	}
}

func (ob OnboardingModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case depsCheckedMsg:
		ob.deps = msg.deps
		ob.checked = true
		ob.allOK = true
		for _, d := range ob.deps {
			if !d.OK {
				ob.allOK = false
				break
			}
		}
		if ob.allOK {
			return ob, func() tea.Msg { return OnboardingDoneMsg{} }
		}
		return ob, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			ob.quitting = true
			return ob, tea.Quit
		case "enter", " ", "s":
			// skip / continue without all deps
			return ob, func() tea.Msg { return OnboardingDoneMsg{} }
		case "up", "k":
			if ob.cursor > 0 {
				ob.cursor--
			}
		case "down", "j":
			if ob.cursor < len(ob.deps)-1 {
				ob.cursor++
			}
		}
	}
	return ob, nil
}

var (
	obTitleStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	obOKStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	obMissingStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	obDimStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("243"))
	obBoxStyle     = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).Padding(1, 2).BorderForeground(lipgloss.Color("240"))
)

func (ob OnboardingModel) View() string {
	var b strings.Builder

	b.WriteString(obTitleStyle.Render("Colima Desktop — Dependency Check") + "\n\n")

	if !ob.checked {
		b.WriteString(obDimStyle.Render("Checking dependencies…") + "\n")
		return obBoxStyle.Render(b.String())
	}

	for i, d := range ob.deps {
		cursor := "  "
		if i == ob.cursor {
			cursor = "▶ "
		}
		if d.OK {
			ver := ""
			if d.Version != "" {
				ver = obDimStyle.Render("  " + d.Version)
			}
			b.WriteString(fmt.Sprintf("%s%s %s%s\n",
				cursor,
				obOKStyle.Render("✓"),
				d.Name,
				ver))
		} else {
			b.WriteString(fmt.Sprintf("%s%s %s\n",
				cursor,
				obMissingStyle.Render("✗"),
				obMissingStyle.Render(d.Name+" — not found")))
		}
	}

	b.WriteString("\n")

	if ob.allOK {
		b.WriteString(obOKStyle.Render("All dependencies satisfied.") + "\n")
	} else {
		b.WriteString(obMissingStyle.Render("Some dependencies are missing.") + "\n\n")
		b.WriteString(installGuide())
		b.WriteString("\n")
	}

	b.WriteString("\n" + obDimStyle.Render("[enter / s] continue anyway   [q] quit"))

	return obBoxStyle.Render(b.String())
}

// installGuide returns platform-appropriate install instructions.
func installGuide() string {
	switch runtime.GOOS {
	case "darwin":
		return obDimStyle.Render(
			"Install missing tools:\n" +
				"  brew install colima docker kubectl lima\n" +
				"Then restart colima-desktop.")
	case "linux":
		return obDimStyle.Render(
			"Install missing tools:\n" +
				"  # Ubuntu/Debian:\n" +
				"  sudo apt install docker.io kubectl\n" +
				"  # Install colima: https://github.com/abiosoft/colima\n" +
				"Then restart colima-desktop.")
	case "windows":
		return obDimStyle.Render(
			"Install missing tools:\n" +
				"  winget install Docker.DockerDesktop\n" +
				"  winget install Kubernetes.kubectl\n" +
				"  # colima via WSL2 — see https://github.com/abiosoft/colima\n" +
				"Then restart colima-desktop.")
	default:
		return obDimStyle.Render(
			"Install colima and docker — see https://github.com/abiosoft/colima")
	}
}

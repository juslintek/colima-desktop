// Package ui implements the Bubble Tea TUI for colima-desktop.
package ui

import (
	"encoding/json"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	pb "github.com/colima-desktop/daemon/proto"
)

// DataSource is the subset of the daemon client the UI needs (interface enables testing).
type DataSource interface {
	// ColimaService
	Status(profile string) (*pb.VMStatus, error)
	Profiles() (*pb.ProfileList, error)
	Machines() (*pb.MachineList, error)
	GetConfig(profile string) (*pb.ColimaConfig, error)
	KubernetesStatus(profile string) (*pb.VMStatus, error)

	// Monitoring (CONTRACT Part A)
	// VMStats reads one bounded sample from the stream. May return (nil, nil)
	// when the daemon has not implemented the RPC yet.
	VMStats(profile string) (*pb.VMStatsEvent, error)
	// ProcessList returns the current process list for the VM.
	ProcessList(profile string) (*pb.ProcessListResponse, error)
	// KillProcess sends signal to pid (9 = SIGKILL).
	KillProcess(profile string, pid int32, signal int32) error

	// DockerService
	Containers(profile string) (string, error)
	Images(profile string) (string, error)
	Volumes(profile string) (string, error)
	Networks(profile string) (string, error)
}

// monitoringData holds a combined snapshot for the Monitoring tab.
type monitoringData struct {
	stats     *pb.VMStatsEvent
	processes *pb.ProcessListResponse
	statsErr  string
	procsErr  string
}

// Model is the root Bubble Tea model for the TUI.
type Model struct {
	cli        DataSource
	profile    string
	tab        int
	width      int
	height     int
	status     string
	body       string
	err        string
	showHelp   bool
	onboarding *OnboardingModel // non-nil when dependency check is needed

	// Monitoring tab state: process selection for kill.
	monProcesses []*pb.ProcessInfo // snapshot of current process list
	monCursor    int               // index into monProcesses (selected row)
	monFeedback  string            // transient success/error message after kill
}

// New creates a new Model. If onboarding is non-nil it is shown first.
func New(cli DataSource, profile string) Model {
	return Model{
		cli:     cli,
		profile: profile,
		status:  "connecting…",
		body:    "Loading…",
	}
}

// NewWithOnboarding creates a Model that first shows the onboarding screen.
func NewWithOnboarding(cli DataSource, profile string, ob *OnboardingModel) Model {
	m := New(cli, profile)
	m.onboarding = ob
	return m
}

// messages
type statusMsg struct{ text string }
type bodyMsg struct {
	tab  int
	text string
	err  string
}

// monitoringMsg carries the loaded monitoring data including the process snapshot.
type monitoringMsg struct {
	data      monitoringData
	processes []*pb.ProcessInfo
}

// killResultMsg is sent after a KillProcess RPC completes.
type killResultMsg struct {
	pid int32
	err error
}

func (m Model) Init() tea.Cmd {
	if m.onboarding != nil {
		return m.onboarding.Init()
	}
	return tea.Batch(m.loadStatus, m.loadTab(m.tab))
}

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
		switch tab {
		case TabDashboard:
			return bodyMsg{tab, dashboardBody(), ""}

		case TabContainers:
			raw, err := m.cli.Containers(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return renderJSONList(tab, raw, "Names", "Image", "State")

		case TabImages:
			raw, err := m.cli.Images(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return renderJSONList(tab, raw, "RepoTags", "Id", "Size")

		case TabVolumes:
			raw, err := m.cli.Volumes(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return renderJSONList(tab, raw, "Name", "Driver", "Mountpoint")

		case TabNetworks:
			raw, err := m.cli.Networks(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return renderJSONList(tab, raw, "Name", "Driver", "Scope")

		case TabKubernetes:
			st, err := m.cli.KubernetesStatus(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			enabled := "disabled"
			if st.Kubernetes {
				enabled = "enabled"
			}
			body := fmt.Sprintf(
				"Kubernetes: %s\nProfile:    %s\nRunning:    %v\nRuntime:    %s\n\n"+
					"Actions:  [s] start   [x] stop   [r] reset",
				enabled, m.profile, st.Running, st.Runtime)
			return bodyMsg{tab, body, ""}

		case TabConfig:
			cfg, err := m.cli.GetConfig(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return bodyMsg{tab, renderConfig(cfg), ""}

		case TabRuntime:
			st, err := m.cli.Status(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			body := fmt.Sprintf(
				"Runtime:    %s\nProfile:    %s\nVM type:    %s\nArch:       %s\n\n"+
					"Actions:  [d] docker   [c] containerd   [i] incus   [u] update",
				st.Runtime, m.profile, st.Driver, st.Arch)
			return bodyMsg{tab, body, ""}

		case TabAI:
			return bodyMsg{tab, aiWorkloadsBody(m.profile), ""}

		case TabProfiles:
			pl, err := m.cli.Profiles()
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return bodyMsg{tab, renderProfiles(pl), ""}

		case TabMachines:
			ml, err := m.cli.Machines()
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return bodyMsg{tab, renderMachines(ml), ""}

		case TabMonitoring:
			// Collect stats + process list concurrently via two goroutines.
			type statsResult struct {
				evt *pb.VMStatsEvent
				err error
			}
			type procsResult struct {
				pl  *pb.ProcessListResponse
				err error
			}
			statsCh := make(chan statsResult, 1)
			procsCh := make(chan procsResult, 1)

			go func() {
				evt, err := m.cli.VMStats(m.profile)
				statsCh <- statsResult{evt, err}
			}()
			go func() {
				pl, err := m.cli.ProcessList(m.profile)
				procsCh <- procsResult{pl, err}
			}()

			sr := <-statsCh
			pr := <-procsCh

			md := monitoringData{}
			if sr.err != nil {
				md.statsErr = sr.err.Error()
			} else {
				md.stats = sr.evt
			}
			if pr.err != nil {
				md.procsErr = pr.err.Error()
			} else {
				md.processes = pr.pl
			}

			var procs []*pb.ProcessInfo
			if md.processes != nil {
				procs = md.processes.Processes
			}
			return monitoringMsg{data: md, processes: procs}

		default:
			return bodyMsg{tab, Tabs[tab] + ": (not wired)", ""}
		}
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Delegate to onboarding model until it signals complete.
	if m.onboarding != nil {
		switch msg := msg.(type) {
		case OnboardingDoneMsg:
			m.onboarding = nil
			return m, tea.Batch(m.loadStatus, m.loadTab(m.tab))
		case tea.KeyMsg:
			if msg.String() == "ctrl+c" {
				return m, tea.Quit
			}
		}
		newOb, cmd := m.onboarding.Update(msg)
		ob := newOb.(OnboardingModel)
		m.onboarding = &ob
		return m, cmd
	}

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height

	case statusMsg:
		m.status = msg.text

	case bodyMsg:
		if msg.tab == m.tab {
			m.body, m.err = msg.text, msg.err
		}

	case monitoringMsg:
		if m.tab == TabMonitoring {
			m.monProcesses = msg.processes
			// Clamp cursor to valid range after refresh.
			if m.monCursor >= len(m.monProcesses) {
				m.monCursor = max(0, len(m.monProcesses)-1)
			}
			m.body = renderMonitoringWithSelection(msg.data, m.monProcesses, m.monCursor)
			if m.monFeedback != "" {
				m.body = renderMonitoringFeedback(m.body, m.monFeedback)
			}
			m.err = ""
		}

	case killResultMsg:
		if msg.err != nil {
			m.monFeedback = fmt.Sprintf("Kill PID %d failed: %s", msg.pid, msg.err.Error())
		} else {
			m.monFeedback = fmt.Sprintf("Killed PID %d (SIGKILL)", msg.pid)
		}
		// Re-render with feedback, then auto-refresh the process list.
		m.body = renderMonitoringFeedback(m.body, m.monFeedback)
		return m, m.loadTab(TabMonitoring)

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "?":
			m.showHelp = !m.showHelp
			return m, nil
		case "right", "l":
			m.tab = (m.tab + 1) % len(Tabs)
			m.body, m.err = "Loading…", ""
			m.monFeedback = ""
			return m, m.loadTab(m.tab)
		case "left", "h":
			m.tab = (m.tab - 1 + len(Tabs)) % len(Tabs)
			m.body, m.err = "Loading…", ""
			m.monFeedback = ""
			return m, m.loadTab(m.tab)
		case "r":
			m.body, m.err = "Loading…", ""
			m.monFeedback = ""
			return m, tea.Batch(m.loadStatus, m.loadTab(m.tab))
		}

		// Monitoring-specific keys: j/down move selection down, k kills.
		// Use up/down for process navigation (j/k would conflict with
		// 'k' = kill). We use "j" = down, "up"/"down" = navigate,
		// "k" = kill on Monitoring tab only.
		if m.tab == TabMonitoring && len(m.monProcesses) > 0 {
			switch msg.String() {
			case "down", "j":
				m.monCursor = (m.monCursor + 1) % len(m.monProcesses)
				m.monFeedback = ""
				m.body = rerenderMonitoringSelection(m.body, m.monProcesses, m.monCursor)
				return m, nil
			case "up":
				m.monCursor = (m.monCursor - 1 + len(m.monProcesses)) % len(m.monProcesses)
				m.monFeedback = ""
				m.body = rerenderMonitoringSelection(m.body, m.monProcesses, m.monCursor)
				return m, nil
			case "k":
				pid := m.monProcesses[m.monCursor].Pid
				profile := m.profile
				cli := m.cli
				return m, func() tea.Msg {
					err := cli.KillProcess(profile, pid, 9)
					return killResultMsg{pid: pid, err: err}
				}
			}
		}

		// 1-9 and 0 shortcut keys for tabs 1-10 (11th tab = 0)
		if len(msg.String()) == 1 {
			ch := msg.String()[0]
			if ch >= '1' && ch <= '9' {
				idx := int(ch - '1')
				if idx < len(Tabs) {
					m.tab = idx
					m.body, m.err = "Loading…", ""
					m.monFeedback = ""
					return m, m.loadTab(m.tab)
				}
			}
			if ch == '0' && len(Tabs) >= 10 {
				m.tab = 9
				m.body, m.err = "Loading…", ""
				m.monFeedback = ""
				return m, m.loadTab(m.tab)
			}
		}
	}
	return m, nil
}

// ─── styles ──────────────────────────────────────────────────────────────────

var (
	activeTabStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("212")).Padding(0, 1)
	dimTabStyle      = lipgloss.NewStyle().Foreground(lipgloss.Color("240")).Padding(0, 1)
	barStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	errStyle         = lipgloss.NewStyle().Foreground(lipgloss.Color("196"))
	helpStyle        = lipgloss.NewStyle().Foreground(lipgloss.Color("243")).Italic(true)
	titleStyle       = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	gaugeFilledStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("212"))
	gaugeEmptyStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("238"))
)

// View renders the full TUI screen.
func (m Model) View() string {
	if m.onboarding != nil {
		return m.onboarding.View()
	}

	// Header: tab bar split into two rows of 6 tabs each (12 total).
	// Row 1: tabs 0-5  Row 2: tabs 6-11
	var row1, row2 []string
	for i, t := range Tabs {
		label := t
		switch {
		case i < 9:
			label = fmt.Sprintf("%d %s", i+1, t)
		case i == 9:
			label = fmt.Sprintf("0 %s", t)
			// tabs 10 (Machines) and 11 (Monitoring) have no digit shortcut
		}
		if i == m.tab {
			s := activeTabStyle.Render(label)
			if i <= 5 {
				row1 = append(row1, s)
			} else {
				row2 = append(row2, s)
			}
		} else {
			s := dimTabStyle.Render(label)
			if i <= 5 {
				row1 = append(row1, s)
			} else {
				row2 = append(row2, s)
			}
		}
	}
	header := strings.Join(row1, "") + "\n" + strings.Join(row2, "")

	divider := barStyle.Render(strings.Repeat("─", max(60, m.width-2)))

	body := m.body
	if m.err != "" {
		body = errStyle.Render("error: " + m.err)
	}

	helpLine := barStyle.Render("←/→ tabs · 1-0 jump · r refresh · ? help · q quit")
	if m.showHelp {
		helpLine = helpView()
	}

	footerStatus := barStyle.Render(m.status)

	return fmt.Sprintf("%s\n%s\n\n%s\n\n%s\n%s",
		header, divider, body, divider, footerStatus+"  "+helpLine)
}

func helpView() string {
	lines := []string{
		"Keybindings:",
		"  ←/→  h/l     navigate tabs",
		"  1-9 / 0       jump to tab 1-10",
		"  r              refresh current tab",
		"  ?              toggle help",
		"  q  ctrl+c     quit",
		"",
		"Tabs:",
		"  1 Dashboard    2 Containers   3 Images",
		"  4 Volumes      5 Networks     6 Kubernetes",
		"  7 Configuration 8 Runtime     9 AI Workloads",
		"  0 Profiles    (→) Machines  (→) Monitoring",
	}
	return helpStyle.Render(strings.Join(lines, "\n"))
}

// ─── body renderers ──────────────────────────────────────────────────────────

func dashboardBody() string {
	return titleStyle.Render("Colima Desktop — TUI") + "\n\n" +
		"Surfaces available:\n" +
		"  Dashboard · Containers · Images · Volumes · Networks\n" +
		"  Kubernetes · Configuration · Runtime · AI Workloads\n" +
		"  Profiles · Machines · Monitoring\n\n" +
		"Backed live by the colima-desktop daemon (gRPC).\n" +
		"Use ←/→ or 1-0 to switch tabs, r to refresh, q to quit.\n" +
		"Press ? for full help."
}

func aiWorkloadsBody(profile string) string {
	return fmt.Sprintf(
		"AI Workloads — profile: %s\n\n"+
			"Actions:\n"+
			"  [s]  model setup      (stream install progress)\n"+
			"  [r]  model run        (interactive inference)\n"+
			"  [v]  model serve      (start OpenAI-compatible API)\n"+
			"  [x]  model stop       (stop serving)\n\n"+
			"Backend: colima model subcommand via daemon gRPC.\n"+
			"Supports docker runner and ramalama runner.",
		profile)
}

// renderGauge renders a simple ASCII progress bar for a percentage value.
func renderGauge(label string, used, total int64, unit string, width int) string {
	if total <= 0 {
		return fmt.Sprintf("%-12s  (unavailable)", label)
	}
	pct := float64(used) / float64(total) * 100
	barWidth := width - 30
	if barWidth < 10 {
		barWidth = 10
	}
	filled := int(float64(barWidth) * pct / 100)
	if filled > barWidth {
		filled = barWidth
	}
	bar := gaugeFilledStyle.Render(strings.Repeat("█", filled)) +
		gaugeEmptyStyle.Render(strings.Repeat("░", barWidth-filled))
	return fmt.Sprintf("%-12s [%s] %5.1f%%  %s/%s %s",
		label, bar,
		pct,
		formatBytes(used), formatBytes(total), unit)
}

func formatBytes(b int64) string {
	const (
		_  = iota
		KB = 1 << (10 * iota)
		MB
		GB
	)
	switch {
	case b >= GB:
		return fmt.Sprintf("%.1fG", float64(b)/GB)
	case b >= MB:
		return fmt.Sprintf("%.1fM", float64(b)/MB)
	case b >= KB:
		return fmt.Sprintf("%.1fK", float64(b)/KB)
	default:
		return fmt.Sprintf("%dB", b)
	}
}

// renderMonitoring builds the Monitoring tab body from a combined snapshot.
// (Used only by tests that invoke loadTab directly with the old bodyMsg path.)
func renderMonitoring(md monitoringData) string {
	var procs []*pb.ProcessInfo
	if md.processes != nil {
		procs = md.processes.Processes
	}
	return renderMonitoringWithSelection(md, procs, 0)
}

// renderMonitoringWithSelection builds the Monitoring tab body with a visible
// cursor on the selected process row.
func renderMonitoringWithSelection(md monitoringData, procs []*pb.ProcessInfo, cursor int) string {
	var b strings.Builder

	b.WriteString(titleStyle.Render("VM Monitoring") + "\n\n")

	// ── Resource gauges ──────────────────────────────────────────────────────
	if md.statsErr != "" {
		b.WriteString(fmt.Sprintf("Stats:  (unavailable: %s)\n", md.statsErr))
	} else if md.stats == nil {
		b.WriteString("Stats:  (not yet sampled — press r to refresh)\n")
	} else {
		s := md.stats
		cpuUsed := int64(s.CpuPercent)
		b.WriteString(renderGauge("CPU", cpuUsed, 100, "%", 72) + "\n")
		b.WriteString(renderGauge("Memory", s.MemoryUsed, s.MemoryTotal, "", 72) + "\n")
		b.WriteString(renderGauge("Disk", s.DiskUsed, s.DiskTotal, "", 72) + "\n")
	}

	b.WriteString("\n")

	// ── Process list ─────────────────────────────────────────────────────────
	if md.procsErr != "" {
		b.WriteString(fmt.Sprintf("Processes:  (unavailable: %s)\n", md.procsErr))
	} else if len(procs) == 0 {
		b.WriteString("Processes:  (none)\n")
	} else {
		fmt.Fprintf(&b, "  %-7s  %-10s  %5s  %5s  %-18s  %s\n",
			"PID", "USER", "CPU%", "MEM%", "CONTAINER", "COMMAND")
		fmt.Fprintf(&b, "  %s\n", strings.Repeat("─", 75))
		for i, p := range procs {
			container := p.Container
			if container == "" {
				container = "—"
			}
			cmd := p.Command
			if len(cmd) > 30 {
				cmd = cmd[:27] + "…"
			}
			prefix := "  "
			if i == cursor {
				prefix = "> "
			}
			fmt.Fprintf(&b, "%s%-7d  %-10s  %5.1f  %5.1f  %-18s  %s\n",
				prefix, p.Pid, p.User, p.CpuPercent, p.MemoryPercent, container, cmd)
		}
		fmt.Fprintf(&b, "\nActions:  [k] kill selected process   [j/↑↓] select   [r] refresh")
	}

	return b.String()
}

// rerenderMonitoringSelection re-renders the monitoring body with updated cursor position.
// It re-derives the full view from the stored monitoringData embedded in the model's body.
// For simplicity, we parse the existing body and update cursor markers.
func rerenderMonitoringSelection(currentBody string, procs []*pb.ProcessInfo, cursor int) string {
	// Replace cursor markers in existing body.
	lines := strings.Split(currentBody, "\n")
	procStart := -1
	procCount := 0
	for i, line := range lines {
		if len(line) >= 2 && (line[:2] == "> " || line[:2] == "  ") {
			// Check if this line looks like a process row (starts with marker + digit)
			trimmed := strings.TrimSpace(line)
			if len(trimmed) > 0 && trimmed[0] >= '0' && trimmed[0] <= '9' {
				if procStart == -1 {
					procStart = i
				}
				procCount++
			}
		}
	}
	if procStart == -1 || procCount != len(procs) {
		// Fallback: can't reliably reparse. Just return as-is.
		return currentBody
	}
	for i := 0; i < procCount; i++ {
		idx := procStart + i
		if i == cursor {
			lines[idx] = "> " + lines[idx][2:]
		} else {
			lines[idx] = "  " + lines[idx][2:]
		}
	}
	return strings.Join(lines, "\n")
}

// renderMonitoringFeedback appends feedback text to the monitoring body.
func renderMonitoringFeedback(body, feedback string) string {
	if feedback == "" {
		return body
	}
	return body + "\n" + errStyle.Render(feedback)
}

func renderProfiles(pl *pb.ProfileList) string {
	if pl == nil || len(pl.Profiles) == 0 {
		return "No profiles found."
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%-20s %-12s %-10s %s\n", "Name", "Status", "Arch", "CPU")
	fmt.Fprintf(&b, "%s\n", strings.Repeat("─", 55))
	for _, p := range pl.Profiles {
		fmt.Fprintf(&b, "%-20s %-12s %-10s %d\n", p.Name, p.Status, p.Arch, p.Cpus)
	}
	return b.String()
}

func renderMachines(ml *pb.MachineList) string {
	if ml == nil || len(ml.Machines) == 0 {
		return "No machines found."
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%-20s %-12s %-10s %s\n", "Name", "Status", "Arch", "CPU")
	fmt.Fprintf(&b, "%s\n", strings.Repeat("─", 55))
	for _, x := range ml.Machines {
		fmt.Fprintf(&b, "%-20s %-12s %-10s %d\n", x.Name, x.Status, x.Arch, x.Cpus)
	}
	return b.String()
}

func renderConfig(cfg *pb.ColimaConfig) string {
	if cfg == nil {
		return "No configuration available."
	}
	var b strings.Builder
	fmt.Fprintf(&b, "CPU:         %d\n", cfg.Cpu)
	fmt.Fprintf(&b, "Memory:      %.1f GiB\n", cfg.Memory)
	fmt.Fprintf(&b, "Disk:        %d GiB\n", cfg.Disk)
	fmt.Fprintf(&b, "Arch:        %s\n", cfg.Arch)
	fmt.Fprintf(&b, "VM Type:     %s\n", cfg.VmType)
	fmt.Fprintf(&b, "Runtime:     %s\n", cfg.Runtime)
	fmt.Fprintf(&b, "Mount Type:  %s\n", cfg.MountType)
	if cfg.Kubernetes != nil {
		fmt.Fprintf(&b, "Kubernetes:  enabled=%v  version=%s\n", cfg.Kubernetes.Enabled, cfg.Kubernetes.Version)
	}
	return b.String()
}

// renderJSONList parses a JSON array and renders a compact list.
func renderJSONList(tab int, raw string, keys ...string) tea.Msg {
	if raw == "" {
		return bodyMsg{tab, "(empty)", ""}
	}
	var arr []map[string]any
	if err := json.Unmarshal([]byte(raw), &arr); err != nil {
		return bodyMsg{tab, raw, ""}
	}
	if len(arr) == 0 {
		return bodyMsg{tab, "(none)", ""}
	}
	var b strings.Builder
	for _, it := range arr {
		name := firstString(it, keys...)
		extra := ""
		if len(keys) > 1 {
			second := firstString(it, keys[1:]...)
			if second != name {
				extra = "  " + second
			}
		}
		fmt.Fprintf(&b, "• %s%s\n", name, extra)
	}
	return bodyMsg{tab, b.String(), ""}
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

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

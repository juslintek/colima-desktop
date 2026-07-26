// Package ui implements the Bubble Tea TUI for colima-desktop.
package ui

import (
	"encoding/json"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/action"
)

// DataSource is the subset of the daemon client the UI needs (interface enables testing).
type DataSource interface {
	action.Runner

	// ColimaService
	Status(profile string) (*pb.VMStatus, error)
	Profiles() (*pb.ProfileList, error)
	Machines() (*pb.MachineList, error)
	GetConfig(profile string) (*pb.ColimaConfig, error)
	GetTemplate() (*pb.ColimaConfig, error)
	KubernetesStatus(profile string) (*pb.VMStatus, error)

	// Monitoring (CONTRACT Part A)
	// VMStats reads one bounded sample from the stream. May return (nil, nil)
	// when the daemon has not implemented the RPC yet.
	VMStats(profile string) (*pb.VMStatsEvent, error)
	// ProcessList returns the current process list for the VM.
	ProcessList(profile string) (*pb.ProcessListResponse, error)
	// DockerService
	Containers(profile string) (string, error)
	Images(profile string) (string, error)
	Volumes(profile string) (string, error)
	Networks(profile string) (string, error)
}

type resourceItem struct {
	ID      string
	Name    string
	Summary string
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
	cli          DataSource
	profile      string
	tab          int
	width        int
	height       int
	status       string
	body         string
	err          string
	showHelp     bool
	onboarding   *OnboardingModel // non-nil when dependency check is needed
	resources    []resourceItem
	cursor       int
	config       *pb.ColimaConfig
	template     *pb.ColimaConfig
	showTemplate bool
	action       actionState
	actionSeq    uint64
	loadSeq      uint64

	// Monitoring tab state: process selection for kill.
	monProcesses []*pb.ProcessInfo // snapshot of current process list
	monCursor    int               // index into monProcesses (selected row)
	monData      monitoringData
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

type resourceMsg struct {
	tab      int
	items    []resourceItem
	template *pb.ColimaConfig
	warning  string
}

type configMsg struct {
	config   *pb.ColimaConfig
	template *pb.ColimaConfig
	err      string
}

type scopedLoadMsg struct {
	seq uint64
	msg tea.Msg
}

// monitoringMsg carries the loaded monitoring data including the process snapshot.
type monitoringMsg struct {
	data      monitoringData
	processes []*pb.ProcessInfo
}

func (m Model) Init() tea.Cmd {
	if m.onboarding != nil {
		return m.onboarding.Init()
	}
	return tea.Batch(m.loadScopedStatus(), m.loadScopedTab(m.tab))
}

func (m Model) loadScopedStatus() tea.Cmd {
	seq := m.loadSeq
	return func() tea.Msg { return scopedLoadMsg{seq: seq, msg: m.loadStatus()} }
}

func (m Model) loadScopedTab(tab int) tea.Cmd {
	seq := m.loadSeq
	load := m.loadTab(tab)
	return func() tea.Msg { return scopedLoadMsg{seq: seq, msg: load()} }
}

func (m Model) loadStatus() tea.Msg {
	st, err := m.cli.Status(m.profile)
	if err != nil {
		return statusMsg{"daemon unreachable: " + err.Error()}
	}
	if st == nil {
		return statusMsg{"daemon returned an empty status"}
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
			return parseResourceList(tab, raw, []string{"Id", "ID"}, []string{"Names", "Name"}, []string{"Image", "State"})

		case TabImages:
			raw, err := m.cli.Images(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return parseResourceList(tab, raw, []string{"Id", "ID"}, []string{"RepoTags", "RepoDigests"}, []string{"Id", "Size"})

		case TabVolumes:
			raw, err := m.cli.Volumes(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return parseResourceList(tab, raw, []string{"Name"}, []string{"Name"}, []string{"Driver", "Mountpoint"})

		case TabNetworks:
			raw, err := m.cli.Networks(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			return parseResourceList(tab, raw, []string{"Id", "ID", "Name"}, []string{"Name"}, []string{"Driver", "Scope"})

		case TabKubernetes:
			st, err := m.cli.KubernetesStatus(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			if st == nil {
				return bodyMsg{tab: tab, err: "daemon returned an empty Kubernetes status"}
			}
			enabled := "disabled"
			if st.Kubernetes {
				enabled = "enabled"
			}
			body := fmt.Sprintf(
				"Kubernetes: %s\nProfile:    %s\nRunning:    %v\nRuntime:    %s",
				enabled, m.profile, st.Running, st.Runtime)
			return bodyMsg{tab, body, ""}

		case TabConfig:
			cfg, cfgErr := m.cli.GetConfig(m.profile)
			template, templateErr := m.cli.GetTemplate()
			if cfgErr != nil {
				return configMsg{err: cfgErr.Error()}
			}
			if templateErr != nil {
				return configMsg{config: cfg, err: "template: " + templateErr.Error()}
			}
			return configMsg{config: cfg, template: template}

		case TabRuntime:
			st, err := m.cli.Status(m.profile)
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			if st == nil {
				return bodyMsg{tab: tab, err: "daemon returned an empty runtime status"}
			}
			body := fmt.Sprintf(
				"Runtime:    %s\nProfile:    %s\nVM type:    %s\nArch:       %s",
				st.Runtime, m.profile, st.Driver, st.Arch)
			return bodyMsg{tab, body, ""}

		case TabAI:
			return bodyMsg{tab, aiWorkloadsBody(m.profile), ""}

		case TabProfiles:
			pl, err := m.cli.Profiles()
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			items := make([]resourceItem, 0, len(pl.GetProfiles()))
			for _, profile := range pl.GetProfiles() {
				items = append(items, resourceItem{ID: profile.GetName(), Name: profile.GetName(), Summary: fmt.Sprintf("%s · %s · %d CPU", profile.GetStatus(), profile.GetArch(), profile.GetCpus())})
			}
			template, templateErr := m.cli.GetTemplate()
			warning := ""
			if templateErr != nil {
				warning = "profile creation unavailable: " + templateErr.Error()
			}
			return resourceMsg{tab: tab, items: items, template: template, warning: warning}

		case TabMachines:
			ml, err := m.cli.Machines()
			if err != nil {
				return bodyMsg{tab, "", err.Error()}
			}
			items := make([]resourceItem, 0, len(ml.GetMachines()))
			for _, machine := range ml.GetMachines() {
				items = append(items, resourceItem{ID: machine.GetName(), Name: machine.GetName(), Summary: fmt.Sprintf("%s · %s · %d CPU", machine.GetStatus(), machine.GetArch(), machine.GetCpus())})
			}
			return resourceMsg{tab: tab, items: items}

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
			return bodyMsg{tab: tab, err: fmt.Sprintf("unsupported tab index %d", tab)}
		}
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Delegate to onboarding model until it signals complete.
	if m.onboarding != nil {
		switch msg := msg.(type) {
		case OnboardingDoneMsg:
			m.onboarding = nil
			return m, tea.Batch(m.loadScopedStatus(), m.loadScopedTab(m.tab))
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

	if updated, cmd, handled := m.updateActionMessage(msg); handled {
		return updated, cmd
	}

	switch msg := msg.(type) {
	case scopedLoadMsg:
		if msg.seq != m.loadSeq {
			return m, nil
		}
		return m.Update(msg.msg)

	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		if isSelectableTab(m.tab) && len(m.resources) > 0 {
			m.body = renderResourceItems(m.resources, m.cursor, m.profile, m.tab, m.listWindowRows())
		} else if m.tab == TabMonitoring && len(m.monProcesses) > 0 {
			m.body = renderMonitoringWindow(m.monData, m.monProcesses, m.monCursor, m.monitoringWindowRows())
		} else if m.tab == TabConfig && m.config != nil && m.template != nil {
			m.body = renderSelectedConfig(m.config, m.template, m.showTemplate)
		}

	case statusMsg:
		m.status = msg.text

	case bodyMsg:
		if msg.tab == m.tab {
			m.body, m.err = appendActionHints(msg.text, msg.tab), msg.err
			m.resources = nil
			m.cursor = 0
		}

	case resourceMsg:
		if msg.tab == m.tab {
			m.resources = msg.items
			if m.cursor >= len(m.resources) {
				m.cursor = max(0, len(m.resources)-1)
			}
			m.body = renderResourceItems(m.resources, m.cursor, m.profile, m.tab, m.listWindowRows())
			if msg.tab == TabProfiles {
				m.template = msg.template
				if msg.warning != "" {
					m.body += "\n" + errStyle.Render(msg.warning)
				}
			}
			m.err = ""
		}

	case configMsg:
		if m.tab == TabConfig {
			m.config, m.template = msg.config, msg.template
			if msg.err != "" {
				m.body, m.err = "", msg.err
			} else {
				m.body = renderSelectedConfig(msg.config, msg.template, m.showTemplate)
				m.err = ""
			}
		}

	case monitoringMsg:
		if m.tab == TabMonitoring {
			m.monProcesses = msg.processes
			m.monData = msg.data
			// Clamp cursor to valid range after refresh.
			if m.monCursor >= len(m.monProcesses) {
				m.monCursor = max(0, len(m.monProcesses)-1)
			}
			m.body = renderMonitoringWindow(msg.data, m.monProcesses, m.monCursor, m.monitoringWindowRows())
			m.err = ""
		}

	case tea.KeyMsg:
		if m.action.phase == actionBusy && isNavigationKey(msg.String()) {
			m.clearAction()
		} else {
			if updated, cmd, handled := m.updateActionKey(msg); handled {
				return updated, cmd
			}
		}
		switch msg.String() {
		case "q", "ctrl+c":
			m.cancelAction()
			return m, tea.Quit
		case "?":
			m.showHelp = !m.showHelp
			return m, nil
		case "right", "l":
			m.cancelAction()
			m.tab = (m.tab + 1) % len(Tabs)
			m.prepareTabRefresh()
			return m, m.loadScopedTab(m.tab)
		case "left", "h":
			m.cancelAction()
			m.tab = (m.tab - 1 + len(Tabs)) % len(Tabs)
			m.prepareTabRefresh()
			return m, m.loadScopedTab(m.tab)
		case "r":
			m.cancelAction()
			m.prepareTabRefresh()
			return m, tea.Batch(m.loadScopedStatus(), m.loadScopedTab(m.tab))
		}

		// Monitoring-specific process selection.
		if m.tab == TabMonitoring && len(m.monProcesses) > 0 {
			switch msg.String() {
			case "down", "j":
				m.monCursor = (m.monCursor + 1) % len(m.monProcesses)
				m.body = renderMonitoringWindow(m.monData, m.monProcesses, m.monCursor, m.monitoringWindowRows())
				return m, nil
			case "up":
				m.monCursor = (m.monCursor - 1 + len(m.monProcesses)) % len(m.monProcesses)
				m.body = renderMonitoringWindow(m.monData, m.monProcesses, m.monCursor, m.monitoringWindowRows())
				return m, nil
			}
		}

		if isSelectableTab(m.tab) && len(m.resources) > 0 {
			switch msg.String() {
			case "down", "j":
				m.cursor = (m.cursor + 1) % len(m.resources)
				m.body = renderResourceItems(m.resources, m.cursor, m.profile, m.tab, m.listWindowRows())
				return m, nil
			case "up":
				m.cursor = (m.cursor - 1 + len(m.resources)) % len(m.resources)
				m.body = renderResourceItems(m.resources, m.cursor, m.profile, m.tab, m.listWindowRows())
				return m, nil
			case "enter":
				if m.tab == TabProfiles {
					return m.selectProfile()
				}
			}
		}

		if m.tab == TabConfig && msg.String() == "v" && m.config != nil && m.template != nil {
			m.showTemplate = !m.showTemplate
			m.body = renderSelectedConfig(m.config, m.template, m.showTemplate)
			return m, nil
		}

		if spec, actionErr, handled := m.actionForKey(msg.String()); handled {
			if actionErr != nil {
				m.action = actionState{phase: actionFailure, spec: actionSpec{title: "Action unavailable"}, message: actionErr.Error()}
				return m, nil
			}
			return m.beginAction(spec)
		}

		// 1-9 and 0 shortcut keys for tabs 1-10 (11th tab = 0)
		if len(msg.String()) == 1 {
			ch := msg.String()[0]
			if ch >= '1' && ch <= '9' {
				idx := int(ch - '1')
				if idx < len(Tabs) {
					m.cancelAction()
					m.tab = idx
					m.prepareTabRefresh()
					return m, m.loadScopedTab(m.tab)
				}
			}
			if ch == '0' && len(Tabs) >= 10 {
				m.cancelAction()
				m.tab = 9
				m.prepareTabRefresh()
				return m, m.loadScopedTab(m.tab)
			}
		}
	}
	return m, nil
}

func (m Model) selectProfile() (tea.Model, tea.Cmd) {
	item, err := m.selectedResource()
	if err != nil {
		m.action = actionState{phase: actionFailure, spec: actionSpec{title: "Select profile"}, message: err.Error()}
		return m, nil
	}
	m.profile = item.Name
	m.config = nil
	m.showTemplate = false
	m.monProcesses = nil
	m.monCursor = 0
	m.prepareTabRefresh()
	m.action = actionState{
		phase:   actionSuccess,
		spec:    actionSpec{title: "Select profile"},
		message: fmt.Sprintf("Active profile is now %q; every surface is refreshing", item.Name),
	}
	// Reload status and the active Profiles tab immediately. All other tabs use
	// m.profile on their next load, so there is no stale daemon scope.
	return m, tea.Batch(m.loadScopedStatus(), m.loadScopedTab(m.tab))
}

func isSelectableTab(tab int) bool {
	switch tab {
	case TabContainers, TabImages, TabVolumes, TabNetworks, TabProfiles, TabMachines:
		return true
	default:
		return false
	}
}

func appendActionHints(body string, tab int) string {
	hints := actionHints(tab)
	if hints == "" {
		return body
	}
	return body + "\n\nActions: " + hints
}

func isNavigationKey(key string) bool {
	if key == "left" || key == "right" || key == "h" || key == "l" || key == "r" {
		return true
	}
	return len(key) == 1 && key[0] >= '0' && key[0] <= '9'
}

func (m *Model) prepareTabRefresh() {
	m.loadSeq++
	m.body = "Loading…"
	m.err = ""
	if isSelectableTab(m.tab) {
		m.resources = nil
		m.cursor = 0
	}
	if m.tab == TabMonitoring {
		m.monProcesses = nil
		m.monCursor = 0
		m.monData = monitoringData{}
	}
	if m.tab == TabConfig {
		m.config = nil
	}
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
	if m.action.phase != actionIdle {
		body = strings.TrimPrefix(m.actionView(), "\n\n")
	} else if m.err != "" {
		body = errStyle.Render("error: " + m.err)
	}

	helpLine := barStyle.Render("←/→ tabs · 1-0 jump · r refresh · ? help · q quit")
	if m.action.phase != actionIdle {
		helpLine = barStyle.Render("action active · Ctrl+C quit")
	} else if m.showHelp {
		helpLine = helpView(m.tab)
	}

	footerStatus := barStyle.Render(m.status)

	return fmt.Sprintf("%s\n%s\n\n%s\n\n%s\n%s",
		header, divider, body, divider, footerStatus+"  "+helpLine)
}

func helpView(tab int) string {
	lines := []string{
		"Keybindings:",
		"  ←/→  h/l     navigate tabs",
		"  1-9 / 0       jump to tab 1-10",
		"  r              refresh current tab",
		"  ?              toggle help",
		"  q  ctrl+c     quit",
		"  Esc            cancel/close action",
		"",
		"Tabs:",
		"  1 Dashboard    2 Containers   3 Images",
		"  4 Volumes      5 Networks     6 Kubernetes",
		"  7 Configuration 8 Runtime     9 AI Workloads",
		"  0 Profiles    (→) Machines  (→) Monitoring",
	}
	if hints := actionHints(tab); hints != "" {
		lines = append(lines, "", "Current tab actions:", "  "+hints)
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
	return renderMonitoringWindow(md, procs, cursor, len(procs))
}

func renderMonitoringWindow(md monitoringData, procs []*pb.ProcessInfo, cursor, maxRows int) string {
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
		start, end := visibleRange(len(procs), cursor, maxRows)
		for i := start; i < end; i++ {
			p := procs[i]
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
		if start > 0 || end < len(procs) {
			fmt.Fprintf(&b, "  showing %d-%d of %d\n", start+1, end, len(procs))
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
	fmt.Fprintf(&b, "Compute:     CPU=%d memory=%.1fGiB disk=%dGiB root=%dGiB\n", cfg.Cpu, cfg.Memory, cfg.Disk, cfg.RootDisk)
	fmt.Fprintf(&b, "VM:          arch=%s type=%s cpu-type=%s hostname=%s\n", cfg.Arch, cfg.VmType, cfg.CpuType, cfg.Hostname)
	fmt.Fprintf(&b, "Features:    rosetta=%v nested=%v binfmt=%v\n", cfg.Rosetta, cfg.NestedVirtualization, cfg.Binfmt)
	fmt.Fprintf(&b, "Runtime:     %s auto-activate=%v model-runner=%s\n", cfg.Runtime, cfg.AutoActivate, cfg.ModelRunner)
	fmt.Fprintf(&b, "Mount:       type=%s notify=%v entries=%d\n", cfg.MountType, cfg.MountInotify, len(cfg.Mounts))
	fmt.Fprintf(&b, "SSH:         config=%v port=%d forward-agent=%v\n", cfg.SshConfig, cfg.SshPort, cfg.ForwardAgent)
	if cfg.Network != nil {
		fmt.Fprintf(&b, "Network:     address=%v mode=%s interface=%s gateway=%s\n",
			cfg.Network.Address, cfg.Network.Mode, cfg.Network.Interface, cfg.Network.GatewayAddress)
	}
	if cfg.Kubernetes != nil {
		fmt.Fprintf(&b, "Kubernetes:  enabled=%v version=%s port=%d args=%s\n",
			cfg.Kubernetes.Enabled, cfg.Kubernetes.Version, cfg.Kubernetes.Port, strings.Join(cfg.Kubernetes.K3SArgs, " "))
	}
	fmt.Fprintf(&b, "Collections: docker=%d provision=%d env=%d\n", len(cfg.Docker), len(cfg.Provision), len(cfg.Env))
	return b.String()
}

func renderSelectedConfig(config, template *pb.ColimaConfig, showTemplate bool) string {
	title := "Profile configuration"
	selected := config
	if showTemplate {
		title = "Global configuration template"
		selected = template
	}
	return titleStyle.Render(title) + "\n" + renderConfig(selected) + "\nActions: " + actionHints(TabConfig)
}

func renderResourceItems(items []resourceItem, cursor int, profile string, tab, maxRows int) string {
	if len(items) == 0 {
		return appendActionHints("(none)", tab)
	}
	var b strings.Builder
	if tab != TabProfiles && tab != TabMachines {
		fmt.Fprintf(&b, "Profile: %s\n", profile)
	}
	start, end := visibleRange(len(items), cursor, maxRows)
	for i := start; i < end; i++ {
		item := items[i]
		prefix := "  "
		if i == cursor {
			prefix = "> "
		}
		fmt.Fprintf(&b, "%s%s", prefix, item.Name)
		if item.Summary != "" && item.Summary != item.Name {
			fmt.Fprintf(&b, "  %s", item.Summary)
		}
		if item.ID != "" && item.ID != item.Name {
			fmt.Fprintf(&b, "  [%s]", item.ID)
		}
		b.WriteByte('\n')
	}
	if start > 0 || end < len(items) {
		fmt.Fprintf(&b, "  showing %d-%d of %d\n", start+1, end, len(items))
	}
	return appendActionHints(strings.TrimRight(b.String(), "\n"), tab)
}

func visibleRange(length, cursor, maxRows int) (int, int) {
	if maxRows <= 0 || maxRows > length {
		maxRows = length
	}
	start := cursor - maxRows/2
	if start < 0 {
		start = 0
	}
	if start+maxRows > length {
		start = max(0, length-maxRows)
	}
	return start, start + maxRows
}

func (m Model) listWindowRows() int {
	if m.height <= 0 {
		return 12
	}
	return max(3, m.height-12)
}

func (m Model) monitoringWindowRows() int {
	if m.height <= 0 {
		return 10
	}
	return max(3, m.height-18)
}

func parseResourceList(tab int, raw string, idKeys, nameKeys, summaryKeys []string) tea.Msg {
	if strings.TrimSpace(raw) == "" {
		return resourceMsg{tab: tab}
	}
	var values []map[string]any
	if err := json.Unmarshal([]byte(raw), &values); err != nil {
		var wrapped map[string]json.RawMessage
		if wrappedErr := json.Unmarshal([]byte(raw), &wrapped); wrappedErr != nil {
			return bodyMsg{tab: tab, text: raw}
		}
		for _, key := range []string{"Volumes", "volumes", "Items", "items"} {
			if payload, ok := wrapped[key]; ok {
				if listErr := json.Unmarshal(payload, &values); listErr != nil {
					return bodyMsg{tab: tab, text: raw}
				}
				break
			}
		}
		if values == nil {
			return bodyMsg{tab: tab, text: raw}
		}
	}
	items := make([]resourceItem, 0, len(values))
	for _, value := range values {
		name := firstString(value, nameKeys...)
		if tab == TabContainers {
			name = strings.TrimPrefix(name, "/")
		}
		id := firstString(value, idKeys...)
		if id == "(unnamed)" {
			id = name
		}
		summaryParts := make([]string, 0, len(summaryKeys))
		for _, key := range summaryKeys {
			part := firstString(value, key)
			if part != "(unnamed)" && part != name && part != id {
				summaryParts = append(summaryParts, part)
			}
		}
		items = append(items, resourceItem{ID: id, Name: name, Summary: strings.Join(summaryParts, " · ")})
	}
	return resourceMsg{tab: tab, items: items}
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

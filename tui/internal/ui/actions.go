package ui

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	pb "github.com/colima-desktop/daemon/proto"
	"github.com/colima-desktop/tui/internal/action"
	"google.golang.org/protobuf/proto"
)

type actionPhase uint8

const (
	actionIdle actionPhase = iota
	actionPrompt
	actionConfirm
	actionBusy
	actionSuccess
	actionFailure
	actionCanceled
)

type promptField struct {
	name       string
	label      string
	value      string
	validate   func(string) error
	allowEmpty bool
}

type actionSpec struct {
	title       string
	note        string
	request     action.Request
	fields      []promptField
	build       func(map[string]string) (action.Request, error)
	destructive bool
	confirm     string
	stream      bool
	refresh     bool
}

type actionState struct {
	phase      actionPhase
	spec       actionSpec
	field      int
	fieldError string
	request    action.Request
	message    string
	output     string
	outputLine int
	progress   float32
	stage      string
	cancel     context.CancelFunc
	seq        uint64
}

type actionResultMsg struct {
	seq    uint64
	result action.Result
	err    error
}

type actionStreamOpenMsg struct {
	seq    uint64
	stream action.ProgressStream
	err    error
}

type actionProgressMsg struct {
	seq    uint64
	stream action.ProgressStream
	event  *pb.ProgressEvent
	err    error
}

func (m Model) beginAction(spec actionSpec) (Model, tea.Cmd) {
	m.clearAction()
	m.showHelp = false
	m.action.spec = spec
	if len(spec.fields) != 0 {
		m.action.phase = actionPrompt
		m.action.field = 0
		return m, nil
	}
	return m.finishPrompt()
}

func (m Model) finishPrompt() (Model, tea.Cmd) {
	values := make(map[string]string, len(m.action.spec.fields))
	for _, field := range m.action.spec.fields {
		values[field.name] = field.value
	}
	req := m.action.spec.request
	if m.action.spec.build != nil {
		var err error
		req, err = m.action.spec.build(values)
		if err != nil {
			m.action.phase = actionFailure
			m.action.message = err.Error()
			return m, nil
		}
	}
	m.action.request = req
	if m.action.spec.destructive {
		m.action.phase = actionConfirm
		m.action.message = m.action.spec.confirm
		return m, nil
	}
	return m.launchAction()
}

func (m Model) launchAction() (Model, tea.Cmd) {
	m.actionSeq++
	seq := m.actionSeq
	cx, cancel := context.WithCancel(context.Background())
	m.action.phase = actionBusy
	m.action.cancel = cancel
	m.action.seq = seq
	m.action.message = "Working…"
	m.action.output = ""
	m.action.progress = 0
	m.action.stage = ""
	req := m.action.request
	cli := m.cli
	if m.action.spec.stream {
		return m, func() tea.Msg {
			stream, err := cli.OpenProgress(cx, req)
			return actionStreamOpenMsg{seq: seq, stream: stream, err: err}
		}
	}
	return m, func() tea.Msg {
		result, err := cli.RunAction(cx, req)
		return actionResultMsg{seq: seq, result: result, err: err}
	}
}

func recvProgress(seq uint64, stream action.ProgressStream) tea.Cmd {
	return func() tea.Msg {
		event, err := stream.Recv()
		return actionProgressMsg{seq: seq, stream: stream, event: event, err: err}
	}
}

func (m Model) updateActionMessage(msg tea.Msg) (Model, tea.Cmd, bool) {
	switch msg := msg.(type) {
	case actionResultMsg:
		if msg.seq != m.action.seq || m.action.phase != actionBusy {
			return m, nil, true
		}
		m.finishActionContext()
		if msg.err != nil {
			m.action.phase = actionFailure
			m.action.message = msg.err.Error()
			return m, nil, true
		}
		m.action.phase = actionSuccess
		m.action.message = "Completed"
		m.action.output = boundedPretty(msg.result.Text)
		m.action.outputLine = 0
		m.prepareActionRefresh()
		return m, m.refreshAfterAction(), true

	case actionStreamOpenMsg:
		if msg.seq != m.action.seq || m.action.phase != actionBusy {
			return m, nil, true
		}
		if msg.err != nil {
			m.finishActionContext()
			m.action.phase = actionFailure
			m.action.message = msg.err.Error()
			return m, nil, true
		}
		if msg.stream == nil {
			m.finishActionContext()
			m.action.phase = actionFailure
			m.action.message = "daemon returned an empty progress stream"
			return m, nil, true
		}
		return m, recvProgress(msg.seq, msg.stream), true

	case actionProgressMsg:
		if msg.seq != m.action.seq || m.action.phase != actionBusy {
			return m, nil, true
		}
		if errors.Is(msg.err, io.EOF) {
			m.finishActionContext()
			m.action.phase = actionSuccess
			m.action.message = "Completed"
			m.prepareActionRefresh()
			return m, m.refreshAfterAction(), true
		}
		if msg.err != nil {
			m.finishActionContext()
			m.action.phase = actionFailure
			m.action.message = msg.err.Error()
			return m, nil, true
		}
		if msg.event == nil {
			m.finishActionContext()
			m.action.phase = actionFailure
			m.action.message = "daemon returned an empty progress event"
			return m, nil, true
		}
		if msg.event.GetError() != "" {
			m.finishActionContext()
			m.action.phase = actionFailure
			m.action.message = msg.event.GetError()
			return m, nil, true
		}
		m.action.progress = msg.event.GetProgress()
		m.action.stage = msg.event.GetStage()
		m.action.message = orEmpty(msg.event.GetMessage(), "Working…")
		m.action.appendOutput(msg.event.GetMessage())
		if msg.event.GetDone() {
			m.finishActionContext()
			m.action.phase = actionSuccess
			m.action.message = orEmpty(msg.event.GetMessage(), "Completed")
			m.prepareActionRefresh()
			return m, m.refreshAfterAction(), true
		}
		return m, recvProgress(msg.seq, msg.stream), true
	}
	return m, nil, false
}

func (m Model) updateActionKey(msg tea.KeyMsg) (Model, tea.Cmd, bool) {
	if m.action.phase == actionIdle {
		return m, nil, false
	}
	key := msg.String()
	if key == "ctrl+c" {
		m.cancelAction()
		return m, tea.Quit, true
	}
	if key == "esc" || key == "ctrl+[" {
		if m.action.phase == actionBusy {
			m.cancelAction()
			m.action.phase = actionCanceled
			m.action.message = "Canceled"
		} else {
			m.clearAction()
		}
		return m, nil, true
	}

	switch m.action.phase {
	case actionPrompt:
		field := &m.action.spec.fields[m.action.field]
		switch msg.Type {
		case tea.KeyEnter:
			value := strings.TrimSpace(field.value)
			if value == "" && !field.allowEmpty {
				m.action.fieldError = field.label + " is required"
				return m, nil, true
			}
			if field.validate != nil {
				if err := field.validate(value); err != nil {
					m.action.fieldError = err.Error()
					return m, nil, true
				}
			}
			field.value = value
			m.action.fieldError = ""
			if m.action.field+1 < len(m.action.spec.fields) {
				m.action.field++
				return m, nil, true
			}
			returnResult, cmd := m.finishPrompt()
			return returnResult, cmd, true
		case tea.KeyBackspace, tea.KeyDelete:
			if field.value != "" {
				_, size := utf8.DecodeLastRuneInString(field.value)
				field.value = field.value[:len(field.value)-size]
			}
			m.action.fieldError = ""
			return m, nil, true
		case tea.KeyRunes:
			field.value += string(msg.Runes)
			m.action.fieldError = ""
			return m, nil, true
		}
		if key == "ctrl+u" {
			field.value = ""
			m.action.fieldError = ""
			return m, nil, true
		}
		return m, nil, true

	case actionConfirm:
		if key == "y" || key == "Y" {
			launched, cmd := m.launchAction()
			return launched, cmd, true
		}
		if key == "n" || key == "N" {
			m.clearAction()
		}
		return m, nil, true

	case actionBusy:
		if key == "q" {
			m.cancelAction()
			return m, tea.Quit, true
		}
		return m, nil, true

	case actionSuccess, actionFailure, actionCanceled:
		if key == "q" {
			return m, tea.Quit, true
		}
		if key == "enter" || key == " " {
			m.clearAction()
			return m, nil, true
		}
		if m.action.phase == actionSuccess && m.action.output != "" {
			lines := strings.Split(m.action.output, "\n")
			page := m.actionOutputRows()
			maxLine := max(0, len(lines)-page)
			if m.action.outputLine > maxLine {
				m.action.outputLine = maxLine
			}
			switch key {
			case "down", "j":
				m.action.outputLine = min(maxLine, m.action.outputLine+1)
			case "up", "k":
				m.action.outputLine = max(0, m.action.outputLine-1)
			case "pgdown":
				m.action.outputLine = min(maxLine, m.action.outputLine+page)
			case "pgup":
				m.action.outputLine = max(0, m.action.outputLine-page)
			case "home", "g":
				m.action.outputLine = 0
			case "end", "G":
				m.action.outputLine = maxLine
			}
		}
		return m, nil, true
	}
	return m, nil, true
}

func (m *Model) finishActionContext() {
	if m.action.cancel != nil {
		m.action.cancel()
		m.action.cancel = nil
	}
}

func (m *Model) cancelAction() {
	m.finishActionContext()
	m.actionSeq++
}

func (m *Model) clearAction() {
	m.cancelAction()
	m.action = actionState{}
}

func (m Model) refreshAfterAction() tea.Cmd {
	if !m.action.spec.refresh {
		return nil
	}
	return tea.Batch(m.loadScopedStatus(), m.loadScopedTab(m.tab))
}

func (m *Model) prepareActionRefresh() {
	if !m.action.spec.refresh {
		return
	}
	m.prepareTabRefresh()
}

func (m Model) actionView() string {
	if m.action.phase == actionIdle {
		return ""
	}
	var b strings.Builder
	fmt.Fprintf(&b, "\n\n%s\n", titleStyle.Render(m.action.spec.title))
	if m.action.spec.note != "" {
		b.WriteString(m.action.spec.note + "\n")
	}
	switch m.action.phase {
	case actionPrompt:
		field := m.action.spec.fields[m.action.field]
		fmt.Fprintf(&b, "Step %d/%d — %s\n> %s█", m.action.field+1, len(m.action.spec.fields), field.label, field.value)
		if m.action.fieldError != "" {
			fmt.Fprintf(&b, "\n%s", errStyle.Render(m.action.fieldError))
		}
		b.WriteString("\nEnter continue · Backspace edit · Ctrl+U clear · Esc cancel")
	case actionConfirm:
		b.WriteString(errStyle.Render("Confirmation required") + "\n")
		b.WriteString(m.action.message + "\n")
		b.WriteString("[y] confirm · [n]/Esc cancel")
	case actionBusy:
		pct := int(m.action.progress * 100)
		if pct < 0 {
			pct = 0
		}
		if pct > 100 {
			pct = 100
		}
		if m.action.spec.stream {
			fmt.Fprintf(&b, "%s %d%%\n", orEmpty(m.action.stage, "progress"), pct)
		}
		if m.action.output != "" {
			view, _, _, _ := outputViewport(m.action.output, 1<<30, m.actionOutputRows())
			b.WriteString(view)
		} else {
			b.WriteString(m.action.message)
		}
		b.WriteString("\nEsc cancel")
	case actionSuccess:
		b.WriteString("Success: " + m.action.message)
		if m.action.output != "" {
			view, start, end, total := outputViewport(m.action.output, m.action.outputLine, m.actionOutputRows())
			fmt.Fprintf(&b, "\nOutput lines %d-%d/%d:\n%s", start+1, end, total, view)
			if total > m.actionOutputRows() {
				b.WriteString("\n↑/↓ or PgUp/PgDn scroll · g/G top/bottom")
			}
		}
		b.WriteString("\nEnter/Esc close")
	case actionFailure:
		b.WriteString(errStyle.Render("Error: "+m.action.message) + "\nEnter/Esc close")
	case actionCanceled:
		b.WriteString("Canceled\nEnter/Esc close")
	}
	return b.String()
}

// Output buffers are bounded so a chatty stream or a large unary payload cannot
// exhaust memory: the newest content is retained and the oldest is dropped.
// Lines are the primary ring (drop-oldest); a byte ceiling is a secondary guard
// against pathologically long single lines. Both the streaming progress path
// (appendOutput) and the unary result path (boundedPretty) share this bound so
// no code path can accumulate an unbounded amount of daemon output.
const (
	maxOutputLines = 2000
	maxOutputBytes = 256 * 1024
)

// boundOutput caps text to at most maxOutputLines lines and maxOutputBytes
// bytes, always keeping the newest content. It never returns invalid UTF-8 and
// never keeps a leading partial line after a byte-level trim.
func boundOutput(text string) string {
	if len(text) > maxOutputBytes {
		text = text[len(text)-maxOutputBytes:]
		if newline := strings.IndexByte(text, '\n'); newline >= 0 {
			text = text[newline+1:]
		}
		text = strings.ToValidUTF8(text, "")
	}
	if lines := strings.Split(text, "\n"); len(lines) > maxOutputLines {
		text = strings.Join(lines[len(lines)-maxOutputLines:], "\n")
	}
	return text
}

// boundedPretty bounds a unary result payload for display. An oversized payload
// skips JSON pretty-printing — which would parse and re-indent the entire blob,
// spiking memory — and is bounded as raw text instead; smaller payloads are
// pretty-printed then bounded.
func boundedPretty(raw string) string {
	if len(raw) > maxOutputBytes {
		return boundOutput(raw)
	}
	return boundOutput(prettyOutput(raw))
}

func (state *actionState) appendOutput(message string) {
	message = strings.TrimSpace(message)
	if message == "" {
		return
	}
	if state.output != "" {
		state.output += "\n"
	}
	state.output += message
	state.output = boundOutput(state.output)
	state.outputLine = 1 << 30 // streaming output follows the newest bounded line
}

func outputViewport(output string, offset, maxRows int) (string, int, int, int) {
	lines := strings.Split(output, "\n")
	if maxRows <= 0 {
		maxRows = 1
	}
	maxOffset := max(0, len(lines)-maxRows)
	if offset < 0 {
		offset = 0
	}
	if offset > maxOffset {
		offset = maxOffset
	}
	end := min(len(lines), offset+maxRows)
	return strings.Join(lines[offset:end], "\n"), offset, end, len(lines)
}

func (m Model) actionOutputRows() int {
	if m.height <= 0 {
		return 12
	}
	return max(3, m.height-12)
}

func prettyOutput(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	var value any
	if json.Unmarshal([]byte(raw), &value) == nil {
		if formatted, err := json.MarshalIndent(value, "", "  "); err == nil {
			return string(formatted)
		}
	}
	return raw
}

func (m Model) selectedResource() (resourceItem, error) {
	if len(m.resources) == 0 {
		return resourceItem{}, errors.New("no resource is available for this action")
	}
	if m.cursor < 0 || m.cursor >= len(m.resources) {
		return resourceItem{}, errors.New("no resource is selected")
	}
	return m.resources[m.cursor], nil
}

func (m Model) actionForKey(key string) (actionSpec, error, bool) {
	profile := m.profile
	selected := func() (resourceItem, error) { return m.selectedResource() }
	unary := func(title string, req action.Request, refresh bool) actionSpec {
		return actionSpec{title: title, request: req, refresh: refresh}
	}
	stream := func(title string, req action.Request, refresh bool) actionSpec {
		return actionSpec{title: title, request: req, stream: true, refresh: refresh}
	}
	destructive := func(spec actionSpec, confirm string) actionSpec {
		spec.destructive = true
		spec.confirm = confirm
		return spec
	}

	switch m.tab {
	case TabDashboard:
		switch key {
		case "s":
			return stream("Start VM", action.Request{Kind: action.VMStart, Profile: profile}, true), nil, true
		case "x":
			return unary("Stop VM", action.Request{Kind: action.VMStop, Profile: profile}, true), nil, true
		case "R":
			return stream("Restart VM", action.Request{Kind: action.VMRestart, Profile: profile}, true), nil, true
		case "D":
			spec := unary("Delete VM", action.Request{Kind: action.VMDelete, Profile: profile, Data: true}, true)
			return destructive(spec, fmt.Sprintf("Delete profile %q VM and its data?", profile)), nil, true
		case "U":
			return unary("Update Colima", action.Request{Kind: action.VMUpdate, Profile: profile}, true), nil, true
		case "P":
			spec := unary("Prune Colima", action.Request{Kind: action.VMPrune, Profile: profile, All: true}, true)
			return destructive(spec, fmt.Sprintf("Prune cached Colima resources for profile %q?", profile)), nil, true
		case "H":
			return unary("SSH configuration", action.Request{Kind: action.VMSSHConfig, Profile: profile}, false), nil, true
		}

	case TabContainers:
		if key == "n" {
			spec := actionSpec{title: "Create container", refresh: true, fields: []promptField{
				{name: "name", label: "Container name", validate: validateName},
				{name: "image", label: "Image reference", validate: required("image")},
			}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ContainerNew, Profile: profile, Name: v["name"], Target: v["image"]}, nil
			}
			return spec, nil, true
		}
		if key == "P" {
			spec := unary("Prune containers", action.Request{Kind: action.ContainerPrune, Profile: profile}, true)
			return destructive(spec, fmt.Sprintf("Remove all stopped containers in profile %q?", profile)), nil, true
		}
		item, err := selected()
		if err != nil {
			return actionSpec{}, err, isContainerActionKey(key)
		}
		req := action.Request{Kind: action.ContainerDo, Profile: profile, ID: item.ID}
		switch key {
		case "s", "x", "R", "k", "p", "u", "d":
			actions := map[string]string{"s": "start", "x": "stop", "R": "restart", "k": "kill", "p": "pause", "u": "unpause", "d": "remove"}
			req.Action = actions[key]
			spec := unary(strings.Title(req.Action)+" container", req, true) //nolint:staticcheck // stable UI label
			if key == "k" || key == "d" {
				spec = destructive(spec, fmt.Sprintf("%s container %q (%s)?", strings.Title(req.Action), item.Name, item.ID)) //nolint:staticcheck
			}
			return spec, nil, true
		case "e":
			spec := actionSpec{title: "Rename container", refresh: true, fields: []promptField{{name: "name", label: "New name", value: item.Name, validate: validateName}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ContainerName, Profile: profile, ID: item.ID, NewName: v["name"]}, nil
			}
			return spec, nil, true
		case "g":
			return unary("Container logs", action.Request{Kind: action.ContainerLogs, Profile: profile, ID: item.ID}, false), nil, true
		case "i":
			return unary("Inspect container", action.Request{Kind: action.ContainerInfo, Profile: profile, ID: item.ID}, false), nil, true
		case "t":
			return unary("Container processes", action.Request{Kind: action.ContainerTop, Profile: profile, ID: item.ID}, false), nil, true
		case "a":
			return unary("Container stats", action.Request{Kind: action.ContainerStat, Profile: profile, ID: item.ID}, false), nil, true
		case "c":
			return unary("Container changes", action.Request{Kind: action.ContainerDiff, Profile: profile, ID: item.ID}, false), nil, true
		}

	case TabImages:
		if key == "p" {
			spec := actionSpec{title: "Pull image", stream: true, refresh: true, fields: []promptField{{name: "name", label: "Image reference", validate: required("image")}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ImagePull, Profile: profile, Name: v["name"]}, nil
			}
			return spec, nil, true
		}
		if key == "s" {
			spec := actionSpec{title: "Search images", fields: []promptField{{name: "term", label: "Search term", validate: required("search term")}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ImageSearch, Profile: profile, Term: v["term"]}, nil
			}
			return spec, nil, true
		}
		if key == "P" {
			spec := unary("Prune images", action.Request{Kind: action.ImagePrune, Profile: profile, All: true}, true)
			return destructive(spec, fmt.Sprintf("Remove all unused images in profile %q?", profile)), nil, true
		}
		item, err := selected()
		if err != nil {
			return actionSpec{}, err, isImageActionKey(key)
		}
		switch key {
		case "u":
			return stream("Push image", action.Request{Kind: action.ImagePush, Profile: profile, Name: item.Name}, false), nil, true
		case "d":
			spec := unary("Remove image", action.Request{Kind: action.ImageRemove, Profile: profile, ID: item.ID}, true)
			return destructive(spec, fmt.Sprintf("Remove image %q (%s)?", item.Name, item.ID)), nil, true
		case "t":
			spec := actionSpec{title: "Tag image", refresh: true, fields: []promptField{
				{name: "repo", label: "Repository", validate: required("repository")},
				{name: "tag", label: "Tag", value: "latest", validate: required("tag")},
			}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ImageTag, Profile: profile, Name: item.Name, Repository: v["repo"], Tag: v["tag"]}, nil
			}
			return spec, nil, true
		case "H":
			return unary("Image history", action.Request{Kind: action.ImageHistory, Profile: profile, Name: item.Name}, false), nil, true
		case "i":
			return unary("Inspect image", action.Request{Kind: action.ImageInspect, Profile: profile, Name: item.Name}, false), nil, true
		}

	case TabVolumes:
		if key == "n" {
			return namedCreateSpec("Create volume", action.VolumeCreate, profile), nil, true
		}
		if key == "P" {
			spec := unary("Prune volumes", action.Request{Kind: action.VolumePrune, Profile: profile}, true)
			return destructive(spec, fmt.Sprintf("Remove all unused volumes in profile %q?", profile)), nil, true
		}
		item, err := selected()
		if err != nil {
			return actionSpec{}, err, key == "d" || key == "i"
		}
		if key == "d" {
			spec := unary("Remove volume", action.Request{Kind: action.VolumeRemove, Profile: profile, Name: item.Name}, true)
			return destructive(spec, fmt.Sprintf("Permanently remove volume %q?", item.Name)), nil, true
		}
		if key == "i" {
			return unary("Inspect volume", action.Request{Kind: action.VolumeInspect, Profile: profile, Name: item.Name}, false), nil, true
		}

	case TabNetworks:
		if key == "n" {
			return namedCreateSpec("Create network", action.NetworkCreate, profile), nil, true
		}
		if key == "P" {
			spec := unary("Prune networks", action.Request{Kind: action.NetworkPrune, Profile: profile}, true)
			return destructive(spec, fmt.Sprintf("Remove all unused networks in profile %q?", profile)), nil, true
		}
		item, err := selected()
		if err != nil {
			return actionSpec{}, err, isNetworkActionKey(key)
		}
		switch key {
		case "d":
			spec := unary("Remove network", action.Request{Kind: action.NetworkRemove, Profile: profile, ID: item.ID}, true)
			return destructive(spec, fmt.Sprintf("Remove network %q (%s)?", item.Name, item.ID)), nil, true
		case "i":
			return unary("Inspect network", action.Request{Kind: action.NetworkInspect, Profile: profile, ID: item.ID}, false), nil, true
		case "c", "x":
			kind := action.NetworkConnect
			title := "Connect network"
			if key == "x" {
				kind, title = action.NetworkDisconnect, "Disconnect network"
			}
			spec := actionSpec{title: title, refresh: true, fields: []promptField{{name: "container", label: "Container ID or name", validate: required("container")}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: kind, Profile: profile, ID: item.ID, ContainerID: v["container"]}, nil
			}
			if key == "x" {
				spec.destructive = true
				spec.confirm = fmt.Sprintf("Disconnect the entered container from network %q?", item.Name)
			}
			return spec, nil, true
		}

	case TabKubernetes:
		switch key {
		case "s":
			return unary("Start Kubernetes", action.Request{Kind: action.KubeStart, Profile: profile}, true), nil, true
		case "x":
			return unary("Stop Kubernetes", action.Request{Kind: action.KubeStop, Profile: profile}, true), nil, true
		case "R":
			spec := unary("Reset Kubernetes", action.Request{Kind: action.KubeReset, Profile: profile}, true)
			return destructive(spec, fmt.Sprintf("Reset Kubernetes state in profile %q?", profile)), nil, true
		case "e":
			spec := actionSpec{title: "Run kubectl command", fields: []promptField{{name: "command", label: "Command (without kubectl)", value: "get pods -A", validate: required("command")}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.KubeExec, Profile: profile, Command: v["command"]}, nil
			}
			return spec, nil, true
		}

	case TabConfig:
		if key == "e" || key == "t" {
			base := m.config
			kind := action.ConfigSet
			title := "Edit profile configuration"
			if key == "t" {
				base, kind, title = m.template, action.TemplateSet, "Edit global configuration template"
			}
			if base == nil {
				return actionSpec{}, errors.New("configuration has not loaded; press r and try again"), true
			}
			return configSpec(title, kind, profile, base), nil, true
		}

	case TabRuntime:
		if key == "u" {
			return unary("Update runtime", action.Request{Kind: action.RuntimeUpdate, Profile: profile}, true), nil, true
		}
		runtimes := map[string]string{"d": "docker", "c": "containerd", "i": "incus"}
		if runtime, ok := runtimes[key]; ok {
			spec := unary("Switch runtime", action.Request{Kind: action.RuntimeSwitch, Profile: profile, Runtime: runtime}, true)
			return destructive(spec, fmt.Sprintf("Switch profile %q to %s? The VM may need to be stopped and existing runtime data is not migrated.", profile, runtime)), nil, true
		}

	case TabAI:
		switch key {
		case "s":
			spec := actionSpec{title: "Set up model runner", stream: true, refresh: true, fields: []promptField{{name: "runner", label: "Runner (docker or ramalama)", value: "docker", validate: validateRunner}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ModelSetup, Profile: profile, Runner: v["runner"]}, nil
			}
			return spec, nil, true
		case "n":
			spec := actionSpec{title: "Run model", stream: true, fields: []promptField{
				{name: "model", label: "Model", validate: required("model")},
				{name: "runner", label: "Runner (docker or ramalama)", value: "docker", validate: validateRunner},
				{name: "prompt", label: "Prompt (optional)", allowEmpty: true},
			}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ModelRun, Profile: profile, Model: v["model"], Runner: v["runner"], Prompt: v["prompt"]}, nil
			}
			return spec, nil, true
		case "v":
			spec := actionSpec{title: "Serve model", refresh: true, fields: []promptField{
				{name: "model", label: "Model", validate: required("model")},
				{name: "runner", label: "Runner (docker or ramalama)", value: "docker", validate: validateRunner},
				{name: "port", label: "Port", value: "8080", validate: validatePort},
			}}
			spec.build = func(v map[string]string) (action.Request, error) {
				port, _ := strconv.ParseInt(v["port"], 10, 32)
				return action.Request{Kind: action.ModelServe, Profile: profile, Model: v["model"], Runner: v["runner"], Port: int32(port)}, nil
			}
			return spec, nil, true
		case "x":
			return unary("Stop model service", action.Request{Kind: action.ModelStop, Profile: profile}, true), nil, true
		}

	case TabProfiles:
		if key == "enter" && len(m.resources) == 0 {
			return actionSpec{}, errors.New("no profile is available to select"), true
		}
		if key == "n" {
			base := m.template
			if base == nil {
				return actionSpec{}, errors.New("global template has not loaded; press r and try again"), true
			}
			spec := actionSpec{title: "Create profile", note: "Creating a profile also starts its VM with the loaded global template.", refresh: true, fields: []promptField{{name: "name", label: "Profile name", validate: validateName}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ProfileCreate, Profile: profile, Name: v["name"], Config: cloneConfig(base)}, nil
			}
			return spec, nil, true
		}
		item, err := selected()
		if err != nil {
			return actionSpec{}, err, key == "d" || key == "c"
		}
		if key == "d" {
			spec := unary("Delete profile", action.Request{Kind: action.ProfileDelete, Profile: profile, Name: item.Name, Data: true}, true)
			return destructive(spec, fmt.Sprintf("Delete profile %q and its data?", item.Name)), nil, true
		}
		if key == "c" {
			spec := actionSpec{title: "Clone profile", refresh: true, fields: []promptField{{name: "destination", label: "Destination profile", validate: validateName}}}
			spec.build = func(v map[string]string) (action.Request, error) {
				return action.Request{Kind: action.ProfileClone, Profile: profile, Source: item.Name, Target: v["destination"]}, nil
			}
			return spec, nil, true
		}

	case TabMonitoring:
		if key == "k" {
			if len(m.monProcesses) == 0 || m.monCursor < 0 || m.monCursor >= len(m.monProcesses) {
				return actionSpec{}, errors.New("no process is selected"), true
			}
			process := m.monProcesses[m.monCursor]
			spec := unary("Kill process", action.Request{Kind: action.ProcessKill, Profile: profile, PID: process.Pid, Signal: 9}, true)
			return destructive(spec, fmt.Sprintf("Send SIGKILL to PID %d (%s) in profile %q?", process.Pid, process.Command, profile)), nil, true
		}
	}
	return actionSpec{}, nil, false
}

func namedCreateSpec(title string, kind action.Kind, profile string) actionSpec {
	spec := actionSpec{title: title, refresh: true, fields: []promptField{{name: "name", label: "Name", validate: validateName}}}
	spec.build = func(v map[string]string) (action.Request, error) {
		return action.Request{Kind: kind, Profile: profile, Name: v["name"]}, nil
	}
	return spec
}

func configSpec(title string, kind action.Kind, profile string, base *pb.ColimaConfig) actionSpec {
	kube := base.GetKubernetes()
	if kube == nil {
		kube = &pb.KubernetesConfig{}
	}
	fields := []promptField{
		{name: "cpu", label: "CPU count", value: strconv.Itoa(int(base.GetCpu())), validate: positiveInt("CPU")},
		{name: "memory", label: "Memory GiB", value: strconv.FormatFloat(float64(base.GetMemory()), 'f', 1, 32), validate: positiveFloat("memory")},
		{name: "disk", label: "Disk GiB", value: strconv.Itoa(int(base.GetDisk())), validate: positiveInt("disk")},
		{name: "arch", label: "Architecture", value: base.GetArch(), validate: required("architecture")},
		{name: "vm_type", label: "VM type", value: base.GetVmType(), validate: required("VM type")},
		{name: "runtime", label: "Runtime", value: base.GetRuntime(), validate: validateRuntime},
		{name: "mount_type", label: "Mount type", value: base.GetMountType(), validate: required("mount type")},
		{name: "auto_activate", label: "Auto activate (true/false)", value: strconv.FormatBool(base.GetAutoActivate()), validate: validateBool},
		{name: "kube_enabled", label: "Kubernetes enabled (true/false)", value: strconv.FormatBool(kube.GetEnabled()), validate: validateBool},
		{name: "kube_version", label: "Kubernetes version (optional)", value: kube.GetVersion(), allowEmpty: true},
		{name: "kube_port", label: "Kubernetes port (0 for default)", value: strconv.Itoa(int(kube.GetPort())), validate: nonNegativeInt("Kubernetes port")},
	}
	spec := actionSpec{title: title, refresh: true, fields: fields}
	if kind == action.TemplateSet {
		spec.note = "This global template is used by newly created profiles."
	} else {
		spec.note = "Some configuration changes require a VM restart before they take effect."
	}
	spec.build = func(v map[string]string) (action.Request, error) {
		cfg := cloneConfig(base)
		cpu, _ := strconv.ParseInt(v["cpu"], 10, 32)
		memory, _ := strconv.ParseFloat(v["memory"], 32)
		disk, _ := strconv.ParseInt(v["disk"], 10, 32)
		autoActivate, _ := strconv.ParseBool(v["auto_activate"])
		kubeEnabled, _ := strconv.ParseBool(v["kube_enabled"])
		kubePort, _ := strconv.ParseInt(v["kube_port"], 10, 32)
		cfg.Cpu = int32(cpu)
		cfg.Memory = float32(memory)
		cfg.Disk = int32(disk)
		cfg.Arch = v["arch"]
		cfg.VmType = v["vm_type"]
		cfg.Runtime = v["runtime"]
		cfg.MountType = v["mount_type"]
		cfg.AutoActivate = autoActivate
		if cfg.Kubernetes == nil {
			cfg.Kubernetes = &pb.KubernetesConfig{}
		}
		cfg.Kubernetes.Enabled = kubeEnabled
		cfg.Kubernetes.Version = v["kube_version"]
		cfg.Kubernetes.Port = int32(kubePort)
		return action.Request{Kind: kind, Profile: profile, Config: cfg}, nil
	}
	return spec
}

func cloneConfig(config *pb.ColimaConfig) *pb.ColimaConfig {
	if config == nil {
		return &pb.ColimaConfig{}
	}
	return proto.Clone(config).(*pb.ColimaConfig)
}

func required(name string) func(string) error {
	return func(value string) error {
		if strings.TrimSpace(value) == "" {
			return fmt.Errorf("%s is required", name)
		}
		return nil
	}
}

func validateName(value string) error {
	if err := required("name")(value); err != nil {
		return err
	}
	if strings.ContainsAny(value, " \t\r\n") {
		return errors.New("name cannot contain whitespace")
	}
	return nil
}

func validateRunner(value string) error {
	if value != "docker" && value != "ramalama" {
		return errors.New("runner must be docker or ramalama")
	}
	return nil
}

func validateRuntime(value string) error {
	if value != "docker" && value != "containerd" && value != "incus" {
		return errors.New("runtime must be docker, containerd, or incus")
	}
	return nil
}

func validateBool(value string) error {
	if _, err := strconv.ParseBool(value); err != nil {
		return errors.New("value must be true or false")
	}
	return nil
}

func positiveInt(name string) func(string) error {
	return func(value string) error {
		parsed, err := strconv.ParseInt(value, 10, 32)
		if err != nil || parsed <= 0 {
			return fmt.Errorf("%s must be a positive integer", name)
		}
		return nil
	}
}

func nonNegativeInt(name string) func(string) error {
	return func(value string) error {
		parsed, err := strconv.ParseInt(value, 10, 32)
		if err != nil || parsed < 0 {
			return fmt.Errorf("%s must be a non-negative integer", name)
		}
		return nil
	}
}

func positiveFloat(name string) func(string) error {
	return func(value string) error {
		parsed, err := strconv.ParseFloat(value, 32)
		if err != nil || parsed <= 0 {
			return fmt.Errorf("%s must be a positive number", name)
		}
		return nil
	}
}

func validatePort(value string) error {
	parsed, err := strconv.ParseInt(value, 10, 32)
	if err != nil || parsed < 1 || parsed > 65535 {
		return errors.New("port must be between 1 and 65535")
	}
	return nil
}

func isContainerActionKey(key string) bool {
	return strings.Contains("sxRkpu degitacP", key) && key != " "
}

func isImageActionKey(key string) bool {
	return strings.Contains("udtHi", key)
}

func isNetworkActionKey(key string) bool {
	return strings.Contains("dicx", key)
}

func actionHints(tab int) string {
	hints := map[int]string{
		TabDashboard:  "[s] start [x] stop [R] restart [D] delete [U] update [P] prune [H] SSH config",
		TabContainers: "[n] create [s/x/R] start/stop/restart [k] kill [p/u] pause/unpause [d] remove [e] rename [g/i/t/a/c] logs/inspect/top/stats/changes [P] prune",
		TabImages:     "[p/u] pull/push [d] remove [t] tag [s] search [H] history [i] inspect [P] prune",
		TabVolumes:    "[n] create [d] remove [i] inspect [P] prune",
		TabNetworks:   "[n] create [d] remove [i] inspect [c/x] connect/disconnect [P] prune",
		TabKubernetes: "[s] start [x] stop [R] reset [e] exec",
		TabConfig:     "[v] view current/template [e] edit/save profile config [t] edit/save global template",
		TabRuntime:    "[d] docker [c] containerd [i] incus [u] update",
		TabAI:         "[s] setup [n] run [v] serve [x] stop",
		TabProfiles:   "[Enter] select [n] create [d] delete [c] clone",
		TabMonitoring: "[k] kill selected process",
	}
	return hints[tab]
}

package main

import (
	"fmt"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var baseStyle = lipgloss.NewStyle()

type item struct {
	SystemdUnit
}

func (i item) Title() string {
	name := i.Name
	if len(name) > 50 {
		name = name[:49] + "…"
	}
	status := i.ActiveState
	var statusColor lipgloss.Color
	var statusIcon string

	switch status {
	case "active":
		statusColor = lipgloss.Color("42") // Green
		statusIcon = "●"
	case "inactive":
		statusColor = lipgloss.Color("243") // Gray
		statusIcon = "○"
	case "activating":
		statusColor = lipgloss.Color("220") // Yellow
		statusIcon = "▴"
	case "deactivating":
		statusColor = lipgloss.Color("220") // Yellow
		statusIcon = "▾"
	case "reloading":
		statusColor = lipgloss.Color("220") // Yellow
		statusIcon = "↻"
	case "failed":
		statusColor = lipgloss.Color("196") // Red
		statusIcon = "✗"
	case "maintenance":
		statusColor = lipgloss.Color("202") // Orange
		statusIcon = "🔧"
	default:
		statusColor = lipgloss.Color("255") // White
		statusIcon = "-"
	}

	statusDisplay := lipgloss.NewStyle().Foreground(statusColor).Render(fmt.Sprintf("%s %-10s", statusIcon, status))

	sub := i.SubState
	var subColor lipgloss.Color
	var subIcon string
	switch sub {
	case "running":
		subColor = lipgloss.Color("42")
		subIcon = "⚡"
	case "listening":
		subColor = lipgloss.Color("42")
		subIcon = "👂"
	case "mounted":
		subColor = lipgloss.Color("42")
		subIcon = "💾"
	case "plugged":
		subColor = lipgloss.Color("42")
		subIcon = "🔌"
	case "dead":
		subColor = lipgloss.Color("243")
		subIcon = "💀"
	case "exited":
		subColor = lipgloss.Color("243")
		subIcon = "○"
	case "failed", "crashed", "timeout":
		subColor = lipgloss.Color("196")
		subIcon = "✗"
	case "start", "start-pre", "start-post":
		subColor = lipgloss.Color("220")
		subIcon = "▴"
	case "stop", "stop-sigabrt", "stop-sigterm", "stop-sigkill", "stop-post", "final-sigterm", "final-sigkill":
		subColor = lipgloss.Color("220")
		subIcon = "▾"
	case "auto-restart", "reload":
		subColor = lipgloss.Color("220")
		subIcon = "↻"
	case "waiting":
		subColor = lipgloss.Color("243")
		subIcon = "⏳"
	default:
		subColor = lipgloss.Color("255")
		subIcon = "-"
	}
	subDisplay := lipgloss.NewStyle().Foreground(subColor).Render(fmt.Sprintf("%s %s", subIcon, sub))

	return fmt.Sprintf("%-50s %s %s", name, statusDisplay, subDisplay)
}

func (i item) Description() string { return i.SystemdUnit.Description }
func (i item) FilterValue() string { return i.Name }

type model struct {
	list        list.Model
	units       []SystemdUnit
	err         error
	width       int
	height      int
	viewport    viewport.Model
	showDetails bool
}

func initialModel() model {
	l := list.New([]list.Item{}, list.NewDefaultDelegate(), 0, 0)
	l.Title = "Centurion Services"
	l.SetShowTitle(true)
	l.SetShowStatusBar(false)
	l.Help.Styles.ShortKey = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.ShortDesc = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.FullKey = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.FullDesc = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.ShortSeparator = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.FullSeparator = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	vp := viewport.New(0, 0)
	return model{list: l, viewport: vp}
}

type servicesMsg []SystemdUnit
type errMsg error

func fetchServices() tea.Cmd {
	return func() tea.Msg {
		units, err := ListServices()
		if err != nil {
			return errMsg(err)
		}
		return servicesMsg(units)
	}
}

type statusMsg string

func fetchStatus(name string) tea.Cmd {
	return func() tea.Msg {
		status, _ := GetUnitStatus(name)
		return statusMsg(status)
	}
}

func performAction(action, name string) tea.Cmd {
	return func() tea.Msg {
		switch action {
		case "start":
			StartUnit(name)
		case "stop":
			StopUnit(name)
		case "restart":
			RestartUnit(name)
		}
		// Refresh list after action
		units, err := ListServices()
		if err != nil {
			return errMsg(err)
		}
		return servicesMsg(units)
	}
}

func (m model) Init() tea.Cmd {
	return fetchServices()
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch msg := msg.(type) {
	case servicesMsg:
		m.units = msg
		items := make([]list.Item, len(msg))
		for i, u := range msg {
			items[i] = item{u}
		}
		m.list.SetItems(items)
		m.list.Title = fmt.Sprintf("Centurion - %d Services", len(items))
	case statusMsg:
		m.viewport.SetContent(string(msg))
		m.showDetails = true
		return m, nil
	case errMsg:
		m.err = msg
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.list.SetSize(msg.Width, msg.Height-1)
		m.viewport.Width = msg.Width
		m.viewport.Height = msg.Height - 1
	case tea.KeyMsg:
		if m.showDetails {
			switch msg.String() {
			case "q", "esc":
				m.showDetails = false
				return m, nil
			}
			m.viewport, cmd = m.viewport.Update(msg)
			return m, cmd
		}

		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "s":
			if i, ok := m.list.SelectedItem().(item); ok {
				return m, tea.Batch(performAction("start", i.Name), m.list.NewStatusMessage(fmt.Sprintf("Starting %s...", i.Name)))
			}
		case "x":
			if i, ok := m.list.SelectedItem().(item); ok {
				return m, tea.Batch(performAction("stop", i.Name), m.list.NewStatusMessage(fmt.Sprintf("Stopping %s...", i.Name)))
			}
		case "r":
			if i, ok := m.list.SelectedItem().(item); ok {
				return m, tea.Batch(performAction("restart", i.Name), m.list.NewStatusMessage(fmt.Sprintf("Restarting %s...", i.Name)))
			}
		case "enter":
			if i, ok := m.list.SelectedItem().(item); ok {
				return m, fetchStatus(i.Name)
			}
		}
	}

	if !m.showDetails {
		m.list, cmd = m.list.Update(msg)
	}
	return m, cmd
}

func (m model) View() string {
	if m.err != nil {
		return fmt.Sprintf("Error: %v\nPress q to quit.", m.err)
	}
	if m.width == 0 {
		return "Loading..."
	}

	if m.showDetails {
		return lipgloss.JoinVertical(lipgloss.Left, "Service Details (Esc/q to close)", m.viewport.View())
	}

	return m.list.View()
}

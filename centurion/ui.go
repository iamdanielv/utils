package main

import (
	"fmt"
	"io"
	"strings"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var baseStyle = lipgloss.NewStyle()

type item struct {
	SystemdUnit
}

func (i item) RenderTitle(colored bool) string {
	name := i.Name
	if len(name) > 50 {
		name = name[:49] + "…"
	}
	name = fmt.Sprintf("%-50s", name)

	if colored {
		name = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("255")).Render(name)
	} else {
		name = "\033[1m" + name + "\033[22m"
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

	statusText := fmt.Sprintf("%s %-10s", statusIcon, status)
	statusDisplay := statusText
	if colored {
		statusDisplay = lipgloss.NewStyle().Foreground(statusColor).Render(statusText)
	}

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
	subText := fmt.Sprintf("%s %s", subIcon, sub)
	subDisplay := subText
	if colored {
		subDisplay = lipgloss.NewStyle().Foreground(subColor).Render(subText)
	}

	return fmt.Sprintf("%s %s %s", name, statusDisplay, subDisplay)
}

func (i item) Description() string { return i.SystemdUnit.Description }
func (i item) FilterValue() string {
	return i.Name + " " + i.ActiveState + " " + i.SubState + " " + i.SystemdUnit.Description
}

type itemDelegate struct{}

func (d itemDelegate) Height() int                             { return 2 }
func (d itemDelegate) Spacing() int                            { return 0 }
func (d itemDelegate) Update(_ tea.Msg, _ *list.Model) tea.Cmd { return nil }
func (d itemDelegate) Render(w io.Writer, m list.Model, index int, listItem list.Item) {
	i, ok := listItem.(item)
	if !ok {
		return
	}

	if index == m.Index() {
		selectedStyle := lipgloss.NewStyle().
			Border(lipgloss.NormalBorder(), false, false, false, true).
			BorderForeground(lipgloss.Color("229")).
			Foreground(lipgloss.Color("229")).
			Background(lipgloss.Color("57")).
			Padding(0, 0, 0, 1).
			Width(m.Width() - 2)

		title := i.RenderTitle(false)
		desc := " " + i.Description()
		fmt.Fprint(w, selectedStyle.Render(lipgloss.JoinVertical(lipgloss.Left, title, desc)))
	} else {
		title := "  " + i.RenderTitle(true)
		desc := lipgloss.NewStyle().Foreground(lipgloss.Color("240")).Render("   " + i.Description())
		fmt.Fprint(w, title+"\n"+desc)
	}
}

func renderBanner(text string, width int) string {
	style := lipgloss.NewStyle().Foreground(lipgloss.Color("4"))
	prefix := "┏ "
	suffix := " "
	contentWidth := lipgloss.Width(prefix) + lipgloss.Width(text) + lipgloss.Width(suffix)
	lineWidth := width - contentWidth
	if lineWidth < 0 {
		lineWidth = 0
	}
	line := strings.Repeat("━", lineWidth)
	return style.Render(prefix + text + suffix + line)
}

type model struct {
	list         list.Model
	units        []SystemdUnit
	err          error
	width        int
	height       int
	viewport     viewport.Model
	showDetails  bool
	detailsTitle string
}

func initialModel() model {
	l := list.New([]list.Item{}, itemDelegate{}, 0, 0)
	l.Title = "Centurion Services"
	l.SetShowTitle(false)
	l.SetShowStatusBar(false)
	l.Filter = filterContains
	l.Help.Styles.ShortKey = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.ShortDesc = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.ShortSeparator = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.FullKey = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.FullDesc = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.Help.Styles.FullSeparator = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	l.AdditionalShortHelpKeys = func() []key.Binding {
		return []key.Binding{
			key.NewBinding(key.WithKeys("s"), key.WithHelp("s", "start")),
			key.NewBinding(key.WithKeys("x"), key.WithHelp("x", "stop")),
			key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "restart")),
			key.NewBinding(key.WithKeys("l"), key.WithHelp("l", "logs")),
			key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "inspect")),
		}
	}
	l.AdditionalFullHelpKeys = l.AdditionalShortHelpKeys

	vp := viewport.New(0, 0)
	return model{list: l, viewport: vp}
}

func filterContains(term string, targets []string) []list.Rank {
	var ranks []list.Rank
	for i, target := range targets {
		lowerTarget := strings.ToLower(target)
		lowerTerm := strings.ToLower(term)
		if strings.Contains(lowerTarget, lowerTerm) {
			start := strings.Index(lowerTarget, lowerTerm)
			var matchedIndexes []int
			for j := 0; j < len(term); j++ {
				matchedIndexes = append(matchedIndexes, start+j)
			}
			ranks = append(ranks, list.Rank{
				Index:          i,
				MatchedIndexes: matchedIndexes,
			})
		}
	}
	return ranks
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
type logsMsg string

func fetchStatus(name string) tea.Cmd {
	return func() tea.Msg {
		status, _ := GetUnitStatus(name)
		return statusMsg(status)
	}
}

func fetchLogs(name string) tea.Cmd {
	return func() tea.Msg {
		logs, _ := GetUnitLogs(name)
		return logsMsg(logs)
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
	case statusMsg:
		m.viewport.SetContent(string(msg))
		m.detailsTitle = "Service Details (Esc/q to close)"
		m.showDetails = true
		return m, nil
	case logsMsg:
		m.viewport.SetContent(string(msg))
		m.detailsTitle = "Service Logs (Esc/q to close)"
		m.showDetails = true
		m.viewport.GotoBottom()
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

		if m.list.FilterState() != list.Filtering {
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
			case "l":
				if i, ok := m.list.SelectedItem().(item); ok {
					return m, fetchLogs(i.Name)
				}
			}
		}
	}

	m.list, cmd = m.list.Update(msg)

	title := fmt.Sprintf("Centurion - %d Services", len(m.list.VisibleItems()))
	if filter := m.list.FilterValue(); filter != "" {
		title += fmt.Sprintf(" - Filter: %s", filter)
	}
	m.list.Title = title

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
		banner := renderBanner(m.detailsTitle, m.width)
		return lipgloss.JoinVertical(lipgloss.Left, banner, m.viewport.View())
	}

	banner := renderBanner(m.list.Title, m.width)
	return lipgloss.JoinVertical(lipgloss.Left, banner, m.list.View())
}

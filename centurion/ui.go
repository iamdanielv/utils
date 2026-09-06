package main

import (
	"fmt"
	"io"
	"regexp"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
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
			Border(lipgloss.BlockBorder(), false, false, false, true).
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
	list           list.Model
	units          []SystemdUnit
	err            error
	width          int
	height         int
	viewport       viewport.Model
	help           help.Model
	showDetails    bool
	detailsTitle   string
	showConfirm    bool
	pendingAction  string
	pendingUnit    string
	activeUnitName string
	textInput      textinput.Model
	showFilter     bool
	rawLogContent  string
	isLogView      bool
	isLoading      bool
	statusMsg      string
	transientMsg   string
	spinner        spinner.Model
}

func (m model) ShortHelp() []key.Binding {
	if m.showDetails {
		if m.showFilter {
			return []key.Binding{
				key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "apply")),
				key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "cancel")),
			}
		}
		bindings := []key.Binding{
			key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc/q", "close")),
		}
		if m.isLogView {
			bindings = append(bindings, key.NewBinding(key.WithKeys("/"), key.WithHelp("/", "filter")))
		}
		bindings = append(bindings, key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "more")))
		return bindings
	}
	if m.list.FilterState() == list.Filtering {
		return []key.Binding{
			key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "select")),
			key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "cancel")),
		}
	}
	return []key.Binding{
		key.NewBinding(key.WithKeys("up"), key.WithHelp("↑up", "")),
		key.NewBinding(key.WithKeys("down"), key.WithHelp("↓down", "")),
		key.NewBinding(key.WithKeys("s"), key.WithHelp("(s)tart/stop", "")),
		key.NewBinding(key.WithKeys("r"), key.WithHelp("(r)estart", "")),
		key.NewBinding(key.WithKeys("l"), key.WithHelp("(l)ogs", "")),
		key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "details")),
		key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "more")),
	}
}

func (m model) FullHelp() [][]key.Binding {
	if m.showDetails {
		return [][]key.Binding{
			{
				key.NewBinding(key.WithKeys("up"), key.WithHelp("↑/k", "scroll up")),
				key.NewBinding(key.WithKeys("down"), key.WithHelp("↓/j", "scroll down")),
				key.NewBinding(key.WithKeys("home"), key.WithHelp("home/g", "top")),
				key.NewBinding(key.WithKeys("end"), key.WithHelp("end/G", "bottom")),
			},
			{
				key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc/q", "close view")),
				key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "close help")),
			},
		}
	}
	return [][]key.Binding{
		{
			key.NewBinding(key.WithKeys("up"), key.WithHelp("↑/k", "move up")),
			key.NewBinding(key.WithKeys("down"), key.WithHelp("↓/j", "move down")),
			key.NewBinding(key.WithKeys("home"), key.WithHelp("home/g", "go to top")),
			key.NewBinding(key.WithKeys("end"), key.WithHelp("end/G", "go to bottom")),
		},
		{
			key.NewBinding(key.WithKeys("s"), key.WithHelp("s", "start/stop service")),
			key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "restart service")),
			key.NewBinding(key.WithKeys("l"), key.WithHelp("l", "view logs")),
		},
		{
			key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "service details")),
			key.NewBinding(key.WithKeys("?"), key.WithHelp("?", "close help")),
		},
	}
}

func initialModel() model {
	l := list.New([]list.Item{}, itemDelegate{}, 0, 0)
	l.Title = "Centurion Services"
	l.SetShowTitle(false)
	l.SetShowStatusBar(false)
	l.SetShowHelp(false)
	l.Filter = filterContains

	ti := textinput.New()
	ti.Placeholder = "Filter logs..."
	ti.Prompt = "  Filter: "
	ti.PromptStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("220"))

	ti.CharLimit = 60
	ti.Width = 30

	h := help.New()
	h.Styles.ShortKey = lipgloss.NewStyle().Foreground(lipgloss.Color("#00FFFF"))
	h.Styles.ShortDesc = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	h.Styles.ShortSeparator = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF00FF"))
	h.Styles.FullKey = lipgloss.NewStyle().Foreground(lipgloss.Color("#00FFFF"))
	h.Styles.FullDesc = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	h.Styles.FullSeparator = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF00FF"))
	h.ShortSeparator = "•"
	h.FullSeparator = " "

	vp := viewport.New(0, 0)

	s := spinner.New()
	s.Spinner = spinner.Dot

	return model{
		list:      l,
		viewport:  vp,
		help:      h,
		textInput: ti,
		isLoading: true,
		statusMsg: "Starting service query...",
		spinner:   s,
	}
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

type transientMsg string
type clearTransientMsg struct{}

func setTransient(text string) tea.Cmd {
	return tea.Sequence(
		func() tea.Msg { return transientMsg(text) },
		setTransientClear(),
	)
}

func setTransientClear() tea.Cmd {
	return tea.Tick(3*time.Second, func(time.Time) tea.Msg {
		return clearTransientMsg{}
	})
}

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
	return tea.Batch(m.spinner.Tick, fetchServices())
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	switch msg := msg.(type) {
	case servicesMsg:
		wasLoading := m.isLoading
		m.units = msg
		m.isLoading = false
		items := make([]list.Item, len(msg))
		for i, u := range msg {
			items[i] = item{u}
		}
		m.list.SetItems(items)
		if !wasLoading {
			return m, setTransient(fmt.Sprintf("Updated %d services", len(msg)))
		}
	case spinner.TickMsg:
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	case statusMsg:
		m.viewport.SetContent(string(msg))
		m.isLogView = false
		m.detailsTitle = fmt.Sprintf("Service Details: %s", m.activeUnitName)
		m.showDetails = true
		return m, nil
	case logsMsg:
		m.rawLogContent = string(msg)
		m.isLogView = true
		m.viewport.SetContent(wrap(m.rawLogContent, m.viewport.Width))
		m.detailsTitle = fmt.Sprintf("Service Logs: %s", m.activeUnitName)
		m.showDetails = true
		m.viewport.GotoBottom()
		m.textInput.Reset()
		m.showFilter = false
		return m, nil
	case errMsg:
		m.err = msg
		m.isLoading = false
	case transientMsg:
		m.transientMsg = string(msg)
	case clearTransientMsg:
		m.transientMsg = ""
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.help.Width = msg.Width
		m.list, cmd = m.list.Update(msg)
		bannerHeight := lipgloss.Height(renderBanner("", m.width))
		helpHeight := lipgloss.Height(m.help.View(m))
		listHeight := msg.Height - bannerHeight - helpHeight - 1
		if listHeight < 0 {
			listHeight = 0
		}
		m.list.SetSize(msg.Width, listHeight)
		m.viewport.Width = msg.Width - 1
		m.viewport.Height = msg.Height - bannerHeight - helpHeight
		if m.showFilter {
			m.viewport.Height--
		}
		if m.showDetails && m.isLogView {
			content := m.rawLogContent
			if m.showFilter && m.textInput.Value() != "" {
				content = filterLogs(m.rawLogContent, m.textInput.Value())
			}
			m.viewport.SetContent(wrap(content, m.viewport.Width))
		}
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}

		if m.showConfirm {
			switch msg.String() {
			case "y", "Y":
				m.showConfirm = false
				msg := ""
				if m.pendingAction == "stop" {
					msg = fmt.Sprintf("Stopping %s...", m.pendingUnit)
				} else {
					msg = fmt.Sprintf("Restarting %s...", m.pendingUnit)
				}
				return m, tea.Batch(performAction(m.pendingAction, m.pendingUnit), m.list.NewStatusMessage(msg))
			default:
				m.showConfirm = false
				m.pendingAction = ""
				m.pendingUnit = ""
				return m, nil
			}
		}
		if m.showDetails {
			if m.showFilter {
				switch msg.String() {
				case "enter":
					m.showFilter = false
					m.textInput.Blur()
					filterTerm := m.textInput.Value()
					if filterTerm != "" {
						m.detailsTitle = fmt.Sprintf("Service Logs: %s (Filter: %s)", m.activeUnitName, filterTerm)
						filtered := filterLogs(m.rawLogContent, filterTerm)
						m.viewport.SetContent(wrap(filtered, m.viewport.Width))
					} else {
						m.detailsTitle = fmt.Sprintf("Service Logs: %s", m.activeUnitName)
						m.viewport.SetContent(wrap(m.rawLogContent, m.viewport.Width))
					}
					m.viewport.GotoBottom()
					m.viewport.Height++
					return m, nil
				case "esc":
					m.showFilter = false
					m.textInput.Blur()
					m.viewport.Height++
					return m, nil
				}
				m.textInput, cmd = m.textInput.Update(msg)
				return m, cmd
			}
			switch msg.String() {
			case "q", "esc":
				m.showDetails = false
				m.isLogView = false
				return m, nil
			case "/":
				if m.isLogView {
					m.showFilter = true
					m.textInput.Focus()
					m.viewport.Height--
					return m, nil
				}
			case "?":
				m.help.ShowAll = !m.help.ShowAll
				bannerHeight := lipgloss.Height(renderBanner("", m.width))
				helpHeight := lipgloss.Height(m.help.View(m))
				m.viewport.Height = m.height - bannerHeight - helpHeight
				if m.showFilter {
					m.viewport.Height--
				}
			case "home":
			case "g":
				m.viewport.GotoTop()
			case "end":
			case "G":
				m.viewport.GotoBottom()
			}
			m.viewport, cmd = m.viewport.Update(msg)
			return m, cmd
		}

		if m.list.FilterState() != list.Filtering {
			switch msg.String() {
			case "q":
				return m, tea.Quit
			case "?":
				m.help.ShowAll = !m.help.ShowAll
				bannerHeight := lipgloss.Height(renderBanner("", m.width))
				helpHeight := lipgloss.Height(m.help.View(m))
				m.list.SetSize(m.width, m.height-bannerHeight-helpHeight-1)
			case "s":
				if i, ok := m.list.SelectedItem().(item); ok {
					if i.ActiveState == "active" || i.ActiveState == "reloading" || i.ActiveState == "activating" {
						m.pendingAction = "stop"
						m.pendingUnit = i.Name
						m.showConfirm = true
						return m, nil
					} else {
						return m, tea.Batch(performAction("start", i.Name), m.list.NewStatusMessage(fmt.Sprintf("Starting %s...", i.Name)))
					}
				}
			case "r":
				if i, ok := m.list.SelectedItem().(item); ok {
					m.pendingAction = "restart"
					m.pendingUnit = i.Name
					m.showConfirm = true
					return m, nil
				}
			case "enter":
				if i, ok := m.list.SelectedItem().(item); ok {
					m.activeUnitName = i.Name
					return m, fetchStatus(i.Name)
				}
			case "l":
				if i, ok := m.list.SelectedItem().(item); ok {
					m.activeUnitName = i.Name
					return m, fetchLogs(i.Name)
				}
			}
		}
	}

	// Only pass messages to list if it's not a WindowSizeMsg, as we've handled that manually
	if _, ok := msg.(tea.WindowSizeMsg); !ok {
		m.list, cmd = m.list.Update(msg)
	}

	total := len(m.list.Items())
	visible := len(m.list.VisibleItems())
	title := fmt.Sprintf("Centurion - %d Services", total)
	if filter := m.list.FilterValue(); filter != "" {
		title = fmt.Sprintf("Centurion - %d/%d Services (Filter: %s)", visible, total, filter)
	}
	m.list.Title = title

	return m, cmd
}

func (m model) View() string {
	if m.err != nil {
		return m.errorView()
	}
	if m.isLoading {
		return m.loadingView()
	}
	if m.width == 0 {
		return "Loading..."
	}

	if m.showConfirm {
		question := fmt.Sprintf("Are you sure you want to %s service:\n\n%s\n\n(y/N)", strings.ToUpper(m.pendingAction), m.pendingUnit)
		dialog := lipgloss.NewStyle().
			Width(50).
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("196")).
			Padding(1, 2).
			Align(lipgloss.Center).
			Render(question)
		return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, dialog)
	}

	if m.showDetails {
		banner := renderBanner(m.detailsTitle, m.width)
		var content string
		vpView := m.viewport.View()
		if m.viewport.TotalLineCount() > m.viewport.Height {
			vpView = lipgloss.JoinHorizontal(lipgloss.Top, vpView, m.scrollbarView())
		}
		if m.showFilter {
			content = lipgloss.JoinVertical(lipgloss.Left, banner, m.textInput.View(), vpView)
		} else {
			content = lipgloss.JoinVertical(lipgloss.Left, banner, vpView)
		}
		return lipgloss.JoinVertical(lipgloss.Left, content, m.help.View(m))
	}

	banner := renderBanner(m.list.Title, m.width)

	listView := m.list.View()
	if m.transientMsg != "" {
		flash := lipgloss.NewStyle().
			Foreground(lipgloss.Color("42")).
			Padding(0, 1).
			Render(" " + m.transientMsg + " ")
		listView = lipgloss.JoinVertical(lipgloss.Left, flash, listView)
	}

	return lipgloss.JoinVertical(lipgloss.Left, banner, listView, m.help.View(m))
}

func (m model) loadingView() string {
	width := m.width
	if width == 0 {
		width = 60
	}
	height := m.height
	if height == 0 {
		height = 10
	}

	spinnerText := m.spinner.View()
	msg := m.statusMsg
	spinnerArea := lipgloss.NewStyle().
		Foreground(lipgloss.Color("42")).
		Render(spinnerText)

	body := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Padding(1, 2).
		Width(width - 6).
		Render(
			lipgloss.JoinVertical(
				lipgloss.Center,
				spinnerArea,
				"",
				lipgloss.NewStyle().Bold(true).Render(msg),
			),
		)

	return lipgloss.Place(width, height, lipgloss.Center, lipgloss.Center, body)
}

func (m model) errorView() string {
	if m.width == 0 {
		return fmt.Sprintf("Error: %v\nPress q to quit.", m.err)
	}
	msg := lipgloss.NewStyle().
		Foreground(lipgloss.Color("196")).
		Bold(true).
		Render("ERROR")
	body := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("196")).
		Padding(1, 2).
		Width(m.width - 6).
		Render(
			lipgloss.JoinVertical(
				lipgloss.Left,
				msg,
				"",
				m.err.Error(),
				"",
				lipgloss.NewStyle().Foreground(lipgloss.Color("243")).Render("Press q to quit."),
			),
		)
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, body)
}

func filterLogs(content, term string) string {
	if term == "" {
		return content
	}

	re, err := regexp.Compile("(?i)" + regexp.QuoteMeta(term))
	if err != nil {
		return content
	}

	highlightStyle := lipgloss.NewStyle().Background(lipgloss.Color("11")).Foreground(lipgloss.Color("0"))

	var lines []string
	linesStr := strings.Split(content, "\n")
	for _, line := range linesStr {
		if re.MatchString(line) {
			highlighted := re.ReplaceAllStringFunc(line, func(match string) string {
				return highlightStyle.Render(match)
			})
			lines = append(lines, highlighted)
		}
	}
	if len(lines) == 0 {
		return "No matches found."
	}
	return strings.Join(lines, "\n")
}

func wrap(s string, width int) string {
	if width <= 0 {
		return s
	}
	return lipgloss.NewStyle().Width(width).Render(s)
}

func (m model) scrollbarView() string {
	height := m.viewport.Height
	if height <= 0 {
		return ""
	}
	total := m.viewport.TotalLineCount()
	if total <= height {
		return ""
	}

	thumbHeight := int(float64(height) * float64(height) / float64(total))
	if thumbHeight < 1 {
		thumbHeight = 1
	}

	thumbY := int(float64(m.viewport.YOffset) * float64(height-thumbHeight) / float64(total-height))

	var sb strings.Builder
	style := lipgloss.NewStyle().Foreground(lipgloss.Color("62"))
	thumb := style.Render("█")
	track := style.Render("░")

	for i := 0; i < height; i++ {
		if i >= thumbY && i < thumbY+thumbHeight {
			sb.WriteString(thumb)
		} else {
			sb.WriteString(track)
		}
		if i < height-1 {
			sb.WriteString("\n")
		}
	}
	return sb.String()
}

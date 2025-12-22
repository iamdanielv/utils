package main

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
)

type model struct {
	units []SystemdUnit
	err   error
}

func initialModel() model {
	return model{}
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

func (m model) Init() tea.Cmd {
	return fetchServices()
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case servicesMsg:
		m.units = msg
	case errMsg:
		m.err = msg
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.err != nil {
		return fmt.Sprintf("Error: %v\nPress q to quit.", m.err)
	}
	if len(m.units) == 0 {
		return "Centurion Loading...\n\nPress q to quit."
	}
	return fmt.Sprintf("Centurion Loaded %d services.\n\nFirst service: %s (%s)\n\nPress q to quit.", len(m.units), m.units[0].Name, m.units[0].ActiveState)
}

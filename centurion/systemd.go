package main

import (
	"bufio"
	"bytes"
	"os/exec"
	"strings"
)

// SystemdUnit represents a single systemd service unit
type SystemdUnit struct {
	Name        string
	LoadState   string
	ActiveState string
	SubState    string
	Description string
}

// ListServices executes systemctl to list all service units and parses the output
func ListServices() ([]SystemdUnit, error) {
	// --full: prevent truncation of names and descriptions
	// --no-pager: prevent paging
	// --no-legend: suppress headers and footers
	// --plain: use plain output mode (no bullet points)
	// --all: show all units, including inactive ones
	cmd := exec.Command("systemctl", "list-units", "--type=service", "--all", "--no-pager", "--no-legend", "--plain", "--full")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var units []SystemdUnit
	scanner := bufio.NewScanner(bytes.NewReader(output))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		fields := strings.Fields(line)
		// We expect at least 4 fields: UNIT, LOAD, ACTIVE, SUB
		if len(fields) < 4 {
			continue
		}

		unit := SystemdUnit{
			Name:        fields[0],
			LoadState:   fields[1],
			ActiveState: fields[2],
			SubState:    fields[3],
		}

		// Description is everything after the 4th field
		if len(fields) > 4 {
			unit.Description = strings.Join(fields[4:], " ")
		}

		units = append(units, unit)
	}

	return units, nil
}

// StartUnit starts a systemd service
func StartUnit(name string) error {
	return exec.Command("systemctl", "start", name).Run()
}

// StopUnit stops a systemd service
func StopUnit(name string) error {
	return exec.Command("systemctl", "stop", name).Run()
}

// RestartUnit restarts a systemd service
func RestartUnit(name string) error {
	return exec.Command("systemctl", "restart", name).Run()
}

// GetUnitStatus returns the full status output for a unit
func GetUnitStatus(name string) (string, error) {
	cmd := exec.Command("systemctl", "status", name, "--no-pager", "--full")
	output, _ := cmd.CombinedOutput()
	return string(output), nil
}

// GetUnitLogs returns the recent logs for a unit
func GetUnitLogs(name string) (string, error) {
	cmd := exec.Command("journalctl", "-u", name, "-n", "1000", "--no-pager")
	output, _ := cmd.CombinedOutput()
	return string(output), nil
}

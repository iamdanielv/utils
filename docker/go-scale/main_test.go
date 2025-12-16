package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"testing"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
)

func TestCheckScaleUp(t *testing.T) {
	testCases := []struct {
		name          string
		cfg           *Config
		cpu           float64
		mem           float64
		shouldScaleUp bool
		reason        string
	}{
		{
			name: "CPU metric, CPU above threshold",
			cfg: &Config{
				ScaleMetric:       "cpu",
				CPUUpperThreshold: 50,
			},
			cpu:           60,
			mem:           10,
			shouldScaleUp: true,
			reason:        "CPU (60.00% > 50%)",
		},
		{
			name: "CPU metric, CPU below threshold",
			cfg: &Config{
				ScaleMetric:       "cpu",
				CPUUpperThreshold: 50,
			},
			cpu:           40,
			mem:           10,
			shouldScaleUp: false,
		},
		{
			name: "Memory metric, Memory above threshold",
			cfg: &Config{
				ScaleMetric:       "mem",
				MemUpperThreshold: 80,
			},
			cpu:           10,
			mem:           90,
			shouldScaleUp: true,
			reason:        "Memory (90.00% > 80%)",
		},
		{
			name: "Any metric, only CPU high",
			cfg: &Config{
				ScaleMetric:       "any",
				CPUUpperThreshold: 50,
				MemUpperThreshold: 80,
			},
			cpu:           60,
			mem:           70,
			shouldScaleUp: true,
			reason:        "CPU (60.00% > 50%)",
		},
		{
			name: "Any metric, both CPU and Memory high",
			cfg: &Config{
				ScaleMetric:       "any",
				CPUUpperThreshold: 50,
				MemUpperThreshold: 80,
			},
			cpu:           60,
			mem:           90,
			shouldScaleUp: true,
			reason:        "CPU (60.00% > 50%) and Memory (90.00% > 80%)",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			shouldScale, reason := checkScaleUp(tc.cfg, tc.cpu, tc.mem)
			if shouldScale != tc.shouldScaleUp {
				t.Errorf("Expected shouldScaleUp to be %v, but got %v", tc.shouldScaleUp, shouldScale)
			}
			if shouldScale && reason != tc.reason {
				t.Errorf("Expected reason to be '%s', but got '%s'", tc.reason, reason)
			}
		})
	}
}

// --- Mocks for Advanced Testing ---

type mockDockerClient struct {
	ContainerListFunc  func(ctx context.Context, options container.ListOptions) ([]types.Container, error)
	ContainerStatsFunc func(ctx context.Context, containerID string, stream bool) (types.ContainerStats, error)
}

func (m *mockDockerClient) ContainerList(ctx context.Context, options container.ListOptions) ([]types.Container, error) {
	return m.ContainerListFunc(ctx, options)
}

func (m *mockDockerClient) ContainerStats(ctx context.Context, containerID string, stream bool) (types.ContainerStats, error) {
	return m.ContainerStatsFunc(ctx, containerID, stream)
}

func newTestStats(totalUsage, systemUsage uint64) io.ReadCloser {
	stats := types.StatsJSON{
		Stats: types.Stats{
			CPUStats: types.CPUStats{
				CPUUsage: types.CPUUsage{
					TotalUsage: totalUsage,
				},
				SystemUsage: systemUsage,
				OnlineCPUs:  1,
			},
			PreCPUStats: types.CPUStats{
				CPUUsage: types.CPUUsage{
					TotalUsage: 0,
				},
				SystemUsage: 0,
			},
		},
	}
	b, _ := json.Marshal(stats)
	return io.NopCloser(bytes.NewReader(b))
}

func TestEvaluateAndScale_ScaleUp(t *testing.T) {
	// --- Setup ---
	originalExecutor := commandExecutor
	defer func() { commandExecutor = originalExecutor }()

	var executedCmd string
	var executedArgs []string

	// Mock the command executor to capture the command instead of running it
	commandExecutor = func(command string, args ...string) *exec.Cmd {
		executedCmd = command
		executedArgs = args
		// Return a command that does nothing and succeeds
		return exec.Command("true")
	}

	mockClient := &mockDockerClient{
		ContainerListFunc: func(ctx context.Context, options container.ListOptions) ([]types.Container, error) {
			return []types.Container{{ID: "container1"}}, nil
		},
		ContainerStatsFunc: func(ctx context.Context, containerID string, stream bool) (types.ContainerStats, error) {
			// Simulate 60% CPU usage: (6000 / 10000) * 1 CPU * 100 = 60%
			return types.ContainerStats{Body: newTestStats(6000, 10000)}, nil
		},
	}

	cfg := &Config{
		ProjectName:       "test-project",
		ServiceName:       "webapp",
		MinReplicas:       1,
		MaxReplicas:       5,
		ScaleMetric:       "cpu",
		CPUUpperThreshold: 50,
		ScaleUpStep:       2,
	}

	state := &State{
		DockerClient:   mockClient,
		ComposeCommand: "docker compose",
	}

	// --- Act ---
	evaluateAndScale(context.Background(), cfg, state)

	// --- Assert ---
	if executedCmd == "" {
		t.Fatal("Expected a command to be executed, but none was.")
	}

	expectedScale := "3" // 1 current + 2 scale-up-step
	foundScale := false
	for i, arg := range executedArgs {
		if arg == "--scale" && i+1 < len(executedArgs) {
			if executedArgs[i+1] == fmt.Sprintf("%s=%s", cfg.ServiceName, expectedScale) {
				foundScale = true
				break
			}
		}
	}

	if !foundScale {
		t.Errorf("Expected to scale to %s replicas, but command was: %v", expectedScale, executedArgs)
	}
}

func TestEvaluateAndScale_ScaleDown(t *testing.T) {
	// --- Setup ---
	originalExecutor := commandExecutor
	defer func() { commandExecutor = originalExecutor }()

	var executedCmd string
	var executedArgs []string

	commandExecutor = func(command string, args ...string) *exec.Cmd {
		executedCmd = command
		executedArgs = args
		return exec.Command("true")
	}

	mockClient := &mockDockerClient{
		ContainerListFunc: func(ctx context.Context, options container.ListOptions) ([]types.Container, error) {
			return []types.Container{{ID: "c1"}, {ID: "c2"}, {ID: "c3"}}, nil // Start with 3 replicas
		},
		ContainerStatsFunc: func(ctx context.Context, containerID string, stream bool) (types.ContainerStats, error) {
			// Simulate 10% CPU usage: (1000 / 10000) * 1 CPU * 100 = 10%
			return types.ContainerStats{Body: newTestStats(1000, 10000)}, nil
		},
	}

	cfg := &Config{
		ProjectName:       "test-project",
		ServiceName:       "webapp",
		MinReplicas:       1,
		MaxReplicas:       5,
		ScaleMetric:       "cpu",
		CPUUpperThreshold: 70, // Set a realistic upper threshold to prevent accidental scale-up
		CPULowerThreshold: 20,
		ScaleDownChecks:   1, // Scale down on the first check for this test
	}

	state := &State{
		DockerClient:   mockClient,
		ComposeCommand: "docker compose",
	}

	// --- Act ---
	evaluateAndScale(context.Background(), cfg, state)

	// --- Assert ---
	if executedCmd == "" {
		t.Fatal("Expected a command to be executed, but none was.")
	}

	expectedScale := "2" // 3 current - 1
	foundScale := false
	for i, arg := range executedArgs {
		if arg == "--scale" && i+1 < len(executedArgs) {
			if executedArgs[i+1] == fmt.Sprintf("%s=%s", cfg.ServiceName, expectedScale) {
				foundScale = true
				break
			}
		}
	}
	if !foundScale {
		t.Errorf("Expected to scale to %s replicas, but command was: %v", expectedScale, executedArgs)
	}
}

func TestCheckScaleDown(t *testing.T) {
	testCases := []struct {
		name            string
		cfg             *Config
		cpu             float64
		mem             float64
		shouldScaleDown bool
	}{
		{
			name: "CPU metric, CPU below threshold",
			cfg:  &Config{ScaleMetric: "cpu", CPULowerThreshold: 20},
			cpu:  10, mem: 50,
			shouldScaleDown: true,
		},
		{
			name: "CPU metric, CPU above threshold",
			cfg:  &Config{ScaleMetric: "cpu", CPULowerThreshold: 20},
			cpu:  30, mem: 50,
			shouldScaleDown: false,
		},
		{
			name: "Any metric, both CPU and Memory low",
			cfg:  &Config{ScaleMetric: "any", CPULowerThreshold: 20, MemLowerThreshold: 30},
			cpu:  10, mem: 20,
			shouldScaleDown: true,
		},
		{
			name: "Any metric, only CPU low",
			cfg:  &Config{ScaleMetric: "any", CPULowerThreshold: 20, MemLowerThreshold: 30},
			cpu:  10, mem: 40,
			shouldScaleDown: false,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			shouldScale := checkScaleDown(tc.cfg, tc.cpu, tc.mem)
			if shouldScale != tc.shouldScaleDown {
				t.Errorf("Expected shouldScaleDown to be %v, but got %v", tc.shouldScaleDown, shouldScale)
			}
		})
	}
}

package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/client"
)

// DockerAPIClient defines the interface for Docker API calls needed by the autoscaler.
// This allows for mocking the Docker client in tests.
type DockerAPIClient interface {
	ContainerList(ctx context.Context, options container.ListOptions) ([]types.Container, error)
	ContainerStats(ctx context.Context, containerID string, stream bool) (types.ContainerStats, error)
}

// Config holds all the configuration parameters for the autoscaler.
type Config struct {
	ProjectName          string
	ServiceName          string
	MinReplicas          int
	MaxReplicas          int
	ScaleMetric          string
	CPUUpperThreshold    float64
	CPULowerThreshold    float64
	MemUpperThreshold    float64
	MemLowerThreshold    float64
	ScaleUpCooldown      time.Duration
	ScaleDownCooldown    time.Duration
	ScaleUpStep          int
	ScaleDownChecks      int
	PollInterval         time.Duration
	LogHeartbeatInterval time.Duration
	InitialGracePeriod   time.Duration
	DryRun               bool
}

// State holds the dynamic state of the autoscaler.
type State struct {
	LastScaleEventTS           time.Time
	LastScaleDirection         string
	ConsecutiveScaleDownChecks int
	LastLogTS                  time.Time
	LastLoggedReplicas         int
	LastLoggedCPU              float64
	LastLoggedMem              float64
	DockerClient               DockerAPIClient
	ComposeCommand             string
}

// commandExecutor defines the function signature for executing external commands.
var commandExecutor = exec.Command

func main() {
	cfg := parseFlags()
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		log.Fatalf("Error creating Docker client: %v", err)
	}
	defer cli.Close()

	composeCmd, err := findComposeCommand()
	if err != nil {
		log.Fatalf("Error finding docker compose command: %v", err)
	}
	log.Printf("Using '%s'", composeCmd)

	// Log the project name at startup for clarity.
	log.Printf("[%s] Initializing autoscaler for project '%s'", cfg.ProjectName, cfg.ProjectName)

	state := &State{
		DockerClient:       cli,
		ComposeCommand:     composeCmd,
		LastScaleDirection: "none",
	}

	if err := validateServiceExists(cfg, state.ComposeCommand); err != nil {
		log.Fatalf("[%s] Validation error: %v", cfg.ProjectName, err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	setupSignalHandler(cancel)

	runAutoscaler(ctx, cfg, state)
}

func parseFlags() *Config {
	cfg := &Config{}
	flag.StringVar(&cfg.ProjectName, "project-name", "", "Docker Compose project name to operate on (required).")
	flag.StringVar(&cfg.ServiceName, "service", "", "The name of the service in docker-compose.yml to scale (required).")
	flag.IntVar(&cfg.MinReplicas, "min", 1, "Minimum number of replicas.")
	flag.IntVar(&cfg.MaxReplicas, "max", 5, "Maximum number of replicas.")
	flag.StringVar(&cfg.ScaleMetric, "metric", "cpu", "Metric to scale on: 'cpu', 'mem', or 'any'.")
	flag.Float64Var(&cfg.CPUUpperThreshold, "cpu-up", 70.0, "CPU percentage threshold to scale up.")
	flag.Float64Var(&cfg.CPULowerThreshold, "cpu-down", 20.0, "CPU percentage threshold to scale down.")
	flag.Float64Var(&cfg.MemUpperThreshold, "mem-up", 80.0, "Memory percentage threshold to scale up.")
	flag.Float64Var(&cfg.MemLowerThreshold, "mem-down", 30.0, "Memory percentage threshold to scale down.")
	flag.DurationVar(&cfg.ScaleUpCooldown, "cooldown-up", 20*time.Second, "Cooldown after scaling up.")
	flag.DurationVar(&cfg.ScaleDownCooldown, "cooldown-down", 20*time.Second, "Cooldown after scaling down.")
	flag.IntVar(&cfg.ScaleUpStep, "scale-up-step", 2, "Number of instances to add on scale-up.")
	flag.IntVar(&cfg.ScaleDownChecks, "scale-down-checks", 2, "Number of consecutive checks before scaling down.")
	flag.DurationVar(&cfg.PollInterval, "poll", 15*time.Second, "Interval to check metrics.")
	flag.DurationVar(&cfg.LogHeartbeatInterval, "heartbeat", 30*time.Second, "Interval to log a heartbeat status.")
	flag.DurationVar(&cfg.InitialGracePeriod, "initial-grace-period", 0, "Seconds to wait on startup before the first check.")
	flag.BoolVar(&cfg.DryRun, "dry-run", false, "Log scaling actions without executing them.")
	flag.Parse()

	if cfg.ProjectName == "" {
		log.Println("Error: --project-name is a required argument.")
		flag.Usage()
		os.Exit(1)
	}
	if cfg.ServiceName == "" {
		log.Println("Error: --service is a required argument.")
		flag.Usage()
		os.Exit(1)
	}
	if cfg.ScaleMetric != "cpu" && cfg.ScaleMetric != "mem" && cfg.ScaleMetric != "any" {
		log.Println("Error: Invalid value for --metric. Must be 'cpu', 'mem', or 'any'.")
		flag.Usage()
		os.Exit(1)
	}

	return cfg
}

func findComposeCommand() (string, error) {
	// Check for "docker compose" (v2)
	cmd := exec.Command("docker", "compose", "version")
	if err := cmd.Run(); err == nil {
		return "docker compose", nil
	}
	// Check for "docker-compose" (v1)
	cmd = exec.Command("docker-compose", "version")
	if err := cmd.Run(); err == nil {
		return "docker-compose", nil
	}
	return "", fmt.Errorf("neither 'docker compose' (v2) nor 'docker-compose' (v1) could be found")
}

func validateServiceExists(cfg *Config, composeCmd string) error {
	parts := strings.Split(composeCmd, " ")
	cmd := exec.Command(parts[0], append(parts[1:], "-p", cfg.ProjectName, "config", "--services")...)
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to get services from docker-compose: %v", err)
	}

	services := strings.Split(strings.TrimSpace(string(output)), "\n")
	for _, srv := range services {
		if srv == cfg.ServiceName {
			return nil
		}
	}

	return fmt.Errorf("service '%s' not found in project '%s'. Available services:\n  %s", cfg.ServiceName, cfg.ProjectName, strings.Join(services, "\n  "))
}

func setupSignalHandler(cancel context.CancelFunc) {
	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-c
		log.Println("Shutdown signal received. Exiting auto-scaler.")
		cancel()
	}()
}

func runAutoscaler(ctx context.Context, cfg *Config, state *State) {
	log.Printf("Starting auto-scaler for service: '%s'", cfg.ServiceName)
	if cfg.DryRun {
		log.Println("--- DRY RUN MODE ENABLED --- No actual scaling will be performed.")
	}

	log.Printf("[%s] Configuration: Metric=%s Min=%d Max=%d Up-Step=%d Poll=%s", cfg.ProjectName, cfg.ScaleMetric, cfg.MinReplicas, cfg.MaxReplicas, cfg.ScaleUpStep, cfg.PollInterval)

	if cfg.InitialGracePeriod > 0 {
		log.Printf("[%s] Initial grace period active. Waiting for %s before starting monitoring...", cfg.ProjectName, cfg.InitialGracePeriod)
		time.Sleep(cfg.InitialGracePeriod)
	}

	ticker := time.NewTicker(cfg.PollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			evaluateAndScale(ctx, cfg, state)
		}
	}
}

func evaluateAndScale(ctx context.Context, cfg *Config, state *State) {
	containers, err := getServiceContainers(ctx, state.DockerClient, cfg.ServiceName)
	if err != nil {
		log.Printf("[%s] Error getting containers for service '%s': %v", cfg.ProjectName, cfg.ServiceName, err)
		return
	}
	currentReplicas := len(containers)

	// Cooldown Check
	cooldown := getCooldown(state.LastScaleDirection, cfg)
	if cooldown > 0 && time.Since(state.LastScaleEventTS) < cooldown {
		remaining := cooldown - time.Since(state.LastScaleEventTS).Round(time.Second)
		if time.Since(state.LastLogTS) >= 10*time.Second {
			log.Printf("[%s] Scale-%s cooldown active (%s left). Waiting...", cfg.ProjectName, state.LastScaleDirection, remaining)
			state.LastLogTS = time.Now()
		}
		return
	}

	avgCPU, avgMem, err := getAverageStats(ctx, cfg, state.DockerClient, containers)
	if err != nil {
		log.Printf("Warning: Failed to get stats for service [%s] '%s'. Assuming 0%% usage. Error: %v", cfg.ProjectName, cfg.ServiceName, err)
		avgCPU, avgMem = 0.0, 0.0
	}

	logHeartbeat(cfg, state, currentReplicas, avgCPU, avgMem)

	shouldScaleUp, scaleUpReason := checkScaleUp(cfg, avgCPU, avgMem)
	shouldScaleDown := checkScaleDown(cfg, avgCPU, avgMem)

	if shouldScaleUp {
		targetReplicas := currentReplicas + cfg.ScaleUpStep
		if targetReplicas > cfg.MaxReplicas {
			targetReplicas = cfg.MaxReplicas
		}
		if targetReplicas > currentReplicas {
			log.Printf("[%s] Scale up triggered by: %s. Scaling up.", cfg.ProjectName, scaleUpReason)
			scaleService(cfg, state, targetReplicas, "up")
		} else {
			log.Printf("[%s] Scale up triggered by: %s. Cannot scale further, already at max replicas (%d).", cfg.ProjectName, scaleUpReason, cfg.MaxReplicas)
		}
		state.ConsecutiveScaleDownChecks = 0
	} else if shouldScaleDown && currentReplicas > cfg.MinReplicas {
		state.ConsecutiveScaleDownChecks++
		log.Printf("[%s] Scale down condition met (%d/%d).", cfg.ProjectName, state.ConsecutiveScaleDownChecks, cfg.ScaleDownChecks)
		if state.ConsecutiveScaleDownChecks >= cfg.ScaleDownChecks {
			log.Printf("[%s] Scaling down: threshold met for %d consecutive checks.", cfg.ProjectName, state.ConsecutiveScaleDownChecks)
			scaleService(cfg, state, currentReplicas-1, "down")
			state.ConsecutiveScaleDownChecks = 0
		}
	} else {
		state.ConsecutiveScaleDownChecks = 0
	}
}

func getCooldown(direction string, cfg *Config) time.Duration {
	if direction == "up" {
		return cfg.ScaleUpCooldown
	} else if direction == "down" {
		return cfg.ScaleDownCooldown
	}
	return 0
}

func logHeartbeat(cfg *Config, state *State, replicas int, cpu, mem float64) {
	if replicas != state.LastLoggedReplicas || cpu != state.LastLoggedCPU || mem != state.LastLoggedMem || time.Since(state.LastLogTS) >= cfg.LogHeartbeatInterval {
		var msg string
		switch cfg.ScaleMetric {
		case "any":
			msg = fmt.Sprintf("[%s] %s: Replicas=%d, AvgCPU=%.2f%% (Up>%.0f%%,Down<%.0f%%), AvgMem=%.2f%% (Up>%.0f%%,Down<%.0f%%)", cfg.ProjectName, cfg.ServiceName, replicas, cpu, cfg.CPUUpperThreshold, cfg.CPULowerThreshold, mem, cfg.MemUpperThreshold, cfg.MemLowerThreshold)
		case "cpu":
			msg = fmt.Sprintf("[%s] %s: Replicas=%d, AvgCPU=%.2f%% (Up>%.0f%%,Down<%.0f%%)", cfg.ProjectName, cfg.ServiceName, replicas, cpu, cfg.CPUUpperThreshold, cfg.CPULowerThreshold)
		case "mem":
			msg = fmt.Sprintf("[%s] %s: Replicas=%d, AvgMem=%.2f%% (Up>%.0f%%,Down<%.0f%%)", cfg.ProjectName, cfg.ServiceName, replicas, mem, cfg.MemUpperThreshold, cfg.MemLowerThreshold)
		}
		log.Println(msg)
		state.LastLogTS = time.Now()
		state.LastLoggedReplicas = replicas
		state.LastLoggedCPU = cpu
		state.LastLoggedMem = mem
	}
}

func checkScaleUp(cfg *Config, cpu, mem float64) (bool, string) {
	var reasons []string
	if cfg.ScaleMetric == "cpu" || cfg.ScaleMetric == "any" {
		if cpu > cfg.CPUUpperThreshold {
			reasons = append(reasons, fmt.Sprintf("CPU (%.2f%% > %.0f%%)", cpu, cfg.CPUUpperThreshold))
		}
	}
	if cfg.ScaleMetric == "mem" || cfg.ScaleMetric == "any" {
		if mem > cfg.MemUpperThreshold {
			reasons = append(reasons, fmt.Sprintf("Memory (%.2f%% > %.0f%%)", mem, cfg.MemUpperThreshold))
		}
	}
	if len(reasons) > 0 {
		return true, strings.Join(reasons, " and ")
	}
	return false, ""
}

func checkScaleDown(cfg *Config, cpu, mem float64) bool {
	switch cfg.ScaleMetric {
	case "cpu":
		return cpu < cfg.CPULowerThreshold
	case "mem":
		return mem < cfg.MemLowerThreshold
	case "any":
		return cpu < cfg.CPULowerThreshold && mem < cfg.MemLowerThreshold
	}
	return false
}

func getServiceContainers(ctx context.Context, cli DockerAPIClient, serviceName string) ([]types.Container, error) {
	containers, err := cli.ContainerList(ctx, container.ListOptions{
		Filters: labelFilter("com.docker.compose.service", serviceName),
	})
	if err != nil {
		return nil, err
	}
	return containers, nil
}

func getAverageStats(ctx context.Context, cfg *Config, cli DockerAPIClient, containers []types.Container) (float64, float64, error) {
	if len(containers) == 0 {
		return 0, 0, nil
	}

	var totalCPU, totalMem float64
	var statsCount int

	for _, cont := range containers {
		stats, err := cli.ContainerStats(ctx, cont.ID, false)
		if err != nil {
			log.Printf("Warning: could not get stats for container [%s] %s: %v", cfg.ProjectName, cont.ID[:12], err)
			continue
		}

		var v types.StatsJSON
		if err := json.NewDecoder(stats.Body).Decode(&v); err != nil {
			stats.Body.Close()
			log.Printf("Warning: could not decode stats for container [%s] %s: %v", cfg.ProjectName, cont.ID[:12], err)
			continue
		}
		stats.Body.Close()

		// Calculate CPU percentage
		var cpuPercent float64
		cpuDelta := float64(v.CPUStats.CPUUsage.TotalUsage - v.PreCPUStats.CPUUsage.TotalUsage)
		systemDelta := float64(v.CPUStats.SystemUsage - v.PreCPUStats.SystemUsage)
		if systemDelta > 0.0 && cpuDelta > 0.0 {
			cpuPercent = (cpuDelta / systemDelta) * float64(v.CPUStats.OnlineCPUs) * 100.0
		}

		// Calculate Memory percentage
		memPercent := (float64(v.MemoryStats.Usage) / float64(v.MemoryStats.Limit)) * 100.0

		if cpuPercent > 0 {
			totalCPU += cpuPercent
		}
		if memPercent > 0 {
			totalMem += memPercent
		}
		statsCount++
	}

	if statsCount == 0 {
		return 0, 0, fmt.Errorf("no containers returned stats")
	}

	return totalCPU / float64(statsCount), totalMem / float64(statsCount), nil
}

func scaleService(cfg *Config, state *State, newReplicas int, direction string) {
	if cfg.DryRun {
		log.Printf("[DRY RUN] Would scale [%s] %s %s to %d replicas.", cfg.ProjectName, cfg.ServiceName, direction, newReplicas)
		return
	}

	log.Printf("Scaling [%s] %s %s to %d replicas...", cfg.ProjectName, cfg.ServiceName, direction, newReplicas)

	parts := strings.Split(state.ComposeCommand, " ")
	// We explicitly pass the service name to 'up' to prevent it from trying to
	// re-evaluate and rebuild other services. The -p flag ensures we target the correct project.
	args := append(parts[1:], "-p", cfg.ProjectName, "up", "-d", "--scale", fmt.Sprintf("%s=%d", cfg.ServiceName, newReplicas), "--no-recreate", cfg.ServiceName)
	cmd := commandExecutor(parts[0], args...)

	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("Error: Failed to scale [%s] %s. Output:\n%s", cfg.ProjectName, cfg.ServiceName, string(output))
		return
	}

	log.Printf("Successfully scaled [%s] %s %s to %d replicas.", cfg.ProjectName, cfg.ServiceName, direction, newReplicas)
	state.LastScaleEventTS = time.Now()
	state.LastScaleDirection = direction
}

// labelFilter is a helper to create the correct filter format for the Docker API
func labelFilter(labelName, labelValue string) filters.Args {
	f := filters.NewArgs()
	f.Add("label", fmt.Sprintf("%s=%s", labelName, labelValue))
	return f
}

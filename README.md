# utils 🛠️

A collection of command-line utilities for SSH management, system monitoring, string generation, and Git automation.

## 🧠 Overview

This repository contains shell scripts for:

- Developer machine setup
- SSH host and key management
- System monitoring (temperature, user checks)
- String generation
- Git automation

All scripts are designed to be run in Unix-like environments.

## 🧩 Scripts

### 💻 Developer Machine Setup (`setup-dev-machine.sh`)

**Description:**  
Script to set up a new dev machine.

- Installs essential CLI tools like `eza`, `ag` (the_silver_searcher), `net-tools`, and `lazygit`.
- Copies the `.bash_aliases` file to the home directory.
- Runs the `install-lazyvim.sh` script to provide a full Neovim and LazyVim environment.

### 🌡️ System Temperature Monitor (`temp-monitor.sh`)

**Description:**  
Continuous temperature monitoring with:

- Color-coded sensor readings
- Trend arrows (↑/↓/→) for temperature changes
- Support for multiple thermal sensors

### 🧑‍🤝‍🧑 User Check (`user-check.sh`)

**Description:**  
Ensures the script is running as a specific user, attempting to switch with sudo if not.

- Automatically switches to target user with `sudo -u`

### 🎲 Random String Generator (`random-string.sh`)

**Description:**  
Generates one or more random hexadecimal strings with configurable:

- Number of strings to generate (`-n`, default: 3)
- Length of each string (`-l`, default: 5)

### 🧾 Git Utilities (`git-utils.sh`)

**Description:**  
Recursively performs Git commands on the current directory and all subdirectories that are Git repositories.

- Check status of all repos (`-gs`)
- Pull changes for all repos (`-gp`)
- View all local and remote branches (`-gvb`)
- Switch all repos to a specific branch (`-gb <branch>`)

### 🐳 Docker Compose Autoscaler (`docker-autoscale.sh`)


**Description:**
Utility to automatically scale a Docker Compose service up or down based on resource utilization. It can run as a sidecar container and monitor the target service or on the host.

- Scales based on CPU, Memory, or a combination of both.

- **Flexible Scaling Logic:**
  - `cpu`: Scale based on average CPU usage.
  - `mem`: Scale based on average Memory usage.
  - `any`: Scale up if *either* CPU or Memory is high, but only scale down if *both* are low.
- **Fine-Grained Control:**
  - Set min/max replica counts.
  - Configure CPU and Memory thresholds for scaling up and down.
  - Define cooldown periods to prevent thrashing.
  - Specify the number of instances to add during scale-up (`--scale-up-step`).
  - Require multiple consecutive checks before scaling down to ensure stability (`--scale-down-checks`).
- **Robust and Informative:**
  - Automatically detects and uses `docker compose` (v2) or `docker-compose` (v1).
  - Includes a `--dry-run` mode to test your configuration without making changes.
  - Provides an initial grace period to allow services to stabilize on startup.
  - Logs detailed status, scaling decisions, and heartbeats.

#### Example Usage

Here is a typical `docker-compose.yml` setup for using the autoscaler as a sidecar container.

```yaml
# docker-compose.yml
services:
  # This is the sample application we want to autoscale.
  # It has CPU limits to make it easier to stress and trigger scaling.
  webapp:
    image: nginx:alpine
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 128M

  # This service runs the autoscaler script.
  autoscaler:
    image: iamdanielv/utils:autoscale # Or build from source
    volumes:
      # Required to interact with the Docker daemon on the host
      - /var/run/docker.sock:/var/run/docker.sock
      # Mount the compose file so the script can find the service to validate it
      - ./docker-compose.yml:/app/docker-compose.yml
    command:
      - "--service"
      - "webapp"
      - "--min"
      - "1"
      - "--max"
      - "10"
      - "--metric"
      - "cpu"
      - "--cpu-up"
      - "20" # Scale up when avg CPU > 20%
      - "--cpu-down"
      - "5"  # Scale down when avg CPU < 5%
      - "--poll"
      - "5"  # Check metrics every 5 seconds
      - "--initial-grace-period"
      - "15" # Wait 15s on startup before first check
      # - "--dry-run" # Uncomment to test without making changes
    environment:
      # This ensures the compose command inside the container targets the correct project
      - COMPOSE_PROJECT_NAME=${PROJECT_NAME}
```

**To run this example:**

1.  Save the content above as `docker-compose.yml`.
2.  Run `PROJECT_NAME=$(basename "$PWD") docker compose up`.
3.  The `autoscaler` will start with one `webapp` instance.
4.  To trigger a scale-up, you can generate load. For example, using `hey` or `ab`:
    ```sh
    # Install hey: sudo apt install hey
    hey -z 1m http://localhost:8080
    ```
5.  Watch the logs from the `autoscaler` container to see it detect the high CPU usage and scale the `webapp` service up to the `--max` limit. When the load test finishes, it will eventually scale back down.


### 🗓️ Docker Compose Scheduler (`docker/schedule/scheduler.py`)

**Description:**
A Python-based scheduler that runs one-off tasks from your `docker-compose.yml` file based on a schedule. It discovers services to run by reading Docker labels.

- **Cron Scheduling:** Run tasks using standard cron expressions (e.g., `* * * * *`).
- **Interval Scheduling:** Run tasks at a fixed interval (e.g., every 60 seconds).
- **Simple Setup:** Define your tasks as regular services in `docker-compose.yml`, add a `scheduler.cron` or `scheduler.interval` label, and use a `profiles: ["donotstart"]` to prevent them from running automatically.
- **Live Log Streaming:** The scheduler captures and streams the logs from each task run in real-time, prefixed with the service name for clarity.

#### Example Usage

Here is a `docker-compose.yml` that defines the scheduler and two sample tasks: one running every 10 seconds (interval) and another running every minute (cron).

```yaml
# docker-compose.yml
services:
  # This service runs the scheduler script.
  scheduler:
    image: iamdanielv/utils:scheduler # Or build from source
    volumes:
      # Required to interact with the Docker daemon on the host
      - /var/run/docker.sock:/var/run/docker.sock
      # Mount this compose file so the scheduler can read the labels
      - ./docker-compose.yml:/app/docker-compose.yml:ro
    command:
      - "--project-name"
      - "${PROJECT_NAME}" # Pass the project name to the script
    environment:
      # This ensures the compose command inside the container targets the correct project
      - PROJECT_NAME=${PROJECT_NAME}

  # An example task that runs every 10 seconds.
  task-interval:
    image: alpine:latest
    command: sh -c 'echo "-> Hello from the 10-second interval task! Timestamp: $(date)"'
    labels:
      - "scheduler.interval=10"
    profiles: ["donotstart"] # Prevents this from starting with 'docker compose up'

  # An example task that runs every minute via a cron schedule.
  task-cron:
    image: alpine:latest
    command: sh -c 'echo "-> Hello from the cron task! Timestamp: $(date)"'
    labels:
      - "scheduler.cron=* * * * *"
    profiles: ["donotstart"] # Prevents this from starting with 'docker compose up'
```

**To run this example:**

1.  Save the content above as `docker-compose.yml`.
2.  Run `PROJECT_NAME=$(basename "$PWD") docker compose up scheduler`.
3.  Watch the logs from the `scheduler` container. You will see it discover the two tasks and start running them based on their defined schedules, streaming their output in real-time.


### 🎨 Color Palette Viewer (`colors.sh`)

**Description:**  
A utility to display all 256 terminal colors for both foreground and background.

- Helps in choosing colors for shell scripts and TUIs
- Can display colors as numbers or solid blocks (`-b` flag)
- Supports foreground (`-g fg`) and background (`-g bg`) modes

### 🔑 SSH Manager (`ssh-manager.sh`)

**Description:**  
An interactive TUI for managing and connecting to SSH hosts defined in `~/.ssh/config`.

- Connect, test, add, edit, rename, clone, reorder, and remove hosts
- Generate new SSH keys and copy them to servers
- Backup, import, and export host configurations
- Bypass menus for quick actions:
  - `-c, --connect`: Directly connect to a host
  - `-a, --add`: Directly add a new host
  - `-t, --test [host|all]`: Test connection to one or all hosts

### 🚀 LazyVim Installer (`install-lazyvim.sh`)

**Description:**  
A comprehensive script to automate the installation of LazyVim and all its prerequisites.

- Supports Debian/Ubuntu-based Linux distributions on x86_64 architecture.
- Installs dependencies like `ripgrep`, `fd`, and build tools
- Installs `fzf` from its official repository
- Downloads, installs, and updates the latest stable Neovim AppImage
- Installs the FiraCode Nerd Font for proper icon display
- Sets up a custom fzf configuration in `.bashrc` for enhanced fuzzy finding
- Backs up your existing Neovim config and sets up the LazyVim starter template

## 🤝 Contributing

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## 📜 License

[MIT License](LICENSE) - See the `LICENSE` file for details.

## 📧 Contact

Let me know if you have any questions.

- [Twitter](https://twitter.com/IAmDanielV)
- [BlueSky](https://bsky.app/profile/iamdanielv.bsky.social)

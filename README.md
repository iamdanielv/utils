# utils 🛠️

A collection of command-line utilities for developer setup, system administration, and automation.

## 🧠 Overview

This repository contains shell scripts for:

- Developer machine setup
- Interactive environment variable management
- Git automation
- Docker automation and scheduling
- System monitoring (temperature, user checks)
- Virtual Machine management (KVM/QEMU)
- Miscellaneous utilities (string generation, color palettes)

All tools are designed to be run in Unix-like environments.

## 🧩 Scripts & Tools

### 🏛️ Centurion (`centurion/`)

**Description:**
A Go-based TUI (Text User Interface) for managing `systemd` services.

- **Service Explorer**: View and filter systemd services.
- **Controls**: Start, stop, and restart units.
- **Logs**: Integrated journalctl log viewing.

### 💻 Developer Machine Setup (`setup-dev-machine.sh`)

**Description:**
Script to set up a new dev machine.

- Installs essential CLI tools like `eza`, `ag` (the_silver_searcher), `net-tools`, `micro`, and `jq`.
- Installs the latest versions of `lazygit`, `lazydocker`, and `golang`.
- Copies the `.bash_aliases` file from the repository to `~/.bash_aliases`.
- Executes the `install-lazyvim.sh` script to provide a full Neovim and LazyVim environment.

### 🚀 LazyVim Installer (`install-lazyvim.sh`)

**Description:**
A comprehensive script to automate the installation of LazyVim and all its prerequisites.

- Supports Debian/Ubuntu-based Linux distributions on x86_64 architecture.
- Installs dependencies like `ripgrep`, `fd`, and build tools.
- Installs `fzf` from its official repository
- Downloads, installs, and updates the latest stable Neovim AppImage
- Installs the FiraCode Nerd Font for proper icon display
- Sets up a custom fzf configuration in `.bashrc` for enhanced fuzzy finding
- Backs up your existing Neovim config and sets up the LazyVim starter template

### 📝 Env Manager (`dv-env`)

**Description:**
An interactive TUI for managing environment variables in a `.env` file. It provides a safe and structured way to view, add, edit, and delete variables without manual text editing.

- **Interactive TUI:** A full-screen, list-based interface to manage your environment variables.
- **Variable Management:** Add, edit, and delete variables and their associated comments.
- **Smart Comments:** Supports special comments (`##@ VAR_NAME comment text`) that are linked to variables and preserved during edits.
- **Safe Editing:** Automatically handles quoting for values with spaces.
- **System Environment Import:** Interactively view and import variables from your current system environment into the `.env` file.
- **External Editor Integration:** Quickly open the `.env` file in your default editor (`$EDITOR`).
- **Automatic Discovery:** Finds and edits the `.env` file in the project root by default, or you can specify a path.

### 🧾 Git Utilities (`git-utils.sh`)

**Description:**
Recursively performs Git commands on the current directory and all subdirectories that are Git repositories.

- Check status of all repos (`-gs`)
- Pull changes for all repos (`-gp`)
- View all local and remote branches (`-gvb`)
- Switch all repos to a specific branch (`-gb <branch>`)

### 🧹 Docker Cleanup (`dv-docker-cleanup`)

**Description:**
A utility to clean up unused Docker resources like containers, images, networks, and volumes.

- Prune stopped containers, unused networks, unused volumes, and dangling/unused images.
- Supports dry-run mode (`--dry-run`).
- Force option (`-f`) to skip confirmation.

### 🐳 Docker Compose Autoscaler (`docker-autoscale.sh`)

**Description:**
Utility to automatically scale a Docker Compose service up or down based on resource utilization. It can run as a sidecar container and monitor the target service or on the host.

*Note: A Go-based version of this tool is available in `docker/go-scale/`.*

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

1. Save the content above as `docker-compose.yml`.
2. Run `PROJECT_NAME=$(basename "$PWD") docker compose up`.
3. The `autoscaler` will start with one `webapp` instance.
4. To trigger a scale-up, you can generate load. For example, using `hey` or `ab`:

    ```sh
    # Install hey: sudo apt install hey
    hey -z 1m http://localhost:8080
    ```

5. Watch the logs from the `autoscaler` container to see it detect the high CPU usage and scale the `webapp` service up to the `--max` limit. When the load test finishes, it will eventually scale back down.

### 🗓️ Docker Compose Scheduler (`docker/schedule/scheduler.py`)

**Description:**
A Python-based scheduler that runs one-off tasks from your `docker-compose.yml` file based on a schedule. It discovers services to run by reading Docker labels.

- **Cron Scheduling:** Run tasks using standard cron expressions (e.g., `* * * * *`).
- **Interval Scheduling:** Run tasks at a fixed interval (e.g., every 60 seconds).
- **Simple Setup:** Define your tasks as regular services in `docker-compose.yml`, add a `scheduler.cron` or `scheduler.interval` label, and use a `profiles: ["donotstart"]` to prevent them from running automatically.
- **Live Log Streaming:** The scheduler captures and streams the logs from each task run in real-time, prefixed with the service name for clarity.

#### Docker Compose Scheduler - Example Usage

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

1. Save the content above as `docker-compose.yml`.
2. Run `PROJECT_NAME=$(basename "$PWD") docker compose up scheduler`.
3. Watch the logs from the `scheduler` container. You will see it discover the two tasks and start running them based on their defined schedules, streaming their output in real-time.

### 🌡️ System Temperature Monitor (`temp-monitor.sh`)

**Description:**
Continuously displays temperatures from system thermal sensors.

- Color-coded sensor readings (green/yellow/red).
- Trend arrows (↑/↓/→) show change against a moving average.
- Supports multiple thermal sensors.
- Configurable refresh interval (`-i`), temperature delta (`-d`), and averaging count (`-a`).

### 🧑‍🤝‍🧑 User Check (`user-check.sh`)

**Description:**
Ensures the script is running as a specific user, attempting to switch with sudo if not.

- Automatically switches to target user with `sudo -u`.

### 🎲 Random String Generator (`random-string.sh`)

**Description:**
Generates one or more random hexadecimal strings with configurable:

- Number of strings to generate (`-n`, default: 3).
- Length of each string (`-l`, default: 5).

### 🎨 Color Palette Viewer (`colors.sh`)

**Description:**
A utility to display all 256 terminal colors for both foreground and background.

- Helps in choosing colors for shell scripts and TUIs.
- Can display colors as numbers or solid blocks (`-b` flag).
- Supports foreground (`-g fg`) and background (`-g bg`) modes.

### 🖥️ VM Manager (`dv-vm-manager`)

**Description:**
A TUI (Text User Interface) for managing KVM/QEMU virtual machines using `virsh`.

- **Dashboard**: View real-time status, CPU usage, and memory usage of all VMs.
- **Controls**: Start, shutdown, reboot, or force stop VMs.
- **Details View**: Inspect VM specifics like network interfaces (IP addresses), storage devices, and guest agent status.

### 🐚 Interactive Shell Workflow

**Description:**
A set of FZF-powered interactive tools and aliases defined in `.bash_aliases` to enhance the terminal experience.

**Keybindings (Prefix: `Alt+x`):**

- **Find in Files** (`Alt+x f`): Interactive search using `ripgrep` and `fzf` with previews.
- **Fuzzy History** (`Alt+x r`): Search command history interactively.
- **Process Killer** (`Alt+x k`): Filter and kill processes with previews.
- **Fuzzy Man Pages** (`Alt+x m`): Search and read man pages.
- **File Finder** (`Alt+x e`): Find files and open them in Neovim.
- **Cheatsheets**:
  - `Alt+x ?`: View all available aliases.
  - `Alt+x /`: View all custom keybindings.

#### Find in Files (`Alt+x f`)

Interactive search using `ripgrep` and `fzf` with previews.

```text
── Find in Files ───────────────────────────────────────────────────────────────────────────────────
  Type to search content | ENTER: ope·· ╭──────────────────────────────────────────────────────────╮
  Search❯                               │    1 #!/bin/bash                                   1/115││
  11694/11694 ───────────────────────── │ ↳                                                        │
▌ sync-bash-aliases.sh:1:1:#!/bin/bash ││    2 # ================================================= │
  sync-bash-aliases.sh:2:1:# ========·· │ ↳ =============================                          │
  sync-bash-aliases.sh:3:1:# Script N·· │    3 # Script Name: sync-bash-aliases.sh                 │
  sync-bash-aliases.sh:4:1:# Descript·· │    4 # Description: Quickly syncs local .bash_aliases to │
  sync-bash-aliases.sh:5:1:#         ·· │ ↳  ~/.bash_aliases                                       │
  sync-bash-aliases.sh:6:1:# Usage:  ·· │    5 #              for rapid development and testing.   │
  sync-bash-aliases.sh:7:1:# ========·· │    6 # Usage:       ./sync-bash-aliases.sh [-c|--cleanup │
  sync-bash-aliases.sh:8:1:             ╰──────────────────────────────────────────────────────────╯
```

#### Fuzzy History (`Alt+x r`)

Search command history interactively.

```text
─ Command History ──────────────────────────────────────────────────────────────────────────────────
  ENTER: Select | CTRL-E: Execute | CTRL-/: View                                                    
  History❯ echo                                                                                     
  3/516 ─────────────────────────────────────────────────────────────────────────────────────────── 
    253  echo $XDG_CONFIG_HOME
▌   175  echo "Hello there"
    173  echo "General Kenobi"
```

#### Process Killer (`Alt+x k`)

Filter and kill processes with previews

```text
── Process Killer ──────────────────────────────────────────────────────────────────────────────────
  ENTER: kill (TERM) | CTRL-K: kill (KILL)        ╭ Details for PID [1] ───────────────────────────╮
  TAB: mark | SHIFT-UP/DOWN: scroll details       │ PID: 1      User: root  CPU: 0.0    Mem: 0.1   │
  Filter❯                                         │ ──────────────────────────────────             │
  332/332 (0) ─────────────────────────────────── │ /usr/lib/systemd/systemd --switched-root --sys │
▌ root           1 /usr/lib/systemd/systemd --s··││ ↳ tem --deserialize=48 splash                  │
  root           2 [kthreadd]                     │                                                │
  root           3 [pool_workqueue_release]       │                                                │
  root           4 [kworker/R-rcu_gp]             │                                                │
  root           5 [kworker/R-sync_wq]            │                                                │
  root           6 [kworker/R-kvfree_rcu_reclaim] │                                                │
  root           7 [kworker/R-slub_flushwq]       ╰────────────────────────────────────────────────╯
```

#### Fuzzy Man Pages (`Alt+x m`)

Search and read man pages

```text
── Manual Pages ────────────────────────────────────────────────────────────────────────────────────
  ENTER: open | CTRL-/: view            ╭──────────────────────────────────────────────────────────╮
  Man❯ bat                              │ BATCAT(1)       General Commands Manual       BATCA1/515││
  1830/7501 ─────────────────────────── │                                                          │
▌ batcat (1)           - a cat(1) clo··││ NAME                                                     │
  ··y-check (8) - Check battery level·· │        batcat - a cat(1) clone with syntax highlighting  │
  ··y (5) - BlueZ D-Bus Battery API d·· │        and Git integration.                              │
  ··service (8) - Check battery level·· │                                                          │
  ··   - update passwords in batch mode │ USAGE                                                    │
  ··r (5) - BlueZ D-Bus BatteryProvid·· │        batcat [OPTIONS] [FILE]...                        │
  ··pdate group passwords in batch mode │                                                          │
  ··r (5) - BlueZ D-Bus BatteryProvid·· ╰──────────────────────────────────────────────────────────╯
```

#### File Finder (`Alt+x e`)

Find files and open them in Neovim

```text
── File Finder ─────────────────────────────────────────────────────────────────────────────────────
  ENTER: open | ESC: quit               ╭─ Previewing [.bash_aliases] ─────────────────────────────╮
  CTRL-/: view                          │    1 # shellcheck shell=bash                       1/793││
  Open❯ bas                             │    2 # -------------------                               │
  2/82 ──────────────────────────────── │    3 # Colors & Styling                                  │
▌ .bash_aliases                         │    4 # -------------------                               │
  sync-bash-aliases.sh                  │    5                                                     │
                                        │    6 # ANSI Color Codes                                  │
                                        │    7 _C_RESET=$'\033[0m'                                 │
                                        │    8 _C_RED=$'\033[1;31m'                                │
                                        │    9 _C_GREEN=$'\033[1;32m'                              │
                                        ╰──────────────────────────────────────────────────────────╯
```

#### Cheatsheet - Tmux All (`Prefix ?`)

View all TMUX available key bindings.


```text
╭─ TMUX KEY BINDINGS ──────────────────────────────────────╮      
│ >                             │ C-h:                     │      
│   112/112 ─────────────────── │   Smart Switch Left      │      
│ ▌     C-h     @@@Smart Swit··││                          │      
│       C-j     @@@Smart Swit·· │                          │      
│       C-k     @@@Smart Swit·· │                          │      
│       C-l     @@@Smart Swit·· │                          │      
│   C-a Space   @@@Select nex·· │                          │      
│   C-a !       @@@Break pane·· │                          │      
│   C-a #       @@@List all p·· │                          │      
│   C-a $       @@@Rename cur·· │                          │      
│   C-a &       @@@Kill curre·· │                          │      
│   C-a '       @@@Prompt for·· │                          │      
│   C-a (       @@@Switch to ·· │                          │      
│   C-a )       @@@Switch to ·· │                          │      
╰──────────────────────────────────────────────────────────╯  
```

#### Cheatsheet - Tmux Custom Bindings (`Prefix /`)

View all custom Tmux keybindings.

```text
╭─ Cheatsheet (Prefix: C-a) ─────────────────────────────────────────╮                
│NAVIGATION - Direct                                                 │                
│  C-h/j/k/l    Move between panes (vim-aware)                       │                
│                                                                    │                
│NAVIGATION - with Prefix                                            │                
│  C-p / C-n    Previous / Next Window                               │                
│                                                                    │                
│WINDOWS & PANES                                                     │                
│  - / =        New Split Vertical / Horizontal                      │                
│  b            Send Pane to [Current Session] +:New Window          │                
│  j            Join a Pane to [Current Session]                     │                
│  k            Send a Pane to [Session] window                      │                
│  s            Session Manager                                      │                
│  S            Choose Tree (Default Session Management)             │                
│  S-Left/Right Swap window position                                 │                
│  z            Zoom pane                                            │                
│:                                                                   │                
╰────────────────────────────────────────────────────────────────────╯ 
```

### Cheatsheet - Custom Bash Binding (`Alt+x /`)

View all custom keybindings and functions.

```text
╭─ Bindings Cheatsheet (Prefix: Alt+x) ────────────────────╮                     
│   Run❯                                                   │                     
│   13/13 ──────────────────────────────────────────────── │                     
│ ▌ /       : Show this Cheatsheet                        ││                     
│   ?       : Show Alias Cheatsheet                       ││                     
│   Alt+x   : Clear Screen (this requires Alt+x twice)    ││                     
│   e       : Find File and Open in Editor - nvim         ││                     
│   f       : Find text in Files (fif)                    ││                     
│   r       : (R)ecent Command History                    ││                     
│   m       : Find Manual Pages (fman)                    ││                     
│   k       : Process Killer (dv-kill)                    ││                     
│   g g     : Git GUI (lazygit)                           ││                     
│   g l     : Git Log (fgl)                                │                     
│   g b     : Git Branch (dv-git-branch)                   │                     
│   g h     : Git File History (dv-git-history)            │                     
╰──────────────────────────────────────────────────────────╯
```

### Alias Cheatsheet (`Alt+x ?`)

```
╭─ Alias Cheatsheet ───────────────────────────────────────╮                     
│   Run❯                                                   │                     
│   26/26 ──────────────────────────────────────────────── │                     
│ ▌ ..       : Go up one directory (cd ..)                ││                     
│   cat      : Replaced with (batcat/bat)                 ││                     
│   check-reboot : Check Reboot Status                    ││                     
│   ga       : Git Add (git add)                          ││                     
│   gb       : Git Show Branches (git branch -a)           │                     
│   gc       : Git Commit (git commit -m)                  │                     
│   gl       : Git Log Graph (git log --graph ...)         │                     
│   glf      : Git Log File (git log --follow ...)         │                     
│   gp       : Git Push (git push)                         │                     
│   gs       : Git Status (git status -sb)                 │                     
│   ip       : IP with color (ip -c)                       │                     
╰──────────────────────────────────────────────────────────╯ 
```


**Utilities:**

- `ports`: View listening TCP/UDP ports and associated processes.
- `update`: Wrapper for `apt update/upgrade/autoremove`.
- `check-reboot`: Checks if a system reboot is required.

#### Ports

View listening TCP/UDP ports and associated processes.

```text
P STATUS           LOCAL:Port           REMOTE:Port  PROGRAM/PID                                    
U UNCONN       127.0.0.1:323           0.0.0.0:*     -                                              
U UNCONN         0.0.0.0:5353          0.0.0.0:*     "avahi-daemon",pid=850                         
U UNCONN      172.17.0.1:3702          0.0.0.0:*     "python3",pid=1234                             
T LISTEN   127.0.0.53%lo:53            0.0.0.0:*     -
T LISTEN       127.0.0.1:631           0.0.0.0:*     -
T LISTEN       127.0.0.1:5432          0.0.0.0:*     "postgres",pid=1543                            
T LISTEN         0.0.0.0:22            0.0.0.0:*     "sshd",pid=1100                                
T LISTEN         0.0.0.0:80            0.0.0.0:*     "nginx",pid=2048                               
T LISTEN         0.0.0.0:4000          0.0.0.0:*     "node",pid=3005                                
T LISTEN           [::1]:631              [::]:*     -
T LISTEN            [::]:22               [::]:*     "sshd",pid=1100                                
```

#### update

Wrapper for `apt update/upgrade/autoremove`.

```shell
Update apt sources...                                                                               
[sudo: authenticate] Password:                                                                      
Hit:1 https://download.docker.com/linux/ubuntu noble InRelease                                      
Hit:2 https://packages.microsoft.com/repos/code stable InRelease                                    
Hit:3 http://us.archive.ubuntu.com/ubuntu noble InRelease                                           
Get:4 http://us.archive.ubuntu.com/ubuntu noble-updates InRelease [136 kB]                          
Get:5 http://security.ubuntu.com/ubuntu noble-security InRelease [136 kB]                           
Get:6 http://us.archive.ubuntu.com/ubuntu noble-backports InRelease [133 kB]                        
Get:7 http://us.archive.ubuntu.com/ubuntu noble-updates/main amd64 Packages [234 kB]                
Get:8 http://us.archive.ubuntu.com/ubuntu noble-updates/main amd64 Components [36.8 kB]             
Get:9 http://us.archive.ubuntu.com/ubuntu noble-updates/restricted amd64 Components [212 B]         
Get:10 http://us.archive.ubuntu.com/ubuntu noble-updates/universe amd64 Packages [138 kB]           
Get:11 http://security.ubuntu.com/ubuntu noble-security/main amd64 Components [448 B]               
Get:12 http://us.archive.ubuntu.com/ubuntu noble-updates/universe amd64 Components [38.4 kB]        
Get:13 http://us.archive.ubuntu.com/ubuntu noble-updates/multiverse amd64 Components [212 B]        
Get:14 http://us.archive.ubuntu.com/ubuntu noble-backports/main amd64 Components [212 B]            
Get:15 http://us.archive.ubuntu.com/ubuntu noble-backports/restricted amd64 Components [216 B]      
Get:16 http://us.archive.ubuntu.com/ubuntu noble-backports/universe amd64 Components [216 B]        
Get:17 http://us.archive.ubuntu.com/ubuntu noble-backports/multiverse amd64 Components [216 B]      
Get:18 http://security.ubuntu.com/ubuntu noble-security/restricted amd64 Components [212 B]         
Get:19 http://security.ubuntu.com/ubuntu noble-security/universe amd64 Components [7,100 B]         
Get:20 http://security.ubuntu.com/ubuntu noble-security/multiverse amd64 Components [212 B]         
Fetched 861 kB in 1s (613 kB/s)                                                                     
3 packages can be upgraded. Run 'apt list --upgradable' to see them.                                
  
Upgrade apt packages...                                                                             
Upgrading:                                                                                          
  docker-ce  docker-ce-cli  docker-ce-rootless-extras                                               
                                                                                                    
Summary:                                                                                            
  Upgrading: 3, Installing: 0, Removing: 0, Not Upgrading: 0                                        
  Download size: 43.7 MB                                                                            
  Freed space: 44.0 kB                                                                              
                                                                                                    
Get:1 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce-cli amd64 5:26.1.5-1~ubu
ntu.24.04~noble [16.3 MB]                                                                           
Get:2 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce amd64 5:26.1.5-1~ubuntu.
24.04~noble [21.1 MB]                                                                               
Get:3 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce-rootless-extras amd64 5:
26.1.5-1~ubuntu.24.04~noble [6,385 kB]                                                              
Fetched 43.7 MB in 1s (29.9 MB/s)  
(Reading database ... 201729 files and directories currently installed.)
Preparing to unpack .../docker-ce-cli_5%3a26.1.5-1~ubuntu.24.04~noble_amd64.deb ...                 
Unpacking docker-ce-cli (5:26.1.5-1~ubuntu.24.04~noble) over (5:26.1.4-1~ubuntu.24.04~noble) ...    
Preparing to unpack .../docker-ce_5%3a26.1.5-1~ubuntu.24.04~noble_amd64.deb ...                     
Unpacking docker-ce (5:26.1.5-1~ubuntu.24.04~noble) over (5:26.1.4-1~ubuntu.24.04~noble) ...        
Preparing to unpack .../docker-ce-rootless-extras_5%3a26.1.5-1~ubuntu.24.04~noble_amd64.deb ...     
Unpacking docker-ce-rootless-extras (5:26.1.5-1~ubuntu.24.04~noble) over (5:26.1.4-1~ubuntu.24.04~noble) ...
Setting up docker-ce-cli (5:26.1.5-1~ubuntu.24.04~noble) ...                                        
Setting up docker-ce-rootless-extras (5:26.1.5-1~ubuntu.24.04~noble) ...                            
Setting up docker-ce (5:26.1.5-1~ubuntu.24.04~noble) ...                                            
invoke-rc.d: policy-rc.d denied execution of restart.
/usr/sbin/policy-rc.d returned 101, not running 'restart docker.service docker.socket'
Processing triggers for man-db (2.13.1-1) ...

Autoremove apt packages...
Summary:                        
  Upgrading: 0, Installing: 0, Removing: 0, Not Upgrading: 0

✓ No Reboot Required
```

#### check-reboot

Checks if a system reboot is required.

```shell
✓ No Reboot Required
```
or

```shell
 Reboot Required
```

### 🧩 Tmux Workflow

**Description:**
A highly configured Tmux setup (`tmux.conf`) focused on speed and integration with Vim.

### Session Manager
```text
󰖲 Session Manager ──────────────────────────────────────────────────────────────────────────╮   
│    New Session                      ╭ 󰖲 Preview: main ───────────────────────────────────╮ │   
│ ▌  main: 1 windows                  │ ├── [1] bash (Active)                         1/14││ │   
│   scratch: 1 windows                 │ │  Summary:                                       ││ │   
│                                      │ │    Upgrading: 0, Installing: 0, Removing: 0, Not││ │   
│   Commands: ─────────────────────────│ │                                                  │ │   
│   ENTER: Switch  C-n: New            │ │  ✓ No Reboot Required                            │ │   
│     C-r: Rename  C-x: Kill           │ │  daniel@dev:~/code/iamdanielv/utils$ check-reboo │ │   
│   3/3 ────────────────────────────── │ │  ✓ No Reboot Required                            │ │   
│ Session ❯                            ╰────────────────────────────────────────────────────╯ │   
╰─────────────────────────────────────────────────────────────────────────────────────────────╯ 
```

**Core Features:**

- **Prefix**: Remapped to `Ctrl+a`.
- **Smart Navigation**: Seamlessly navigate between Tmux panes and Vim splits using `Ctrl+h/j/k/l`.
- **Scratchpad** (`Prefix + \``): A toggleable popup terminal for quick tasks.
- **Session Manager** (`Prefix + s`): Interactive session switcher, creator, and manager.

**Execute Menu (`Prefix + e`):**
Opens a menu to launch utilities:
- **Find File**: `dv-find`
- **Find in Files**: `dv-fif`
- **Process Killer**: `dv-kill`
- **System Monitor**: `btop`
- **Ports**: `dv-ports`
- **Man Pages**: `dv-man`
- **LazyDocker**: `lazydocker`
- **Env Manager**: `dv-env`
- **System Update**: `dv-update`

**Git Integration (`Prefix + g`):**
Opens a menu with interactive tools:
- **Branch Manager**: Checkout, delete, and track branches.
- **Git Log**: Browse commit history with diff previews.
- **Git Status**: View and act on changed files.

**Pane Management:**

- **Push/Pull**:
  - `Prefix + j`: Pull a pane from another window to the current one.
  - `Prefix + k`: Send the current pane to another window.
- **Sync**: `Prefix + C-s` toggles input synchronization across all panes in the window.

## 🤝 Contributing

I'm open to and encourage contributions of bug fixes, improvements, and documentation! I like working on tooling to make developer experience better. Let me know if there is something you would like to see or would make your developer experience better.

## 📜 License

[MIT License](LICENSE) - See the `LICENSE` file for details.

## 📧 Contact

Let me know if you have any questions.

- [Twitter](https://twitter.com/IAmDanielV)
- [BlueSky](https://bsky.app/profile/iamdanielv.bsky.social)

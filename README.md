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

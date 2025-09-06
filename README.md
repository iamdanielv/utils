# utils 🛠️

A collection of command-line utilities for system monitoring, string generation, and Git automation.

## 🧠 Overview

This repository contains shell scripts for:

- System monitoring (temperature, user checks)
- String generation
- Git automation

All scripts are designed to be run in Unix-like environments.

## 🧩 Scripts

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

## 🤝 Contributing

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## 📜 License

[MIT License](LICENSE) - See the `LICENSE` file for details.

## 📧 Contact

Let me know if you have any questions.

- [Twitter](https://twitter.com/IAmDanielV)
- [BlueSky](https://bsky.app/profile/iamdanielv.bsky.social)

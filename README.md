# utils 🛠️

A collection of command-line utilities for system monitoring, string generation, and Git automation.

## 🎁 Bonus: Shell Aliases (` .bash_aliases `)

**Description:**  
Provides enhanced shell aliases for tools like `vim`, `cat`,

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
Generates random hexadecimal strings with configurable:

- Length (default: 5 characters)
- Output format options

### 🧾 Git Utilities (`git-utils.sh`)

**Description:**  
Streamlines common Git workflows with:

- Branch management shortcuts
- Commit automation
- Repository analysis tools

### 🎨 Color Palette Viewer (`colors.sh`)

**Description:**  
A utility to display all 256 terminal colors for both foreground and background.

- Helps in choosing colors for shell scripts and TUIs
- Can display colors as numbers or solid blocks (`-b` flag)
- Supports foreground (`-g fg`) and background (`-g bg`) modes

### 🔑 SSH Manager (`ssh-manager.sh`)

**Description:**  
An interactive TUI for managing and connecting to SSH hosts defined in `~/.ssh/config`.

- Connect, test, add, edit, clone, and remove hosts
- Generate new SSH keys and copy them to servers
- Backup, import, and export host configurations

## 🤝 Contributing

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## 📜 License

[MIT License](LICENSE) - See the `LICENSE` file for details.

## 📧 Contact

Let me know if you have any questions.

- [Twitter](https://twitter.com/IAmDanielV)
- [BlueSky](https://bsky.app/profile/iamdanielv.bsky.social)

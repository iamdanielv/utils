#!/bin/bash
# A script to automate the setup of a new dev machine.

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for TUI functions and error handling.
# shellcheck source=./shared.sh
# shellcheck source=./src/lib/shared.lib.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/src/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

# --- Global Variables ---
SCRIPT_DIR=""

# --- Script Functions ---

print_usage() {
    printBanner "Developer Machine Setup Script"
    printMsg "This script automates the setup of a new developer environment by installing"
    printMsg "essential tools and setting up a complete LazyVim configuration."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"
    printMsg "\n${T_ULINE}What it does:${T_RESET}"
    printMsg "  1. Checks for a compatible system (Debian/Ubuntu-based Linux)."
    printMsg "  2. Installs essential CLI tools referenced in '.bash_aliases' (eza, ag, net-tools)."
    printMsg "  3. Copies the '.bash_aliases' file from this repository to '~/.bash_aliases'."
    printMsg "  4. Executes the 'install-lazyvim.sh' script for a full Neovim setup."
    printMsg "  5. Installs the latest versions of Go, lazygit, and lazydocker."
    printMsg "  6. Provides final instructions for the user."
    printMsg "\nRun without arguments to start the setup."
}

# Installs a package if it's not already installed.
# Usage: install_package <package_name> [command_to_check]
install_package() {
    local package_name="$1"
    local command_to_check="${2:-$1}"

    if command -v "$command_to_check" &>/dev/null; then
        printInfoMsg "'${package_name}' is already installed. Skipping."
        return
    fi

    printInfoMsg "Installing '${package_name}'..."
    if ! sudo apt-get install -y "$package_name"; then
        printErrMsg "Failed to install '${package_name}'. Please try installing it manually."
        # We don't exit here to allow the rest of the setup to continue.
    else
        printOkMsg "Successfully installed '${package_name}'."
    fi
}

# Installs lazygit by downloading the latest binary from GitHub releases.
install_lazygit() {
    
    # Determine architecture for download URL
    local arch
    if [[ "$(uname -m)" == "x86_64" ]]; then
        arch="x86_64"
    else
        printErrMsg "Unsupported architecture for lazygit: $(uname -m). Only x86_64 is supported by this script."
        return 1
    fi
    printBanner "Install/Update lazygit"

    # Get latest version tag
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name')

    if [[ -z "$latest_version" ]]; then
        printErrMsg "Could not determine latest lazygit version from GitHub API."
        return
    fi

    printInfoMsg "Latest available lazygit version: ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version_string="Not installed"
    if command -v lazygit &>/dev/null; then
        installed_version_string=$(lazygit --version)
    fi
    printInfoMsg "Currently installed version:      ${C_L_YELLOW}${installed_version_string}${T_RESET}"

    if ! prompt_yes_no "Do you want to install/update to version ${latest_version}?" "y"; then
        printInfoMsg "Lazygit installation skipped."
        return
    fi

    # The version tag from GitHub includes 'v' (e.g., v0.40.2), but the tarball name does not.
    local version_number_only="${latest_version#v}"
    local tarball_name="lazygit_${version_number_only}_Linux_${arch}.tar.gz"
    local download_url="https://github.com/jesseduffield/lazygit/releases/download/${latest_version}/${tarball_name}"
    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    local temp_dir; temp_dir=$(mktemp -d)
    # Ensure the temp directory is cleaned up on exit
    trap 'rm -rf "$temp_dir"' RETURN

    printInfoMsg "Downloading lazygit ${latest_version}..."
    printMsg "  ${C_L_BLUE}${download_url}${T_RESET}"

    if curl -L -f --progress-bar "$download_url" -o "${temp_dir}/${tarball_name}"; then
        printInfoMsg "Extracting binary..."
        tar -xzf "${temp_dir}/${tarball_name}" -C "$temp_dir"
        
        printInfoMsg "Installing to ${install_dir}/lazygit..."
        mv "${temp_dir}/lazygit" "${install_dir}/lazygit"
        printOkMsg "Successfully installed lazygit ${latest_version}."
    else
        printErrMsg "Failed to download lazygit. Please try installing it manually."
    fi
}

# Installs lazydocker by downloading the latest binary from GitHub releases.
install_lazydocker() {
    # Determine architecture for download URL
    local arch
    if [[ "$(uname -m)" == "x86_64" ]]; then
        arch="x86_64"
    else
        printErrMsg "Unsupported architecture for lazydocker: $(uname -m). Only x86_64 is supported by this script."
        return 1
    fi
    printBanner "Install/Update lazydocker"

    # Get latest version tag
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | jq -r '.tag_name')

    if [[ -z "$latest_version" ]]; then
        printErrMsg "Could not determine latest lazydocker version from GitHub API."
        return
    fi

    printInfoMsg "Latest available lazydocker version: ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version_string="Not installed"
    if command -v lazydocker &>/dev/null; then
        installed_version_string=$(lazydocker --version | grep -o 'Version: [^,]*' | sed 's/Version: //')
    fi
    printInfoMsg "Currently installed version:         ${C_L_YELLOW}${installed_version_string}${T_RESET}"

    if ! prompt_yes_no "Do you want to install/update to version ${latest_version}?" "y"; then
        printInfoMsg "Lazydocker installation skipped."
        return
    fi

    local version_number_only="${latest_version#v}"
    local tarball_name="lazydocker_${version_number_only}_Linux_${arch}.tar.gz"
    local download_url="https://github.com/jesseduffield/lazydocker/releases/download/${latest_version}/${tarball_name}"
    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    local temp_dir; temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN

    if run_with_spinner "Downloading lazydocker ${latest_version}..." curl -L -f "$download_url" -o "${temp_dir}/${tarball_name}"; then
        run_with_spinner "Extracting binary..." tar -xzf "${temp_dir}/${tarball_name}" -C "$temp_dir"
        run_with_spinner "Installing to ${install_dir}/lazydocker..." mv "${temp_dir}/lazydocker" "${install_dir}/lazydocker"
    else
        printErrMsg "Failed to download lazydocker. Please try installing it manually."
    fi
}

# Installs or updates Go (Golang) to the latest stable version.
install_golang() {
    printBanner "Install/Update Go (Golang)"

    # Determine architecture for download URL
    local arch
    if [[ "$(uname -m)" == "x86_64" ]]; then
        arch="amd64"
    else
        printErrMsg "Unsupported architecture for Go: $(uname -m). Only x86_64 is supported."
        return 1
    fi

    # Get latest version from the official Go JSON endpoint
    local latest_version
    printInfoMsg "Fetching latest Go version..."
    latest_version=$(curl -s "https://go.dev/dl/?mode=json" | jq -r '.[0].version')

    if [[ -z "$latest_version" ]]; then
        printErrMsg "Could not determine the latest Go version from go.dev."
        return
    fi
    printInfoMsg "Latest available Go version: ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version="Not installed"
    if command -v go &>/dev/null; then
        # 'go version' output is like: go version go1.22.1 linux/amd64
        installed_version=$(go version | awk '{print $3}')
    fi
    printInfoMsg "Currently installed version:   ${C_L_YELLOW}${installed_version}${T_RESET}"

    if [[ "$installed_version" == "$latest_version" ]]; then
        printOkMsg "You already have the latest version of Go. Skipping."
        return
    fi

    if ! prompt_yes_no "Do you want to install/update to version ${latest_version}?" "y"; then
        printInfoMsg "Go installation skipped."
        return
    fi

    local tarball_name="${latest_version}.linux-${arch}.tar.gz"
    local download_url="https://go.dev/dl/${tarball_name}"
    local install_path="/usr/local"

    local temp_dir; temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' RETURN

    if run_with_spinner "Downloading Go ${latest_version}..." curl -L -f "$download_url" -o "${temp_dir}/${tarball_name}"; then
        printInfoMsg "Removing any previous Go installation from ${install_path}..."
        if [[ -d "${install_path}/go" ]]; then
            sudo rm -rf "${install_path}/go"
        fi

        printInfoMsg "Extracting to ${install_path}..."
        if sudo tar -C "$install_path" -xzf "${temp_dir}/${tarball_name}"; then
            printOkMsg "Successfully installed Go ${latest_version}."
            _setup_go_path
        fi
    else
        printErrMsg "Failed to download Go. Please try installing it manually."
    fi
}

# (Private) Checks and offers to add the Go binary path to ~/.bashrc.
# This is called by install_golang after a successful installation.
_setup_go_path() {
    local go_bin_path="/usr/local/go/bin"
    local bashrc_path="${HOME}/.bashrc"
    local path_export_line="export PATH=\$PATH:${go_bin_path}"
    local path_comment="# Add Go binary to PATH (added by setup-dev-machine.sh)"

    if [[ ! -f "$bashrc_path" ]]; then
        printWarnMsg "Could not find '${bashrc_path}'. Cannot configure PATH automatically."
        printInfoMsg "Please add '${go_bin_path}' to your shell's PATH manually."
        return
    fi

    # Check if the Go binary path is already in .bashrc to avoid duplicates.
    if grep -q "${go_bin_path}" "$bashrc_path"; then
        printInfoMsg "Go binary path seems to be already configured in '${bashrc_path}'. Skipping."
        return
    fi

    printMsg "" # Add a newline for spacing
    if ! prompt_yes_no "Add Go binary path to your '${bashrc_path}'?" "y"; then
        printInfoMsg "Skipping PATH modification. Please add it manually:"
        printMsg "  ${C_L_CYAN}${path_export_line}${T_RESET}"
        return
    fi

    if prompt_yes_no "Create a backup of '${bashrc_path}' before modifying?" "y"; then
        local backup_file="${bashrc_path}.bak_$(date +"%Y%m%d_%H%M%S")"
        cp "$bashrc_path" "$backup_file"
        printOkMsg "Backup created at: ${backup_file}"
    fi

    # Append the comment and the export line to .bashrc
    echo -e "\n${path_comment}\n${path_export_line}" >> "$bashrc_path"
    printOkMsg "Successfully updated '${bashrc_path}'."
    printInfoMsg "Please run '${C_L_CYAN}source ~/.bashrc${T_RESET}' or open a new terminal to apply the changes."
}

# Installs the core tools referenced in the .bash_aliases file.
install_core_tools() {
    printBanner "Installing Core CLI Tools"

    # Update package manager repositories first
    printInfoMsg "Updating package lists..."
    sudo apt-get update

    # used to install multiple packages
    install_package "curl" "curl"
    install_package "git" "git"

    # For 'ag' alias
    install_package "silversearcher-ag" "ag"
    # For 'ports' alias (netstat)
    install_package "net-tools" "netstat"
    # For 'ls', 'll', 'lt', etc. aliases
    install_package "eza"
    
    # Replacement for nano
    install_package "micro"
    # For parsing JSON in scripts
    install_package "jq"

    # For 'lg' alias
    install_lazygit
    # For docker management
    install_lazydocker
    # For Go development
    install_golang
}

# Copies the .bash_aliases file to the user's home directory.
setup_bash_aliases() {
    printBanner "Setting up .bash_aliases"
    local source_aliases_path="${SCRIPT_DIR}/.bash_aliases"
    local dest_aliases_path="${HOME}/.bash_aliases"

    if [[ ! -f "$source_aliases_path" ]]; then
        printErrMsg "Could not find '.bash_aliases' in the script directory: ${SCRIPT_DIR}"
        return 1
    fi

    if [[ -f "$dest_aliases_path" ]]; then
        if prompt_yes_no "File '~/.bash_aliases' already exists. Back it up and overwrite it?" "n"; then
            local backup_file="${dest_aliases_path}.bak_$(date +"%Y%m%d_%H%M%S")"
            printInfoMsg "Backing up current file to ${backup_file}..."
            cp "$dest_aliases_path" "$backup_file"
            cp "$source_aliases_path" "$dest_aliases_path"
            printOkMsg "Backup created and '~/.bash_aliases' has been overwritten."
        else
            printInfoMsg "Skipping '.bash_aliases' setup."
        fi
    else
        cp "$source_aliases_path" "$dest_aliases_path"
        printOkMsg "Copied '.bash_aliases' to your home directory."
    fi
}

main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage
        exit 0
    fi

    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

    printBanner "Developer Machine Setup"
    printWarnMsg "This script will install packages using sudo and modify shell configuration."
    if ! prompt_yes_no "Do you want to continue?" "y"; then
        printInfoMsg "Setup cancelled."
        exit 0
    fi

    install_core_tools
    setup_bash_aliases

    # Execute the LazyVim installer script
    bash "${SCRIPT_DIR}/install-lazyvim.sh"

    printBanner "Dev Machine Setup Complete!"
    printOkMsg "All tasks have finished."
    printMsg "\n${T_ULINE}Final Steps:${T_RESET}"
    printMsg "\nTo apply all changes (new aliases, fzf, PATH) to your current session, please run:"
    printMsg "  ${C_L_CYAN}source ~/.bashrc${T_RESET}"
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

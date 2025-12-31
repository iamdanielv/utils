#!/bin/bash
# A script to automate the setup of a new dev machine.

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Colors & Styles
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_L_RED=$'\033[31;1m'
C_L_GREEN=$'\033[32m'
C_L_YELLOW=$'\033[33m'
C_L_BLUE=$'\033[34m'
C_L_CYAN=$'\033[36m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'
T_CURSOR_HIDE=$'\033[?25l'
T_CURSOR_SHOW=$'\033[?25h'
T_CLEAR_LINE=$'\033[K'

# Icons
T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"

# Key Codes
KEY_ENTER="ENTER"
KEY_ESC=$'\033'

# Logging
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
printInfoMsg() { printMsg "${T_INFO_ICON} ${1}${T_RESET}"; }
printWarnMsg() { printMsg "${T_WARN_ICON} ${1}${T_RESET}"; }

# Banner Utils
strip_ansi_codes() {
    local s="$1"; local esc=$'\033'
    if [[ "$s" != *"$esc"* ]]; then echo -n "$s"; return; fi
    local pattern="$esc\\[[0-9;]*[a-zA-Z]"
    while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
    echo -n "$s"
}

_truncate_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"; local trunc_char_len=${#trunc_char}
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then echo -n "$input_str"; return; fi
    local truncate_to_len=$(( max_len - trunc_char_len )); local new_str=""; local visible_count=0; local i=0; local in_escape=false
    while (( i < ${#input_str} && visible_count < truncate_to_len )); do
        local char="${input_str:i:1}"; new_str+="$char"
        if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then (( visible_count++ )); fi
        if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi; ((i++))
    done
    echo -n "${new_str}${trunc_char}"
}

generate_banner_string() {
    local text="$1"; local total_width=70; local prefix="┏"; local line
    printf -v line '%*s' "$((total_width - 1))"; line="${line// /━}"; printf '%s' "${C_L_BLUE}${prefix}${line}${T_RESET}"; printf '\r'
    local text_to_print; text_to_print=$(_truncate_string "$text" $((total_width - 3)))
    printf '%s' "${C_L_BLUE}${prefix} ${text_to_print} ${T_RESET}"
}

printBanner() { printMsg "$(generate_banner_string "$1")"; }

# Terminal Control
clear_current_line() { printf '\033[2K\r' >/dev/tty; }
clear_lines_up() {
    local lines=${1:-1}; for ((i = 0; i < lines; i++)); do printf '\033[1A\033[2K'; done; printf '\r'
} >/dev/tty

# User Input
read_single_char() {
    local char; local seq; IFS= read -rsn1 char < /dev/tty
    if [[ -z "$char" ]]; then echo "$KEY_ENTER"; return; fi
    if [[ "$char" == "$KEY_ESC" ]]; then
        if IFS= read -rsn1 -t 0.001 seq < /dev/tty; then
            char+="$seq"
            if [[ "$seq" == "[" || "$seq" == "O" ]]; then
                while IFS= read -rsn1 -t 0.001 seq < /dev/tty; do char+="$seq"; if [[ "$seq" =~ [a-zA-Z~] ]]; then break; fi; done
            fi
        fi
    fi
    echo "$char"
}

show_timed_message() {
    local message="$1"; local duration="${2:-1.8}"; local message_lines; message_lines=$(echo -e "$message" | wc -l)
    printMsg "$message" >/dev/tty; sleep "$duration"; clear_lines_up "$message_lines" >/dev/tty
}

prompt_yes_no() {
    local question="$1"; local default_answer="${2:-}"; local has_error=false; local answer; local prompt_suffix
    if [[ "$default_answer" == "y" ]]; then prompt_suffix="(Y/n)"; elif [[ "$default_answer" == "n" ]]; then prompt_suffix="(y/N)"; else prompt_suffix="(y/n)"; fi
    local question_lines; question_lines=$(echo -e "$question" | wc -l)
    _clear_all_prompt_content() { clear_current_line >/dev/tty; if (( question_lines > 1 )); then clear_lines_up $(( question_lines - 1 )); fi; if $has_error; then clear_lines_up 1; fi; }
    printf '%b' "${T_QST_ICON} ${question} ${prompt_suffix} " >/dev/tty
    while true; do
        answer=$(read_single_char); if [[ "$answer" == "$KEY_ENTER" ]]; then answer="$default_answer"; fi
        case "$answer" in
            [Yy]|[Nn]) _clear_all_prompt_content; if [[ "$answer" =~ [Yy] ]]; then return 0; else return 1; fi ;;
            "$KEY_ESC"|"q") _clear_all_prompt_content; show_timed_message " ${C_L_YELLOW}-- cancelled --${T_RESET}" 1; return 2 ;;
            *) _clear_all_prompt_content; printErrMsg "Invalid input. Please enter 'y' or 'n'." >/dev/tty; has_error=true; printf '%b' "${T_QST_ICON} ${question} ${prompt_suffix} " >/dev/tty ;;
        esac
    done
}

# Spinners
SPINNER_OUTPUT=""
_run_with_spinner_non_interactive() {
    local desc="$1"; shift; local cmd=("$@"); printMsgNoNewline "${desc} " >&2
    if SPINNER_OUTPUT=$("${cmd[@]}" 2>&1); then printf '%s\n' "${C_L_GREEN}Done.${T_RESET}" >&2; return 0
    else local exit_code=$?; printf '%s\n' "${C_RED}Failed.${T_RESET}" >&2
        while IFS= read -r line; do printf '    %s\n' "$line"; done <<< "$SPINNER_OUTPUT" >&2; return $exit_code; fi
}

_run_with_spinner_interactive() {
    local desc="$1"; shift; local cmd=("$@"); local temp_output_file; temp_output_file=$(mktemp)
    if [[ ! -f "$temp_output_file" ]]; then printErrMsg "Failed to create temp file."; return 1; fi
    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"; local i=0; "${cmd[@]}" &> "$temp_output_file" &
    local pid=$!; printMsgNoNewline "${T_CURSOR_HIDE}" >&2; trap 'printMsgNoNewline "${T_CURSOR_SHOW}" >&2; rm -f "$temp_output_file"; exit 130' INT TERM
    while ps -p $pid > /dev/null; do
        printf '\r\033[2K' >&2; local line; line=$(tail -n 1 "$temp_output_file" 2>/dev/null | tr -d '\r' || true)
        printf ' %s%s%s  %s' "${C_L_BLUE}" "${spinner_chars:$i:1}" "${T_RESET}" "${desc}" >&2
        if [[ -n "$line" ]]; then printf ' %s[%s]%s' "${C_GRAY}" "${line:0:70}" "${T_RESET}" >&2; fi
        i=$(((i + 1) % ${#spinner_chars})); sleep 0.1; done
    wait $pid; local exit_code=$?; SPINNER_OUTPUT=$(<"$temp_output_file"); rm "$temp_output_file";
    printMsgNoNewline "${T_CURSOR_SHOW}" >&2; trap - INT TERM; clear_current_line >&2
    if [[ $exit_code -eq 0 ]]; then printOkMsg "${desc}" >&2
    else printErrMsg "Task failed: ${desc}" >&2
        while IFS= read -r line; do printf '    %s\n' "$line"; done <<< "$SPINNER_OUTPUT" >&2; fi
    return $exit_code
}

run_with_spinner() {
    if [[ ! -t 1 ]]; then _run_with_spinner_non_interactive "$@"; else _run_with_spinner_interactive "$@"; fi
}

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

# Installs tools from Jesse Duffield (lazygit, lazydocker) by downloading the latest binary from GitHub releases.
# Usage: install_jesseduffield_tool "lazygit"
install_jesseduffield_tool() {
    local tool_name="$1"
    local repo="jesseduffield/${tool_name}"
    
    if [[ "$(uname -m)" == "x86_64" ]]; then
        arch="x86_64"
    else
        printErrMsg "Unsupported architecture for ${tool_name}: $(uname -m). Only x86_64 is supported by this script."
        return 1
    fi
    printBanner "Install/Update ${tool_name}"

    # Get latest version tag
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name')

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        printErrMsg "Could not determine latest ${tool_name} version from GitHub API."
        return
    fi

    printInfoMsg "Latest available ${tool_name} version: ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version_string="Not installed"
    if command -v "$tool_name" &>/dev/null; then
        if [[ "$tool_name" == "lazygit" ]]; then
            installed_version_string=$($tool_name --version)
        else
            installed_version_string=$($tool_name --version | grep -o 'Version: [^,]*' | sed 's/Version: //')
        fi
    fi
    printInfoMsg "Currently installed version:      ${C_L_YELLOW}${installed_version_string}${T_RESET}"

    if ! prompt_yes_no "Do you want to install/update to version ${latest_version}?" "y"; then
        printInfoMsg "${tool_name} installation skipped."
        return
    fi

    # The version tag from GitHub includes 'v' (e.g., v0.40.2), but the tarball name does not.
    local version_number_only="${latest_version#v}"
    local tarball_name="${tool_name}_${version_number_only}_Linux_${arch}.tar.gz"
    local download_url="https://github.com/${repo}/releases/download/${latest_version}/${tarball_name}"
    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    local temp_dir; temp_dir=$(mktemp -d)
    # Ensure the temp directory is cleaned up on exit
    trap 'rm -rf "$temp_dir"' RETURN

    if run_with_spinner "Downloading ${tool_name} ${latest_version}..." curl -L -f "$download_url" -o "${temp_dir}/${tarball_name}"; then
        run_with_spinner "Extracting binary..." tar -xzf "${temp_dir}/${tarball_name}" -C "$temp_dir"
        run_with_spinner "Installing to ${install_dir}/${tool_name}..." mv "${temp_dir}/${tool_name}" "${install_dir}/${tool_name}"
        printOkMsg "Successfully installed ${tool_name} ${latest_version}."
    else
        printErrMsg "Failed to download ${tool_name}. Please try installing it manually."
    fi
}

# (Private) Checks and offers to add ~/.local/bin to ~/.bashrc.
_setup_local_bin_path() {
    local local_bin_path="${HOME}/.local/bin"
    local bashrc_path="${HOME}/.bashrc"
    local path_export_line="export PATH=\"\$HOME/.local/bin:\$PATH\""
    local path_comment="# Add local bin to PATH (added by setup-dev-machine.sh)"

    if [[ ! -f "$bashrc_path" ]]; then
        return
    fi

    # Check if the directory is already mentioned in .bashrc
    if grep -q ".local/bin" "$bashrc_path"; then
        return
    fi

    printMsg "" # Add a newline for spacing
    if prompt_yes_no "Add '${local_bin_path}' to your '${bashrc_path}'?" "y"; then
        if prompt_yes_no "Create a backup of '${bashrc_path}' before modifying?" "y"; then
            local backup_file="${bashrc_path}.bak_$(date +"%Y%m%d_%H%M%S")"
            cp "$bashrc_path" "$backup_file"
            printOkMsg "Backup created at: ${backup_file}"
        fi
        echo -e "\n${path_comment}\n${path_export_line}" >> "$bashrc_path"
        printOkMsg "Successfully updated '${bashrc_path}'."
        export PATH="${local_bin_path}:${PATH}"
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

# Installs bat or batcat for file previews (used by fzf).
install_bat_or_batcat() {
    # fzf-preview.sh prefers 'batcat' then 'bat'.
    if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
        printInfoMsg "bat/batcat is already installed. Skipping."
        return
    fi

    printInfoMsg "Attempting to install 'bat'..."
    # Temporarily disable exit-on-error to allow fallback
    if sudo apt-get install -y bat &>/dev/null; then
        printOkMsg "Successfully installed bat."
    else
        printWarnMsg "'bat' installation failed, trying 'batcat'. This may not provide file previews."
        install_package "batcat"
    fi
}

# Clones and installs fzf from the official GitHub repository.
install_fzf_from_source() {
    printBanner "Installing fzf (from source)"
    local fzf_dir="${HOME}/.fzf"
    
    if [[ -d "$fzf_dir" ]]; then
        printInfoMsg "fzf is already installed. Updating..."
        if ! run_with_spinner "Updating fzf repo..." git -C "$fzf_dir" pull; then
            printErrMsg "Failed to update fzf."
            return 1
        fi
    else
        printInfoMsg "Cloning fzf repository..."
        local fzf_repo="https://github.com/junegunn/fzf.git"
        if ! run_with_spinner "Cloning fzf..." git clone --depth 1 "$fzf_repo" "$fzf_dir"; then
            printErrMsg "Failed to clone fzf repository."
            return 1
        fi
    fi

    # Run the fzf install script non-interactively.
    printInfoMsg "Running fzf install script..."
    if ! run_with_spinner "Installing fzf binaries..." "${HOME}/.fzf/install" --all; then
        printErrMsg "fzf install script failed."
        return 1
    fi
}

# Sets up custom fzf configuration and preview script.
setup_fzf_config() {
    printBanner "Setting up Custom FZF Configuration"

    local bin_dir="${HOME}/.local/bin"
    mkdir -p "$bin_dir"

    # --- Download fzf-preview.sh script ---
    local preview_script_path="${bin_dir}/fzf-preview.sh"
    local preview_script_url="https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-preview.sh"

    if [[ ! -f "$preview_script_path" ]]; then
        if run_with_spinner "Downloading fzf-preview.sh..." curl -L -f -o "$preview_script_path" "$preview_script_url"; then
            chmod +x "$preview_script_path"
            printOkMsg "fzf-preview.sh downloaded successfully."
        else
            printErrMsg "Failed to download fzf-preview.sh."
        fi
    fi

    # --- Append fzf settings to .bashrc ---
    local bashrc_path="${HOME}/.bashrc"
    local fzf_marker="# FZF_CUSTOM_CONFIG_FOR_DEV_MACHINE"

    if grep -q "$fzf_marker" "$bashrc_path"; then
        printInfoMsg "Custom fzf configuration already exists in ${bashrc_path}. Skipping."
        return
    fi

    printInfoMsg "Appending custom fzf configuration to ${bashrc_path}..."
    # We use the cat << 'EOF' trick to append the block.
    # Note: We are reusing the block previously found in install-lazyvim.sh
    # but updating the marker comment.
    cat >> "$bashrc_path" << 'EOF'

# -----------------------------------------------------------------------------
# FZF Configuration (added by setup-dev-machine.sh)
# FZF_CUSTOM_CONFIG_FOR_DEV_MACHINE
# -----------------------------------------------------------------------------

# Use fd as the default command for fzf to use for finding files.
export FZF_DEFAULT_COMMAND='fd --hidden --follow --exclude ".git"'

# Options for CTRL-T (insert file path in command line)
export FZF_CTRL_T_OPTS="--style full \
    --input-label ' Input ' --header-label ' File Type ' \
    --preview 'fzf-preview.sh {}' \
    --layout reverse \
    --bind 'result:transform-list-label: \
        if [[ -z \$FZF_QUERY ]]; then \
          echo \" \$FZF_MATCH_COUNT items \" \
        else \
          echo \" \$FZF_MATCH_COUNT matches for [\$FZF_QUERY] \" \
        fi \
        ' \
    --bind 'focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" {}' \
    --bind 'focus:+transform-header:file --brief {} || echo \"No file selected\"' \
    --color 'border:#aaaaaa,label:#cccccc,preview-border:#9999cc,preview-label:#ccccff' \
    --color 'list-border:#669966,list-label:#99cc99,input-border:#996666,input-label:#ffcccc' \
    --color 'header-border:#6699cc,header-label:#99ccff'"

# Options for ALT-C (cd into a directory)
export FZF_ALT_C_OPTS="--exact --style full \
                        --bind 'focus:transform-header:file --brief {}' \
                        --preview 'tree -L 1 -C {}'"

# --- FZF Completion Overrides ---
# Use fd to power fzf's path and directory completion (**<TAB>).
_fzf_compgen_path() {
  fd --hidden --follow --exclude ".git" . "$1"
}
_fzf_compgen_dir() {
  fd --type d --hidden --follow --exclude ".git" . "$1"
}

# --- Custom FZF Functions & Bindings ---
# Custom function to find a file and open it in Neovim (Alt+F).
fzf_nvim() {
  fzf --exact --style full --preview 'fzf-preview.sh {}' --bind "enter:become(nvim {})"
}
bind -x '"\ef":fzf_nvim'
bind -x '"\C-x":clear' # Utility binding: Ctrl+X to clear the screen.
EOF
    printOkMsg "fzf configuration added to .bashrc."
}

# (Private) Checks and offers to add the Go binary path to ~/.bashrc.
# This is called by install_golang after a successful installation.
_setup_go_path() {
    local go_bin_path="/usr/local/go/bin"
    local bashrc_path="${HOME}/.bashrc"
    local path_export_line="export PATH=\$PATH:${go_bin_path}:\$HOME/go/bin"
    local path_comment="# Add Go binary paths to PATH (added by setup-dev-machine.sh)"

    if [[ ! -f "$bashrc_path" ]]; then
        printWarnMsg "Could not find '${bashrc_path}'. Cannot configure PATH automatically."
        printInfoMsg "Please add '${go_bin_path}' and '\$HOME/go/bin' to your shell's PATH manually."
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

    install_package "curl"
    install_package "git"

    # For 'ag' alias
    install_package "silversearcher-ag" "ag"
    # For fzf and general searching
    install_package "ripgrep" "rg"
    install_package "fd-find" "fd"
    # Symlink fd if needed (fdfind -> fd)
    if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
        printInfoMsg "Creating symlink for 'fd' from 'fdfind'..."
        ln -sf "$(which fdfind)" "${HOME}/.local/bin/fd"
    fi
    install_bat_or_batcat

    # For 'ports' alias (netstat)
    install_package "net-tools" "netstat"
    # For 'ls', 'll', 'lt', etc. aliases
    install_package "eza"
    
    # Replacement for nano
    install_package "micro"
    # For parsing JSON in scripts
    install_package "jq"

    # For 'lg' alias (lazygit) and docker management (lazydocker)
    install_jesseduffield_tool "lazygit"
    install_jesseduffield_tool "lazydocker"

    # Ensure ~/.local/bin is in PATH
    _setup_local_bin_path

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

    # Install and configure fzf
    install_fzf_from_source
    setup_fzf_config

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

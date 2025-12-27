#!/bin/bash
# A script to automate the installation of LazyVim prerequisites.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Colors & Styles
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'
C_L_RED=$'\033[31;1m'
C_L_GREEN=$'\033[32m'
C_L_YELLOW=$'\033[33m'
C_L_BLUE=$'\033[34m'
C_L_CYAN=$'\033[36m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'
T_REVERSE=$'\033[7m'
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

prompt_to_continue() {
    local msg="${1:-Press any key to continue...}"
    printMsgNoNewline "${T_INFO_ICON} ${msg} " >/dev/tty
    read_single_char >/dev/null
    clear_current_line >/dev/tty
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

# --- Script Functions ---

print_usage() {
    printBanner "LazyVim Prerequisite Installer"
    printMsg "This script installs Neovim (latest stable) and all required dependencies for LazyVim."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"
    printMsg "\n${T_ULINE}What it does:${T_RESET}"
    printMsg "  1. Checks for a compatible system (Debian/Ubuntu-based Linux on x86_64)."
    printMsg "  2. Installs dependencies (git, ripgrep, fd, fzf, build tools, etc.)."
    printMsg "  3. Downloads, installs, and updates the latest stable release of Neovim."
    printMsg "  4. Backs up any existing Neovim configuration."
    printMsg "  5. Clones the LazyVim starter template."
    printMsg "  6. Sets up custom fzf configuration with previews in '~/.bashrc'."
    printMsg "  7. Ensures '~/.local/bin' is in your PATH."
    printMsg "  7. Installs the FiraCode Nerd Font for proper icon display."
    printMsg "\nRun without arguments to start the installation."
}

# Helper to fetch the latest release version tag from a GitHub repository.
# Usage: get_latest_release_version "user/repo"
get_latest_release_version() {
    local repo="$1"
    curl -s -I "https://github.com/${repo}/releases/latest" \
        | grep -i "location:" \
        | sed 's|.*/v||' | tr -d '\r'
}

# Detects the operating system, architecture, and package manager.
detect_system() {
    printInfoMsg "Detecting system specifications..."
    # OS Detection
    if [[ "$(uname -s)" != "Linux" ]]; then
        printErrMsg "Unsupported operating system: $(uname -s). This script only supports Linux."
        exit 1
    fi
    local os='linux'

    # Architecture Detection
    if [[ "$(uname -m)" != "x86_64" ]]; then
        printErrMsg "Unsupported architecture: $(uname -m). This script only supports x86_64."
        exit 1
    fi
    local arch='x64'

    # Package Manager Detection
    if ! command -v apt-get &>/dev/null; then
        printErrMsg "Could not find 'apt'. This script only supports apt-based distributions (like Debian, Ubuntu)."
        exit 1
    fi
    local pkg_manager="apt"
    printOkMsg "System: ${os}-${arch} with ${pkg_manager}"
}

# Installs a package if it's not already installed.
# Usage: install_package <package_name> [command_to_check]
install_package() {
    local package_name="$1"
    local command_to_check="${2:-$1}"

    if command -v "$command_to_check" &>/dev/null; then
        printInfoMsg "${package_name} is already installed. Skipping."
        return
    fi

    printInfoMsg "Installing ${package_name}..."
    sudo apt-get install -y "$package_name"
    printOkMsg "Successfully installed ${package_name}."
}

# Installs bat or batcat for file previews.
# On newer Debian/Ubuntu, 'bat' provides 'batcat'. On older ones, it's reversed.
# We need either command to be available for fzf previews.
install_bat_or_batcat() {
    # fzf-preview.sh prefers 'batcat' then 'bat'.
    if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
        printInfoMsg "bat/batcat is already installed. Skipping."
        return
    fi

    printInfoMsg "Attempting to install 'bat'..."
    # Temporarily disable exit-on-error to allow fallback
    (set +e; sudo apt-get install -y bat &>/dev/null)
    if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
        printOkMsg "Successfully installed bat/batcat."
    else
        printWarnMsg "'bat' installation failed, trying 'batcat'. This may not provide file previews."
        install_package "batcat"
    fi
}

# Installs core dependencies required for building and running plugins.
install_dependencies() {
    printBanner "Installing Core Dependencies"
    
    # Update package manager repositories first
    printInfoMsg "Updating package lists..."
    sudo apt-get update
    install_package "curl"

    # Install build tools, git, and other essentials
    install_package "build-essential" "gcc"

    install_package "cmake"
    install_package "git"
    install_package "ripgrep" "rg"
    install_package "fd-find" "fd"

    
    # On Debian/Ubuntu, the 'fd-find' package installs the binary as 'fdfind'.
    # Many scripts and tools (including fzf config) expect 'fd'.
    # We create a symlink in a user-local directory to bridge this gap.
    if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
        printInfoMsg "Creating symlink for 'fd' from 'fdfind'..."
        ln -sf "$(which fdfind)" "${HOME}/.local/bin/fd"
    fi
    
    # For fzf preview script
    install_bat_or_batcat
    install_package "tree"
    install_package "fontconfig" "fc-cache"
    install_package "unzip"
}

# Clones and installs fzf from the official GitHub repository.
install_fzf_from_source() {
    printBanner "Installing fzf (from source)"
    local fzf_dir="${HOME}/.fzf"
    
    if [[ -d "$fzf_dir" ]]; then
        printInfoMsg "fzf is already installed. Updating..."
        if ! git -C "$fzf_dir" pull; then
            printErrMsg "Failed to update fzf."
            return 1
        fi
    else
        printInfoMsg "Cloning fzf repository..."
        local fzf_repo="https://github.com/junegunn/fzf.git"
        if ! git clone --depth 1 "$fzf_repo" "$fzf_dir"; then
            printErrMsg "Failed to clone fzf repository."
            return 1
        fi
    fi

    # Run the fzf install script non-interactively.
    # --all enables key-bindings and completion.
    # The script will automatically update .bashrc or .zshrc.
    printInfoMsg "Running fzf install script..."
    if ! "${HOME}/.fzf/install" --all; then
        printErrMsg "fzf install script failed."
        return 1
    fi
}

# Downloads and installs the latest stable version of Neovim.
install_neovim() {
    printBanner "Installing/Updating Neovim (Latest Stable)"

    local install_dir="${HOME}/.local"
    local bin_dir="${install_dir}/bin"
    local version_file="${install_dir}/nvim-version"
    mkdir -p "$bin_dir"

    printInfoMsg "Checking for latest Neovim version..."
    local latest_version
    latest_version=$(get_latest_release_version "neovim/neovim")

    if [[ -z "$latest_version" ]]; then
        printErrMsg "Could not determine latest Neovim version from GitHub."
        return 1
    fi
    printInfoMsg "Latest stable version is: v${latest_version}"

    local installed_version="0"
    if [[ -f "$version_file" ]]; then
        installed_version=$(<"$version_file")
    fi

    # Also check for a system-installed nvim to report its version
    if command -v nvim &>/dev/null; then
        local system_version; system_version=$(nvim --version | head -n 1 | awk '{print $2}')
        printInfoMsg "Found installed Neovim version: ${system_version} (managed by this script: v${installed_version})"
    fi


    if [[ "$installed_version" == "$latest_version" ]]; then
        printOkMsg "You already have the latest version of Neovim (v${installed_version}). Skipping."
        return
    fi

    printInfoMsg "New version available. Installing v${latest_version}..."

    # Use AppImage for Linux
    local nvim_appimage_path="${bin_dir}/nvim-linux-x86_64.appimage"
    local nvim_url="https://github.com/neovim/neovim/releases/download/v${latest_version}/nvim-linux-x86_64.appimage"
    
    printInfoMsg "Downloading Neovim AppImage v${latest_version} from:"
    printMsg "  ${C_L_BLUE}${nvim_url}${T_RESET}"
    # Use -L to follow redirects, -f to fail silently on server errors, and show progress.
    if curl -L -f --progress-bar "$nvim_url" -o "$nvim_appimage_path"; then
        chmod +x "$nvim_appimage_path"
        ln -sf "$nvim_appimage_path" "${bin_dir}/nvim"
        echo "$latest_version" > "$version_file"
        printOkMsg "Neovim v${latest_version} installed to ${bin_dir}/nvim"
    else
        printErrMsg "Failed to download Neovim AppImage. Please check your connection or the URL."
        return 1
    fi
}

# Checks if ~/.local/bin is in the user's PATH and provides instructions if not.
check_local_bin_in_path() {
    printBanner "Checking PATH Environment Variable"
    local local_bin_dir="${HOME}/.local/bin"

    # Check if the directory is in the PATH. The colons are important for matching.
    if [[ ":$PATH:" == *":${local_bin_dir}:"* ]]; then
        printOkMsg "'${local_bin_dir}' is already in your PATH."
    else
        printWarnMsg "'${local_bin_dir}' is not in your current PATH."
        printInfoMsg "Temporarily adding it to the PATH for this session."
        export PATH="${local_bin_dir}:${PATH}"
        printOkMsg "PATH updated for current session."
        printInfoMsg "For this change to be permanent, add the following line to your ~/.bashrc or ~/.zshrc:"
        printMsg "  ${C_L_CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${T_RESET}"
        prompt_to_continue "Press any key to continue with the installation..."
    fi
}

# Downloads and installs Nerd Fonts
install_nerd_fonts() {
    printBanner "Installing Nerd Fonts"

    # An associative array mapping the font's display name to its details.
    # Format: "Display Name"="GrepPattern|ZipFileName"
    declare -A font_map=(
        ["FiraCode Nerd Font"]="FiraCode|FiraCode"
        ["Meslo Nerd Font"]="Meslo|Meslo"
        ["CaskaydiaCove Nerd Font"]="CaskaydiaCove|CascadiaCode"
    )

    local fonts_installed=0
    for font_name in "${!font_map[@]}"; do
        # Parse details: "GrepPattern|ZipFileName"
        IFS='|' read -r font_grep_pattern font_zip_name <<< "${font_map[$font_name]}"
        local font_dir_name="${font_zip_name}NerdFont"
        local font_dir="${HOME}/.local/share/fonts/${font_dir_name}"

        # Use fc-list to check if the font is already installed and available system-wide.
        if fc-list | grep -q "$font_grep_pattern Nerd Font"; then
            printInfoMsg "'${font_name}' is already installed. Skipping."
            continue
        fi

        if ! prompt_yes_no "Install '${font_name}'? (Recommended for icons)" "n"; then
            printInfoMsg "Skipping '${font_name}' installation."
            continue
        fi

        printInfoMsg "Finding latest Nerd Fonts release..."
        local latest_nerd_font_version
        latest_nerd_font_version=$(get_latest_release_version "ryanoasis/nerd-fonts")

        if [[ -z "$latest_nerd_font_version" ]]; then
            printErrMsg "Could not determine latest Nerd Fonts version from GitHub. Skipping font installs."
            return # Exit the function if we can't get the version
        fi

        local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v${latest_nerd_font_version}/${font_zip_name}.zip"
        local temp_dir; temp_dir=$(mktemp -d)
        trap 'rm -rf "$temp_dir"' RETURN

        printInfoMsg "Downloading ${font_name}..."
        printInfoMsg "URL: ${font_url}"
        if curl -L -f "$font_url" -o "${temp_dir}/${font_zip_name}.zip"; then
            printOkMsg "Download complete."
            mkdir -p "$font_dir"
            unzip -o "${temp_dir}/${font_zip_name}.zip" -d "$font_dir"
            fonts_installed=1 # Mark that we need to update the cache
            printOkMsg "'${font_name}' files extracted."
        else
            printErrMsg "Failed to download '${font_name}'."
        fi
        echo # Add a newline for spacing before the next prompt
    done

    if [[ $fonts_installed -eq 1 ]]; then
        printInfoMsg "Updating font cache... (this may take a moment)"
        fc-cache -f -v
        printOkMsg "Font cache updated."
        printInfoMsg "Please set one of the installed Nerd Fonts in your terminal to see icons correctly."
    fi
}

# Backs up existing Neovim config and clones the LazyVim starter.
setup_lazyvim() {
    printBanner "Setting up LazyVim"
    
    local nvim_config_dir="${HOME}/.config/nvim"
    local lazyvim_json_path="${nvim_config_dir}/lazyvim.json"
    
    # Check if LazyVim is already installed by looking for lazyvim.json
    if [[ -f "$lazyvim_json_path" ]]; then
        printInfoMsg "LazyVim is already installed (found lazyvim.json). Skipping setup."
        return
    fi

    # If not, check if a generic nvim config directory exists
    if [[ -d "$nvim_config_dir" ]]; then
        printWarnMsg "Found an existing Neovim configuration that is not LazyVim."
        if prompt_yes_no "Do you want to back it up and replace it with the LazyVim starter?" "y"; then
            local backup_dir="${nvim_config_dir}.bak_$(date +"%Y%m%d_%H%M%S")"
            printInfoMsg "Backing up current config to ${backup_dir}..."
            mv "$nvim_config_dir" "$backup_dir"
            printOkMsg "Backup complete."
        else
            printInfoMsg "Skipping LazyVim setup as requested."
            return
        fi
    fi

    # Clone LazyVim starter
    printInfoMsg "Cloning the LazyVim starter repository..."
    if git clone https://github.com/LazyVim/starter "$nvim_config_dir"; then
        printOkMsg "LazyVim starter cloned to ${nvim_config_dir}."
        printInfoMsg "You can now start Neovim by running: ${C_L_CYAN}nvim${T_RESET}"
    else
        printErrMsg "Failed to clone LazyVim starter repository."
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

    printInfoMsg "Downloading latest fzf preview script..."
    # Use curl with -f to fail silently on server errors, which run_with_spinner will catch.
    # --create-dirs is redundant here since we already did mkdir -p, but it's good practice.
    if curl -L -f --create-dirs -o "$preview_script_path" "$preview_script_url"; then
        chmod +x "$preview_script_path"
        printOkMsg "fzf-preview.sh downloaded successfully."
    else
        printErrMsg "Failed to download fzf-preview.sh. A custom fzf preview will not be available."
        # We don't exit here, as the rest of the installation can still succeed.
    fi

    # --- Append fzf settings to .bashrc ---
    local bashrc_path="${HOME}/.bashrc"
    local fzf_marker="# FZF_CUSTOM_CONFIG_FOR_LAZYVIM_INSTALLER"

    if grep -q "$fzf_marker" "$bashrc_path"; then
        printInfoMsg "Custom fzf configuration already exists in ${bashrc_path}. Skipping."
        return
    fi

    printInfoMsg "Appending custom fzf configuration to ${bashrc_path}..."

    # Use a heredoc to define the configuration block.
    # The 'cat << EOF' syntax with unquoted EOF prevents variable expansion inside the heredoc.
    cat >> "$bashrc_path" << 'EOF'

# -----------------------------------------------------------------------------
# FZF Configuration (added by LazyVim installer)
# FZF_CUSTOM_CONFIG_FOR_LAZYVIM_INSTALLER
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

    printOkMsg "fzf configuration added. Please run 'source ~/.bashrc' or open a new terminal."
}

main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage
        exit 0
    fi

    printBanner "LazyVim Prerequisite Installer"
    printWarnMsg "This script will install packages using sudo."
    if ! prompt_yes_no "Do you want to continue?" "y"; then
        printInfoMsg "Installation cancelled."
        exit 0
    fi

    detect_system
    install_dependencies
    install_fzf_from_source
    install_neovim
    check_local_bin_in_path
    install_nerd_fonts
    setup_fzf_config
    setup_lazyvim

    echo
    printBanner "Installation Complete!"
    printOkMsg "All steps finished."
    printMsg "\n${T_ULINE}Next Steps:${T_RESET}"
    printMsg "  1. ${C_L_YELLOW}Restart your terminal${T_RESET} or run ${C_L_CYAN}source ~/.bashrc${T_RESET} to apply PATH and fzf changes."
    printMsg "  2. ${C_L_YELLOW}Change your terminal font${T_RESET} to one of the installed Nerd Fonts to see all icons correctly."
    printMsg "  3. Start Neovim by running: ${C_L_CYAN}nvim${T_RESET}"
    printMsg "     LazyVim will finish its setup on the first run. This may take a few minutes."
    echo
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi 
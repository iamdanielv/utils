#!/bin/bash
# A script to automate the setup of a new dev machine.

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

if (( BASH_VERSINFO[0] < 4 )); then
    printf 'setup-dev-machine.sh requires Bash 4 or newer. Found Bash %s.\n' "${BASH_VERSION}" >&2
    exit 1
fi

# --- XDG Base Directory Standards ---
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_BIN_HOME="${HOME}/.local/bin"

# Colors & Styles
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_L_RED=$'\033[31;1m'
C_L_GREEN=$'\033[32m'
C_L_YELLOW=$'\033[33m'
C_L_BLUE=$'\033[34m'
C_L_MAGENTA=$'\033[35;1m'
C_L_CYAN=$'\033[36m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'
T_CURSOR_HIDE=$'\033[?25l'
T_CURSOR_SHOW=$'\033[?25h'

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
    local text="$1"
    local color="${2:-$C_L_BLUE}"
    local line_char="${3:-━}"
    local prefix="${4:-┏}"
    local total_width=70; local line
    printf -v line '%*s' "$((total_width - 1))" ""; line="${line// /${line_char}}"; printf '%s' "${color}${prefix}${line}${T_RESET}"; printf '\r'
    local text_to_print; text_to_print=$(_truncate_string "$text" $((total_width - 3)))
    printf '%s' "${color}${prefix} ${text_to_print} ${T_RESET}"
}

printBanner() {
    if [[ "$VERIFY_MODE" == "true" ]]; then return; fi
    printMsg "$(generate_banner_string "$1" "${C_L_BLUE}" "─" "─")"
}

printPhaseBanner() {
    if [[ "$VERIFY_MODE" == "true" ]]; then return; fi
    printMsg "$(generate_banner_string "$1" "${C_L_MAGENTA}" "━" "┏")"
}

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
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        if [[ "$default_answer" == "n" ]]; then
            printInfoMsg "[Non-Interactive] ${question} -> Auto-answering NO"
            return 1
        else
            printInfoMsg "[Non-Interactive] ${question} -> Auto-answering YES"
            return 0
        fi
    fi
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
VERIFY_MODE=false
NON_INTERACTIVE=false
SUMMARY_ENABLED=true
SETUP_FAILED=false
VERIFY_FAILED=false
declare -A SUMMARY_RESULTS
SUMMARY_ORDER=()
declare -A VERIFY_RESULTS
VERIFY_ORDER=()

# --- Summary Reporting ---
record_summary() {
    if [[ "$SUMMARY_ENABLED" == "true" ]]; then
        local task="$1"
        local status="$2"
        local detail="$3"
        if [[ "$status" == "Failed" && "$VERIFY_MODE" != "true" ]]; then
            SETUP_FAILED=true
        fi
        if [[ -z "${SUMMARY_RESULTS[$task]+x}" ]]; then
            SUMMARY_ORDER+=("$task")
        fi
        SUMMARY_RESULTS["$task"]="$status|$detail"
    fi
}

printSummaryBanner() {
    local line_char="━"
    local total_width=61
    local line
    printf -v line '%*s' "$((total_width - 1))" ""; line="${line// /${line_char}}"; printf '%s%s%s\n' "${C_L_BLUE}" "${line}" "${T_RESET}"
}

print_report_header() {
    local title="$1"
    printMsg ""
    printSummaryBanner
    printMsg " ${title}"
    printSummaryBanner
}

print_report_footer() {
    printSummaryBanner
}

get_report_status_style() {
    local status="$1"
    REPORT_ICON=""
    REPORT_COLOR=""

    case "$status" in
        "Installed"|"Configured"|"Synced"|"Running")
            REPORT_ICON="${T_BOLD}${C_GREEN}✓${T_RESET}"
            REPORT_COLOR="${C_GREEN}"
            ;;
        "Updated"|"Current")
            REPORT_ICON="${T_BOLD}${C_L_BLUE}↑${T_RESET}"
            REPORT_COLOR="${C_L_BLUE}"
            ;;
        "Already Present")
            REPORT_ICON="${T_BOLD}${C_GRAY}~${T_RESET}"
            REPORT_COLOR="${C_GRAY}"
            ;;
        "Skipped"|"Optional"|"Unknown")
            REPORT_ICON="${T_BOLD}${C_L_CYAN}?${T_RESET}"
            REPORT_COLOR="${C_L_CYAN}"
            ;;
        "Outdated"|"Differs"|"Not Configured"|"Unavailable")
            REPORT_ICON="${T_BOLD}${C_YELLOW}!${T_RESET}"
            REPORT_COLOR="${C_YELLOW}"
            ;;
        "Failed"|"Missing")
            REPORT_ICON="${T_BOLD}${C_L_RED}✗${T_RESET}"
            REPORT_COLOR="${C_L_RED}"
            ;;
        *)
            REPORT_ICON="${T_BOLD}${C_GRAY}?${T_RESET}"
            REPORT_COLOR="${C_GRAY}"
            ;;
    esac
}

print_report_row() {
    local task="$1"
    local status="$2"
    local detail="$3"
    get_report_status_style "$status"
    printf " [%s] %-25s %s%-16s%s %s\n" "$REPORT_ICON" "$task" "$REPORT_COLOR" "$status" "$T_RESET" "$detail"
}

print_summary_report() {
    if [[ "$SUMMARY_ENABLED" != "true" ]]; then return; fi

    print_report_header "INSTALLATION SUMMARY REPORT"

    local task
    for task in "${SUMMARY_ORDER[@]}"; do
        local data="${SUMMARY_RESULTS[$task]}"
        local status="${data%|*}"
        local detail="${data#*|}"
        print_report_row "$task" "$status" "$detail"
    done

    print_report_footer
}

print_verification_report() {
    print_report_header "Dev Machine Verification"

    local item
    for item in "${VERIFY_ORDER[@]}"; do
        local data="${VERIFY_RESULTS[$item]}"
        local status="${data%%|*}"
        local detail="${data#*|}"
        print_report_row "$item" "$status" "$detail"
    done

    print_report_footer
}

# --- Verification Helper ---
report_verify() {
    local item="$1"
    local status="$2"
    local details="$3"
    if [[ "$status" == "Missing" || "$status" == "Differs" || "$status" == "Not Configured" || "$status" == "Unavailable" || "$status" == "Unknown" || "$status" == "Outdated" ]]; then
        VERIFY_FAILED=true
    fi
    if [[ -z "${VERIFY_RESULTS[$item]+x}" ]]; then
        VERIFY_ORDER+=("$item")
    fi
    VERIFY_RESULTS["$item"]="$status|$details"
}

# --- Script Functions ---

print_usage() {
    printPhaseBanner "Developer Machine Setup Script"
    printMsg "This script automates the setup of a new developer environment by installing"
    printMsg "essential tools and setting up a complete LazyVim configuration."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [options]"
    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}      Show this help message"
    printMsg "  ${C_L_BLUE}-y, --yes, --non-interactive${T_RESET}"
    printMsg "                      Skip all confirmation prompts and use default answers"
    printMsg "  ${C_L_BLUE}--verify${T_RESET}        Check system state without making changes"
    printMsg "  ${C_L_BLUE}--no-vim${T_RESET}        Skip Neovim installation and configuration"
    printMsg "  ${C_L_BLUE}--only-vim${T_RESET}      Run ONLY Neovim installation and configuration"
    printMsg "\n${T_ULINE}What it does:${T_RESET}"
    printMsg "  1. Checks for a compatible system (Debian/Ubuntu-based Linux)."
    printMsg "  2. Installs essential CLI tools (curl, git, tmux, etc.)."
    printMsg "  3. Installs modern utilities (ripgrep, fd, bat, eza) from GitHub."
    printMsg "  4. Sets up shell environment (zoxide, starship, .bash_aliases)."
    printMsg "  5. Installs dev tools (Go, lazygit, lazydocker, delta)."
    printMsg "  6. Installs Neovim and configures LazyVim."
    printMsg "\nRun without arguments to start the setup."
}

# Installs a package if it's not already installed.
# Usage: install_package <package_name> [command_to_check]
install_package() {
    local package_name="$1"
    local command_to_check="${2:-$1}"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if command -v "$command_to_check" &>/dev/null; then
            report_verify "$package_name" "Installed" ""
        else
            report_verify "$package_name" "Missing" "Action: Install via apt"
        fi
        return
    fi

    if command -v "$command_to_check" &>/dev/null; then
        printInfoMsg "'${package_name}' is already installed. Skipping."
        record_summary "$package_name" "Already Present" "${command_to_check} available"
        return 0
    fi

    printInfoMsg "Installing '${package_name}'..."
    if ! sudo apt-get install -y "$package_name"; then
        printErrMsg "Failed to install '${package_name}'. Please try installing it manually."
        record_summary "$package_name" "Failed" "apt install failed"
        return 1
    else
        printOkMsg "Successfully installed '${package_name}'."
        record_summary "$package_name" "Installed" "apt package installed"
        return 0
    fi
}

# (Private) Helper to query GitHub API and parse error responses
_gh_api_request() {
    local endpoint="$1"
    local response
    local http_code
    local temp_file
    temp_file=$(mktemp)

    local headers=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=("-H" "Authorization: token $GITHUB_TOKEN")
    fi

    # Retrieve response body and HTTP status code
    http_code=$(curl -s -w "%{http_code}" "${headers[@]}" "$endpoint" -o "$temp_file")
    response=$(<"$temp_file")
    rm -f "$temp_file"

    if (( http_code >= 400 )); then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.message' 2>/dev/null || true)
        if [[ -z "$error_msg" || "$error_msg" == "null" ]]; then
            error_msg="HTTP status $http_code"
        fi

        if [[ "$error_msg" == *"rate limit"* ]]; then
            printErrMsg "GitHub API rate limit exceeded. Please set GITHUB_TOKEN or try again later." >&2
        else
            printErrMsg "GitHub API error: ${error_msg}" >&2
        fi
        return 1
    fi

    echo "$response"
    return 0
}

# (Private) Fetches the latest version tag from GitHub API
_gh_get_latest_version() {
    local repo="$1"
    local response
    if response=$(_gh_api_request "https://api.github.com/repos/${repo}/releases/latest"); then
        echo "$response" | jq -r '.tag_name'
    else
        echo ""
    fi
}

# (Private) Gets the installed version of a binary
_gh_get_installed_version() {
    local binary_name="$1"
    if ! command -v "$binary_name" &>/dev/null; then
        echo "Not installed"
        return
    fi
    local raw_version_output
    raw_version_output=$("$binary_name" --version 2>/dev/null || "$binary_name" -v 2>/dev/null || echo "unknown")
    local installed_version_string
    installed_version_string=$(echo "$raw_version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [[ -z "$installed_version_string" ]]; then installed_version_string="$raw_version_output"; fi
    echo "$installed_version_string"
}

# (Private) Finds the download URL for the correct asset
_gh_find_download_url() {
    local repo="$1"
    local asset_regex="${2:-}"
    local response
    if response=$(_gh_api_request "https://api.github.com/repos/${repo}/releases/latest"); then
        echo "$response" | \
            jq -r --arg regex "$asset_regex" '.assets[] | select(.name | test("linux"; "i") and (test("amd64"; "i") or test("x86_64"; "i"))) | select(.name | test("\\.tar\\.gz$|\\.zip$"; "i")) | select($regex == "" or (.name | test($regex; "i"))) | .browser_download_url' | head -n 1
    else
        echo ""
    fi
}

# (Private) Downloads and installs the binary
_gh_download_and_install() {
    local download_url="$1"
    local binary_name="$2"
    local version="$3"

    local temp_dir; temp_dir=$(mktemp -d); trap 'rm -rf "$temp_dir"' RETURN
    local archive_name; archive_name=$(basename "$download_url")

    if ! run_with_spinner "Downloading ${binary_name} ${version}..." curl -L -f "$download_url" -o "${temp_dir}/${archive_name}"; then
        printErrMsg "Failed to download ${binary_name}. Please try installing it manually."
        return 1
    fi

    if [[ "$archive_name" == *.tar.gz ]]; then
        run_with_spinner "Extracting tarball..." tar -xzf "${temp_dir}/${archive_name}" -C "$temp_dir"
    elif [[ "$archive_name" == *.zip ]]; then
        run_with_spinner "Extracting zip..." unzip -o "${temp_dir}/${archive_name}" -d "$temp_dir"
    else
        printErrMsg "Unsupported archive format: ${archive_name}"; return 1
    fi

    local found_bin; found_bin=$(find "$temp_dir" -type f -name "$binary_name" | head -n 1)
    if [[ -n "$found_bin" ]]; then
        mkdir -p "${XDG_BIN_HOME}"
        run_with_spinner "Installing to ${XDG_BIN_HOME}/${binary_name}..." mv "$found_bin" "${XDG_BIN_HOME}/${binary_name}"
        chmod +x "${XDG_BIN_HOME}/${binary_name}"
        printOkMsg "Successfully installed ${binary_name} ${version}."
    else
        printErrMsg "Binary '${binary_name}' not found in extracted archive."; ls -R "$temp_dir"; return 1
    fi
}

# Generic installer for GitHub release binaries
# Usage: install_github_binary "owner/repo" "binary_name" [ "asset_regex" ]
install_github_binary() {
    local repo="$1"
    local binary_name="$2"
    # Optional regex to match specific assets (e.g., "musl", "amd64"). Case-insensitive.
    local asset_regex="${3:-}"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        local installed_version_string
        installed_version_string=$(_gh_get_installed_version "$binary_name")
        
        if [[ "$installed_version_string" == "Not installed" ]]; then
             report_verify "$binary_name" "Missing" "Repo: $repo"
        else
               report_verify "$binary_name" "Installed" "v${installed_version_string#v}"
        fi
        return
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        printErrMsg "Unsupported architecture for ${binary_name}: $(uname -m). Only x86_64 is supported."
        record_summary "$binary_name" "Failed" "unsupported architecture"
        return 1
    fi
    
    printBanner "Install/Update ${binary_name} from ${repo}"

    local latest_version
    latest_version=$(_gh_get_latest_version "$repo")
    
    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        printErrMsg "Could not determine latest ${binary_name} version from GitHub API."
        record_summary "$binary_name" "Failed" "latest version unavailable"
        return 1
    fi
    printInfoMsg "Latest version:       ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version_string
    installed_version_string=$(_gh_get_installed_version "$binary_name")
    printInfoMsg "Installed version:    ${C_L_YELLOW}${installed_version_string}${T_RESET}"

    local norm_latest="${latest_version#v}"
    local norm_installed="${installed_version_string#v}"

    if [[ "$norm_latest" == "$norm_installed" ]]; then
        printOkMsg "You already have the latest version of ${binary_name} (${latest_version}). Skipping."
        record_summary "$binary_name" "Already Present" "$latest_version"
        return 0
    fi

    if ! prompt_yes_no "Do you want to install/update to version ${latest_version}?" "y"; then
        printInfoMsg "${binary_name} installation skipped."
        record_summary "$binary_name" "Skipped" "user declined"
        return 0
    fi

    local download_url
    download_url=$(_gh_find_download_url "$repo" "$asset_regex")

    if [[ -z "$download_url" ]]; then
        printErrMsg "Could not find a compatible download asset for ${repo} on Linux x86_64."
        record_summary "$binary_name" "Failed" "compatible asset unavailable"
        return 1
    fi

    if _gh_download_and_install "$download_url" "$binary_name" "$latest_version"; then
        local result_status="Installed"
        if [[ "$installed_version_string" != "Not installed" ]]; then
            result_status="Updated"
        fi
        record_summary "$binary_name" "$result_status" "$installed_version_string -> $latest_version"
        return 0
    fi

    record_summary "$binary_name" "Failed" "binary installation failed"
    return 1
}

# Installs or updates Go (Golang) to the latest stable version.
install_golang() {
    printBanner "Install/Update Go (Golang)"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        local installed_version="Not installed"
        if command -v go &>/dev/null; then installed_version=$(go version | awk '{print $3}'); fi
        
        if [[ "$installed_version" == "Not installed" ]]; then
            report_verify "Go (Golang)" "Missing" ""
        else
            report_verify "Go (Golang)" "Installed" "$installed_version"
        fi
        return
    fi

    # Determine architecture for download URL
    local arch
    if [[ "$(uname -m)" == "x86_64" ]]; then
        arch="amd64"
    else
        printErrMsg "Unsupported architecture for Go: $(uname -m). Only x86_64 is supported."
        record_summary "Go (Golang)" "Failed" "unsupported architecture"
        return 1
    fi

    # Get latest version from the official Go JSON endpoint
    local latest_version
    printInfoMsg "Fetching latest Go version..."
    latest_version=$(curl -s "https://go.dev/dl/?mode=json" | jq -r '.[0].version')

    if [[ -z "$latest_version" ]]; then
        printErrMsg "Could not determine the latest Go version from go.dev."
        record_summary "Go (Golang)" "Failed" "latest version unavailable"
        return 1
    fi
    printInfoMsg "Latest version:       ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version="Not installed"
    if command -v go &>/dev/null; then
        # 'go version' output is like: go version go1.22.1 linux/amd64
        installed_version=$(go version | awk '{print $3}')
    fi
    printInfoMsg "Installed version:    ${C_L_YELLOW}${installed_version}${T_RESET}"

    if [[ "$installed_version" == "$latest_version" ]]; then
        printOkMsg "You already have the latest version of Go. Skipping."
        record_summary "Go (Golang)" "Already Present" "$latest_version"
        return 0
    fi

    if ! prompt_yes_no "Do you want to install/update to version ${latest_version}?" "y"; then
        printInfoMsg "Go installation skipped."
        record_summary "Go (Golang)" "Skipped" "user declined"
        return 0
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
            local result_status="Installed"
            if [[ "$installed_version" != "Not installed" ]]; then result_status="Updated"; fi
            record_summary "Go (Golang)" "$result_status" "$installed_version -> $latest_version"
            return 0
        fi
        printErrMsg "Failed to extract Go."
        record_summary "Go (Golang)" "Failed" "extraction failed"
        return 1
    else
        printErrMsg "Failed to download Go. Please try installing it manually."
        record_summary "Go (Golang)" "Failed" "download failed"
        return 1
    fi
}

# Installs zoxide (smarter cd) using the official install script
install_zoxide() {
    printBanner "Install/Update zoxide"
    local repo="ajeetdsouza/zoxide"
    local binary_name="zoxide"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        local installed_version_string; installed_version_string=$(_gh_get_installed_version "$binary_name")
        if [[ "$installed_version_string" == "Not installed" ]]; then report_verify "zoxide" "Missing" "";
        else report_verify "zoxide" "Installed" "v${installed_version_string#v}"; fi
        return
    fi

    local latest_version
    latest_version=$(_gh_get_latest_version "$repo")

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        printErrMsg "Could not determine latest zoxide version from GitHub API."
        record_summary "zoxide" "Failed" "latest version unavailable"
        return 1
    fi
    printInfoMsg "Latest version:       ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version_string
    installed_version_string=$(_gh_get_installed_version "$binary_name")
    printInfoMsg "Installed version:    ${C_L_YELLOW}${installed_version_string}${T_RESET}"

    local norm_latest="${latest_version#v}"
    local norm_installed="${installed_version_string#v}"

    if [[ "$norm_latest" == "$norm_installed" ]]; then
        printOkMsg "You already have the latest version of zoxide (${latest_version}). Skipping."
        record_summary "zoxide" "Already Present" "$latest_version"
        return 0
    fi

    if ! prompt_yes_no "Do you want to install/update zoxide to version ${latest_version}?" "y"; then
        printInfoMsg "zoxide installation skipped."
        record_summary "zoxide" "Skipped" "user declined"
        return 0
    fi

    if run_with_spinner "Installing zoxide via official script..." bash -c "curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | BIN_DIR='${XDG_BIN_HOME}' bash"; then
        printOkMsg "Successfully installed zoxide."
        local result_status="Installed"
        if [[ "$installed_version_string" != "Not installed" ]]; then result_status="Updated"; fi
        record_summary "zoxide" "$result_status" "$installed_version_string -> $latest_version"
        return 0
    else
        printErrMsg "Failed to install zoxide."
        record_summary "zoxide" "Failed" "installation failed"
        return 1
    fi
}

# Installs starship (custom prompt) using the official install script
install_starship() {
    printBanner "Install/Update Starship"
    local repo="starship/starship"
    local binary_name="starship"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        local installed_version_string; installed_version_string=$(_gh_get_installed_version "$binary_name")
        if [[ "$installed_version_string" == "Not installed" ]]; then report_verify "starship" "Missing" "";
        else report_verify "starship" "Installed" "v${installed_version_string#v}"; fi
        return
    fi

    local latest_version
    latest_version=$(_gh_get_latest_version "$repo")

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        printErrMsg "Could not determine latest starship version from GitHub API."
        record_summary "starship" "Failed" "latest version unavailable"
        return 1
    fi
    printInfoMsg "Latest version:       ${C_L_GREEN}${latest_version}${T_RESET}"

    local installed_version_string
    installed_version_string=$(_gh_get_installed_version "$binary_name")
    printInfoMsg "Installed version:    ${C_L_YELLOW}${installed_version_string}${T_RESET}"

    local norm_latest="${latest_version#v}"
    local norm_installed="${installed_version_string#v}"

    if [[ "$norm_latest" == "$norm_installed" ]]; then
        printOkMsg "You already have the latest version of starship (${latest_version}). Skipping."
        record_summary "starship" "Already Present" "$latest_version"
        return 0
    fi

    if ! prompt_yes_no "Do you want to install/update starship to version ${latest_version}?" "y"; then
        printInfoMsg "starship installation skipped."
        record_summary "starship" "Skipped" "user declined"
        return 0
    fi

    if run_with_spinner "Installing starship via official script..." sh -c "curl -sS https://starship.rs/install.sh | sh -s -- -y -b '${XDG_BIN_HOME}'"; then
        printOkMsg "Successfully installed starship."
        local result_status="Installed"
        if [[ "$installed_version_string" != "Not installed" ]]; then result_status="Updated"; fi
        record_summary "starship" "$result_status" "$installed_version_string -> $latest_version"
        return 0
    else
        printErrMsg "Failed to install starship."
        record_summary "starship" "Failed" "installation failed"
        return 1
    fi
}

# Downloads and installs the latest stable version of Neovim.
install_neovim() {
    printBanner "Installing/Updating Neovim (Latest Stable)"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        local installed_version="0"
        local version_file="${XDG_STATE_HOME}/nvim-version"
        if [[ -f "$version_file" ]]; then installed_version=$(<"$version_file"); fi
        
        if [[ "$installed_version" == "0" ]]; then
            report_verify "Neovim (AppImage)" "Missing" ""
        else
            report_verify "Neovim" "Installed" "v$installed_version"
        fi
        return
    fi

    local bin_dir="${XDG_BIN_HOME}"
    local version_file="${XDG_STATE_HOME}/nvim-version"
    mkdir -p "$bin_dir"
    mkdir -p "$(dirname "$version_file")"

    printInfoMsg "Checking for latest Neovim version..."
    local latest_version_tag
    latest_version_tag=$(_gh_get_latest_version "neovim/neovim")

    if [[ -z "$latest_version_tag" || "$latest_version_tag" == "null" ]]; then
        printErrMsg "Could not determine latest Neovim version from GitHub API."
        record_summary "Neovim" "Failed" "latest version unavailable"
        return 1
    fi
    
    local latest_version="${latest_version_tag#v}"
    printInfoMsg "Latest stable version is: ${latest_version_tag}"

    local installed_version="0"
    if [[ -f "$version_file" ]]; then
        installed_version=$(<"$version_file")
    fi

    # Also check for a system-installed nvim to report its version
    if command -v nvim &>/dev/null; then
        local system_version_output
        system_version_output=$(nvim --version 2>/dev/null | head -n 1)
        local system_version
        system_version=$(echo "$system_version_output" | awk '{print $2}')
        printInfoMsg "Found installed Neovim version: ${system_version} (managed by this script: v${installed_version})"
    fi

    if [[ "$installed_version" == "$latest_version" ]]; then
        printOkMsg "You already have the latest version of Neovim (v${installed_version}). Skipping."
        record_summary "Neovim" "Already Present" "$latest_version_tag"
        return 0
    fi

    if ! prompt_yes_no "Do you want to install/update Neovim to ${latest_version_tag}?" "y"; then
        printInfoMsg "Neovim installation skipped."
        record_summary "Neovim" "Skipped" "user declined"
        return 0
    fi

    # Use AppImage for Linux
    local nvim_appimage_path="${bin_dir}/nvim-linux-x86_64.appimage"
    local nvim_url="https://github.com/neovim/neovim/releases/download/${latest_version_tag}/nvim-linux-x86_64.appimage"
    
    if run_with_spinner "Downloading Neovim AppImage ${latest_version_tag}..." curl -L -f "$nvim_url" -o "$nvim_appimage_path"; then
        chmod +x "$nvim_appimage_path"
        ln -sf "$nvim_appimage_path" "${bin_dir}/nvim"
        echo "$latest_version" > "$version_file"
        printOkMsg "Neovim ${latest_version_tag} installed to ${bin_dir}/nvim"
        local result_status="Installed"
        if [[ "$installed_version" != "0" ]]; then result_status="Updated"; fi
        record_summary "Neovim" "$result_status" "$installed_version -> $latest_version"
        return 0
    else
        printErrMsg "Failed to download Neovim AppImage."
        record_summary "Neovim" "Failed" "download failed"
        return 1
    fi
}

# Backs up existing Neovim config and clones the LazyVim starter.
setup_lazyvim() {
    printBanner "Setting up LazyVim"
    
    local nvim_config_dir="${XDG_CONFIG_HOME}/nvim"
    local lazyvim_json_path="${nvim_config_dir}/lazyvim.json"
    
    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ -f "$lazyvim_json_path" ]]; then
            report_verify "LazyVim Config" "Installed" ""
        else
            report_verify "LazyVim Config" "Missing" "lazyvim.json not found"
        fi
        return
    fi

    # Check if LazyVim is already installed by looking for lazyvim.json
    if [[ -f "$lazyvim_json_path" ]]; then
        printInfoMsg "LazyVim is already installed (found lazyvim.json). Skipping setup."
        record_summary "LazyVim Config" "Already Present" "starter config exists"
        return 0
    fi

    # If not, check if a generic nvim config directory exists
    if [[ -d "$nvim_config_dir" ]]; then
        printWarnMsg "Found an existing Neovim configuration that is not LazyVim."
        if prompt_yes_no "Do you want to back it up and replace it with the LazyVim starter?" "y"; then
            local backup_dir="${nvim_config_dir}.bak_$(date +"%Y%m%d_%H%M%S")"
            printInfoMsg "Backing up current config to ${backup_dir}..."
            if ! mv "$nvim_config_dir" "$backup_dir"; then
                printErrMsg "Failed to back up existing Neovim configuration."
                record_summary "LazyVim Config" "Failed" "backup failed"
                return 1
            fi
            printOkMsg "Backup complete."
        else
            printInfoMsg "Skipping LazyVim setup as requested."
            record_summary "LazyVim Config" "Skipped" "user declined"
            return 0
        fi
    fi

    # Clone LazyVim starter
    printInfoMsg "Cloning the LazyVim starter repository..."
    if run_with_spinner "Cloning LazyVim..." git clone https://github.com/LazyVim/starter "$nvim_config_dir"; then
        printOkMsg "LazyVim starter cloned to ${nvim_config_dir}."
        printInfoMsg "You can now start Neovim by running: ${C_L_CYAN}nvim${T_RESET}"
        record_summary "LazyVim Config" "Installed" "starter config ready"
        return 0
    else
        printErrMsg "Failed to clone LazyVim starter repository."
        record_summary "LazyVim Config" "Failed" "clone failed"
        return 1
    fi
}

# Copies custom LazyVim plugin configs
setup_lazyvim_plugins() {
    printBanner "Setting up Custom LazyVim Plugins"
    local source_plugins_dir="${SCRIPT_DIR}/config/nvim/lua/plugins"
    local dest_plugins_dir="${XDG_CONFIG_HOME}/nvim/lua/plugins"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        # Just check if dest dir exists for now, deep check is complex
        if [[ -d "$dest_plugins_dir" ]]; then report_verify "LazyVim Plugins" "Installed" ""; else report_verify "LazyVim Plugins" "Missing" ""; fi
        return
    fi

    if [[ ! -d "$source_plugins_dir" ]] || [[ -z "$(ls -A "$source_plugins_dir")" ]]; then
        printInfoMsg "No custom LazyVim plugins found to install. Skipping."
        record_summary "LazyVim Plugins" "Skipped" "source directory empty"
        return 0
    fi

    # This function should only run if LazyVim is installed.
    if [[ ! -d "${XDG_CONFIG_HOME}/nvim/lua" ]]; then
        printWarnMsg "LazyVim installation not found at '${XDG_CONFIG_HOME}/nvim'. Skipping custom plugin setup."
        record_summary "LazyVim Plugins" "Skipped" "LazyVim config missing"
        return 0
    fi

    printInfoMsg "Copying nvim plugin configs to ${dest_plugins_dir}..."
    mkdir -p "$dest_plugins_dir"

    local file_copied=false
    for src_file in "$source_plugins_dir"/*.lua; do
        if [[ ! -f "$src_file" ]]; then continue; fi
        
        local filename; filename=$(basename "$src_file")
        local dest_file="${dest_plugins_dir}/${filename}"

        # For plugins, we just want to ensure they exist.
        # We won't prompt for overwrite, just copy if it's not there.
        if [[ ! -f "$dest_file" ]]; then
            if ! cp "$src_file" "$dest_file"; then
                printErrMsg "Failed to copy plugin config '${filename}'."
                record_summary "LazyVim Plugins" "Failed" "copy failed"
                return 1
            fi
            printOkMsg "Copied new plugin config '${filename}'."
            file_copied=true
        else
            printInfoMsg "Plugin config '${filename}' already exists. Skipping."
        fi
    done

    if $file_copied; then
        record_summary "LazyVim Plugins" "Installed" "plugin configs copied"
    else
        record_summary "LazyVim Plugins" "Already Present" "plugin configs synchronized"
    fi
    return 0
}

# Clones and installs fzf from the official GitHub repository.
install_fzf_from_source() {
    printBanner "Installing fzf (from source)"
    local fzf_dir="${XDG_DATA_HOME}/fzf"
    
    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ -d "$fzf_dir" ]]; then report_verify "fzf (source)" "Installed" ""; else report_verify "fzf (source)" "Missing" ""; fi
        return
    fi

    local result_status="Installed"
    if [[ -d "$fzf_dir" ]]; then
        result_status="Updated"
        printInfoMsg "fzf is already installed. Updating..."
        if ! run_with_spinner "Updating fzf repo..." git -C "$fzf_dir" pull; then
            printErrMsg "Failed to update fzf."
            record_summary "fzf" "Failed" "repository update failed"
            return 1
        fi
    else
        printInfoMsg "Cloning fzf repository..."
        mkdir -p "$(dirname "$fzf_dir")"
        local fzf_repo="https://github.com/junegunn/fzf.git"
        if ! run_with_spinner "Cloning fzf..." git clone --depth 1 "$fzf_repo" "$fzf_dir"; then
            printErrMsg "Failed to clone fzf repository."
            record_summary "fzf" "Failed" "repository clone failed"
            return 1
        fi
    fi

    # Run the fzf install script non-interactively.
    printInfoMsg "Running fzf install script..."
    if ! run_with_spinner "Installing fzf binaries..." "${fzf_dir}/install" --all; then
        printErrMsg "fzf install script failed."
        record_summary "fzf" "Failed" "binary installation failed"
        return 1
    fi

    record_summary "fzf" "$result_status" "source and binaries ready"
    return 0
}

# Sets up custom fzf configuration and preview script.
setup_fzf_config() {
    printBanner "Setting up Custom FZF Configuration"

    local bin_dir="${XDG_BIN_HOME}"
    mkdir -p "$bin_dir"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ -f "${bin_dir}/fzf-preview.sh" ]]; then report_verify "fzf-preview.sh" "Installed" ""; else report_verify "fzf-preview.sh" "Missing" ""; fi
        return
    fi

    # --- Download fzf-preview.sh script ---
    local preview_script_path="${bin_dir}/fzf-preview.sh"
    local preview_script_url="https://raw.githubusercontent.com/junegunn/fzf/master/bin/fzf-preview.sh"

    if [[ ! -f "$preview_script_path" ]]; then
        if run_with_spinner "Downloading fzf-preview.sh..." curl -L -f -o "$preview_script_path" "$preview_script_url"; then
            chmod +x "$preview_script_path"
            printOkMsg "fzf-preview.sh downloaded successfully."
            record_summary "fzf-preview.sh" "Installed" "preview script ready"
        else
            printErrMsg "Failed to download fzf-preview.sh."
            record_summary "fzf-preview.sh" "Failed" "download failed"
        fi
    else
        record_summary "fzf-preview.sh" "Already Present" "preview script exists"
    fi

    return 0
}

# Configures git to use delta as the default pager
configure_git_delta() {
    # Ensure local bin is in PATH so we can detect delta if it was just installed
    if [[ "$VERIFY_MODE" == "true" ]]; then
        local current_pager; current_pager=$(git config --global core.pager || true)
        if [[ "$current_pager" == "delta" ]]; then report_verify "Git Delta" "Configured" ""; else report_verify "Git Delta" "Not Configured" "core.pager != delta"; fi
        return
    fi

    export PATH="${XDG_BIN_HOME}:${PATH}"

    if ! command -v delta &>/dev/null; then
        printInfoMsg "delta not found. Skipping git configuration."
        record_summary "Git Delta" "Skipped" "delta unavailable"
        return
    fi

    printBanner "Configuring Delta (Git Pager)"
    
    # Check if core.pager is already delta
    local current_pager
    current_pager=$(git config --global core.pager || true)
    
    if [[ "$current_pager" == "delta" ]]; then
        printInfoMsg "Git is already configured to use delta. Skipping."
        record_summary "Git Delta" "Already Present" "git pager configured"
        return
    fi

    if prompt_yes_no "Configure 'delta' as the default git pager?" "y"; then
        printInfoMsg "Setting git config..."
        git config --global core.pager "delta"
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.light false
        git config --global merge.conflictstyle "diff3"
        git config --global diff.colorMoved "default"
        printOkMsg "Git configured to use delta."
        record_summary "Git Delta" "Configured" "git pager configured"
    else
        record_summary "Git Delta" "Skipped" "user declined"
    fi
}

# Configures .bashrc with a consolidated block of environment settings
configure_shell_environment() {
    printBanner "Configuring Shell Environment"
    local bashrc="${HOME}/.bashrc"
    local marker_start="# --- DEV MACHINE SETUP START ---"
    local marker_end="# --- DEV MACHINE SETUP END ---"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if grep -qF "$marker_start" "$bashrc"; then report_verify ".bashrc config" "Present" ""; else report_verify ".bashrc config" "Missing" "Setup block not found"; fi
        return
    fi

    if [[ ! -f "$bashrc" ]]; then
        printWarnMsg "Could not find ${bashrc}. Skipping shell configuration."
        record_summary ".bashrc config" "Skipped" "bashrc missing"
        return 0
    fi

    # Ensure local bin is in PATH so we can detect newly installed tools
    export PATH="${XDG_BIN_HOME}:${PATH}"

    local block_exists=false
    if grep -qF "$marker_start" "$bashrc"; then
        block_exists=true
    fi

    # Construct the configuration block
    local config_block=""
    config_block+="${marker_start}\n"
    config_block+="[[ \":\$PATH:\" != *\":\$HOME/.local/bin:\"* ]] && export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
    config_block+="[[ \":\$PATH:\" != *\":/usr/local/go/bin:\"* ]] && export PATH=\"\$PATH:/usr/local/go/bin\"\n"
    config_block+="[[ \":\$PATH:\" != *\":\$HOME/go/bin:\"* ]] && export PATH=\"\$PATH:\$HOME/go/bin\"\n"
    
    # Tool Integrations
    if command -v starship &>/dev/null; then
        config_block+="\n# Starship (prompt)\n"
        config_block+="eval \"\$(starship init bash)\"\n"
    fi

    if command -v zoxide &>/dev/null; then
        config_block+="\n# Zoxide (better cd)\n"
        config_block+="eval \"\$(zoxide init bash)\"\n"
    fi
    config_block+="${marker_end}"
    
    # If block exists, check if it's identical to what we would write.
    if $block_exists; then
        local existing_block
        existing_block=$(sed -n "/^${marker_start}$/,/^${marker_end}$/p" "$bashrc")
        
        # Compare existing block with the one we want to write.
        if [[ "$existing_block" == "$(echo -e "${config_block}")" ]]; then
            printInfoMsg "Shell configuration is already up to date. Skipping."
            record_summary ".bashrc config" "Already Present" "setup block synchronized"
            return
        fi
    fi

    local prompt_msg="Add environment configuration to .bashrc?"
    if $block_exists; then
        prompt_msg="Your shell configuration is out of date. Update it?"
    fi

    printMsg ""
    if prompt_yes_no "$prompt_msg" "y"; then
        local backup_file="${bashrc}.bak_$(date +"%Y%m%d_%H%M%S")"
        cp "$bashrc" "$backup_file"
        printInfoMsg "Backup created at: ${backup_file}"

        if $block_exists; then
            sed -i "/^${marker_start}$/,/^${marker_end}$/d" "$bashrc"
        fi
        echo -e "\n${config_block}" >> "$bashrc"
        printOkMsg "Injected/Updated shell configuration in .bashrc."
        printInfoMsg "Please run '${C_L_CYAN}source ~/.bashrc${T_RESET}' to apply changes."
        if $block_exists; then
            record_summary ".bashrc config" "Updated" "setup block updated"
        else
            record_summary ".bashrc config" "Installed" "setup block added"
        fi
    else
        record_summary ".bashrc config" "Skipped" "user declined"
    fi

    return 0
}

# Copies custom binaries/scripts to ~/.local/bin
setup_binaries() {
    printBanner "Setting up Custom Binaries"
    local source_bin_path="${SCRIPT_DIR}/bin"
    local dest_bin_path="${XDG_BIN_HOME}"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        # Simple check: count files
        if [[ -d "$dest_bin_path" ]]; then report_verify "Custom Binaries" "Installed" "$(ls "$dest_bin_path"/dv-* 2>/dev/null | wc -l) scripts"; else report_verify "Custom Binaries" "Missing" ""; fi
        return
    fi

    if [[ ! -d "$source_bin_path" ]] || [[ -z "$(ls -A "$source_bin_path")" ]]; then
        printInfoMsg "No custom binaries found in '${source_bin_path}'. Skipping."
        record_summary "Custom Binaries" "Skipped" "source directory empty"
        return 0
    fi

    printInfoMsg "Copying binaries to ${dest_bin_path}..."
    mkdir -p "$dest_bin_path"
    local destination_exists=false
    if [[ -n "$(find "$dest_bin_path" -maxdepth 1 -type f -name 'dv-*' -print -quit)" ]]; then
        destination_exists=true
    fi
    if ! cp "$source_bin_path"/* "$dest_bin_path/"; then
        printErrMsg "Failed to copy custom binaries."
        record_summary "Custom Binaries" "Failed" "copy failed"
        return 1
    fi

    # chmod +x only dv-* files to avoid touching unrelated files
    chmod +x "${dest_bin_path}"/dv-* 2>/dev/null || true

    # Ensure library files are not executable
    if [[ -f "${dest_bin_path}/dv-common.sh" ]]; then
        chmod -x "${dest_bin_path}/dv-common.sh"
    fi
    printOkMsg "Custom binaries installed."
    if $destination_exists; then
        record_summary "Custom Binaries" "Updated" "scripts synchronized"
    else
        record_summary "Custom Binaries" "Installed" "scripts copied"
    fi
    return 0
}

# Copies the .bash_aliases file to the user's home directory.
setup_bash_aliases() {
    printBanner "Setting up .bash_aliases"
    local source_aliases_path="${SCRIPT_DIR}/config/bash/.bash_aliases"
    local dest_aliases_path="${HOME}/.bash_aliases"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ ! -f "$dest_aliases_path" ]]; then report_verify ".bash_aliases" "Missing" "";
        elif cmp -s "$source_aliases_path" "$dest_aliases_path"; then report_verify ".bash_aliases" "Synced" "";
        else report_verify ".bash_aliases" "Differs" "Content mismatch"; fi
        return
    fi

    if [[ ! -f "$source_aliases_path" ]]; then
        printErrMsg "Could not find '.bash_aliases' in the script directory: ${SCRIPT_DIR}"
        record_summary ".bash_aliases" "Failed" "source file missing"
        return 1
    fi

    if [[ -f "$dest_aliases_path" ]]; then
        if cmp -s "$source_aliases_path" "$dest_aliases_path"; then
            printInfoMsg "'~/.bash_aliases' is identical to source. Skipping."
            record_summary ".bash_aliases" "Already Present" "aliases synchronized"
            return 0
        fi

        if prompt_yes_no "File '~/.bash_aliases' already exists. Back it up and overwrite it?" "y"; then
            local backup_file
            backup_file="${dest_aliases_path}.bak_$(date +"%Y%m%d_%H%M%S")"
            printInfoMsg "Backing up current file to ${backup_file}..."
            cp "$dest_aliases_path" "$backup_file"
            if ! cp "$source_aliases_path" "$dest_aliases_path"; then
                record_summary ".bash_aliases" "Failed" "copy failed"
                return 1
            fi
            printOkMsg "Backup created and '~/.bash_aliases' has been overwritten."
            record_summary ".bash_aliases" "Updated" "aliases synchronized"
        else
            printInfoMsg "Skipping '.bash_aliases' setup."
            record_summary ".bash_aliases" "Skipped" "user declined"
        fi
    else
        if ! cp "$source_aliases_path" "$dest_aliases_path"; then
            record_summary ".bash_aliases" "Failed" "copy failed"
            return 1
        fi
        printOkMsg "Copied '.bash_aliases' to your home directory."
        record_summary ".bash_aliases" "Installed" "aliases copied"
    fi

    return 0
}

# Copies the tmux configuration to ~/.config/tmux/tmux.conf
setup_tmux_config() {
    printBanner "Setting up Tmux Configuration"
    local source_conf_path="${SCRIPT_DIR}/config/tmux/tmux.conf"
    local dest_conf_dir="${XDG_CONFIG_HOME}/tmux"
    local dest_conf_path="${dest_conf_dir}/tmux.conf"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ ! -f "$dest_conf_path" ]]; then report_verify "tmux.conf" "Missing" "";
        elif cmp -s "$source_conf_path" "$dest_conf_path"; then report_verify "tmux.conf" "Synced" "";
        else report_verify "tmux.conf" "Differs" "Content mismatch"; fi
        return
    fi

    if [[ ! -f "$source_conf_path" ]]; then
        printWarnMsg "Could not find 'tmux.conf' in: ${source_conf_path}"
        record_summary "tmux.conf" "Failed" "source file missing"
        return 1
    fi

    local config_status="Installed"

    if [[ ! -d "$dest_conf_dir" ]]; then
        printInfoMsg "Creating directory: ${dest_conf_dir}"
        mkdir -p "$dest_conf_dir"
    fi

    if [[ -f "$dest_conf_path" ]]; then
        if cmp -s "$source_conf_path" "$dest_conf_path"; then
            printInfoMsg "'tmux.conf' is identical to source. Skipping."
            config_status="Already Present"
            # Fall through to script setup
        elif prompt_yes_no "File '${dest_conf_path}' already exists. Back it up and overwrite it?" "y"; then
            local backup_file
            backup_file="${dest_conf_path}.bak_$(date +"%Y%m%d_%H%M%S")"
            printInfoMsg "Backing up current file to ${backup_file}..."
            cp "$dest_conf_path" "$backup_file"
            cp "$source_conf_path" "$dest_conf_path"
            printOkMsg "Backup created and 'tmux.conf' has been overwritten."
            config_status="Updated"
        else
            printInfoMsg "Skipping 'tmux.conf' setup."
            config_status="Skipped"
        fi
    else
        cp "$source_conf_path" "$dest_conf_path"
        printOkMsg "Copied 'tmux.conf' to '${dest_conf_path}'."
    fi

    # Setup Tmux Scripts
    local source_scripts_dir="${SCRIPT_DIR}/config/tmux/scripts/dv"
    local dest_scripts_dir="${dest_conf_dir}/scripts/dv"

    if [[ -d "$source_scripts_dir" ]]; then
        mkdir -p "$dest_scripts_dir"
        if ! cp "${source_scripts_dir}"/* "$dest_scripts_dir" 2>/dev/null; then
            printErrMsg "Failed to install tmux scripts."
            record_summary "tmux.conf" "Failed" "script copy failed"
            return 1
        fi
        chmod +x "${dest_scripts_dir}"/*.sh 2>/dev/null || true
        printOkMsg "Installed/Updated tmux scripts in '${dest_scripts_dir}':"
        ls "$dest_scripts_dir"
    fi

    record_summary "tmux.conf" "$config_status" "config and scripts ready"
    return 0
}

# Copies the starship.toml configuration to ~/.config/starship.toml
setup_starship_config() {
    printBanner "Setting up Starship Configuration"
    local source_config="${SCRIPT_DIR}/config/starship.toml"
    local dest_config="${XDG_CONFIG_HOME}/starship.toml"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ ! -f "$dest_config" ]]; then report_verify "starship.toml" "Missing" "";
        elif cmp -s "$source_config" "$dest_config"; then report_verify "starship.toml" "Synced" "";
        else report_verify "starship.toml" "Differs" "Content mismatch"; fi
        return
    fi

    if [[ ! -f "$source_config" ]]; then
        printWarnMsg "Could not find 'starship.toml' in: ${source_config}"
        record_summary "starship.toml" "Failed" "source file missing"
        return 1
    fi

    local config_status="Installed"

    if [[ -f "$dest_config" ]]; then
        if cmp -s "$source_config" "$dest_config"; then
            printInfoMsg "'starship.toml' is identical to source. Skipping."
            config_status="Already Present"
        elif prompt_yes_no "File '${dest_config}' already exists. Back it up and overwrite it?" "y"; then
            local backup_file="${dest_config}.bak_$(date +"%Y%m%d_%H%M%S")"
            printInfoMsg "Backing up current file to ${backup_file}..."
            cp "$dest_config" "$backup_file"
            cp "$source_config" "$dest_config"
            printOkMsg "Backup created and 'starship.toml' has been overwritten."
            config_status="Updated"
        else
            printInfoMsg "Skipping 'starship.toml' setup."
            config_status="Skipped"
        fi
    else
        mkdir -p "$(dirname "$dest_config")"
        cp "$source_config" "$dest_config"
        printOkMsg "Copied 'starship.toml' to '${dest_config}'."
    fi

    record_summary "starship.toml" "$config_status" "configuration ready"
    return 0
}

# Installs Tmux Plugin Manager and plugins
install_tpm() {
    printBanner "Installing Tmux Plugin Manager (TPM)"
    local tpm_dir="${XDG_CONFIG_HOME}/tmux/plugins/tpm"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        if [[ -d "$tpm_dir" ]]; then report_verify "TPM" "Installed" ""; else report_verify "TPM" "Missing" ""; fi
        return
    fi

    local install_status="Installed"
    if [[ -d "$tpm_dir" ]]; then
        install_status="Updated"
        printInfoMsg "TPM is already installed. Updating..."
        if ! run_with_spinner "Updating TPM repo..." git -C "$tpm_dir" pull; then
            printErrMsg "Failed to update TPM."
            record_summary "TPM" "Failed" "repository update failed"
            return 1
        fi
    else
        printInfoMsg "Cloning TPM repository..."
        mkdir -p "$(dirname "$tpm_dir")"
        if ! run_with_spinner "Cloning TPM..." git clone https://github.com/tmux-plugins/tpm "$tpm_dir"; then
            printErrMsg "Failed to clone TPM repository."
            record_summary "TPM" "Failed" "repository clone failed"
            return 1
        fi
    fi

    printInfoMsg "Installing Tmux plugins..."
    if [[ -f "$tpm_dir/bin/install_plugins" ]]; then
        if run_with_spinner "Running TPM install_plugins..." "$tpm_dir/bin/install_plugins"; then
            printOkMsg "Tmux plugins installed."
        else
            printErrMsg "Failed to install Tmux plugins."
            record_summary "TPM" "Failed" "plugin installation failed"
            return 1
        fi
    else
        printWarnMsg "TPM plugin installer not found."
        record_summary "TPM" "Failed" "plugin installer missing"
        return 1
    fi

    record_summary "TPM" "$install_status" "TPM and plugins ready"
    return 0
}

# Downloads and installs Nerd Fonts
install_nerd_fonts() {
    printBanner "Installing Nerd Fonts"

    if [[ "$VERIFY_MODE" == "true" ]]; then
        # Skip font verification for now as it's complex to check properly without fc-list
        local font_name
        local font_zip_name
        local font_dir
        for font_name in "FiraCode Nerd Font" "Meslo Nerd Font" "CaskaydiaCove Nerd Font"; do
            case "$font_name" in
                "FiraCode Nerd Font") font_zip_name="FiraCode" ;;
                "Meslo Nerd Font") font_zip_name="Meslo" ;;
                "CaskaydiaCove Nerd Font") font_zip_name="CascadiaCode" ;;
            esac
            font_dir="${XDG_DATA_HOME}/fonts/${font_zip_name}NerdFont"
            if [[ -d "$font_dir" ]]; then
                report_verify "$font_name" "Installed" "font directory exists"
            else
                report_verify "$font_name" "Optional" "not installed"
            fi
        done
        return
    fi

    # An associative array mapping the font's display name to its ZipFileName.
    declare -A font_map=(
        ["FiraCode Nerd Font"]="FiraCode"
        ["Meslo Nerd Font"]="Meslo"
        ["CaskaydiaCove Nerd Font"]="CascadiaCode"
    )

    local fonts_installed=0
    local latest_nerd_font_version=""

    for font_name in "${!font_map[@]}"; do
        local font_zip_name="${font_map[$font_name]}"
        local font_dir_name="${font_zip_name}NerdFont"
        local font_dir="${XDG_DATA_HOME}/fonts/${font_dir_name}"

        if [[ -d "$font_dir" ]]; then
            printInfoMsg "'${font_name}' is already installed in '${font_dir}'. Skipping."
            record_summary "$font_name" "Already Present" "font directory exists"
            continue
        fi

        if ! prompt_yes_no "Install '${font_name}'? (Recommended for icons)" "n"; then
            printInfoMsg "Skipping '${font_name}' installation."
            record_summary "$font_name" "Skipped" "user declined"
            continue
        fi

        # Fetch version only once if needed
        if [[ -z "$latest_nerd_font_version" ]]; then
            printInfoMsg "Finding latest Nerd Fonts release..."
            latest_nerd_font_version=$(_gh_get_latest_version "ryanoasis/nerd-fonts")
            
            if [[ -z "$latest_nerd_font_version" || "$latest_nerd_font_version" == "null" ]]; then
                printErrMsg "Could not determine latest Nerd Fonts version from GitHub API. Skipping font installs."
                record_summary "$font_name" "Failed" "latest version unavailable"
                continue
            fi
            printInfoMsg "Latest version: ${C_L_GREEN}${latest_nerd_font_version}${T_RESET}"
        fi

        local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/${latest_nerd_font_version}/${font_zip_name}.zip"
        local temp_dir; temp_dir=$(mktemp -d)
        
        if run_with_spinner "Downloading ${font_name}..." curl -L -f -o "${temp_dir}/${font_zip_name}.zip" "$font_url"; then
            mkdir -p "$font_dir"
            if run_with_spinner "Extracting to ${font_dir}..." unzip -o "${temp_dir}/${font_zip_name}.zip" -d "$font_dir"; then
                fonts_installed=1
                printOkMsg "'${font_name}' installed."
                record_summary "$font_name" "Installed" "font files ready"
            else
                printErrMsg "Failed to extract '${font_name}'."
                rm -rf "$font_dir"
                record_summary "$font_name" "Failed" "extraction failed"
            fi
        else
            printErrMsg "Failed to download '${font_name}'."
            record_summary "$font_name" "Failed" "download failed"
        fi
        rm -rf "$temp_dir"
    done

    if [[ $fonts_installed -eq 1 ]]; then
        printInfoMsg "Updating font cache... (this may take a moment)"
        if run_with_spinner "Running fc-cache..." fc-cache -f -v; then
            printOkMsg "Font cache updated."
            record_summary "Font Cache" "Updated" "font cache refreshed"
        else
            printErrMsg "Failed to update font cache."
            record_summary "Font Cache" "Failed" "cache refresh failed"
        fi
    fi

    return 0
}

# --- Phases ---

detect_system() {
    printPhaseBanner "System Detection"
    if [[ "$VERIFY_MODE" == "true" ]]; then
        report_verify "OS" "Linux" "$(uname -s)"
        report_verify "Arch" "x86_64" "$(uname -m)"
        return
    fi
    # OS Detection
    if [[ "$(uname -s)" != "Linux" ]]; then
        printErrMsg "Unsupported operating system: $(uname -s). This script only supports Linux."
        record_summary "System" "Failed" "unsupported operating system"
        return 1
    fi

    # Architecture Detection
    if [[ "$(uname -m)" != "x86_64" ]]; then
        printErrMsg "Unsupported architecture: $(uname -m). This script only supports x86_64."
        record_summary "System" "Failed" "unsupported architecture"
        return 1
    fi

    # Package Manager Detection
    if ! command -v apt-get &>/dev/null; then
        printErrMsg "Could not find 'apt'. This script only supports apt-based distributions (like Debian, Ubuntu)."
        record_summary "System" "Failed" "apt not available"
        return 1
    fi
    printOkMsg "System check passed: Linux x86_64 with apt."
}

phase_bootstrap() {
    printPhaseBanner "Phase 1: Bootstrap"

    if [[ "$VERIFY_MODE" != "true" ]]; then
        printInfoMsg "Updating package lists..."
        sudo apt-get update
    fi

    install_package "curl"
    install_package "git"
    install_package "build-essential" "gcc"
    install_package "cmake"
}

check_docker() {
    if [[ "$VERIFY_MODE" == "true" ]]; then
        if command -v docker &>/dev/null; then
            if docker info &>/dev/null; then
                report_verify "Docker" "Running" ""
            else
                report_verify "Docker" "Optional" "daemon not running or no permissions"
            fi
        else
            report_verify "Docker" "Optional" "not installed"
        fi
        return
    fi

    printInfoMsg "Checking for Docker..."
    if ! command -v docker &>/dev/null; then
        printWarnMsg "Docker is not installed. Note: 'lazydocker' will not work without Docker."
        printInfoMsg "  To install Docker, visit: https://docs.docker.com/engine/install/"
    elif ! docker info &>/dev/null; then
        printWarnMsg "Docker is installed, but the daemon is not running or current user has no permissions."
        printInfoMsg "  Ensure the docker service is started: sudo systemctl start docker"
        printInfoMsg "  And your user is in the docker group: sudo usermod -aG docker \$USER"
    else
        printOkMsg "Docker is installed and running."
    fi
}

phase_system_tools() {
    printPhaseBanner "Phase 2: System Tools (APT)"
    local -a packages=(
        "silversearcher-ag:ag"
        "micro"
        "tmux"
        "jq"
        "unzip"
        "fontconfig:fc-cache"
        "openssh-client:ssh"
    )
    for pkg_spec in "${packages[@]}"; do
        IFS=':' read -r pkg cmd <<< "$pkg_spec"
        install_package "$pkg" "${cmd:-$pkg}"
    done
    check_docker
}

phase_user_binaries() {
    printPhaseBanner "Phase 3: User Binaries (~/.local/bin)"
    setup_binaries
    
    local -a gh_tools=(
        "jesseduffield/lazygit:lazygit"
        "jesseduffield/lazydocker:lazydocker"
        "dandavison/delta:delta"
        "BurntSushi/ripgrep:rg"
        "sharkdp/fd:fd"
        "sharkdp/bat:bat"
        "eza-community/eza:eza"
    )
    for tool in "${gh_tools[@]}"; do
        IFS=':' read -r repo binary <<< "$tool"
        install_github_binary "$repo" "$binary"
    done
    
    install_zoxide
    install_starship
    install_fzf_from_source
}

phase_language_runtimes() {
    printPhaseBanner "Phase 4: Language Runtimes"
    install_golang
}

phase_configuration() {
    printPhaseBanner "Phase 5: Configuration & Dotfiles"
    setup_bash_aliases
    setup_starship_config
    setup_tmux_config
    install_tpm
    setup_fzf_config
    install_nerd_fonts
    configure_git_delta
    configure_shell_environment
}

phase_neovim_binary() {
    printPhaseBanner "Phase: Neovim Installation"
    install_neovim
}

phase_neovim_setup() {
    printPhaseBanner "Phase: Neovim Configuration"
    setup_lazyvim
    setup_lazyvim_plugins
}

phase_neovim_dependencies() {
    printPhaseBanner "Phase: Neovim Dependencies"
    printInfoMsg "Updating package lists..."
    sudo apt-get update
    
    local -a packages=("curl" "git" "build-essential" "cmake" "unzip" "jq" "fontconfig")
    for pkg in "${packages[@]}"; do
        install_package "$pkg"
    done
    
    local -a gh_tools=("BurntSushi/ripgrep:rg" "sharkdp/fd:fd")
    for tool in "${gh_tools[@]}"; do
        IFS=':' read -r repo binary <<< "$tool"
        install_github_binary "$repo" "$binary"
    done
}

main() {
    local SKIP_VIM=false
    local ONLY_VIM=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -y|--yes|--non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --no-vim)
                SKIP_VIM=true
                shift
                ;;
            --only-vim)
                ONLY_VIM=true
                shift
                ;;
            --verify)
                VERIFY_MODE=true
                shift
                ;;
            *)
                printErrMsg "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
    SUMMARY_RESULTS=()
    SUMMARY_ORDER=()
    VERIFY_RESULTS=()
    VERIFY_ORDER=()
    SETUP_FAILED=false
    VERIFY_FAILED=false

    if [[ "$VERIFY_MODE" == "true" ]]; then
        printMsg "${C_L_BLUE}${T_BOLD}Running in Verification Mode (Read-Only)${T_RESET}\n"
        # Fall through to run phases, but they will now use report_verify
    fi

    printPhaseBanner "Developer Machine Setup"
    
    if [[ "$ONLY_VIM" == "true" ]]; then
        printInfoMsg "Mode: Only Neovim setup"
    elif [[ "$SKIP_VIM" == "true" ]]; then
        printInfoMsg "Mode: Skipping Neovim setup"
    fi

    if [[ "$VERIFY_MODE" == "false" ]]; then
        printWarnMsg "This script will install packages using sudo and modify shell configuration."
        if ! prompt_yes_no "Do you want to continue?" "y"; then
            printInfoMsg "Setup cancelled."
            exit 0
        fi
    fi

    if [[ "$ONLY_VIM" == "true" ]]; then
        phase_neovim_dependencies
        phase_neovim_binary
        install_nerd_fonts
        phase_neovim_setup
        if [[ "$VERIFY_MODE" == "true" ]]; then
            print_verification_report
            if [[ "$VERIFY_FAILED" == "true" ]]; then return 1; fi
            return 0
        fi
        printOkMsg "Neovim Setup Complete"
        print_summary_report
        if [[ "$SETUP_FAILED" == "true" ]]; then return 1; fi
        return 0
    fi

    if ! detect_system; then
        print_summary_report
        return 1
    fi
    phase_bootstrap
    phase_system_tools
    phase_user_binaries
    phase_language_runtimes
    phase_configuration
    
    if [[ "$SKIP_VIM" == "false" ]]; then
        phase_neovim_binary
        phase_neovim_setup
    fi

    if [[ "$VERIFY_MODE" == "true" ]]; then
        print_verification_report
        if [[ "$VERIFY_FAILED" == "true" ]]; then return 1; fi
        return 0
    fi

    printPhaseBanner "Dev Machine Setup Complete"
    printOkMsg "All tasks have finished."
    printMsg "\n${T_ULINE}Final Steps:${T_RESET}"
    printMsg "\nTo apply all changes (new aliases, fzf, PATH) to your current session, please run:"
    printMsg "  ${C_L_CYAN}source ~/.bashrc${T_RESET}"
    print_summary_report
    if [[ "$SETUP_FAILED" == "true" ]]; then return 1; fi
    return 0
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

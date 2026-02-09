#!/bin/bash
# ===============
# Script Name: dv-dsh.sh
# Description: Interactive Docker Shell selector using fzf.
# Keybinding:  N/A
# Config:      N/A
# Dependencies: docker, fzf
# ===============

set -o pipefail

#region Library Functions

#region Colors and Styles
export C_RED=$'\033[31m'
export C_GREEN=$'\033[32m'
export C_YELLOW=$'\033[33m'
export C_BLUE=$'\033[34m'
export C_GRAY=$'\033[38;5;244m'
export C_L_RED=$'\033[31;1m'
export C_L_GREEN=$'\033[32m'
export C_L_YELLOW=$'\033[33m'
export C_L_BLUE=$'\033[34m'
export C_L_CYAN=$'\033[36m'

export T_RESET=$'\033[0m'
export T_BOLD=$'\033[1m'

export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
#endregion Colors and Styles

#region Logging
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
#endregion Logging

#region Prerequisite Checks
_check_command_exists() {
    command -v "$1" &>/dev/null
}

prereq_checks() {
    local missing_commands=()
    for cmd in "$@"; do
        if ! _check_command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        printErrMsg "Prerequisite checks failed. Missing commands:"
        for cmd in "${missing_commands[@]}"; do
            printMsg "    - ${C_L_YELLOW}${cmd}${T_RESET}"
        done
        exit 1
    fi
}
#endregion

#endregion

main() {
    prereq_checks "docker" "fzf"

    if ! docker ps &>/dev/null; then
        printErrMsg "Docker daemon is not running or current user cannot access it."
        exit 1
    fi

    # Format: ID, Names, Image, Status
    local format="table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}"
    
    # FZF Styling (Tokyo Night)
    local FZF_COMMON_OPTS=(
      --ansi --reverse --tiebreak=index --border=top
      --preview-window 'down,50%,border,wrap'
      --border-label-pos='2'
      --preview-label-pos='3'
      --bind 'ctrl-/:change-preview-window(right,60%,border-top|hidden|)'
      --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff'
      --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7'
    )

    local selected_line
    # We use --header-lines=1 to treat the first line (headers) as static
    selected_line=$(docker ps --format "$format" | \
        fzf "${FZF_COMMON_OPTS[@]}" --header-lines=1 --border-label=" Docker Shell " --prompt="  Container❯ " --preview='docker logs --tail 50 {1}' \
    )

    if [[ -z "$selected_line" ]]; then
        exit 0
    fi

    local container_id
    container_id=$(echo "$selected_line" | awk '{print $1}')
    local container_name
    container_name=$(echo "$selected_line" | awk '{print $2}')

    if [[ -z "$container_id" ]]; then
        printErrMsg "Could not extract container ID."
        exit 1
    fi

    # Shell detection
    local shells=("/bin/bash" "/bin/zsh" "/bin/ash" "/bin/sh")
    local selected_shell=""

    printMsgNoNewline "${T_INFO_ICON} Detecting shell for ${C_L_CYAN}${container_name}${T_RESET}..."

    for shell in "${shells[@]}"; do
        if docker exec "$container_id" "$shell" -c "exit" &>/dev/null; then
            selected_shell="$shell"
            break
        fi
    done
    
    echo # Newline

    if [[ -n "$selected_shell" ]]; then
        printOkMsg "Found ${C_L_GREEN}${selected_shell}${T_RESET}. Connecting..."
        docker exec -it "$container_id" "$selected_shell"
    else
        printErrMsg "No suitable shell found (tried: ${shells[*]})."
        exit 1
    fi
}

main "$@"
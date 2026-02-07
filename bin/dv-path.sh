#!/bin/bash
# ===============
# Script Name: dv-path.sh
# Description: PATH manager to visualize, validate, and clean $PATH.
# Keybinding:  N/A
# Config:      N/A
# Dependencies: stat
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
export T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
#endregion Colors and Styles

#region Logging
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
#endregion Logging

#region Prerequisite Checks
_check_command_exists() {
    command -v "$1" &>/dev/null
}

prereq_checks() {
    local missing_commands=()
    printMsgNoNewline "${T_INFO_ICON} Running prereq checks"
    for cmd in "$@"; do
        printMsgNoNewline "${C_L_BLUE}.${T_RESET}"
        if ! _check_command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    echo # Newline after the dots

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        printErrMsg "Prerequisite checks failed. Missing commands:"
        for cmd in "${missing_commands[@]}"; do
            printMsg "    - ${C_L_YELLOW}${cmd}${T_RESET}"
        done
        printMsg "${T_INFO_ICON} Please install the missing commands and try again."
        exit 1
    fi
}
#endregion

#region Source Detection
find_path_source() {
    local target_path="$1"
    local runtime_count="${2:-1}"
    local home_dir="$HOME"
    
    # Generate search patterns (Literal, $HOME, ${HOME}, ~)
    local -a patterns
    patterns+=("$target_path")
    
    if [[ "$target_path" == "$home_dir"* ]]; then
        local rel_path="${target_path#$home_dir/}"
        patterns+=("\$HOME/$rel_path")
        patterns+=("\${HOME}/$rel_path")
        patterns+=("~/$rel_path")
    fi

    local -a config_files
    config_files=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
        "$HOME/.bash_aliases"
        "$HOME/.zshrc"
        "$HOME/.zshenv"
        "$HOME/.config/fish/config.fish"
        "/etc/profile"
        "/etc/environment"
        "/etc/bash.bashrc"
    )
    
    if compgen -G "/etc/profile.d/*.sh" > /dev/null; then
        for f in /etc/profile.d/*.sh; do config_files+=("$f"); done
    fi

    local total_matches=0
    for file in "${config_files[@]}"; do
        [[ -f "$file" ]] || continue
        
        for pattern in "${patterns[@]}"; do
            # Grep for fixed string (-F), line number (-n), whole word (-w)
            local matches
            matches=$(grep -Fnw "$pattern" "$file" 2>/dev/null)
            if [[ -n "$matches" ]]; then
                while IFS= read -r match; do
                    local line_num="${match%%:*}"
                    printMsg "  └─ Found in ${C_L_BLUE}${file/#$HOME/~}:${line_num}${T_RESET} (matches \"${pattern}\")"
                    ((total_matches++))
                done <<< "$matches"
            fi
        done
    done

    if (( runtime_count > 1 && runtime_count > total_matches )); then
        printMsg "  └─ ${C_GRAY}ℹ Hint: Path appears ${runtime_count} times in \$PATH but found ${total_matches} static matches.${T_RESET}"
        printMsg "     ${C_GRAY}  Config files might be sourced multiple times or the path is added dynamically.${T_RESET}"
    fi
}
#endregion

main() {
    prereq_checks "stat"

    local -a path_entries
    IFS=':' read -ra path_entries <<< "$PATH"

    # Pass 1: Count duplicates
    local -A path_counts
    for p in "${path_entries[@]}"; do
        ((path_counts["$p"]++))
    done

    # Pass 2: Display unique paths with details
    local -A processed_paths
    for p in "${path_entries[@]}"; do
        # Only process each unique path once
        if [[ -n "${processed_paths["$p"]}" ]]; then continue; fi
        processed_paths["$p"]=1
        
        local count="${path_counts["$p"]}"
        local display_path="${C_BOLD}${C_L_CYAN}${p}${T_RESET}"
        
        if (( count > 1 )); then
            display_path="${C_BOLD}${C_L_RED}${p}${T_RESET}  ${C_L_YELLOW}(x${count})${T_RESET}"
        fi
        
        printMsg "${display_path}"
        
        # Check for existence
        if [[ ! -d "$p" ]]; then 
            printMsg "  ${C_RED}✗ Path does not exist${T_RESET}"
        else
            # Check world-writable
            local perms
            if [[ "$OSTYPE" == "darwin"* ]]; then
                perms=$(stat -f %A "$p")
            else
                perms=$(stat -c %a "$p")
            fi
            local other_perm=${perms: -1}
            if (( other_perm & 2 )); then
                printMsg "  ${C_RED}! Insecure (World-Writable)${T_RESET}"
            fi
        fi

        find_path_source "$p" "$count"
        echo ""
    done
}

main "$@"

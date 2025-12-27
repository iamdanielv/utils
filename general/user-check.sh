#!/bin/bash
# Ensures the script is running as a specific user, attempting to switch with sudo if not.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Colors & Styles
C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'
C_L_RED=$'\033[31;1m'
C_L_BLUE=$'\033[34m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'

# Icons
T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"

# Logging
printMsg() { printf '%b\n' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }

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

print_usage() {
    printBanner "User Check Utility"
    printMsg "Ensures the script is running as a specific user."
    printMsg "If not, it attempts to re-run itself using 'sudo -u <user>'."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [username] [-h]"
    printMsg "\n${T_ULINE}Arguments:${T_RESET}"
    printMsg "  ${C_L_BLUE}username${T_RESET}   The target user to run as (default: daniel)."
    printMsg "  ${C_L_BLUE}-h${T_RESET}          Show this help message."
    printMsg "\n${T_ULINE}Example:${T_RESET}"
    printMsg "  ${C_GRAY}# Ensure the script runs as the user 'www-data'${T_RESET}"
    printMsg "  $(basename "$0") www-data"
}

main() {
    # Check for help flag first
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage
        exit 0
    fi

    # Set default value for TARGET_USER if not provided as an argument
    local TARGET_USER=${1:-daniel}

    printBanner "User Check"
    printMsg "Current user: ${C_L_BLUE}${USER}${T_RESET}"
    printMsg "Target user:  ${C_L_BLUE}${TARGET_USER}${T_RESET}"

    # Check if we are already running as the target user
    if [[ "${USER}" == "${TARGET_USER}" ]]; then
        printOkMsg "Already running as target user (${USER})."
        exit 0
    fi

    # If not the target user, check if sudo is available
    if ! command -v sudo &>/dev/null; then
        printErrMsg "sudo command not found. Cannot switch to user '${TARGET_USER}'."
        exit 1
    fi

    printMsg "${T_INFO_ICON} Not running as target user. Attempting to switch with sudo..."

    # Re-execute the script with sudo, replacing the current process.
    # "$0" is the path to the current script. "$@" passes along all original arguments.
    # If sudo fails (e.g., wrong password), it will exit with a non-zero status,
    # and 'set -e' will terminate this script.
    exec sudo -H -u "${TARGET_USER}" -- "$0" "$@"
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

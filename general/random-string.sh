#!/bin/bash

# Generate one or more random hexadecimal strings.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Colors & Styles
C_RED=$'\033[31m'
C_L_RED=$'\033[31;1m'
C_L_BLUE=$'\033[34m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'

# Icons
T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

# Logging
printMsg() { printf '%b\n' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }

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

# --- Script Functions ---

print_usage() {
    # This function prints to stdout, which is standard for help text.
    printBanner "Random String Generator"
    printMsg "Generates random hexadecimal strings suitable for use in scripts."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-n <count>] [-l <length>] [-h]"
    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-n <count>${T_RESET}   Number of strings to generate (default: 3)."
    printMsg "  ${C_L_BLUE}-l <length>${T_RESET}  Length of each string (default: 5)."
    printMsg "  ${C_L_BLUE}-h${T_RESET}          Show this help message."
    printMsg "\n${T_ULINE}Examples:${T_RESET}"
    printMsg "  ${C_GRAY}# Generate 5 strings of length 10${T_RESET}"
    printMsg "  $(basename "$0") -n 5 -l 10"
    printMsg "  ${C_GRAY}# Generate 1 string of default length (5)${T_RESET}"
    printMsg "  $(basename "$0") -n 1"
}

# Function to generate a random string of specified length using hexadecimal characters.
generate_random_string() {
    local length=$1
    # We must run this in a subshell with pipefail disabled.
    # `head` closes the pipe after reading, causing `tr` to receive a SIGPIPE signal.
    # With `set -o pipefail` active, this non-zero exit from `tr` would cause the
    # entire script to terminate due to `set -e`.
    # By disabling pipefail locally, the pipeline's exit status is that of the last
    # command (`head`), which is 0 on success.
    (set +o pipefail; < /dev/urandom tr -dc 'a-f0-9' | head -c "$length")
}

main() {
    # Default values
    local NUM_STRINGS=3
    local LENGTH=5

    # Process arguments using getopts for robust option parsing
    while getopts ":n:l:h" opt; do
        case ${opt} in
            n)
                if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                    printErrMsg "Value for -n must be a positive integer." >&2
                    exit 1
                fi
                NUM_STRINGS=$OPTARG
                ;;
            l)
                if ! [[ $OPTARG =~ ^[0-9]+$ ]]; then
                    printErrMsg "Value for -l must be a positive integer." >&2
                    exit 1
                fi
                LENGTH=$OPTARG
                ;;
            h)
                print_usage
                exit 0
                ;;
            \?)
                printErrMsg "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :)
                printErrMsg "Option -$OPTARG requires an argument." >&2
                exit 1
                ;;
        esac
    done

    # Generate and print the random strings to stdout, one per line.
    for ((i = 0; i < NUM_STRINGS; i++)); do
        generate_random_string "$LENGTH"
        echo # Add a newline after each string
    done
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
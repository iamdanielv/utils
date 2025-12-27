#!/bin/bash

# Generate one or more random hexadecimal strings.

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
generate_banner_string() {
    local text="$1"; local total_width=70; local prefix="┏"; local line
    # Create a full-width line of '━' characters.
    printf -v line '%*s' "$((total_width - 1))"; line="${line// /━}"; printf '%s' "${C_L_BLUE}${prefix}${line}${T_RESET}"; printf '\r'
    # Use carriage return (\r) to move cursor to the start and print the text over the line.
    printf '%s' "${C_L_BLUE}${prefix} ${text} ${T_RESET}"
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

    # Calculate the total number of characters needed.
    local total_chars=$((NUM_STRINGS * LENGTH))

    # Generate all random characters in a single pipeline for efficiency.
    # - Read from /dev/urandom
    # - Filter for hexadecimal characters
    # - Take the total number of characters needed
    # - Fold the stream into lines of the desired length.
    < /dev/urandom tr -dc 'a-f0-9' | head -c "$total_chars" | fold -w "$LENGTH"
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
#!/bin/bash

# Generate one or more random hexadecimal strings.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    # Fallback for error message if shared.sh is not available
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

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

# --- Main Script ---

# Default values
NUM_STRINGS=3
LENGTH=5

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
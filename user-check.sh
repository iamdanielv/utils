#!/bin/bash
# Ensures the script is running as a specific user, attempting to switch with sudo if not.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for TUI functions and error handling.
# shellcheck source=./shared.sh
# shellcheck source=./src/lib/shared.lib.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/src/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

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

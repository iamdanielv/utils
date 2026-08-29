#!/bin/bash
# ===============
# Script Name: dv-ip.sh
# Description: A simplified, color-coded network interface viewer (clean 'ip a').
# Keybinding:  N/A
# Config:      N/A
# Dependencies: ip (iproute2), jq
# ===============

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
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
printMsg() { printf '%b\n' "$1" >&2; }
printMsgNoNewline() { printf '%b' "$1" >&2; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printWarnMsg() { printMsg "${T_WARN_ICON} ${1}${T_RESET}"; }
#endregion Logging

#region Terminal Control
clear_lines_up() {
    local lines=${1:-1}; for ((i = 0; i < lines; i++)); do printf '\033[1A\033[2K'; done; printf '\r'
} >/dev/tty
#endregion Terminal Control

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
        clear_lines_up 1
        printErrMsg "Prerequisite checks failed. Missing commands:"
        for cmd in "${missing_commands[@]}"; do
            printMsg "    - ${C_L_YELLOW}${cmd}${T_RESET}"
        done
        printMsg "${T_INFO_ICON} Please install the missing commands and try again."
        exit 1
    fi
    clear_lines_up 1
}
#endregion

#region Table Formatter
format_tsv_as_table() {
    local indent="${1:-}"
    local padding=4
    awk -v indent="$indent" -v padding="$padding" '
        function visible_length(s, temp_s) {
            temp_s = s
            gsub(/\x1b\[[0-9;?]*[a-zA-Z]/, "", temp_s)
            return length(temp_s)
        }
        BEGIN { FS="\t" }
        {
            for(i=1; i<=NF; i++) {
                len = visible_length($i)
                if(len > max_width[i]) { max_width[i] = len }
            }
            data[NR] = $0
        }
        END {
            for(row=1; row<=NR; row++) {
                printf "%s", indent
                num_fields = split(data[row], fields, FS)
                if (num_fields == 1 && fields[1] == "") { continue }
                for(col=1; col<=num_fields; col++) {
                    align_pad = max_width[col] - visible_length(fields[col])
                    printf "%s", fields[col]; for (p=0; p<align_pad; p++) { printf " " }
                    if (col < num_fields) { for (p=0; p<padding; p++) { printf " " } }
                }
                printf "\n"
            }
        }
    '
}
#endregion

#endregion

main() {
    prereq_checks "ip" "jq"

    local tsv_output=""
    # Add header with bold styling
    tsv_output+="${T_BOLD}INTERFACE\tSTATE\tIPv4\tIPv6\tMAC${T_RESET}\n"

    # This jq filter extracts the required fields for each network interface.
    # It uses `// "-"` to provide a default value if an address is not found.
    local jq_filter='
    .[] |
      [
        .ifname,
        .operstate,
        (.addr_info[]? | select(.family == "inet") | "\(.local)/\(.prefixlen)") // "-",
        (.addr_info[]? | select(.family == "inet6" and .scope == "global") | "\(.local)/\(.prefixlen)") // "-",
        .address // "-"
      ] | @tsv
    '

    local raw_json
    if ! raw_json=$(ip -j addr); then
        printErrMsg "Failed to get network interface data from 'ip -j addr'."
        return 1
    fi

    # Process the JSON with jq and loop through the TSV results
    while IFS=$'\t' read -r ifname state ipv4 ipv6 mac; do
        local state_colored="$state"
        if [[ "$state" == "UP" ]]; then
            state_colored="${C_L_GREEN}${state}${T_RESET}"
        elif [[ "$state" == "DOWN" ]]; then
            state_colored="${C_L_RED}${state}${T_RESET}"
        fi

        local ifname_colored="${T_BOLD}${C_L_BLUE}${ifname}${T_RESET}"
        local ipv4_colored="${C_L_CYAN}${ipv4}${T_RESET}"
        local ipv6_colored="${C_GRAY}${ipv6}${T_RESET}"
        local mac_colored="${C_GRAY}${mac}${T_RESET}"

        # Append formatted line to TSV output
        tsv_output+="${ifname_colored}\t${state_colored}\t${ipv4_colored}\t${ipv6_colored}\t${mac_colored}\n"
    done < <(echo "$raw_json" | jq -r "$jq_filter")

    # Print the final formatted table
    if [[ -n "$tsv_output" ]]; then
        echo -e "$tsv_output" | format_tsv_as_table "  "
    else
        printWarnMsg "No network interfaces found."
    fi
}

main "$@"
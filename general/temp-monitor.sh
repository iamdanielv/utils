#!/bin/bash

# Continuously monitor system temperatures from thermal zones.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Colors & Styles
C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'
C_L_RED=$'\033[31;1m'
C_L_GREEN=$'\033[32m'
C_L_YELLOW=$'\033[33m'
C_L_BLUE=$'\033[34m'
C_L_CYAN=$'\033[36m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'
T_CURSOR_HIDE=$'\033[?25l'
T_CURSOR_SHOW=$'\033[?25h'

# Icons
T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"

# Logging
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
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

# Terminal Control
clear_screen() { printf '\033[H\033[J' >/dev/tty; }

# Interrupt Handler
script_interrupt_handler() {
    trap - INT
    printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
    stty echo >/dev/tty
    clear_screen
    printMsg "${T_WARN_ICON} ${C_L_YELLOW}Operation cancelled by user.${T_RESET}"
    exit 130
}

# --- Script Functions ---

print_usage() {
    printBanner "System Temperature Monitor"
    printMsg "Continuously displays temperatures from system thermal sensors with trend indicators."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-i <interval>] [-d <delta>] [-a <count>] [-h]"
    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-i <interval>${T_RESET}  Refresh interval in seconds (default: 1)."
    printMsg "  ${C_L_BLUE}-d <delta>${T_RESET}    Temperature delta to trigger trend arrows (default: 2.0)."
    printMsg "  ${C_L_BLUE}-a <count>${T_RESET}    Number of past readings to average for trend (default: 5)."
    printMsg "  ${C_L_BLUE}-h${T_RESET}            Show this help message."
    printMsg "\nTrend arrows (↑,↓,→) show change against the average of the last <count> readings."
    printMsg "\n${T_ULINE}Example:${T_RESET}"
    printMsg "  ${C_GRAY}# Monitor temperatures, refreshing every 5 seconds${T_RESET}"
    printMsg "  $(basename "$0") -i 5"
}

# Checks if the system provides thermal zone information.
check_thermal_sensors() {
    if ! ls /sys/class/thermal/thermal_zone* &>/dev/null; then
        printErrMsg "No thermal sensors found in /sys/class/thermal/."
        printMsg "${T_INFO_ICON} This script is designed for Linux systems with thermal monitoring support."
        exit 1
    fi
}

# Checks for required commands and bash version.
check_dependencies() {
    # Associative arrays were introduced in bash 4.0
    if (( BASH_VERSINFO[0] < 4 )); then
        printErrMsg "This script requires Bash version 4.0 or higher."
        printMsg "${T_INFO_ICON} Your version is ${BASH_VERSION}. Please upgrade your shell."
        exit 1
    fi
}

# Returns a color based on a raw temperature value (e.g., 55000).
# This is more efficient than using 'bc' for simple integer comparisons.
get_temp_color_from_raw() {
    local temp_raw=$1
    if (( temp_raw >= 70000 )); then
        echo -n "$C_L_RED"
    elif (( temp_raw >= 50000 )); then
        echo -n "$C_L_YELLOW"
    else
        echo -n "$C_L_GREEN"
    fi
}

# Helper to parse float delta input (e.g. 2.5) into raw millidegrees (2500)
# without using 'bc'.
calculate_delta_raw() {
    local delta="$1"
    if [[ "$delta" =~ ^([0-9]+)(\.([0-9]+))?$ ]]; then
        local int_part="${BASH_REMATCH[1]}"
        local dec_part="${BASH_REMATCH[3]}000" # Pad with zeros
        dec_part="${dec_part:0:3}" # Take first 3 digits
        # Use 10# to force base 10 to avoid octal interpretation
        echo $(( int_part * 1000 + 10#$dec_part ))
    else
        echo "2000" # Default 2.0
    fi
}

# Main monitoring loop.
monitor_temperatures() {
    local interval="$1"
    local temp_delta="$2"
    local avg_count="$3"
    local -A temp_history # Associative array to store raw temperature history
    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"
    
    local num_spinner_chars=${#spinner_chars}
    local spinner_idx=0

    # Use the shared interrupt handler for a consistent exit experience.
    trap 'script_interrupt_handler' INT

    # --- Initial Draw ---
    clear_screen
    printBanner "System Temps (Updated every ${interval}s, press 'q', ESC, or Ctrl+C to exit)"
    printf "  ${C_GRAY}(Trend: ${C_L_RED}↑-hotter${C_GRAY}, ${C_L_BLUE}↓-cooler${C_GRAY}, →-stable vs avg of last %s readings)\n\n" "$avg_count"
 
    # Get initial sensor list and draw the static labels once.
    # Store the full paths to each zone to handle non-sequential zone numbers (e.g., thermal_zone0, thermal_zone10).
    local sensor_zones
    mapfile -d '' -t sensor_zones < <(printf '%s\0' /sys/class/thermal/thermal_zone*)
    
    local sensor_types=()
    for zone_path in "${sensor_zones[@]}"; do
        local type_file="${zone_path}/type"
        if [[ -r "$type_file" ]]; then
            sensor_types+=("$(<"$type_file")")
        else
            sensor_types+=("unknown")
        fi
    done
    local -r num_sensors=${#sensor_types[@]}
 
    for name in "${sensor_types[@]}"; do # 'name' is implicitly local in modern bash for-loops
        # Print only the static label part of the line
        printf "  %b%-20s%b\n" "$C_L_BLUE" "$name" "$T_RESET"
    done
 
    # Hide cursor after initial draw for a cleaner display
    printMsgNoNewline "${T_CURSOR_HIDE}"
 
    # Pre-calculate temp_delta in raw format to avoid using 'bc' in the loop
    local temp_delta_raw; temp_delta_raw=$(calculate_delta_raw "$temp_delta")
 
    # --- Update Loop ---
    while true; do
        # Move cursor up to the beginning of the data block to overwrite.
        printf "\033[%sA" "${num_sensors}"
 
        # Update a spinner on the line above the sensors to show activity.
        # It saves the cursor, moves up one line, prints the spinner, then restores.
        local spinner_char="${spinner_chars:spinner_idx:1}"
        printf "\033[s\033[1A\033[3G%b%s%b\033[K\033[u" "${C_L_CYAN}" "${spinner_char}" "${T_RESET}"
        spinner_idx=$(((spinner_idx + 1) % num_spinner_chars))

        # Loop through each sensor by its index
        for i in "${!sensor_zones[@]}"; do # 'i' is implicitly local
            local name="${sensor_types[$i]}"
            local temp_raw=0 # Default to 0
            local temp_file="${sensor_zones[$i]}/temp"

            # Safely read the temperature for the current sensor.
            # If the file is unreadable or contains non-numeric data, temp_raw remains 0.
            if [[ -r "$temp_file" ]]; then
                local content
                content=$(<"$temp_file")
                if [[ "$content" =~ ^-?[0-9]+$ ]]; then
                    temp_raw="$content"
                fi
            fi

            # --- History & Trend Logic ---
            local hist_str="${temp_history[$name]}"
            local -a hist_arr
            read -ra hist_arr <<< "$hist_str"

            local trend_arrow="→"
            local trend_color="$C_GRAY"

            # Calculate average of previous readings if we have enough history
            if (( ${#hist_arr[@]} >= avg_count )); then
                local sum=0
                for val in "${hist_arr[@]}"; do sum=$((sum + val)); done
                local avg_prev=$((sum / ${#hist_arr[@]}))

                if (( (temp_raw - avg_prev) > temp_delta_raw )); then
                    trend_arrow="↑"; trend_color="$C_L_RED"
                elif (( (avg_prev - temp_raw) > temp_delta_raw )); then
                    trend_arrow="↓"; trend_color="$C_L_BLUE"
                fi
            fi

            # Update history: prepend new value and truncate
            hist_arr=("$temp_raw" "${hist_arr[@]}")
            temp_history["$name"]="${hist_arr[*]:0:avg_count}"
            
            # --- Display Logic ---
            local temp_color; temp_color=$(get_temp_color_from_raw "$temp_raw")
            # Simulate float formatting: 55000 -> 55.0
            local t_int=$(( temp_raw / 1000 ))
            local t_dec=$(( (temp_raw % 1000) / 100 ))

            # Move to the column after the label and print only the dynamic data.
            printf "\033[23G%b%s%b %b%5.1f%b°C\033[K\n" \
                "$trend_color" "$trend_arrow" "$T_RESET" \
                "$temp_color" "${t_int}.${t_dec}" "$T_RESET"
        done

        # Wait for the interval, but also listen for key presses.
        # -s: silent, -n 1: read 1 char, -t: timeout
        local key
        if read -s -n 1 -t "$interval" key; then
            # Check if 'q' or ESC was pressed. ESC key sends a single char \x1b
            if [[ "$key" == "q" || "$key" == $'\e' ]]; then
                kill -INT $$ # Trigger the trap for a graceful exit
            fi
        fi
    done
}

main() {
    # Default values
    local interval=1
    local delta=2.0
    local avg_count=5

    # Process arguments using getopts for robust option parsing
    while getopts ":i:d:a:h" opt; do
        case ${opt} in
            i)
                # Validate that the interval is a positive integer.
                if ! [[ $OPTARG =~ ^[1-9][0-9]*$ ]]; then
                    printErrMsg "Value for -i must be a positive integer." >&2
                    exit 1
                fi
                interval=$OPTARG
                ;;
            d)
                # Validate that delta is a non-negative number (integer or float)
                if ! [[ $OPTARG =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    printErrMsg "Value for -d must be a non-negative number." >&2
                    exit 1
                fi
                delta=$OPTARG
                ;;
            a)
                # Validate that avg_count is a positive integer.
                if ! [[ $OPTARG =~ ^[1-9][0-9]*$ ]]; then
                    printErrMsg "Value for -a must be a positive integer." >&2
                    exit 1
                fi
                avg_count=$OPTARG
                ;;
            h)
                print_usage
                exit 0
                ;;
            \?)
                printErrMsg "Invalid option: -$OPTARG" >&2
                print_usage
                exit 1
                ;;
            :)
                printErrMsg "Option -$OPTARG requires an argument." >&2
                print_usage
                exit 1
                ;;
        esac
    done

    check_dependencies
    check_thermal_sensors
    monitor_temperatures "$interval" "$delta" "$avg_count"
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
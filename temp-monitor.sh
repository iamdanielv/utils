#!/bin/bash

# Continuously monitor system temperatures from thermal zones.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for TUI functions and error handling
# shellcheck source=./src/lib/shared.lib.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/src/lib/shared.lib.sh"; then
    echo "Error: Could not source shared.lib.sh. Make sure it's in the 'src/lib' directory." >&2
    exit 1
fi

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
    if ! command -v bc &>/dev/null; then
        printErrMsg "'bc' (basic calculator) is required but is not installed."
        printMsg "${T_INFO_ICON} Please install it using your package manager (e.g., 'sudo apt-get install bc')."
        exit 1
    fi
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

# (Private) Calculates the trend of a temperature reading against its history.
# Usage: _get_temp_trend <current_raw> <history_string> <avg_count> <delta_raw> trend_arrow_ref trend_color_ref
_get_temp_trend() {
    local current_raw="$1"
    local history_string="$2"
    local avg_count="$3"
    local delta_raw="$4"
    local -n trend_arrow_ref="$5" # Nameref for the arrow
    local -n trend_color_ref="$6" # Nameref for the color

    # Default to stable trend
    trend_arrow_ref="→"
    trend_color_ref="$C_GRAY"

    local -a history_array
    # Use mapfile for safer parsing of space-separated strings into an array
    mapfile -t history_array < <(echo "$history_string")
    local num_readings="${#history_array[@]}"

    # Only calculate trend if we have enough historical data
    if (( num_readings >= avg_count )); then
        local sum=0
        for val in "${history_array[@]}"; do
            sum=$((sum + val))
        done
        local avg_prev_raw=$((sum / num_readings))

        if (( (current_raw - avg_prev_raw) > delta_raw )); then
            trend_arrow_ref="↑"
            trend_color_ref="$C_L_RED" # Increasing
        elif (( (avg_prev_raw - current_raw) > delta_raw )); then
            trend_arrow_ref="↓"
            trend_color_ref="$C_L_BLUE" # Decreasing
        fi
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
    local temp_delta_raw
    temp_delta_raw=$(echo "$temp_delta * 1000" | bc)
    temp_delta_raw=${temp_delta_raw%.*} # Ensure it's an integer
 
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

            local trend_arrow trend_color temp_color
            _get_temp_trend "$temp_raw" "${temp_history[$name]:-""}" "$avg_count" "$temp_delta_raw" trend_arrow trend_color
            temp_color=$(get_temp_color_from_raw "$temp_raw")
            
            # Only call bc once per loop for display purposes
            local temp_current; temp_current=$(echo "scale=1; $temp_raw / 1000" | bc)

            # Move to the column after the label and print only the dynamic data.
            printf "\033[23G%b%s%b %b%5.1f%b°C\033[K\n" \
                "$trend_color" "$trend_arrow" "$T_RESET" \
                "$temp_color" "$temp_current" "$T_RESET"

            # Add current RAW temp to history and trim the array to avg_count
            history_array=("$temp_raw" "${history_array[@]}")
            local -a history_array
            mapfile -t history_array < <(echo "${temp_history[$name]:-""}")
            temp_history["$name"]="${history_array[*]:0:avg_count}"
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
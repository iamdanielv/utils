#!/bin/bash

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
BOLD='\033[1m'
REVERSE='\033[7m'
NC='\033[0m' # No Color

# Check dependencies
if ! command -v virsh &> /dev/null; then
    echo -e "${RED}Error: 'virsh' command not found. Please install libvirt-clients${NC}"
    exit 1
fi

# Global State
VM_NAMES=()
VM_STATES=()
declare -A VM_CPU_USAGE
declare -A VM_MEM_USAGE
declare -A PREV_CPU_TIME
LAST_TIMESTAMP=0
SELECTED=0
STATUS_MSG=""

# Function to fetch VM data
fetch_vms() {
    VM_NAMES=()
    VM_STATES=()
    
    # Capture current time in nanoseconds for CPU calc
    local current_timestamp
    current_timestamp=$(date +%s%N)
    local time_diff=$(( current_timestamp - LAST_TIMESTAMP ))
    
    # Fetch bulk stats (CPU time in ns, Memory in KiB)
    local stats_output
    stats_output=$(virsh domstats --cpu-total --balloon 2>/dev/null)
    
    local -A current_cpu_times
    local -A current_mems
    local current_vm=""
    
    # Parse domstats output
    while read -r line; do
        if [[ "$line" =~ ^Domain:\ \'(.*)\' ]]; then
            current_vm="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ cpu\.time=([0-9]+) ]]; then
            current_cpu_times["$current_vm"]="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ balloon\.current=([0-9]+) ]]; then
            current_mems["$current_vm"]="${BASH_REMATCH[1]}"
        fi
    done <<< "$stats_output"
    
    # Get all VM names, sorted, removing empty lines
    local raw_names
    raw_names=$(virsh list --all --name | sort | sed '/^$/d')
    
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            VM_NAMES+=("$name")
            # Get state
            local state
            state=$(virsh domstate "$name" 2>/dev/null | tr -d '\n')
            VM_STATES+=("$state")
            
            # Process Memory (KiB -> MiB/GiB)
            local mem_kib="${current_mems[$name]}"
            if [[ -n "$mem_kib" && "$mem_kib" -gt 0 ]]; then
                if (( mem_kib > 1048576 )); then
                    local gib=$(( mem_kib * 10 / 1048576 ))
                    VM_MEM_USAGE["$name"]="${gib:0:-1}.${gib: -1} GiB"
                else
                    VM_MEM_USAGE["$name"]="$(( mem_kib / 1024 )) MiB"
                fi
            else
                VM_MEM_USAGE["$name"]="-"
            fi
            
            # Process CPU Usage
            local cpu_time="${current_cpu_times[$name]}"
            if [[ -n "$cpu_time" && -n "${PREV_CPU_TIME[$name]}" && $time_diff -gt 0 ]]; then
                local cpu_diff=$(( cpu_time - PREV_CPU_TIME[$name] ))
                # Usage % = (cpu_diff_ns / time_diff_ns) * 100. Multiply by 1000 for 1 decimal place.
                local usage=$(( cpu_diff * 1000 / time_diff ))
                if (( usage < 10 )); then
                    VM_CPU_USAGE["$name"]="0.${usage}%"
                else
                    VM_CPU_USAGE["$name"]="${usage:0:-1}.${usage: -1}%"
                fi
            else
                VM_CPU_USAGE["$name"]="---"
            fi
            PREV_CPU_TIME["$name"]="$cpu_time"
        fi
    done <<< "$raw_names"
    
    LAST_TIMESTAMP="$current_timestamp"
}

# Function to render the UI
draw() {
    clear
    echo -e "${CYAN}==VM Manager========================================${NC}"
    
    local count=${#VM_NAMES[@]}
    
    if [[ $count -eq 0 ]]; then
        echo -e "\n  ${YELLOW}No VMs defined on this host${NC}\n"
    else
        printf "  ${BOLD}%-20s %-10s %-6s %-10s${NC}\n" "NAME" "STATE" "CPU" "MEM"
        echo -e "  ${BLUE}----                 -----      ---    ---${NC}"
        
        for ((i=0; i<count; i++)); do
            local name="${VM_NAMES[$i]}"
            local state="${VM_STATES[$i]}"
            local cpu="${VM_CPU_USAGE[$name]}"
            local mem="${VM_MEM_USAGE[$name]}"
            local line_color="$NC"
            local state_color="$NC"
            local cursor="  "
            
            # Determine State Color
            case "$state" in
                "running") state_color="$GREEN" ;;
                "shut off") state_color="$RED" ;;
                "paused") state_color="$YELLOW" ;;
                *) state_color="$NC" ;;
            esac
            
            # Highlight selection
            if [[ $i -eq $SELECTED ]]; then
                cursor="${CYAN}❯ ${NC}"
                line_color="${BOLD}${BLUE}${REVERSE}"
            fi
            
            # Print line with padding
            printf "${cursor}${line_color}%-20s ${state_color}%-10s${NC}${line_color} %-6s %-10s${NC}\n" "$name" "$state" "$cpu" "$mem"
        done
    fi
    
    echo -e "${BLUE}====================================================${NC}"
    echo -e "${BOLD} ${STATUS_MSG}${NC}"
    echo -e "${BLUE}----------------------------------------------------${NC}"
    echo -e "${BOLD}Controls:${NC}"
    echo -e " [${BOLD}↑/↓${NC}] Select   [${BOLD}S${NC}]tart      [${BOLD}x${NC}]Shutdown"
    echo -e " [${BOLD}F${NC}]orce Stop   [${BOLD}R${NC}]eboot     [${BOLD}Q${NC}]uit"
}

# Main Loop
fetch_vms
while true; do
    # Ensure selection is within bounds
    if [[ $SELECTED -ge ${#VM_NAMES[@]} ]]; then SELECTED=$((${#VM_NAMES[@]} - 1)); fi
    if [[ $SELECTED -lt 0 ]]; then SELECTED=0; fi

    draw

    # Read input (1 char) with 2s timeout for auto-refresh
    read -rsn1 -t 2 key
    if [[ $? -ne 0 ]]; then
        fetch_vms
        STATUS_MSG=""
        continue
    fi

    STATUS_MSG=""
    
    # Handle Escape sequences (Arrow keys)
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 key
        case "$key" in
            '[A') # Up
                ((SELECTED--))
                ;;
            '[B') # Down
                ((SELECTED++))
                ;;
        esac
    else
        # Handle regular keys
        cmd=""
        case "$key" in
            q) clear; exit 0 ;;
            s) action="start"; cmd="start" ;;
            x)
                STATUS_MSG="SHUTDOWN ${VM_NAMES[$SELECTED]}? (y/n)"
                draw
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="shutdown"; cmd="shutdown"
                else
                    STATUS_MSG="Shutdown cancelled"
                fi ;;
            f)
                STATUS_MSG="FORCE STOP ${VM_NAMES[$SELECTED]}? (y/n)"
                draw
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="force stop"; cmd="destroy"
                else
                    STATUS_MSG="Force stop cancelled"
                fi ;;
            r) action="reboot"; cmd="reboot" ;;
        esac

        if [[ -n "$cmd" && -n "${VM_NAMES[$SELECTED]}" ]]; then
            vm="${VM_NAMES[$SELECTED]}"
            STATUS_MSG="Performing $action on $vm..."
            draw
            virsh "$cmd" "$vm" >/dev/null 2>&1
            sleep 1
            fetch_vms
            STATUS_MSG="Command '$action' sent to $vm."
            cmd="" # Reset command
        fi
    fi
done

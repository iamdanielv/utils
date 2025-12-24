#!/bin/bash

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
BOLD='\033[1m'
REVERSE='\033[7m'
UNDERLINE='\033[4m'
NO_UNDERLINE='\033[24m'
NC='\033[0m' # No Color
CURSOR_HIDE='\033[?25l'
CURSOR_SHOW='\033[?25h'
CLEAR_LINE='\033[K'

# Icons
ICON_RUNNING="✔"
ICON_STOPPED="✘"
ICON_PAUSED="⏸"
ICON_UNKNOWN="?"

clear_screen() { printf '\033[H\033[J' >/dev/tty; }

# Trap to restore cursor on exit
trap 'echo -e "${CURSOR_SHOW}"; exit' EXIT INT TERM

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
declare -A VM_AUTOSTART
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
    
    local autostart_list
    autostart_list=$(virsh list --all --autostart --name)
    
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            VM_NAMES+=("$name")
            # Get state
            local state
            state=$(virsh domstate "$name" 2>/dev/null | tr -d '\n')
            VM_STATES+=("$state")
            
            if echo "$autostart_list" | grep -qFx "$name"; then
                VM_AUTOSTART["$name"]="Yes"
            else
                VM_AUTOSTART["$name"]="No"
            fi
            
            # Process Memory (KiB -> MiB/GiB)
            local mem_kib="${current_mems[$name]}"
            if [[ -n "$mem_kib" && "$mem_kib" -gt 0 ]]; then
                if (( mem_kib > 1048576 )); then
                    local gib=$(( mem_kib / 1048576 ))
                    VM_MEM_USAGE["$name"]="${gib} GiB"
                else
                    VM_MEM_USAGE["$name"]="$(( mem_kib / 1024 )) MiB"
                fi
            else
                VM_MEM_USAGE["$name"]="-"
            fi
            
            # Process CPU Usage
            local cpu_time="${current_cpu_times[$name]}"
            if [[ "$state" == "running" && -n "$cpu_time" && -n "${PREV_CPU_TIME[$name]}" && $time_diff -gt 0 ]]; then
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

# Function to show VM details
show_vm_details() {
    local vm="$1"
    
    clear_screen

    # show loading message
    printf "%b==VM Details: %bLoading...%b" "${CYAN}" "${YELLOW}" "${NC}"
    
    # Gather Info
    local dominfo
    dominfo=$(virsh dominfo "$vm")
    local state
    state=$(echo "$dominfo" | grep "^State:" | awk '{$1=""; print $0}' | xargs)
    local cpus
    cpus=$(echo "$dominfo" | grep "^CPU(s):" | awk '{print $2}')
    local max_mem_kib
    max_mem_kib=$(echo "$dominfo" | grep "^Max memory:" | awk '{print $3}')
    local autostart
    autostart=$(echo "$dominfo" | grep "^Autostart:" | awk '{print $2}')
    
    # Format Memory
    local mem_display=""
    if [[ -n "$max_mem_kib" ]]; then
        local mem_gib
        mem_gib=$(awk -v m="$max_mem_kib" 'BEGIN { printf "%.0f", m / 1048576 }')
        mem_display="$mem_gib GiB"
    else
        mem_display="Unknown"
    fi

    local state_color="$NC"
    local state_icon=""
    case "$state" in
        "running")
            state_color="$GREEN"
            state_icon="$ICON_RUNNING"
            ;;
        "shut off")
            state_color="$RED"
            state_icon="$ICON_STOPPED"
            ;;
        "paused")
            state_color="$YELLOW"
            state_icon="$ICON_PAUSED"
            ;;
        *)
            state_icon="$ICON_UNKNOWN"
            ;;
    esac

    local agent_status="Not Detected"
    local agent_color="$RED"
    local agent_hint=""
    local os_info=""
    if [[ "$state" == "running" ]]; then
        if virsh qemu-agent-command "$vm" '{"execute":"guest-ping"}' &>/dev/null; then
            agent_status="Running"
            agent_color="$GREEN"
            # Attempt to fetch OS info via guest agent
            local os_json
            os_json=$(virsh qemu-agent-command "$vm" '{"execute":"guest-get-osinfo"}' 2>/dev/null)
            if [[ -n "$os_json" ]]; then
                os_info=$(echo "$os_json" | grep -o '"pretty-name":"[^"]*"' | sed 's/"pretty-name":"//;s/"//')
            fi
        else
            agent_hint=" (Try: apt install qemu-guest-agent)"
        fi
    else
        agent_status="${REVERSE} VM Not Running ${REVERSE}"
        agent_color="${YELLOW}"
    fi

    local buffer=""
    buffer+="${CYAN}╭─VM Details: ${BOLD}${YELLOW}$vm${NC} (${REVERSE}${state_color}${state_icon}${state}${REVERSE}${NC})${CYAN}──────────────────────${NC}\n"
    
    local line
    printf -v line "  CPU(s): ${CYAN}%s${NC}\t Memory: ${CYAN}%s${NC}\t Autostart: ${CYAN}%s${NC}\n" "$cpus" "$mem_display" "$autostart"
    buffer+="$line"
    if [[ -n "$os_info" ]]; then
        printf -v line "  ${GREEN}Agent OS: ${CYAN}%s${NC}\n" "$os_info"
        buffer+="$line"
    else
        printf -v line "  Agent:  ${agent_color}%s${NC}%s\n" "$agent_status" "$agent_hint"
        buffer+="$line"
    fi

    local net_info
    local net_source="Agent"
    # Try agent first, then lease
    net_info=$(virsh domifaddr "$vm" --source agent 2>/dev/null)
    if [[ -z "$net_info" ]]; then
        net_info=$(virsh domifaddr "$vm" --source lease 2>/dev/null)
        net_source="Lease"
    fi
    
    local clean_net_info
    clean_net_info=$(echo "$net_info" | tail -n +3)
    if [[ -n "$clean_net_info" ]]; then
        buffer+="${BOLD}Network Interfaces (${CYAN}Source: $net_source${NC}${BOLD}):${NC}\n"
        while read -r iface mac proto addr; do
            [[ -z "$iface" ]] && continue
            local iface_disp="$iface"
            local mac_disp="$mac"
            [[ "$iface" == "-" ]] && iface_disp=""
            [[ "$mac" == "-" ]] && mac_disp=""
            printf -v line "  ${CYAN}%-10s${NC} ${BLUE}%-17s${NC} ${YELLOW}%-4s${NC} ${GREEN}%s${NC}\n" "$iface_disp" "$mac_disp" "$proto" "$addr"
            buffer+="$line"
        done <<< "$clean_net_info"
    else
        buffer+="${BOLD}Network Interfaces:${NC}\n"
        buffer+="  ${YELLOW}No IP address found (requires qemu-guest-agent or DHCP lease)${NC}\n"
    fi

    buffer+="${BOLD}Storage:${NC}\n"
    local blklist
    blklist=$(virsh domblklist "$vm" --details | tail -n +3)
    
    if [[ -z "$blklist" ]]; then
        buffer+="  No storage devices found.\n"
    else
        while read -r type device target source; do
            [[ -z "$target" ]] && continue
            
            if [[ "$source" == "-" && "$device" == "cdrom" ]]; then
                buffer+="  ${BOLD}Device: $target${NC} (${YELLOW}$device${NC}) - ${CYAN}(Empty)${NC}\n"
                continue
            fi

            buffer+="  ${BOLD}Device: $target${NC} (${YELLOW}$device${NC}) - Type: ${CYAN}${type}${NC}\n"
            
            if [[ "$source" == "-" ]]; then
                source="(unknown or passthrough)"
            fi
            buffer+="    Host path: ${CYAN}$source${NC}\n"
            
            local blk_info
            blk_info=$(virsh domblkinfo "$vm" "$target" 2>/dev/null)
            
            if [[ -n "$blk_info" ]]; then
                local cap
                cap=$(echo "$blk_info" | grep "Capacity:" | awk '{print $2}')
                local alloc
                alloc=$(echo "$blk_info" | grep "Allocation:" | awk '{print $2}')
                
                if [[ -n "$cap" && -n "$alloc" ]]; then
                    local usage_str
                    usage_str=$(awk -v c="$cap" -v a="$alloc" 'BEGIN { printf "%.0f/%.0f GiB", a/1073741824, c/1073741824 }')
                    buffer+="    Capacity: $usage_str\n"
                else
                    buffer+="    (No info available)\n"
                fi
            else
                buffer+="    (No info available)\n"
            fi
        done <<< "$blklist"
    fi

    buffer+="\n${BLUE}Press any key to return...${NC}\n"
    clear_screen
    printf "\033[H%b\033[J" "$buffer"
    read -rsn1
    clear_screen
}

# Function to render the main UI
render_main_ui() {
    # Double buffering to prevent flicker
    local buffer=""
    buffer+="${CYAN}╭─VM Manager────────────────────────────────────────────${NC}\n"
    local header
    printf -v header "${CYAN}│${NC} ${BOLD}${UNDERLINE}%-20s${NO_UNDERLINE} ${UNDERLINE}%-10s${NO_UNDERLINE} ${UNDERLINE}%-8s${NO_UNDERLINE} ${UNDERLINE}%-8s${NO_UNDERLINE} ${UNDERLINE}%-3s${NO_UNDERLINE}${NC}\n" "NAME" "STATE" "CPU" "MEM" "A/S"
    buffer+="$header"
        
    local count=${#VM_NAMES[@]}
    
    if [[ $count -eq 0 ]]; then
        buffer+="\n  ${YELLOW}No VMs defined on this host${NC}\n\n"
    else
        for ((i=0; i<count; i++)); do
            local name="${VM_NAMES[$i]}"
            local state="${VM_STATES[$i]}"
            local cpu="${VM_CPU_USAGE[$name]}"
            local mem="${VM_MEM_USAGE[$name]}"
            local autostart="${VM_AUTOSTART[$name]}"
            local autostart_display=""
            
            if [[ "$autostart" == "Yes" ]]; then
                autostart_display="${GREEN}Yes${NC}"
            else
                autostart_display="${RED}No ${NC}"
            fi

            local line_color="$NC"
            local state_color="$NC"
            local cursor="${CYAN}│${NC} "
            local state_icon=" "
            
            # Determine State Color
            case "$state" in
                "running")
                    state_color="$GREEN"
                    state_icon="$ICON_RUNNING"
                    ;;
                "shut off")
                    state_color="$RED"
                    state_icon="$ICON_STOPPED"
                    ;;
                "paused")
                    state_color="$YELLOW"
                    state_icon="$ICON_PAUSED"
                    ;;
                *)
                    state_color="$NC"
                    state_icon="$ICON_UNKNOWN"
                    ;;
            esac
            
            local state_display="${state_icon}${state}"
            
            # Highlight selection
            if [[ $i -eq $SELECTED ]]; then
                cursor="${CYAN}│❱${NC}"
                line_color="${BOLD}${BLUE}${REVERSE}"
            fi
            
            # Print line with padding
            local line_str
            printf -v line_str "${cursor}${line_color}%-20s ${state_color}%-12s${NC}${line_color} %-8s %-8s %b${NC}${CLEAR_LINE}\n" "$name" "$state_display" "$cpu" "$mem" "$autostart_display"
            buffer+="$line_str"
        done
    fi
    
    buffer+="${CYAN}╰───────────────────────────────────────────────────────${NC}\n"
    buffer+="${BLUE}╭Controls:──────────────────────────────────────────────${NC}\n"
    buffer+="${BLUE}│${NC} [${BOLD}${CYAN}↑/↓/j/k${NC}]Select  [${BOLD}${CYAN}S${NC}]tart   [${BOLD}${RED}X${NC}]Shutdown${CLEAR_LINE}\n"
    buffer+="${BLUE}╰${NC} [${BOLD}${RED}F${NC}]orce Stop     [${BOLD}${YELLOW}R${NC}]eboot  [${BOLD}${CYAN}I${NC}]nfo       [${BOLD}${RED}Q${NC}]uit${CLEAR_LINE}\n"
    if [[ -n "$STATUS_MSG" ]]; then
        buffer+="${YELLOW}╭Message:───────────────────────────────────────────────${NC}\n"
        buffer+="${YELLOW}╰${NC} ${BOLD}${STATUS_MSG}${NC}${CLEAR_LINE}\n"
    fi
    
    # Print buffer at home position and clear rest of screen
    printf "\033[H%b\033[J" "$buffer"
}

# Main Loop
echo -e "${CURSOR_HIDE}"
clear_screen
# Will render a skeleton UI before data is fetched
render_main_ui
fetch_vms
while true; do
    # Ensure selection is within bounds
    if [[ $SELECTED -ge ${#VM_NAMES[@]} ]]; then SELECTED=$((${#VM_NAMES[@]} - 1)); fi
    if [[ $SELECTED -lt 0 ]]; then SELECTED=0; fi

    render_main_ui

    # Read input (1 char) with 2s timeout for auto-refresh
    if ! read -rsn1 -t 2 key; then
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
            q|Q) clear_screen; exit 0 ;;
            k|K) ((SELECTED--)) ;;
            j|J) ((SELECTED++)) ;;
            i|I)
                if [[ -n "${VM_NAMES[$SELECTED]}" ]]; then
                    show_vm_details "${VM_NAMES[$SELECTED]}"
                fi
                ;;
            s|S)
                STATUS_MSG="${GREEN}START${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_main_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="start"; cmd="start"
                else
                    STATUS_MSG="${YELLOW}Start cancelled${NC}"
                fi ;;
            x|X)
                STATUS_MSG="${RED}SHUTDOWN${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_main_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="shutdown"; cmd="shutdown"
                else
                    STATUS_MSG="${YELLOW}Shutdown cancelled${NC}"
                fi ;;
            f|F)
                STATUS_MSG="${RED}FORCE STOP${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_main_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="force stop"; cmd="destroy"
                else
                    STATUS_MSG="${YELLOW}Force stop cancelled${NC}"
                fi ;;
            r|R)
                STATUS_MSG="${YELLOW}REBOOT${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_main_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="reboot"; cmd="reboot"
                else
                    STATUS_MSG="${YELLOW}Reboot cancelled${NC}"
                fi ;;
        esac

        if [[ -n "$cmd" && -n "${VM_NAMES[$SELECTED]}" ]]; then
            vm="${VM_NAMES[$SELECTED]}"
            STATUS_MSG="Performing $action on $vm..."
            render_main_ui
            virsh "$cmd" "$vm" >/dev/null 2>&1
            sleep 1
            fetch_vms
            STATUS_MSG="Command '$action' sent to $vm."
            cmd="" # Reset command
        fi
    fi
done

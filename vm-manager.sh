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
CURSOR_HIDE='\033[?25l'
CURSOR_SHOW='\033[?25h'

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
    clear
    
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
    case "$state" in
        "running") state_color="$GREEN" ;;
        "shut off") state_color="$RED" ;;
        "paused") state_color="$YELLOW" ;;
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
        agent_status="VM Not Running"
        agent_color="$YELLOW"
    fi

    echo -e "${CYAN}== VM Details: ${BOLD}${YELLOW}$vm${NC} (${state_color}$state${NC})${CYAN} ========================================${NC}"
    printf "   CPU(s): ${CYAN}%s${NC}\t Memory: ${CYAN}%s${NC}\t Autostart: ${CYAN}%s${NC}\n" "$cpus" "$mem_display" "$autostart"
    if [[ -n "$os_info" ]]; then
        printf "   ${GREEN}Agent OS: ${CYAN}%s${NC}\n" "$os_info"
    else
        printf "   Agent:  ${agent_color}%s${NC}%s\n" "$agent_status" "$agent_hint"
    fi

    local net_info
    local net_source="Agent"
    # Try agent first, then lease
    net_info=$(virsh domifaddr "$vm" --source agent 2>/dev/null)
    if [[ -z "$net_info" ]]; then
        net_info=$(virsh domifaddr "$vm" --source lease 2>/dev/null)
        net_source="Lease"
    fi
    
    local clean_net_info=$(echo "$net_info" | tail -n +3)
    if [[ -n "$clean_net_info" ]]; then
        echo -e "${BOLD}Network Interfaces (${CYAN}Source: $net_source${NC}${BOLD}):${NC}"
        while read -r iface mac proto addr; do
            [[ -z "$iface" ]] && continue
            local iface_disp="$iface"
            local mac_disp="$mac"
            [[ "$iface" == "-" ]] && iface_disp=""
            [[ "$mac" == "-" ]] && mac_disp=""
            printf "  ${CYAN}%-10s${NC} ${BLUE}%-17s${NC} ${YELLOW}%-4s${NC} ${GREEN}%s${NC}\n" "$iface_disp" "$mac_disp" "$proto" "$addr"
        done <<< "$clean_net_info"
    else
        echo -e "${BOLD}Network Interfaces:${NC}"
        echo -e "  ${YELLOW}No IP address found (requires qemu-guest-agent or DHCP lease)${NC}"
    fi

    echo -e "${BOLD}Storage:${NC}"
    local blklist
    blklist=$(virsh domblklist "$vm" | tail -n +3)
    
    if [[ -z "$blklist" ]]; then
        echo "  No storage devices found."
    else
        while read -r target source; do
            [[ -z "$target" ]] && continue
            echo -e "  ${BOLD}Device: $target${NC}"
            
            if [[ "$source" == "-" ]]; then
                source="(unknown or passthrough)"
            fi
            echo -e "    Host path: ${CYAN}$source${NC}"
            
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
                    echo "    Capacity: $usage_str"
                else
                    echo "    (No info available)"
                fi
            else
                echo "    (No info available)"
            fi
        done <<< "$blklist"
    fi

    echo -e "\n${BLUE}Press any key to return...${NC}"
    read -rsn1
}

# Function to render the UI
render_ui() {
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
    echo -e " [${BOLD}${CYAN}↑/↓/j/k${NC}]Select [${BOLD}${CYAN}S${NC}]tart      [${BOLD}${RED}X${NC}]Shutdown"
    echo -e " [${BOLD}${RED}F${NC}]orce Stop    [${BOLD}${YELLOW}R${NC}]eboot     [${BOLD}${CYAN}I${NC}]nfo     [${BOLD}${RED}Q${NC}]uit"
}

# Main Loop
echo -e "${CURSOR_HIDE}"
fetch_vms
while true; do
    # Ensure selection is within bounds
    if [[ $SELECTED -ge ${#VM_NAMES[@]} ]]; then SELECTED=$((${#VM_NAMES[@]} - 1)); fi
    if [[ $SELECTED -lt 0 ]]; then SELECTED=0; fi

    render_ui

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
            q|Q) clear; exit 0 ;;
            k|K) ((SELECTED--)) ;;
            j|J) ((SELECTED++)) ;;
            i|I)
                if [[ -n "${VM_NAMES[$SELECTED]}" ]]; then
                    show_vm_details "${VM_NAMES[$SELECTED]}"
                fi
                ;;
            s|S)
                STATUS_MSG="${GREEN}START${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="start"; cmd="start"
                else
                    STATUS_MSG="${YELLOW}Start cancelled${NC}"
                fi ;;
            x|X)
                STATUS_MSG="${RED}SHUTDOWN${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="shutdown"; cmd="shutdown"
                else
                    STATUS_MSG="${YELLOW}Shutdown cancelled${NC}"
                fi ;;
            f|F)
                STATUS_MSG="${RED}FORCE STOP${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_ui
                read -rsn1 confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    action="force stop"; cmd="destroy"
                else
                    STATUS_MSG="${YELLOW}Force stop cancelled${NC}"
                fi ;;
            r|R)
                STATUS_MSG="${YELLOW}REBOOT${NC} ${VM_NAMES[$SELECTED]}? (y/n)"
                render_ui
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
            render_ui
            virsh "$cmd" "$vm" >/dev/null 2>&1
            sleep 1
            fetch_vms
            STATUS_MSG="Command '$action' sent to $vm."
            cmd="" # Reset command
        fi
    fi
done

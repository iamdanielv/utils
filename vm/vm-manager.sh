#!/bin/bash

# Colors
readonly RED=$'\033[31m'
readonly GREEN=$'\033[32m'
readonly YELLOW=$'\033[33m'
readonly BLUE=$'\033[34m'
readonly CYAN=$'\033[36m'
readonly GRAY=$'\033[38;5;244m'
readonly BOLD=$'\033[1m'
readonly REVERSE=$'\033[7m'
readonly UNDERLINE=$'\033[4m'
readonly NO_UNDERLINE=$'\033[24m'
readonly NC=$'\033[0m' # No Color
readonly CURSOR_HIDE=$'\033[?25l'
readonly CURSOR_SHOW=$'\033[?25h'
readonly CLEAR_LINE=$'\033[K'

# Icons
readonly ICON_RUNNING="✔"
readonly ICON_STOPPED="✘"
readonly ICON_PAUSED="⏸"
readonly ICON_UNKNOWN="?"

clear_screen() { printf '\033[H\033[J' >/dev/tty; }
move_cursor_up() { local lines=${1:-1}; if (( lines > 0 )); then for ((i = 0; i < lines; i++)); do printf '\033[1A'; done; fi; printf '\r'; } >/dev/tty

# Trap to restore cursor on exit
trap 'printf "%b" "${CURSOR_SHOW}"; exit' EXIT INT TERM

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
declare -A PREV_CPU_TIME=()
declare -A VM_AUTOSTART
LAST_TIMESTAMP=0
SELECTED=0
STATUS_MSG=""
MSG_TITLE=""
MSG_COLOR=""
MSG_INPUT=""
CMD_OUTPUT=""
HAS_ERROR=false

# Function to fetch VM data
fetch_vms() {
    VM_NAMES=()
    VM_STATES=()
    
    # Capture current time in nanoseconds for CPU calc
    local current_timestamp time_diff
    current_timestamp=$(date +%s%N)
    time_diff=$(( current_timestamp - LAST_TIMESTAMP ))
    
    # Fetch bulk stats (CPU time in ns, Memory in KiB)
    local stats_output
    stats_output=$(virsh domstats --cpu-total --balloon --state 2>/dev/null)
    
    local -A current_cpu_times
    local -A current_mems=()
    local -A current_states_int
    local current_vm=""
    
    # Parse domstats output
    while read -r line; do
        if [[ "$line" =~ ^Domain:\ \'(.*)\' ]]; then
            current_vm="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ cpu\.time=([0-9]+) ]]; then
            current_cpu_times["$current_vm"]="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ balloon\.current=([0-9]+) ]]; then
            current_mems["$current_vm"]="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ state\.state=([0-9]+) ]]; then
            current_states_int["$current_vm"]="${BASH_REMATCH[1]}"
        fi
    done <<< "$stats_output"
    
    # Get all VM names, sorted, removing empty lines
    local raw_names
    raw_names=$(virsh list --all --name | sort | sed '/^$/d')
    
    # Optimize autostart check: Load into map to avoid grep in loop
    local -A autostart_map
    while read -r name; do
        [[ -n "$name" ]] && autostart_map["$name"]=1
    done < <(virsh list --all --autostart --name)
    
    while IFS= read -r name; do
        if [[ -n "$name" ]]; then
            VM_NAMES+=("$name")
            # Get state
            local state_int="${current_states_int[$name]-}"
            local state="unknown"
            case "$state_int" in
                1) state="running" ;;
                2) state="blocked" ;;
                3) state="paused" ;;
                4) state="shutdown" ;;
                5) state="shut off" ;;
                6) state="crashed" ;;
                7) state="pmsuspended" ;;
            esac
            VM_STATES+=("$state")
            
            if [[ -n "${autostart_map[$name]-}" ]]; then
                VM_AUTOSTART["$name"]="Yes"
            else
                VM_AUTOSTART["$name"]="No"
            fi
            
            # Process Memory (KiB -> MiB/GiB)
            local mem_kib="${current_mems[$name]-}"
            if [[ -n "$mem_kib" && "$mem_kib" -gt 0 ]]; then
                if (( mem_kib >= 1048576 )); then
                    local gib=$(( mem_kib / 1048576 ))
                    VM_MEM_USAGE["$name"]="${gib} GiB"
                else
                    VM_MEM_USAGE["$name"]="$(( mem_kib / 1024 )) MiB"
                fi
            else
                VM_MEM_USAGE["$name"]="-"
            fi
            
            # Process CPU Usage
            local cpu_time="${current_cpu_times[$name]-}"
            if [[ "$state" == "running" && -n "$cpu_time" && -n "${PREV_CPU_TIME[$name]-}" && $time_diff -gt 0 ]]; then
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

# Helper to set state colors and icons
set_state_visuals() {
    local state="$1"
    STATE_COLOR="${NC}"
    STATE_ICON="${ICON_UNKNOWN}"
    
    case "$state" in
        "running")
            STATE_COLOR="$GREEN"
            STATE_ICON="$ICON_RUNNING"
            ;;
        "shut off")
            STATE_COLOR="$RED"
            STATE_ICON="$ICON_STOPPED"
            ;;
        "paused")
            STATE_COLOR="$YELLOW"
            STATE_ICON="$ICON_PAUSED"
            ;;
    esac
}

append_network_info() {
    local vm="$1"
    local -n buf="$2"
    
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
        buf+=$(printBanner "Network Interfaces (${CYAN}Source: $net_source${NC})" "$BLUE")
        buf+="\n"
        while read -r iface mac proto addr; do
            [[ -z "$iface" ]] && continue
            local iface_disp="$iface"
            local mac_disp="$mac"
            [[ "$iface" == "-" ]] && iface_disp=""
            [[ "$mac" == "-" ]] && mac_disp=""
            printf -v line "  ${CYAN}%-10s${NC} ${BLUE}%-17s${NC} ${YELLOW}%-4s${NC} ${GREEN}%s${NC}\n" "$iface_disp" "$mac_disp" "$proto" "$addr"
            buf+="$line"
        done <<< "$clean_net_info"
    else
        buf+=$(printBanner "Network Interfaces" "$BLUE")
        buf+="\n"
        buf+="  ${YELLOW}No IP address found (requires qemu-guest-agent or DHCP lease)${NC}\n"
    fi
}

append_storage_info() {
    local vm="$1"
    local -n buf="$2"

    buf+=$(printBanner "Storage" "$BLUE")
    buf+="\n"
    local blklist
    blklist=$(virsh domblklist "$vm" --details | tail -n +3)
    
    if [[ -z "$blklist" ]]; then
        buf+="  No storage devices found.\n"
    else
        while read -r type device target source; do
            [[ -z "$target" ]] && continue
            
            if [[ "$source" == "-" && "$device" == "cdrom" ]]; then
                buf+="  ${BOLD}Device: $target${NC} (${YELLOW}$device${NC}) - ${CYAN}(Empty)${NC}\n"
                continue
            fi

            buf+="  ${BOLD}Device: $target${NC} (${YELLOW}$device${NC}) - Type: ${CYAN}${type}${NC}\n"
            
            if [[ "$source" == "-" ]]; then
                source="(unknown or passthrough)"
            fi
            buf+="    Host path: ${CYAN}$source${NC}\n"
            
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
                    buf+="    Capacity: $usage_str\n"
                else
                    buf+="    (No info available)\n"
                fi
            else
                buf+="    (No info available)\n"
            fi
        done <<< "$blklist"
    fi
}

# Function to show VM details
show_vm_details() {
    local vm="$1"
    
    clear_screen

    # show loading message
    printBanner "VM Details: ${BOLD}${YELLOW}Loading..." "${CYAN}"
    
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

    set_state_visuals "$state"
    local state_color="$STATE_COLOR"
    local state_icon="$STATE_ICON"

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
    buffer+=$(printBanner "VM Details: ${BOLD}${YELLOW}$vm${NC} (${REVERSE}${state_color} ${state_icon} ${state} ${REVERSE}${NC})" "$CYAN")
    buffer+="\n"
    
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

    append_network_info "$vm" buffer
    append_storage_info "$vm" buffer

    buffer+="\n${BLUE}Press any key to return...${NC}\n"
    printf "\033[H%b\033[J" "$buffer"
    read -rsn1
    clear_screen
}

# Function to show help overlay
show_help() {
    clear_screen
    local buffer=""
    buffer+=$(printBanner "Help & Shortcuts" "$CYAN")
    buffer+="\n"
    
    buffer+=$(printBanner "Navigation" "\033[38;5;216m")
    buffer+="\n"
    buffer+="  ${CYAN}↓${NC}/${CYAN}↑${NC} or ${CYAN}j${NC}/${CYAN}k${NC}  Select VM from the list\n"
    
    buffer+=$(printBanner "Power Actions" "\033[38;5;216m")
    buffer+="\n"
    buffer+="  ${CYAN}S${NC}           Start VM\n"
    buffer+="  ${CYAN}X${NC}           Shutdown (ACPI signal)\n"
    buffer+="  ${CYAN}F${NC}           Force Stop (Hard power off)\n"
    buffer+="  ${CYAN}R${NC}           Reboot\n"
    
    buffer+=$(printBanner "Management" "\033[38;5;216m")
    buffer+="\n"
    buffer+="  ${CYAN}C${NC}           Clone VM\n"
    buffer+="  ${CYAN}D${NC}           Delete VM\n"
    buffer+="  ${CYAN}I${NC}           Show Details (IP, Disk, Network)\n"
    
    buffer+=$(printBanner "Other" "\033[38;5;216m")
    buffer+="\n"
    buffer+="  ${CYAN}Q${NC}           Quit\n"
    buffer+="  ${CYAN}?${NC}/${CYAN}h${NC}         Show this help\n"
    
    buffer+="\n${BLUE}Press any key to return...${NC}\n"
    
    printf "\033[H%b\033[J" "$buffer"
    read -rsn1
    clear_screen
}

# Check if a VM is selected
require_vm_selected() {
    if [[ -z "${VM_NAMES[$SELECTED]}" ]]; then
        STATUS_MSG="${YELLOW}No VM selected${NC}"
        HAS_ERROR=true
        return 1
    fi
    return 0
}

# Helper for yes/no confirmation
ask_confirmation() {
    local prompt="$1"
    STATUS_MSG="${prompt} (y/n)"
    render_main_ui
    local key
    read -rsn1 key
    [[ "$key" == "y" || "$key" == "Y" ]]
}

# Helper to format and set a wrapped error status message
set_error_status() {
    local prefix="$1"
    local error_text="$2"
    local terminal_width=70
    # Width available for text inside the message box.
    # ╰ (1) + space (1) = 2 chars for prefix on first line.
    # Subsequent lines are indented by 2 spaces.
    local wrap_width=$(( terminal_width - 2 ))

    # Remove redundant "error: " if it exists at the start of the string
    if [[ "$error_text" == "error: "* ]]; then
        error_text="${error_text#error: }"
    fi
    # Capitalize the first letter of the cleaned error
    error_text="$(tr '[:lower:]' '[:upper:]' <<< "${error_text:0:1}")${error_text:1}"

    # Combine prefix and wrapped text, then fold it
    STATUS_MSG=$(echo "${prefix}${error_text}" | fold -s -w "$wrap_width")
    HAS_ERROR=true
    MSG_COLOR="$RED"
    MSG_TITLE="Error"
}

# Helper to run a command with a spinner
run_with_spinner() {
    local message="$1"
    shift
    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"
    local spinner_idx=0
    local temp_out
    temp_out=$(mktemp)
    
    "$@" > "$temp_out" 2>&1 &
    local pid=$!
    
    STATUS_MSG="${message}  "
    render_main_ui
    local color="${MSG_COLOR:-$YELLOW}"
    
    while kill -0 "$pid" 2>/dev/null; do
        local char="${spinner_chars:spinner_idx:1}"
        local current_msg="${message} ${char}"
        printf "\033[1A\r${color}╰${NC} ${BOLD}${current_msg}${NC}${CLEAR_LINE}\n"
        spinner_idx=$(( (spinner_idx + 1) % ${#spinner_chars} ))
        sleep 0.1
    done
    
    wait "$pid"
    local exit_code=$?
    CMD_OUTPUT=$(<"$temp_out")
    rm -f "$temp_out"
    
    return $exit_code
}

# Function to handle Clone VM
handle_clone_vm() {
    require_vm_selected || return

    if ! command -v virt-clone &> /dev/null; then
        STATUS_MSG="${RED}Error: 'virt-clone' not found. Install 'virtinst'.${NC}"
        HAS_ERROR=true
        return
    fi

    local default_name="${VM_NAMES[$SELECTED]}-c"
    MSG_TITLE="CLONE ${VM_NAMES[$SELECTED]}? (empty name to cancel)"
    MSG_COLOR="\033[38;5;216m"
    MSG_INPUT="true"
    STATUS_MSG="" # Clear any previous status
    render_main_ui
    echo -ne "${CURSOR_SHOW}"
    read -e -p " Enter new name: " -i "$default_name" -r new_name
    echo -e "${CURSOR_HIDE}"
    MSG_INPUT="false"
    if [[ -n "$new_name" ]]; then
        # Validate VM name: alphanumeric, dot, underscore, hyphen only
        if [[ ! "$new_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            STATUS_MSG="${RED}Error: Invalid name. Use only a-z, 0-9, ., _, - (no spaces).${NC}"
            HAS_ERROR=true
            return
        fi

        # Check if name already exists
        for existing_vm in "${VM_NAMES[@]}"; do
            if [[ "$existing_vm" == "$new_name" ]]; then
                STATUS_MSG="${RED}Error: VM '$new_name' already exists.${NC}"
                HAS_ERROR=true
                return
            fi
        done


        if run_with_spinner "Cloning ${VM_NAMES[$SELECTED]} to $new_name... (Please wait)" \
            virt-clone --original "${VM_NAMES[$SELECTED]}" --name "$new_name" --auto-clone; then
            STATUS_MSG="${GREEN}Clone successful: $new_name${NC}"
            fetch_vms
        else
            set_error_status "Clone failed: " "$CMD_OUTPUT"
        fi
    else
        STATUS_MSG="${YELLOW}Clone cancelled.${NC}"
    fi
}

# Function to handle Delete VM
handle_delete_vm() {
    require_vm_selected || return
    local vm="${VM_NAMES[$SELECTED]}"

    if ! ask_confirmation "${RED}DELETE${NC} $vm?"; then
        STATUS_MSG="${YELLOW}Delete cancelled.${NC}"
        return
    fi

    local remove_storage_flag=""
    if ask_confirmation "Also remove storage volumes?"; then
        remove_storage_flag="--remove-all-storage"
    fi

    _perform_delete() {
        if [[ "${VM_STATES[$SELECTED]}" == "running" || "${VM_STATES[$SELECTED]}" == "paused" ]]; then
            virsh destroy "$vm" >/dev/null 2>&1 || true
        fi
        virsh undefine "$vm" $remove_storage_flag
    }

    if run_with_spinner "Deleting $vm..." _perform_delete; then
        STATUS_MSG="${GREEN}Deleted $vm${NC}"
        fetch_vms
    else
        set_error_status "Delete failed: " "$CMD_OUTPUT"
    fi
}

# Function to handle VM actions (Start, Stop, etc.)
handle_vm_action() {
    local color="$1"
    local display_name="$2"
    local action_name="$3"
    local virsh_cmd="$4"

    require_vm_selected || return

    if ask_confirmation "${color}${display_name}${NC} ${VM_NAMES[$SELECTED]}?"; then
        action="$action_name"
        cmd="$virsh_cmd"
    else
        local cancel_name="${display_name,,}"
        STATUS_MSG="${YELLOW}${cancel_name^} cancelled${NC}"
    fi
}

printBanner() {
    local msg="$1"
    local color="${2:-$BLUE}"
    local line="────────────────────────────────────────────────────────────────────────"
    printf "${color}${line}${NC}\r${color}╭─${msg}${NC}"
}

# Function to render the main UI
render_main_ui() {
    # Double buffering to prevent flicker
    local buffer=""
    buffer+=$(printBanner "VM Manager" "$CYAN")
    buffer+="\n"
    local header
    printf -v header "${CYAN}│${NC} ${BOLD}${UNDERLINE}%-20s${NO_UNDERLINE} ${UNDERLINE}%-10s${NO_UNDERLINE} ${UNDERLINE}%-8s${NO_UNDERLINE} ${UNDERLINE}%-8s${NO_UNDERLINE} ${UNDERLINE}%-3s${NO_UNDERLINE}${NC}\n" "NAME" "STATE" "CPU" "MEM" "A/S"
    buffer+="$header"
        
    local count=${#VM_NAMES[@]}
    
    if [[ $count -eq 0 ]]; then
        buffer+="${CYAN}│${NC}  ${YELLOW}No VMs defined on this host${NC}\n"
    else
        for ((i=0; i<count; i++)); do
            local name="${VM_NAMES[$i]}"
            local state="${VM_STATES[$i]-unknown}"
            local cpu="${VM_CPU_USAGE[$name]-}"
            local mem="${VM_MEM_USAGE[$name]-}"
            local autostart="${VM_AUTOSTART[$name]-}"
            local autostart_display=""
            
            if [[ "$autostart" == "Yes" ]]; then
                autostart_display="${GREEN}Yes${NC}"
            else
                autostart_display="${RED}No ${NC}"
            fi

            local line_color="$NC"
            local row_text_color="$GRAY"
            local cursor="${CYAN}│${NC} "
            
            set_state_visuals "$state"
            local state_color="$STATE_COLOR"
            local state_icon="$STATE_ICON"
            
            if [[ "$state" == "running" ]]; then
                row_text_color="${NC}"
            fi
            
            # Truncate name if too long (max 20 chars)
            if (( ${#name} > 20 )); then name="${name:0:19}…"; fi
            
            local state_display="${state_icon} ${state}"
            
            # Highlight selection
            if [[ $i -eq $SELECTED ]]; then
                cursor="${CYAN}│❱${NC}"
                line_color="${BOLD}${BLUE}${REVERSE}"
                row_text_color=""
            fi
            
            # Print line with padding
            local line_str
            printf -v line_str "${cursor}${line_color}${row_text_color}%-20s${NC}${line_color} ${state_color}%-12s${NC}${line_color} ${row_text_color}%-8s %-8s${NC}${line_color} %b${NC}${CLEAR_LINE}\n" "$name" "$state_display" "$cpu" "$mem" "$autostart_display"
            buffer+="$line_str"
        done
    fi
    
    buffer+="${CYAN}╰───────────────────────────────────────────────────────────────────────${NC}\n"
    buffer+=$(printBanner "Controls:" "$BLUE")
    buffer+="\n"
    buffer+="${BLUE}│${NC} [${BOLD}${CYAN}↓/↑/j/k${NC}]Select  [${BOLD}${CYAN}S${NC}]tart   [${BOLD}${RED}X${NC}]Shutdown  [${BOLD}${CYAN}C${NC}]lone${CLEAR_LINE}\n"
    buffer+="${BLUE}╰${NC} [${BOLD}${RED}F${NC}]orce Stop     [${BOLD}${YELLOW}R${NC}]eboot  [${BOLD}${CYAN}I${NC}]nfo  [${BOLD}${RED}D${NC}]elete  [${BOLD}${RED}Q${NC}]uit  [${BOLD}${CYAN}?${NC}]Help${CLEAR_LINE}\n"

    if [[ -n "$STATUS_MSG" || -n "$MSG_TITLE" ]]; then
        local title="${MSG_TITLE:-Message:}"
        local color="${MSG_COLOR:-$YELLOW}"
        buffer+=$(printBanner "$title" "$color")
        buffer+="\n"
        if [[ "$MSG_INPUT" == "true" ]]; then
            buffer+="${color}╰${NC} "
        else
            local first_line=true
            while IFS= read -r line; do
                if [[ "$first_line" == "true" ]]; then
                    buffer+="${color}╰${NC} ${BOLD}${line}${NC}${CLEAR_LINE}\n"
                    first_line=false
                else
                    buffer+="  ${BOLD}${line}${NC}${CLEAR_LINE}\n"
                fi
            done <<< "$STATUS_MSG"
        fi
    fi
    
    # Print buffer at home position and clear rest of screen
    printf "\033[H%b\033[J" "$buffer"
}

# Main Loop
echo -e "${CURSOR_HIDE}"
clear_screen

# Handle window resize
trap 'clear_screen; render_main_ui' WINCH

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
        if [[ "$HAS_ERROR" != "true" ]]; then
            fetch_vms
            STATUS_MSG=""
            MSG_TITLE=""
            MSG_COLOR=""
            MSG_INPUT=""
        fi
        continue
    fi

    STATUS_MSG=""
    MSG_TITLE=""
    MSG_COLOR=""
    MSG_INPUT=""
    HAS_ERROR=false
    
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
        action=""
        case "$key" in
            q|Q) clear_screen; exit 0 ;;
            k|K) ((SELECTED--)) ;;
            j|J) ((SELECTED++)) ;;
            i|I)
                require_vm_selected && show_vm_details "${VM_NAMES[$SELECTED]}"
                ;;
            \?|h|H)
                show_help ;;
            c|C)
                handle_clone_vm ;;
            d|D)
                handle_delete_vm ;;
            s|S)
                handle_vm_action "$GREEN" "START" "start" "start" ;;
            x|X)
                handle_vm_action "$RED" "SHUTDOWN" "shutdown" "shutdown" ;;
            f|F)
                handle_vm_action "$RED" "FORCE STOP" "force stop" "destroy" ;;
            r|R)
                handle_vm_action "$YELLOW" "REBOOT" "reboot" "reboot" ;;
        esac

        if [[ -n "$cmd" && -n "${VM_NAMES[$SELECTED]}" ]]; then
            vm="${VM_NAMES[$SELECTED]}"
            if run_with_spinner "Performing $action on $vm..." virsh "$cmd" "$vm"; then
                fetch_vms
                STATUS_MSG="Command '$action' sent to $vm"
            else
                set_error_status "Error: " "$CMD_OUTPUT"
            fi
            cmd="" # Reset command
        fi
    fi
done

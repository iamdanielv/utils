#!/bin/bash

declare -rx C_RED=$'\033[31m'
declare -rx C_GREEN=$'\033[32m'
declare -rx C_YELLOW=$'\033[33m'
declare -rx C_BLUE=$'\033[34m'
declare -rx C_MAGENTA=$'\033[35m'
declare -rx C_CYAN=$'\033[36m'
declare -rx C_WHITE=$'\033[37m'
declare -rx C_GRAY=$'\033[38;5;244m'
declare -rx C_ORANGE=$'\033[38;5;216m'
declare -rx C_MAUVE=$'\033[38;5;99m'

readonly T_RESET=$'\033[0m'
readonly T_BOLD=$'\033[1m'
readonly T_ULINE=$'\033[4m'
readonly T_NO_ULINE=$'\033[24m'
readonly T_REVERSE=$'\033[7m'
readonly T_NO_REVERSE=$'\033[27m'
readonly T_CLEAR_LINE=$'\033[K'
readonly T_CURSOR_HIDE=$'\033[?25l'
readonly T_CURSOR_SHOW=$'\033[?25h'
readonly T_CURSOR_HOME=$'\033[H'
readonly T_CLEAR_SCREEN_DOWN=$'\033[J'
readonly T_CURSOR_UP=$'\033[1A'
readonly T_CURSOR_DOWN=$'\033[1B'
readonly T_CURSOR_LEFT=$'\033[1D'
readonly T_CURSOR_RIGHT=$'\033[1C'
readonly T_CLEAR_WHOLE_LINE=$'\033[2K'

readonly KEY_ESC=$'\033'
readonly KEY_ENTER="ENTER"
readonly KEY_UP=$'\033[A'
readonly KEY_DOWN=$'\033[B'
readonly KEY_RIGHT=$'\033[C'
readonly KEY_LEFT=$'\033[D'
readonly KEY_BACKSPACE=$'\x7f'
readonly KEY_HOME=$'\033[H'
readonly KEY_END=$'\033[F'
readonly KEY_DELETE=$'\033[3~'

# Icons
readonly ICON_ERR="[${T_BOLD}${C_RED}✗${T_RESET}]"
readonly ICON_OK="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
readonly ICON_INFO="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
readonly ICON_WARN="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
readonly ICON_QST="[${T_BOLD}${C_CYAN}?${T_RESET}]"
readonly ICON_RUNNING="✔"
readonly ICON_STOPPED="✘"
readonly ICON_PAUSED="⏸"
readonly ICON_UNKNOWN="?"

printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }

printBanner() {
	local msg="$1"
	local color="${2:-$C_BLUE}"
	local start_char="${3:-╭}"
	local line="────────────────────────────────────────────────────────────────────────"
	printf "${color}${line}${T_RESET}${T_CLEAR_LINE}\r${color}${start_char}─${msg}${T_RESET}"
}

printBannerMiddle() {
	local msg="$1"
	local color="${2:-$C_BLUE}"
	printBanner "$msg" "$color" "├"
}

strip_ansi_codes() {
	local s="$1"
	local esc=$'\033'
	if [[ "$s" != *"$esc"* ]]; then
		echo -n "$s"
		return
	fi
	local pattern="$esc\\[[0-9;]*[a-zA-Z]"
	while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
	echo -n "$s"
}

_truncate_string() {
	local input_str="$1"
	local max_len="$2"
	local trunc_char="${3:-…}"
	local trunc_char_len=${#trunc_char}
	local stripped_str
	stripped_str=$(strip_ansi_codes "$input_str")
	local len=${#stripped_str}
	if ((len <= max_len)); then
		echo -n "$input_str"
		return
	fi
	local truncate_to_len=$((max_len - trunc_char_len))
	local new_str=""
	local visible_count=0
	local i=0
	local in_escape=false
	while ((i < ${#input_str} && visible_count < truncate_to_len)); do
		local char="${input_str:i:1}"
		new_str+="$char"
		if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then ((visible_count++)); fi
		if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi
		((i++))
	done
	echo -n "${new_str}${trunc_char}"
}

_format_fixed_width_string() {
	local input_str="$1"
	local max_len="$2"
	local trunc_char="${3:-…}"
	local pad_str="${4:- }"
	local stripped_input
	stripped_input=$(strip_ansi_codes "$input_str")
	local input_len=${#stripped_input}

	if ((input_len > max_len)); then
		_truncate_string "$input_str" "$max_len" "$trunc_char"
		return
	fi

	local padding_needed=$((max_len - input_len))
	if ((padding_needed == 0)); then
		printf "%s" "$input_str"
		return
	fi

	local stripped_pad
	stripped_pad=$(strip_ansi_codes "$pad_str")
	local pad_len=${#stripped_pad}
	if ((pad_len == 0)); then
		pad_str=" "
		pad_len=1
	fi

	local full_repeats=$((padding_needed / pad_len))
	local remainder=$((padding_needed % pad_len))
	local padding=""
	for ((i = 0; i < full_repeats; i++)); do padding+="$pad_str"; done
	if ((remainder > 0)); then
		local partial
		partial=$(_truncate_string "$pad_str" "$remainder" "")
		padding+="$partial"
	fi

	printf "%s%s" "$input_str" "$padding"
}

read_single_char() {
	local timeout="${1:-}"
	local char
	local seq
	if [[ -n "$timeout" ]]; then
		if ! IFS= read -rsn1 -t "$timeout" char </dev/tty; then return 1; fi
	else
		IFS= read -rsn1 char </dev/tty
	fi
	if [[ -z "$char" ]]; then
		echo "$KEY_ENTER"
		return 0
	fi
	if [[ "$char" == "$KEY_ESC" ]]; then
		if IFS= read -rsn1 -t 0.001 seq </dev/tty; then
			char+="$seq"
			if [[ "$seq" == "[" || "$seq" == "O" ]]; then while IFS= read -rsn1 -t 0.001 seq </dev/tty; do
				char+="$seq"
				if [[ "$seq" =~ [a-zA-Z~] ]]; then break; fi
			done; fi
		fi
	fi
	echo "$char"
}

clear_current_line() { printf "${T_CLEAR_WHOLE_LINE}\r" >/dev/tty; }
clear_lines_up() {
	local lines=${1:-1}
	for ((i = 0; i < lines; i++)); do printf "${T_CURSOR_UP}${T_CLEAR_WHOLE_LINE}"; done
	printf '\r'
} >/dev/tty
clear_screen() { printf "${T_CURSOR_HOME}${T_CLEAR_SCREEN_DOWN}" >/dev/tty; }
move_cursor_up() {
	local lines=${1:-1}
	if ((lines > 0)); then for ((i = 0; i < lines; i++)); do printf "${T_CURSOR_UP}"; done; fi
	printf '\r'
} >/dev/tty
render_buffer() { printf "${T_CURSOR_HOME}%b${T_CLEAR_SCREEN_DOWN}" "$1"; }

# Trap to restore cursor on exit
trap 'printf "%b" "${T_CURSOR_SHOW}"; exit' EXIT INT TERM

# Check dependencies
if ! command -v virsh &>/dev/null; then
	echo -e "${C_RED}Error: 'virsh' command not found. Please install libvirt-clients${T_RESET}"
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
	time_diff=$((current_timestamp - LAST_TIMESTAMP))

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
	done <<<"$stats_output"

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
				if ((mem_kib >= 1048576)); then
					local gib=$((mem_kib / 1048576))
					VM_MEM_USAGE["$name"]="${gib} GiB"
				else
					VM_MEM_USAGE["$name"]="$((mem_kib / 1024)) MiB"
				fi
			else
				VM_MEM_USAGE["$name"]="-"
			fi

			# Process CPU Usage
			local cpu_time="${current_cpu_times[$name]-}"
			if [[ "$state" == "running" && -n "$cpu_time" && -n "${PREV_CPU_TIME[$name]-}" && $time_diff -gt 0 ]]; then
				local cpu_diff=$((cpu_time - PREV_CPU_TIME[$name]))
				# Usage % = (cpu_diff_ns / time_diff_ns) * 100. Multiply by 1000 for 1 decimal place.
				local usage=$((cpu_diff * 1000 / time_diff))
				if ((usage < 10)); then
					VM_CPU_USAGE["$name"]="0.${usage}%"
				else
					VM_CPU_USAGE["$name"]="${usage:0:-1}.${usage: -1}%"
				fi
			else
				VM_CPU_USAGE["$name"]="---"
			fi
			PREV_CPU_TIME["$name"]="$cpu_time"
		fi
	done <<<"$raw_names"

	LAST_TIMESTAMP="$current_timestamp"
}

# Helper to set state colors and icons
set_state_visuals() {
	local state="$1"
	STATE_COLOR="${T_RESET}"
	STATE_ICON="${ICON_UNKNOWN}"

	case "$state" in
	"running")
		STATE_COLOR="$C_GREEN"
		STATE_ICON="$ICON_RUNNING"
		;;
	"shut off")
		STATE_COLOR="$C_RED"
		STATE_ICON="$ICON_STOPPED"
		;;
	"paused")
		STATE_COLOR="$C_YELLOW"
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
		buf+=$(printBanner "Network Interfaces (${C_CYAN}Source: $net_source${T_RESET})" "$C_BLUE")
		buf+="\n"
		while read -r iface mac proto addr; do
			[[ -z "$iface" ]] && continue
			local iface_disp="$iface"
			local mac_disp="$mac"
			[[ "$iface" == "-" ]] && iface_disp=""
			[[ "$mac" == "-" ]] && mac_disp=""
			printf -v line "  ${C_CYAN}%-10s${T_RESET} ${C_BLUE}%-17s${T_RESET} ${C_YELLOW}%-4s${T_RESET} ${C_GREEN}%s${T_RESET}\n" "$iface_disp" "$mac_disp" "$proto" "$addr"
			buf+="$line"
		done <<<"$clean_net_info"
	else
		buf+=$(printBanner "Network Interfaces" "$C_BLUE")
		buf+="\n"
		buf+="  ${C_YELLOW}No IP address found (requires qemu-guest-agent or DHCP lease)${T_RESET}\n"
	fi
}

append_storage_info() {
	local vm="$1"
	local -n buf="$2"

	buf+=$(printBanner "Storage" "$C_BLUE")
	buf+="\n"
	local blklist
	blklist=$(virsh domblklist "$vm" --details | tail -n +3)

	if [[ -z "$blklist" ]]; then
		buf+="  No storage devices found.\n"
	else
		while read -r type device target source; do
			[[ -z "$target" ]] && continue

			if [[ "$source" == "-" && "$device" == "cdrom" ]]; then
				buf+="  ${T_BOLD}Device: $target${T_RESET} (${C_YELLOW}$device${T_RESET}) - ${C_CYAN}(Empty)${T_RESET}\n"
				continue
			fi

			buf+="  ${T_BOLD}Device: $target${T_RESET} (${C_YELLOW}$device${T_RESET}) - Type: ${C_CYAN}${type}${T_RESET}\n"

			if [[ "$source" == "-" ]]; then
				source="(unknown or passthrough)"
			fi
			buf+="    Host path: ${C_CYAN}$source${T_RESET}\n"

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
		done <<<"$blklist"
	fi
}

# Function to show VM details
show_vm_details() {
	local vm="$1"

	clear_screen

	# show loading message
	printBanner "VM Details: ${T_BOLD}${C_YELLOW}Loading..." "${C_CYAN}"

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
	local agent_color="$C_RED"
	local agent_hint=""
	local os_info=""
	if [[ "$state" == "running" ]]; then
		if virsh qemu-agent-command "$vm" '{"execute":"guest-ping"}' &>/dev/null; then
			agent_status="Running"
			agent_color="$C_GREEN"
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
		agent_status="${T_REVERSE} VM Not Running ${T_REVERSE}"
		agent_color="${C_YELLOW}"
	fi

	local buffer=""
	buffer+=$(printBanner "VM Details: ${T_BOLD}${C_YELLOW}$vm${T_RESET} (${T_REVERSE}${state_color} ${state_icon} ${state} ${T_REVERSE}${T_RESET})" "$C_CYAN")
	buffer+="\n"

	local line
	printf -v line "  CPU(s): ${C_CYAN}%s${T_RESET}\t Memory: ${C_CYAN}%s${T_RESET}\t Autostart: ${C_CYAN}%s${T_RESET}\n" "$cpus" "$mem_display" "$autostart"
	buffer+="$line"
	if [[ -n "$os_info" ]]; then
		printf -v line "  ${C_GREEN}Agent OS: ${C_CYAN}%s${T_RESET}\n" "$os_info"
		buffer+="$line"
	else
		printf -v line "  Agent:  ${agent_color}%s${T_RESET}%s\n" "$agent_status" "$agent_hint"
		buffer+="$line"
	fi

	append_network_info "$vm" buffer
	append_storage_info "$vm" buffer

	buffer+="\n${C_BLUE}Press any key to return...${T_RESET}\n"
	render_buffer "$buffer"
	read -rsn1
	clear_screen
}

# Function to show help overlay
show_help() {
	clear_screen
	local buffer=""
	buffer+=$(printBanner "Help & Shortcuts" "$C_CYAN")
	buffer+="\n"

	buffer+=$(printBanner "Navigation" "$C_ORANGE")
	buffer+="\n"
	buffer+="  ${C_CYAN}↓${T_RESET}/${C_CYAN}↑${T_RESET} or ${C_CYAN}j${T_RESET}/${C_CYAN}k${T_RESET}  Select VM from the list\n"

	buffer+=$(printBanner "Power Actions" "$C_ORANGE")
	buffer+="\n"
	buffer+="  ${C_GREEN}S${T_RESET}           Start/Shutdown/Resume VM (Toggle)\n"
	buffer+="  ${C_YELLOW}R${T_RESET}           Reboot\n"
	buffer+="  ${C_RED}F${T_RESET}           Force Stop (Hard power off)\n"

	buffer+=$(printBanner "Management" "$C_ORANGE")
	buffer+="\n"
	buffer+="  ${C_YELLOW}I${T_RESET}           Show Details (IP, Disk, Network)\n"
	buffer+="  ${C_CYAN}C${T_RESET}           Clone VM\n"
	buffer+="  ${C_RED}D${T_RESET}           Delete VM\n"

	buffer+=$(printBanner "Other" "$C_ORANGE")
	buffer+="\n"
	buffer+="  ${C_CYAN}?${T_RESET}/${C_CYAN}h${T_RESET}         Show this help\n"
	buffer+="  ${C_RED}Q${T_RESET}           Quit\n"

	buffer+="\n${C_BLUE}Press any key to return...${T_RESET}\n"

	render_buffer "$buffer"
	read -rsn1
	clear_screen
}

# Check if a VM is selected
require_vm_selected() {
	if [[ -z "${VM_NAMES[$SELECTED]}" ]]; then
		STATUS_MSG="${C_YELLOW}No VM selected${T_RESET}"
		HAS_ERROR=true
		return 1
	fi
	return 0
}

# Helper for yes/no confirmation
ask_confirmation() {
	local question="$1"
	local default_answer="${2:-n}"
	local prompt_suffix
	if [[ "$default_answer" == "y" ]]; then prompt_suffix="(Y/n)"; else prompt_suffix="(y/N)"; fi

	# Clear status to ensure clean slate
	STATUS_MSG=""
	render_main_ui

	local buffer=""
	buffer+="\n"
	buffer+=$(printBanner "Confirmation" "${C_YELLOW}")
	buffer+="\n"
	buffer+="${C_YELLOW}╰${T_RESET} ${T_BOLD}${question} ${prompt_suffix}${T_RESET}"
	printMsgNoNewline "$buffer"

	local answer
	while true; do
		answer=$(read_single_char)
		if [[ "$answer" == "$KEY_ENTER" ]]; then answer="$default_answer"; fi
		case "$answer" in
		[Yy] | [Nn])
			if [[ "$answer" =~ [Yy] ]]; then return 0; else return 1; fi
			;;
		"$KEY_ESC" | "q" | "Q") return 1 ;;
		esac
	done
}

# Helper to format and set a wrapped error status message
set_error_status() {
	local prefix="$1"
	local error_text="$2"
	local terminal_width=70
	# Width available for text inside the message box.
	# ╰ (1) + space (1) = 2 chars for prefix on first line.
	# Subsequent lines are indented by 2 spaces.
	local wrap_width=$((terminal_width - 2))

	# Remove redundant "error: " if it exists at the start of the string
	if [[ "$error_text" == "error: "* ]]; then
		error_text="${error_text#error: }"
	fi
	# Capitalize the first letter of the cleaned error
	error_text="$(tr '[:lower:]' '[:upper:]' <<<"${error_text:0:1}")${error_text:1}"

	# Combine prefix and wrapped text, then fold it
	STATUS_MSG=$(echo "${prefix}${error_text}" | fold -s -w "$wrap_width")
	HAS_ERROR=true
	MSG_COLOR="$C_RED"
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

	"$@" >"$temp_out" 2>&1 &
	local pid=$!

	STATUS_MSG="${message}  "
	render_main_ui
	local color="${MSG_COLOR:-$C_YELLOW}"

	while kill -0 "$pid" 2>/dev/null; do
		local char="${spinner_chars:spinner_idx:1}"
		local current_msg="${message} ${C_MAUVE}${char}${T_RESET}"
		printf "${T_CURSOR_UP}\r${color}╰${T_RESET} ${T_BOLD}${current_msg}${T_RESET}${T_CLEAR_LINE}\n"
		spinner_idx=$(((spinner_idx + 1) % ${#spinner_chars}))
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

	if ! command -v virt-clone &>/dev/null; then
		STATUS_MSG="${C_RED}Error: 'virt-clone' not found. Install 'virtinst'.${T_RESET}"
		HAS_ERROR=true
		return
	fi

	local default_name="${VM_NAMES[$SELECTED]}-c"
	MSG_TITLE="CLONE ${VM_NAMES[$SELECTED]}? (empty name to cancel)"
	MSG_COLOR="$C_ORANGE"
	MSG_INPUT="true"
	STATUS_MSG="" # Clear any previous status
	render_main_ui
	echo -ne "${T_CURSOR_SHOW}"
	read -e -p " Enter new name: " -i "$default_name" -r new_name
	echo -e "${T_CURSOR_HIDE}"
	MSG_INPUT="false"
	if [[ -n "$new_name" ]]; then
		# Validate VM name: alphanumeric, dot, underscore, hyphen only
		if [[ ! "$new_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
			STATUS_MSG="${C_RED}Error: Invalid name. Use only a-z, 0-9, ., _, - (no spaces).${T_RESET}"
			HAS_ERROR=true
			return
		fi

		# Check if name already exists
		for existing_vm in "${VM_NAMES[@]}"; do
			if [[ "$existing_vm" == "$new_name" ]]; then
				STATUS_MSG="${C_RED}Error: VM '$new_name' already exists.${T_RESET}"
				HAS_ERROR=true
				return
			fi
		done

		if run_with_spinner "Cloning ${VM_NAMES[$SELECTED]} to $new_name... (Please wait)" \
			virt-clone --original "${VM_NAMES[$SELECTED]}" --name "$new_name" --auto-clone; then
			STATUS_MSG="${C_GREEN}Clone successful: $new_name${T_RESET}"
			fetch_vms
		else
			set_error_status "Clone failed: " "$CMD_OUTPUT"
		fi
	else
		STATUS_MSG="${C_YELLOW}Clone cancelled${T_RESET}"
	fi
}

# Function to handle Delete VM
handle_delete_vm() {
	require_vm_selected || return
	local vm="${VM_NAMES[$SELECTED]}"

	if ! ask_confirmation "${C_RED}DELETE${T_RESET} $vm?"; then
		STATUS_MSG="${C_YELLOW}Delete cancelled${T_RESET}"
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
		STATUS_MSG="${C_GREEN}Deleted $vm${T_RESET}"
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

	if ask_confirmation "${color}${display_name}${T_RESET} ${VM_NAMES[$SELECTED]}?"; then
		action="$action_name"
		cmd="$virsh_cmd"
	else
		local cancel_name="${display_name,,}"
		STATUS_MSG="${C_YELLOW}${cancel_name^} cancelled${T_RESET}"
	fi
}

# Draw header for VM list
draw_header() {
	printf "${C_CYAN}│${T_RESET} ${T_BOLD}${T_ULINE}%-35s${T_RESET} ${T_BOLD}${T_ULINE}%-12s${T_RESET} ${T_BOLD}${T_ULINE}%-7s${T_RESET} ${T_BOLD}${T_ULINE}%-7s${T_RESET} ${T_BOLD}${T_ULINE}%-3s${T_RESET}" "NAME" "STATE" "CPU" "MEM" "A/S"
}

draw_footer() {
	local banner_msg="Controls:──┬──────────────┬──────────┬─────────────────────┬──────────"
	printBannerMiddle "$banner_msg" "$C_CYAN"
	printf "\n"

	local sep="${C_CYAN}│${C_GRAY}"

	printf "${C_CYAN}│${C_GRAY} [${T_BOLD}${C_CYAN}↓↑${C_GRAY}]Select ${sep} [${T_BOLD}${C_GREEN}S${C_GRAY}]tart/Stop ${sep} [${T_BOLD}${C_YELLOW}R${C_GRAY}]eboot ${sep} [${T_BOLD}${C_RED}F${C_GRAY}]orce Stop        ${sep} [${T_BOLD}${C_CYAN}?${C_GRAY}]Help${T_CLEAR_LINE}\n"
	printf "${C_CYAN}╰${C_GRAY} [${T_BOLD}${C_CYAN}jk${C_GRAY}]Select ${sep} [${T_BOLD}${C_YELLOW}I${C_GRAY}]nfo       ${sep} [${T_BOLD}${C_CYAN}C${C_GRAY}]lone  ${sep} [${T_BOLD}${C_RED}D${C_GRAY}]elete            ${sep} [${T_BOLD}${C_RED}Q${C_GRAY}]uit${T_CLEAR_LINE}"
}

# Function to render the main UI
render_main_ui() {
	# Double buffering to prevent flicker
	local buffer=""
	buffer+=$(printBanner "VM Manager" "$C_CYAN")
	buffer+="\n"
	buffer+=$(draw_header)
	buffer+="\n"

	local count=${#VM_NAMES[@]}

	if [[ $count -eq 0 ]]; then
		buffer+="${C_CYAN}│${T_RESET}  ${C_YELLOW}No VMs defined on this host${T_RESET}\n"
	else
		for ((i = 0; i < count; i++)); do
			local name="${VM_NAMES[$i]}"
			local state="${VM_STATES[$i]-unknown}"
			local cpu="${VM_CPU_USAGE[$name]-}"
			local mem="${VM_MEM_USAGE[$name]-}"
			local autostart="${VM_AUTOSTART[$name]-}"
			local autostart_display=""

			if [[ "$autostart" == "Yes" ]]; then
				autostart_display="${C_GREEN}Yes${T_RESET}"
			else
				autostart_display="${C_RED}No ${T_RESET}"
			fi

			set_state_visuals "$state"
			local state_color="$STATE_COLOR"
			local state_icon="$STATE_ICON"
			local state_display="${state_icon} ${state}"

			# Prepare formatted strings
			local name_fmt
			name_fmt=$(_format_fixed_width_string " $name" 35)
			local state_fmt
			state_fmt=$(_format_fixed_width_string " $state_display" 12)
			local cpu_fmt
			cpu_fmt=$(_format_fixed_width_string "$cpu" 7)
			local mem_fmt
			mem_fmt=$(_format_fixed_width_string "$mem" 7)
			local as_fmt
			as_fmt=$(_format_fixed_width_string "$autostart_display" 3)

			local cursor="${C_CYAN}│${T_RESET} "
			local line_bg="${T_RESET}"
			local text_color="$C_GRAY"
			if [[ "$state" == "running" ]]; then text_color="${T_RESET}"; fi

			if [[ $i -eq $SELECTED ]]; then
				cursor="${C_CYAN}│❱${T_RESET}"
				line_bg="${T_BOLD}${C_BLUE}${T_REVERSE}"
				text_color=""
			fi

			local line_content="${text_color}${name_fmt} ${state_color}${state_fmt}${T_RESET} ${text_color}${cpu_fmt} ${mem_fmt} ${as_fmt}"
			if [[ $i -eq $SELECTED ]]; then
				line_content="${line_content//${T_RESET}/${T_RESET}${line_bg}}"
			fi

			buffer+="${cursor}${line_bg}${line_content}${T_RESET}${T_CLEAR_LINE}\n"
		done
	fi

	buffer+=$(draw_footer)
	buffer+="\n"

	if [[ -n "$STATUS_MSG" || -n "$MSG_TITLE" ]]; then
		local title="${MSG_TITLE:-Message:}"
		local color="${MSG_COLOR:-$C_YELLOW}"
		buffer+=$(printBanner "$title" "$color")
		buffer+="\n"
		if [[ "$MSG_INPUT" == "true" ]]; then
			buffer+="${color}╰${T_RESET} "
		else
			local first_line=true
			while IFS= read -r line; do
				if [[ "$first_line" == "true" ]]; then
					buffer+="${color}╰${T_RESET} ${T_BOLD}${line}${T_RESET}${T_CLEAR_LINE}\n"
					first_line=false
				else
					buffer+="  ${T_BOLD}${line}${T_RESET}${T_CLEAR_LINE}\n"
				fi
			done <<<"$STATUS_MSG"
		fi
	fi

	# Print buffer at home position and clear rest of screen
	render_buffer "$buffer"
}

# Main Loop
echo -e "${T_CURSOR_HIDE}"
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
	if ! key=$(read_single_char 2); then
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

	# Handle keys
	cmd=""
	action=""
	case "$key" in
	q | Q)
		clear_screen
		exit 0
		;;
	"$KEY_UP" | k | K) ((SELECTED--)) ;;
	"$KEY_DOWN" | j | J) ((SELECTED++)) ;;
	i | I)
		require_vm_selected && show_vm_details "${VM_NAMES[$SELECTED]}"
		;;
	\? | h | H)
		show_help
		;;
	c | C)
		handle_clone_vm
		;;
	d | D)
		handle_delete_vm
		;;
	s | S)
		if require_vm_selected; then
			case "${VM_STATES[$SELECTED]}" in
			"running")
				handle_vm_action "$C_RED" "SHUTDOWN" "shutdown" "shutdown"
				;;
			"shut off")
				handle_vm_action "$C_GREEN" "START" "start" "start"
				;;
			"paused")
				handle_vm_action "$C_GREEN" "RESUME" "resume" "resume"
				;;
			*)
				STATUS_MSG="${C_YELLOW}Action unavailable for state: ${VM_STATES[$SELECTED]}${T_RESET}"
				HAS_ERROR=true
				;;
			esac
		fi
		;;
	f | F)
		handle_vm_action "$C_RED" "FORCE STOP" "force stop" "destroy"
		;;
	r | R)
		handle_vm_action "$C_YELLOW" "REBOOT" "reboot" "reboot"
		;;
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
done

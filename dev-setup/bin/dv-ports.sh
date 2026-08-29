#!/bin/bash
# ===============
# Script Name: dv-ports.sh
# Description: List listening TCP/UDP ports with process info.
# Keybinding:  None
# Config:      alias ports='dv-ports.sh'
# Dependencies: ss, awk, fzf
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Configuration ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_ULINE=$'\033[4m'

print_usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --raw       Output raw table (no FZF)"
    echo "  -h, --help  Show this help"
}

RAW_MODE=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --raw) RAW_MODE=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $1"; print_usage; exit 1 ;;
    esac
    shift
done

generate_list() {
    # Header
    printf "${C_BOLD}${C_ULINE}%-1s %-6s %21s %21s %s${C_RESET}\n" "P" "STATUS" "LOCAL:Port " "REMOTE:Port " "PROGRAM/PID"

    ss -tulpn | awk \
      -v c_reset="${C_RESET}" \
      -v c_green="${ansi_green}" \
      -v c_yellow="${ansi_yellow}" \
      -v c_blue="${ansi_blue}" \
      -v c_magenta="${ansi_magenta}" \
      -v c_cyan="${ansi_cyan}" '

  function split_addr(addr, parts) {
    match(addr, /:[^:]*$/)
    if (RSTART > 0) {
      parts[1] = substr(addr, 1, RSTART-1)
      parts[2] = substr(addr, RSTART)
    } else {
      parts[1] = addr
      parts[2] = ""
    }
  }

  NR > 1 {
    proto=toupper(substr($1, 1, 1))
    c_proto = (proto == "T") ? c_green : c_yellow
    state=$2
    if (state == "LISTEN") c_state = c_green; else if (state == "UNCONN") c_state = c_yellow; else if (state == "ESTAB") c_state = c_blue; else c_state = c_magenta
    split_addr($5, l_parts)
    split_addr($6, r_parts)
    proc_info=""
    for (i=7; i<=NF; i++) proc_info = proc_info $i " "
    sub(/users:\(\(/, "", proc_info); sub(/(\),|\)\)).*/, "", proc_info); sub(/,fd=[0-9]+/, "", proc_info); sub(/ +$/, "", proc_info)
    if (proc_info == "") proc_info = "-"
    printf "%s%-1s%s %s%-6s%s %15s%s%-6s%s %15s%s%-6s%s %s%s\n", 
      c_proto, proto, c_reset, c_state, state, c_reset,
      l_parts[1], c_cyan, l_parts[2], c_reset, r_parts[1], c_cyan, r_parts[2], c_reset,
      c_reset, proc_info
  }
'
}

if [[ "$RAW_MODE" == "true" ]]; then
    generate_list
else
    # Preview: Extract PID and show details
    # We try to use dv-kill.sh's preview if available, otherwise fallback to ps
    preview_cmd="pid=\$(echo {} | grep -o 'pid=[0-9]*' | cut -d= -f2); \
        if [ -n \"\$pid\" ]; then \
            if [ -x \"$script_dir/dv-kill.sh\" ]; then \
                \"$script_dir/dv-kill.sh\" --preview \"\$pid\"; \
            else \
                ps -fp \"\$pid\"; \
            fi \
        else \
            echo 'No PID found (try running as root)'; \
        fi"

    # Browser: Extract port and open localhost
    open_cmd="xdg-open"
    if command -v open &>/dev/null; then open_cmd="open"; fi
    
    browser_cmd="port=\$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$3}' | awk -F: '{print \$NF}'); \
        if [[ \"\$port\" =~ ^[0-9]+$ ]]; then \
            $open_cmd http://localhost:\"\$port\"; \
        fi"

    # Kill: Extract PID and kill
    kill_cmd="pid=\$(echo {} | grep -o 'pid=[0-9]*' | cut -d= -f2); \
        if [ -n \"\$pid\" ]; then \
            kill \"\$pid\"; \
        fi"

    # Styled Header
    header="${C_BOLD}ENTER${C_RESET}: Refresh • ${C_BOLD}CTRL-K${C_RESET}: Kill • ${C_BOLD}CTRL-O${C_RESET}: Open Browser"

    generate_list | dv_run_fzf \
        --header-lines=1 \
        --no-sort \
        --prompt="Ports> " \
        --border-label=" Network Ports " \
        --border-label-pos='3' \
        --header-first \
        --header "$header" \
        --preview "$preview_cmd" \
        --preview-window="bottom:40%:wrap" \
        --bind "enter:reload($0 --raw)" \
        --bind "ctrl-k:execute($kill_cmd)+reload($0 --raw)" \
        --bind "ctrl-o:execute($browser_cmd)"
fi
#!/bin/bash
# ==============================================================================
# Script Name: dv-ports
# Description: List listening TCP/UDP ports with process info in a table.
# Usage:       dv-ports
# ==============================================================================

# --- Configuration ---
C_RESET=$'\033[0m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'
C_MAGENTA=$'\033[1;35m'
C_CYAN=$'\033[1;36m'
C_BOLD=$'\033[1m'
C_ULINE=$'\033[4m'

# Header
printf "${C_BOLD}${C_ULINE}%-1s %-6s %21s %21s %s${C_RESET}\n" "P" "STATUS" "LOCAL:Port " "REMOTE:Port " "PROGRAM/PID"

ss -tulpn | awk \
  -v c_reset="${C_RESET}" \
  -v c_green="${C_GREEN}" \
  -v c_yellow="${C_YELLOW}" \
  -v c_blue="${C_BLUE}" \
  -v c_magenta="${C_MAGENTA}" \
  -v c_cyan="${C_CYAN}" '

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
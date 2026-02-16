#!/bin/bash
# ===============
# Script Name: dv-update.sh
# Description: Update system packages and check if a reboot is required.
# Keybinding:  None
# Config:      alias update='dv-update.sh'
# Dependencies: apt, sudo
# ===============

set -e
set -o pipefail

# Ensure sudo permissions are cached
sudo -v

# --- Configuration ---
C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_BLUE=$'\033[1;34m'
C_MAGENTA=$'\033[1;35m'
C_CYAN=$'\033[1;36m'
C_BOLD=$'\033[1m'
 
run_transient() {
  local cmd="$1"
  local custom_summary="$2"
  local temp_log
  temp_log=$(mktemp)

  # Run command, piping to tee to show output live, and capture to file.
  # We use eval to handle arguments correctly.
  # Using 'if' ensures set -e doesn't crash the script on failure before we handle it.
  if eval "$cmd" | tee "$temp_log"; then
    # Success
    local line_count
    line_count=$(wc -l < "$temp_log")
    
    # Move cursor up and clear lines
    if [ "$line_count" -gt 0 ]; then
      for ((i=0; i<line_count; i++)); do
        tput cuu1
        tput el
      done
    fi
    
    # Print summary (last line)
    if [[ -n "$custom_summary" ]]; then
      echo "$custom_summary"
    else
      tail -n 1 "$temp_log"
    fi
    rm "$temp_log"
    return 0
  else
    # Failure: Leave output visible for debugging
    local exit_code=${PIPESTATUS[0]}
    rm "$temp_log"
    return $exit_code
  fi
}

check_reboot() {
  local color="${C_GREEN}"
  local msg="✓ No Reboot Required"
 
  if [ -f /var/run/reboot-required ]; then
    color="${C_RED}"
    msg=" Reboot Required"
  fi
  printf "%s%s%s\n" "${color}" "${msg}" "${C_RESET}"
}

# Using transient output to reduce verbosity while showing progress.
printf "%sUpdating apt sources...%s\n" "${C_BLUE}" "${C_RESET}"
run_transient "sudo apt-get update -o Acquire::Color=1" "Sources updated." || exit 1
printf "%sUpgrading apt packages...%s\n" "${C_MAGENTA}" "${C_RESET}"
run_transient "sudo apt-get -y upgrade -o Acquire::Color=1"
printf "%sAutoremoving apt packages...%s\n" "${C_CYAN}" "${C_RESET}"
run_transient "sudo apt-get -y autoremove -o Acquire::Color=1"

echo
check_reboot
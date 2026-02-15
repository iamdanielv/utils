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

# --- Configuration ---
C_RESET=$'\033[0m'
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_BLUE=$'\033[1;34m'
C_MAGENTA=$'\033[1;35m'
C_CYAN=$'\033[1;36m'
C_BOLD=$'\033[1m'
 
check_reboot() {
  local color="${C_GREEN}"
  local msg="✓ No Reboot Required"
 
  if [ -f /var/run/reboot-required ]; then
    color="${C_RED}"
    msg=" Reboot Required"
  fi
  printf "%s%s%s\n" "${color}" "${msg}" "${C_RESET}"
}

# Using -qq to reduce verbosity. Using apt-get for script stability.
printf "%sUpdating apt sources...%s\n" "${C_BLUE}" "${C_RESET}"
sudo apt-get -qq update || exit 1
printf "%sUpgrading apt packages...%s\n" "${C_MAGENTA}" "${C_RESET}"
sudo apt-get -y upgrade
printf "%sAutoremoving apt packages...%s\n" "${C_CYAN}" "${C_RESET}"
sudo apt-get -y -q autoremove
 
echo
check_reboot
#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

print_usage() {
  printBanner "Git Directory Utility"
  printMsg "Recursively performs Git commands on the current directory and its subdirectories."
  printMsg "\n${T_ULINE}Usage:${T_RESET}"
  printMsg "  $(basename "$0") [option]"
  printMsg "\n${T_ULINE}Options:${T_RESET}"
  printMsg "  ${C_L_BLUE}-gs${T_RESET}           Perform 'git status -sb' on all Git repositories."
  printMsg "  ${C_L_BLUE}-gp${T_RESET}           Perform 'git status -sb && git pull' on all Git repositories."
  printMsg "  ${C_L_BLUE}-gvb${T_RESET}          View local and remote branches for all Git repositories."
  printMsg "  ${C_L_BLUE}-gb <branch>${T_RESET}   Switch all Git repositories to the specified branch."
  printMsg "  ${C_L_BLUE}-h${T_RESET}            Show this help message."
  printMsg "\n${T_ULINE}Examples:${T_RESET}"
  printMsg "  ${C_GRAY}# Check the status of all repositories${T_RESET}"
  printMsg "  $(basename "$0") -gs"
  printMsg "  ${C_GRAY}# Switch all repositories to the 'main' branch${T_RESET}"
  printMsg "  $(basename "$0") -gb main"
}

# Takes in a command to perform on all sub directories
performCommandOnGitDirectories() {
  local commandToPerform="${1}"

  # check the current directory
  if [[ -d ".git" ]]; then
    printMsg "${C_GRAY}In ${C_YELLOW}${PWD}${T_RESET}"
    #printMsg "command: ${commandToPerform}"
    eval "${commandToPerform}"
    echo ""
  else
    printMsg "${C_GRAY}${PWD##*/} is not a git repo${T_RESET}"
    echo ""
  fi

  for FILE in */; do
    # if it's a directory, check if it contains a .git folder
    if [[ -d "${FILE}" ]]; then
      cd "${FILE}" || return
      if [[ -d ".git" ]]; then
        printMsg "${C_GRAY}In ${C_YELLOW}${FILE}${T_RESET}"
        #printMsg "command: ${commandToPerform}"
        eval "${commandToPerform}"
        echo ""
      else
        printMsg "${C_GRAY}Exploring ${C_BLUE}${FILE}${T_RESET}"
        performCommandOnGitDirectories "${commandToPerform}"
      fi
      #printMsg "${C_GRAY}Leaving ${C_BLUE}${PWD##*/}${T_RESET}\n"
      cd ..
    fi
  done
}

gitStatus() {
  printBanner "Doing a git status for directories"
  performCommandOnGitDirectories "git status -sb"
}

gitPull() {
  printBanner "Doing a git pull for directories"
  performCommandOnGitDirectories "git status -sb && git pull"
}

gitViewBranches() {
  printBanner "Get Branches"
  performCommandOnGitDirectories "git fetch -q && git branch -a"
  #git remote prune origin
}

switchToBranch() {
  local branchName="${1}"
  if [ -z "${branchName}" ]; then
    printMsg "${T_ERR_ICON} Can't switch branch, no branch name supplied${T_RESET}"
    printMsg "${T_QST_ICON} Did you mean 'gvb'?${T_RESET}"
    exit 1
  fi

  printBanner "Switching to ${branchName} branch for directories"
  performCommandOnGitDirectories "git checkout ${branchName}"
}

# --- Main Execution ---
# This block will only run when the script is executed directly.
if [ $# -eq 0 ]; then
  # No arguments provided, print help
  print_usage
  exit 0
fi

# parameters
while [[ $# -gt 0 ]]; do
  case $1 in
  "-gs" | "gs")
    gitStatus
    shift #go to next argument
    ;;
  "-gp" | "gp")
    gitPull
    shift #go to next argument
    ;;
  "-gvb" | "gvb")
    gitViewBranches
    shift #go to next argument
    ;;
  "-gb" | "gb")
    switchToBranch "$2"
    shift #go to next argument
    shift #skip the branch name
    ;;
  "-h" | "h")
    print_usage
    exit 0
    ;;
  -* | *)
    printMsg " ${T_ERR_ICON} Unknown argument ${T_ERR}$1${T_RESET}"
    print_usage
    exit 1
    ;;

  esac
done
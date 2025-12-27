#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Colors & Styles
C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_L_BLUE=$'\033[34m'
C_L_CYAN=$'\033[36m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'
T_ULINE=$'\033[4m'
T_ERR=$'\033[31;1m'

# Icons
T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"

# Logging
printMsg() { printf '%b\n' "$1"; }

# Banner Utils
strip_ansi_codes() {
    local s="$1"; local esc=$'\033'
    if [[ "$s" != *"$esc"* ]]; then echo -n "$s"; return; fi
    local pattern="$esc\\[[0-9;]*[a-zA-Z]"
    while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
    echo -n "$s"
}

_truncate_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"; local trunc_char_len=${#trunc_char}
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then echo -n "$input_str"; return; fi
    local truncate_to_len=$(( max_len - trunc_char_len )); local new_str=""; local visible_count=0; local i=0; local in_escape=false
    while (( i < ${#input_str} && visible_count < truncate_to_len )); do
        local char="${input_str:i:1}"; new_str+="$char"
        if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then (( visible_count++ )); fi
        if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi; ((i++))
    done
    echo -n "${new_str}${trunc_char}"
}

generate_banner_string() {
    local text="$1"; local total_width=70; local prefix="┏"; local line
    printf -v line '%*s' "$((total_width - 1))"; line="${line// /━}"; printf '%s' "${C_L_BLUE}${prefix}${line}${T_RESET}"; printf '\r'
    local text_to_print; text_to_print=$(_truncate_string "$text" $((total_width - 3)))
    printf '%s' "${C_L_BLUE}${prefix} ${text_to_print} ${T_RESET}"
}

printBanner() { printMsg "$(generate_banner_string "$1")"; }

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

main() {
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
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
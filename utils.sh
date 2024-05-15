#!/bin/bash
export C_RED='\e[31m'
export C_GREEN='\e[32m'
export C_YELLOW='\e[33m'
export C_BLUE='\e[34m'
export C_MAGENTA='\e[35m'
export C_CYAN='\e[36m'
export C_WHITE='\e[37m'
export C_GRAY='\e[30;1m'
export C_L_RED='\e[31;1m'
export C_L_GREEN='\e[32;1m'
export C_L_YELLOW='\e[33;1m'
export C_L_BLUE='\e[34;1m'
export C_L_MAGENTA='\e[35;1m'
export C_L_CYAN='\e[36;1m'
export C_L_WHITE='\e[37;1m'

export T_RESET='\e[0m'
export T_BOLD='\e[1m'
export T_ULINE='\e[4m'

export T_ERR="${T_BOLD}\e[31;1m"
export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_QST_ICON="${T_BOLD}[?]${T_RESET}"

export DIV="-------------------------------------------------------------------------------"

function printMsg() {
  echo -e "${1}"
}

function printMsgNoNewline() {
  echo -n -e "${1}"
}

function printDatedMsgNoNewLine() {
  echo -n -e "$(getPrettyDate) ${1}"
}

function printErrMsg() {
  printMsg "${T_ERR_ICON}${T_ERR} ${1} ${T_RESET}"
}

function printOkMsg() {
  printMsg "${T_OK_ICON} ${1}${T_RESET}"
}

function getFormattedDate() {
  date +"%Y-%m-%d %I:%M:%S"
}

function getPrettyDate() {
  echo "${C_BLUE}$(getFormattedDate)${T_RESET}"
}

function printBanner() {
  printMsg "${C_BLUE}${DIV}"
  printMsg " ${1}"
  printMsg "${DIV}${T_RESET}"
}

printHelp() {
  printMsg " Will traverse directories and perform one of"
  printMsg " the following:"
  printMsg "  ${T_BOLD}${C_BLUE}-gs${T_RESET}\t\t git status"
  printMsg "  ${T_BOLD}${C_BLUE}-gp${T_RESET}\t\t git status followed by git pull"
  printMsg "  ${T_BOLD}${C_BLUE}-gvb${T_RESET}\t\t git view branches "
  printMsg "  ${T_BOLD}${C_BLUE}-gb ${C_BLUE}<name>${T_RESET}\t switch repos to ${T_BOLD}${C_BLUE}<name>${T_RESET} branch"
  printMsg "  ${T_BOLD}${C_BLUE}-h${T_RESET}\t\t Show this help dialog"
  printMsg ""
  printMsg "Sample Usage: ./utils.sh -gs"
  printMsg
  exit 0
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

# Start of script
if [ $# -eq 0 ]; then
  # No arguments provided, print help
  printHelp
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
    printHelp
    ;;
  -* | *)
    printMsg " ${T_ERR_ICON} Unknown argument ${T_ERR}$1${T_RESET}"
    printHelp
    ;;

  esac
done

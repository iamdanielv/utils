#!/bin/bash
export C_RED='\033[31m'
export C_GREEN='\033[32m'
export C_YELLOW='\033[33m'
export C_BLUE='\033[34m'
export C_MAGENTA='\033[35m'
export C_CYAN='\033[36m'
export C_WHITE='\033[37m'
export C_GRAY='\033[30;1m'
export C_L_RED='\033[31;1m'
export C_L_GREEN='\033[32;1m'
export C_L_YELLOW='\033[33m'
export C_L_BLUE='\033[34m'
export C_L_MAGENTA='\033[35m'
export C_L_CYAN='\033[36m'
export C_L_WHITE='\033[37m'

export T_RESET='\033[0m'
export T_BOLD='\033[1m'
export T_ULINE='\033[4m'

export T_ERR="${T_BOLD}\033[31;1m"
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

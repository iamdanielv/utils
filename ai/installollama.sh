#!/bin/bash
# Install Ollama
# This script installs or updates Ollama

# Color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'

T_RESET='\e[0m'
T_BOLD='\e[1m'

ERR_ICON="[${T_BOLD}${RED}✗${T_RESET}]"
OK_ICON="[${T_BOLD}${GREEN}✓${T_RESET}]"
INFO_ICON="[${T_BOLD}${YELLOW}i${T_RESET}]"

# Function to check if command exists and print success or failure
# @param $1: Command to check
# @param $2: Success message
# @param $3: Failure message
# @return 0 if command exists, 1 otherwise
check_command() {
    local cmd="$1"
    local success_msg="$2"
    local failure_msg="$3"

    if command -v ${cmd} &>/dev/null; then
        echo -e "${OK_ICON} ${success_msg}"
        return 0
    else
        echo -e "${ERR_ICON} ${RED}${cmd} not found.${T_RESET} ${failure_msg}"
        return 1
    fi
}

echo -e "${BLUE} Checking Pre-Req's..."
echo -e "${BLUE}-----------------------${T_RESET}"
echo -n "Checking for curl... "
if ! check_command "curl" "${GREEN}installed${T_RESET}" "Please install curl."; then
    exit 1
fi

# Check if Ollama is installed and its version
echo -n "Checking for 🤖 Ollama... "
if ! check_command "ollama" "${GREEN}installed${T_RESET}" ""; then
    echo -e "${INFO_ICON} Ollama not found, ${YELLOW}going to install...${T_RESET}"
else
    echo -e "    $(ollama --version)"
    echo -e "    ${INFO_ICON} ${YELLOW}trying to update...${T_RESET}"
fi

echo "Downloading 📥 auto-install script... "
curl -fsSL https://ollama.com/install.sh | sh

# Check if the installation was successful
echo -n "Checking for 🤖 Ollama... "
if ! check_command "ollama" "${GREEN}installed${T_RESET}" "Problem installing Ollama."; then
    exit 1
else
    sleep 1  # Add a 1-second delay before checking version
    echo -e "    $(ollama --version)"
fi

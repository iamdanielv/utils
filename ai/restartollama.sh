#!/bin/bash

# Sometimes on wake from sleep, the ollama service will go into an inconsistent state.
# This script will stop, reset, and start Ollama using systemd.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=../shared.sh
if ! source "$(dirname "$0")/../shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the parent directory." >&2
    exit 1
fi

printBanner "Ollama Service Restarter"

printMsg "${T_INFO_ICON} Checking prerequisites..."

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    printErrMsg "Ollama is not installed. Please run the installer first."
    exit 1
fi
printOkMsg "Ollama is installed."

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    printErrMsg "This script must be run as root."
    exit 1
fi
printOkMsg "Running with root privileges."

# Detect if using NVIDIA
printMsgNoNewline "${C_BLUE}Checking for NVIDIA GPU...${T_RESET}\t"
if nvidia-smi &> /dev/null; then
    printMsg "${T_OK_ICON} NVIDIA GPU detected."
else
    printMsg "${T_INFO_ICON} No NVIDIA GPU found. Running on CPU only."
fi

# Stop Ollama gracefully
printMsgNoNewline "${C_BLUE}Stopping Ollama service...${T_RESET}\t"
if systemctl stop ollama.service &>/dev/null; then
    printMsg "${T_OK_ICON} Stopped via systemctl"
elif pkill -f ollama &>/dev/null; then
    printMsg "${T_OK_ICON} Stopped via pkill"
else
    printMsg "${T_ERR_ICON} Failed to stop Ollama"
    exit 1
fi

# Reset NVIDIA UVM if NVIDIA is detected
if nvidia-smi &> /dev/null; then
    # Reset NVIDIA UVM (force unload/reload)
    printMsgNoNewline "${C_BLUE}Resetting NVIDIA UVM...${T_RESET}\t\t"
    rmmod nvidia_uvm &>/dev/null || true # Ignore error if module not loaded
    if modprobe nvidia_uvm; then
        printMsg "${T_OK_ICON} OK"
    else
        printMsg "${T_ERR_ICON} Failed to reset NVIDIA UVM"
        printMsg "    ${T_INFO_ICON} Check your NVIDIA driver installation."
        exit 1
    fi
fi

# Start Ollama
printMsgNoNewline "${C_BLUE}Starting Ollama service...${T_RESET}\t"
if ! systemctl start ollama.service &>/dev/null; then
    printMsg "${T_ERR_ICON} Failed to start Ollama"
    printMsg "    ${T_INFO_ICON} Preview of system log:"
    journalctl -u ollama.service -n 10 --no-pager | sed 's/^/    /'
    exit 1
else
    printMsg "${T_OK_ICON} OK"
fi

# Verify startup status
if systemctl is-active --quiet ollama.service; then
    printMsg "${T_OK_ICON} Ollama service is active."
else
    printErrMsg "Ollama service failed to activate."
    exit 1
fi

exit 0
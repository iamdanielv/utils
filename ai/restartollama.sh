#!/bin/bash

# Sometimes on wake from sleep, the ollama service will go into an inconsistent state.
# This script will stop, reset, and start Ollama using systemd and NVIDIA UVM

# Color codes
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo -e "${RED}❌ Error:${NC} Ollama is not installed. Please install Ollama before running this script."
    exit 1
fi

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ Error:${NC} This script must be run as root."
    exit 1
fi

# Stop Ollama gracefully
echo -e -n "${BLUE}Stopping Ollama...  \t${NC}"
if systemctl stop ollama.service; then
    echo -e "${GREEN}✅ via systemctl${NC}"
else
    echo -e "${YELLOW}Trying alternate stop method...${NC}"
    pkill -f ollama > /dev/null && echo -e "${GREEN}✅ via pkill{NC}" || {
        echo -e "${RED}❌ Failed to stop Ollama${NC}"
        exit 1
    }
fi

# Reset NVIDIA UVM (force unload/reload)
echo -e -n "${BLUE}Resetting NVIDIA UVM...\t${NC}"
rmmod nvidia_uvm || true   # Ignore error if module not loaded
modprobe nvidia_uvm
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ OK${NC}"
else
    echo -e "${RED}❌ Failed to reset NVIDIA UVM${NC}"
    echo -e "${YELLOW} Check NVIDIA driver installation.${NC}"
    exit 1
fi

# Start Ollama
echo -e -n "${BLUE}Starting Ollama...  \t${NC}"
systemctl start ollama.service 2>/dev/null || {
    echo -e "${RED}❌ Failed to start Ollama${NC}"
    echo -e "${YELLOW}Preview of system log:${NC}"
    journalctl -u ollama.service -n 10  # Print the last 10 lines of the log
    exit 1
}

# Verify startup status
if systemctl is-active --quiet ollama.service; then
    echo -e "${GREEN}✅ Ollama started${NC}"
else
    echo -e "${RED}❌ Ollama failed to start${NC}"
    exit 1
fi

exit 0
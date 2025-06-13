#!/bin/bash

# Sometimes on wake from sleep, the ollama service will go into an inconsistent state.
# This script will stop, reset, and start Ollama using systemd and NVIDIA UVM

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "❌ Error: Ollama is not installed. Please install Ollama before running this script."
    exit 1
fi

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Error: This script must be run as root."
    exit 1
fi

# Stop Ollama gracefully first (with signal)
echo "Stopping Ollama..."
systemctl stop ollama.service || {
    # If systemctl fails, try sending KILL signal
    pkill -f ollama > /dev/null && echo "Ollama stopped via pkill" || exit 1
}

# Reset NVIDIA UVM (force unload/reload)
echo -e "\n\033[1;34mResetting NVIDIA UVM...\033[0m"
rmmod nvidia_uvm || true   # Ignore error if module not loaded
modprobe nvidia_uvm

# Start Ollama
echo -e "\n\033[1;32mStarting Ollama...\033[0m"
systemctl start ollama.service 2>/dev/null || {
    echo -e "\n\033[1;35m❌ Error: Failed to start Ollama. Check system logs for details.\033[0m\n" >&2
    journalctl -u ollama.service -n 10  # Print the last 10 lines of the log
    exit 1
}

# Verify startup status
if systemctl is-active --quiet ollama.service; then
    echo -e "\n\033[1;36m✅ Ollama started successfully!\033[0m"
else
    echo -e "\n\033[1;37m❌Error: Ollama failed to start.\033[0m" >&2
    exit 1
fi

exit 0
#!/bin/bash
# Install or update Ollama.

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

# --- Main Script ---

printBanner "Ollama Installer/Updater"

printMsg "${T_INFO_ICON} Checking prerequisites..."

# Check for curl
if ! command -v curl &>/dev/null; then
    printErrMsg "curl is not installed. Please install it to continue."
    exit 1
fi
printOkMsg "curl is installed."

# Check if Ollama is installed and its version
if command -v ollama &>/dev/null; then
    printOkMsg "🤖 Ollama is already installed."
    printMsg "    Current version: $(ollama --version)"
    printMsg "${T_INFO_ICON} Trying to update Ollama..."
else
    printMsg "${T_INFO_ICON} 🤖 Ollama not found. going to install..."
fi

printMsg "Downloading 📥 and running the official Ollama install script..."
# The following command downloads and executes a script from the internet.
# This is a common practice for installers but carries a security risk.
# For higher security, download the script, inspect it, and then run it manually.
curl -fsSL https://ollama.com/install.sh | sh

printOkMsg "Ollama installation script finished successfully."

# Check if the installation was successful
printMsg "${T_INFO_ICON} Verifying Ollama installation..."

# The 'hash' command clears the shell's command lookup cache.
# This is more reliable than 'sleep' for finding a newly installed command.
hash ollama

printOkMsg "Ollama installed/updated successfully."
printMsg "    New version: $(ollama --version)"

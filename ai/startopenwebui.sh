#!/bin/bash

# Start OpenWebUI using docker compose in detached mode

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

printBanner "OpenWebUI Starter"

printMsg "${T_INFO_ICON} Checking prerequisites..."

# Check if Docker and Docker Compose are installed
if ! command -v docker &>/dev/null; then
    printErrMsg "Docker is not installed. Please install Docker to continue."
    exit 1
fi
printOkMsg "Docker is installed."

if ! docker compose version &>/dev/null; then
    printErrMsg "Docker Compose is not installed or not available in the PATH."
    exit 1
fi
printOkMsg "Docker Compose is available."

printMsg "${T_INFO_ICON} Starting OpenWebUI containers in detached mode..."
if ! docker compose up -d; then
    printErrMsg "Failed to start OpenWebUI containers."
    exit 1
fi

printOkMsg "OpenWebUI started successfully!"
printMsg "    🌐 Access it at: ${C_L_BLUE}http://localhost:8080${T_RESET}"

#!/usr/bin/env bash
# ===============
# Script Name: dv-docker-networks.sh
# Description: Displays all Docker networks and the running containers attached to each, with enhanced DevEx/UX.
# Dependencies: docker, jq
# ===============

set -euo pipefail

# --- Color Definitions (Following dv-*.sh standards) ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GRAY=$'\033[38;5;244m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'

# --- Utility Functions ---
print_section() {
    printf '\n%b%s%b\n' "$C_BOLD$C_CYAN" "$1" "$C_RESET"
}

print_network_header() {
    local name="$1"
    local driver="$2"
    local newline="${3:-true}"

    if [[ "$newline" == "true" ]]; then
        # Populated network header: prints and ends line
        printf '\n%b%s%b (%s)\n' "$C_BOLD$C_CYAN" "$name" "$C_RESET" "$driver"
    else
        # Empty network header: prints without trailing newline, ends with a space for inline text
        printf '\n%b%s%b (%s) ' "$C_BOLD$C_CYAN" "$name" "$C_RESET" "$driver"
    fi
}

print_container() {
    local name="$1"
    local state="$2"
    local ip="$3"
    local id_short="$4"
    
    # Determine state color
    local state_color="$C_GREEN"
    local state_icon="✓"
    if [[ "$state" != "running" ]]; then
        state_color="$C_YELLOW"
        local state_icon="●"
    fi
    
    printf '  %b%s%b [ID: %s] - %s %s (IP: %s)\n' \
        "$C_BOLD" "$name" "$C_RESET" "$id_short" "$state_icon" "$state" "$ip"
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0")

Shows all Docker networks and lists all containers attached to each.
Requires 'docker' and 'jq' to be installed.
EOF
}

# --- Validation and Setup ---
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${C_RED}Error: Docker command not found. Please ensure Docker is installed and in your PATH.${C_RESET}" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${C_RED}Error: jq command not found. Please install it to parse network inspection JSON.${C_RESET}" >&2
    exit 1
fi

# --- Main Logic ---
if [ "$#" -gt 0 ] && [[ "$1" == "--help" ]]; then
    print_usage
    exit 0
fi

# Get all network IDs
NETWORK_IDS=$(docker network ls -q)

if [ -z "$NETWORK_IDS" ]; then
    echo -e "${C_YELLOW}No Docker networks found.${C_RESET}"
    exit 0
fi

# Iterate over each network ID
for NET_ID in $NETWORK_IDS; do
    # Get network details in JSON format
    NETWORK_INFO=$(docker network inspect "$NET_ID" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${C_RED}Error inspecting network $NET_ID. Skipping.${C_RESET}"
        continue
    fi

    # Extract network name and driver
    NETWORK_NAME=$(echo "$NETWORK_INFO" | jq -r '.[0].Name')
    NETWORK_DRIVER=$(echo "$NETWORK_INFO" | jq -r '.[0].Driver')

    # Extract containers attached to this network safely
    CONTAINERS=$(echo "$NETWORK_INFO" | jq -r '.[0].Containers // {} | to_entries[] | "\(.value.Name)|\(.value.IPv4Address)|\(.key)"')

    if [ -z "$CONTAINERS" ]; then
        # Empty network: print simplified, single line, followed by a newline
        print_network_header "$NETWORK_NAME" "$NETWORK_DRIVER" false
        printf '%b[No containers attached]%b\n' "$C_GRAY" "$C_RESET"
    else
        # Populated network: print header and then iterate containers
        print_network_header "$NETWORK_NAME" "$NETWORK_DRIVER" true
        echo "$CONTAINERS" | while IFS='|' read -r CONTAINER_NAME IP CONTAINER_ID; do
            
            # Get container status for this specific container
            CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_ID")
            
            # Shorten ID for display
            ID_SHORT=${CONTAINER_ID:0:12}
            
            # Print container details using the enhanced model
            print_container "$CONTAINER_NAME" "$CONTAINER_STATUS" "$IP" "$ID_SHORT"
        done
    fi
done

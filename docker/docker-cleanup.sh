#!/bin/bash
set -e
set -o pipefail

# --- Default Configuration ---
FORCE=false
CLEAN_IMAGES=false
ALL_IMAGES=false # Controls 'docker image prune -a'

# --- Helper Functions ---
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

A utility to clean up unused Docker resources.

Options:
  --images          Clean up unused Docker images.
  --all-images      When cleaning images, remove all unused images, not just dangling ones.
                    (Equivalent to 'docker image prune -a').
  -f, --force       Do not prompt for confirmation before removing resources.
  -h, --help        Show this help message.
EOF
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --images) CLEAN_IMAGES=true ;;
        --all-images) ALL_IMAGES=true ;;
        -f|--force) FORCE=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# --- Validation ---
if ! command -v docker &> /dev/null; then
    log_msg "Error: 'docker' command not found. Please ensure Docker is installed and in your PATH."
    exit 1
fi

# --- Main Logic ---

# 1. Clean up Docker Images
if $CLEAN_IMAGES; then
    log_msg "--- Checking for Docker images to prune ---"
    
    prune_cmd="docker image prune"
    if $ALL_IMAGES; then
        prune_cmd+=" -a"
        log_msg "Pruning all unused images (including non-dangling)..."
    else
        log_msg "Pruning dangling images..."
    fi
    if $FORCE; then
        prune_cmd+=" -f"
    fi
    eval "$prune_cmd"
    
    echo # Add a newline for readability
else
    log_msg "No cleanup action specified. Use --images to clean up images."
    print_usage
fi

log_msg "Docker cleanup process finished."


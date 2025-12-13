#!/bin/bash
set -e
set -o pipefail

# --- Default Configuration ---
DRY_RUN=false
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
  --dry-run         Show what would be removed without actually deleting anything.
  -f, --force       Do not prompt for confirmation before removing resources.
  -h, --help        Show this help message.
EOF
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --images) CLEAN_IMAGES=true ;;
        --all-images) ALL_IMAGES=true ;;
        --dry-run) DRY_RUN=true ;;
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

if $DRY_RUN && $FORCE; then
    log_msg "Warning: --dry-run and --force are mutually exclusive. --dry-run will take precedence."
    FORCE=false
fi

if $DRY_RUN; then
    log_msg "--- DRY RUN MODE ENABLED --- No resources will be deleted."
fi

# --- Main Logic ---

# 1. Clean up Docker Images
if $CLEAN_IMAGES; then
    log_msg "--- Checking for Docker images to prune ---"
    if $DRY_RUN; then
        if $ALL_IMAGES; then
            log_msg "[DRY RUN] Would list all unused images (not just dangling)."
            # This is an approximation. `docker image prune -a` has complex logic.
            # We list images that are not tagged and not part of any container.
            image_ids=$(docker images -a -q --filter "dangling=true")
            if [ -n "$image_ids" ]; then
                echo "Dangling images that would be removed:"
                docker images --filter "dangling=true"
            else
                echo "No dangling images to remove."
            fi
            log_msg "[DRY RUN] Note: 'prune -a' also removes non-dangling, unused images, which is complex to simulate."
        else
            log_msg "[DRY RUN] Listing dangling images that would be removed:"
            image_ids=$(docker images -f "dangling=true" -q)
            if [ -n "$image_ids" ]; then
                docker images -f "dangling=true"
            else
                echo "No dangling images to remove."
            fi
        fi
    else
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
    fi
    
    echo # Add a newline for readability
else
    log_msg "No cleanup action specified. Use --images to clean up images."
    print_usage
fi

log_msg "Docker cleanup process finished."

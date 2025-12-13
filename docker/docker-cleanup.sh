#!/bin/bash
set -e
set -o pipefail

# --- Default Configuration ---
DRY_RUN=false
FORCE=false
CLEAN_IMAGES=false
CLEAN_NETWORKS=false
CLEAN_VOLUMES=false
CLEAN_CONTAINERS=false
ALL_IMAGES=false # Controls 'docker image prune -a'

# --- Helper Functions ---
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
}

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

A utility to clean up unused Docker resources like containers, images, networks, and volumes.
By default, if no resource type is specified, all are targeted for cleanup.

Options:
  --containers      Clean up stopped Docker containers.
  --images          Clean up unused Docker images.
  --networks        Clean up unused Docker networks.
  --volumes         Clean up unused Docker volumes.
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
        --containers) CLEAN_CONTAINERS=true ;;
        --images) CLEAN_IMAGES=true ;;
        --networks) CLEAN_NETWORKS=true ;;
        --volumes) CLEAN_VOLUMES=true ;;
        --all-images) ALL_IMAGES=true ;;
        --dry-run) DRY_RUN=true ;;
        -f|--force) FORCE=true ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# If no specific resource type is provided, default to cleaning all.
if ! $CLEAN_CONTAINERS && ! $CLEAN_IMAGES && ! $CLEAN_NETWORKS && ! $CLEAN_VOLUMES; then
    log_msg "No specific resource type selected. Defaulting to all (containers, images, networks, volumes)."
    CLEAN_CONTAINERS=true
    CLEAN_IMAGES=true
    CLEAN_NETWORKS=true
    CLEAN_VOLUMES=true
fi

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

# 1. Clean up stopped Docker Containers
if $CLEAN_CONTAINERS; then
    log_msg "--- Checking for stopped containers to prune ---"
    if $DRY_RUN; then
        log_msg "[DRY RUN] Listing stopped containers that would be removed:"
        # 'exited' covers containers that ran and finished. 'created' covers containers that were created but never started.
        docker ps -a --filter "status=exited" --filter "status=created"
    else
        prune_cmd="docker container prune"
        if $FORCE; then
            prune_cmd+=" -f"
        fi
        log_msg "Pruning stopped containers..."
        eval "$prune_cmd"
    fi
    echo # Add a newline for readability
fi


# 2. Clean up Docker Images
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
fi

# 3. Clean up Docker Networks
if $CLEAN_NETWORKS; then
    log_msg "--- Checking for Docker networks to prune ---"
    if $DRY_RUN; then
        log_msg "[DRY RUN] Listing custom networks that are not used by any container:"
        # The 'driver!=' filter is not supported on all Docker versions.
        # Instead, we list all networks and use grep to exclude the default ones.
        docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none)$' | while read -r net; do
            # Check if any container (running or stopped) is using this network.
            if [ -z "$(docker ps -aq --filter network="$net")" ]; then
                echo "  - $net"
            fi
        done
    else
        prune_cmd="docker network prune"
        if $FORCE; then
            prune_cmd+=" -f"
        fi
        log_msg "Pruning unused networks..."
        eval "$prune_cmd"
    fi
    echo
fi


# 4. Clean up Docker Volumes
if $CLEAN_VOLUMES; then
    log_msg "--- Checking for Docker volumes to prune ---"
    if $DRY_RUN; then
        log_msg "[DRY RUN] Listing dangling volumes (not used by any container):"
        docker volume ls -f "dangling=true"
    else
        prune_cmd="docker volume prune"
        if $FORCE; then
            prune_cmd+=" -f"
        fi
        log_msg "Pruning unused volumes..."
        eval "$prune_cmd"
    fi
    echo
fi


log_msg "Docker cleanup process finished."

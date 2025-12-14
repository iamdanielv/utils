#!/bin/bash
set -o pipefail

# Source the shared library for colors and utilities
source "$(dirname "${BASH_SOURCE[0]}")/../src/lib/shared.lib.sh"

# --- Default Configuration ---
DRY_RUN=false
FORCE=false
CLEAN_IMAGES=false
CLEAN_NETWORKS=false
CLEAN_VOLUMES=false
CLEAN_CONTAINERS=false
ALL_IMAGES=false # Controls 'docker image prune -a'

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

A utility to clean up unused Docker resources.
By default, if no resource type is specified, all are targeted for cleanup.

Options:
  ${C_L_BLUE}--containers${T_RESET}      Clean up stopped Docker containers.
  ${C_L_BLUE}--images${T_RESET}          Clean up unused (dangling) Docker images.
  ${C_L_BLUE}--networks${T_RESET}        Clean up unused Docker networks.
  ${C_L_BLUE}--volumes${T_RESET}         Clean up unused Docker volumes.
  ${C_L_BLUE}--all-images${T_RESET}      When cleaning images, remove all unused images, not just dangling ones.
  ${C_L_BLUE}--dry-run${T_RESET}         Show what would be removed without actually deleting anything.
  ${C_L_BLUE}-f, --force${T_RESET}       Do not prompt for confirmation before removing resources.
  ${C_L_BLUE}-h, --help${T_RESET}        Show this help message.
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
        *) print_usage; printErrMsg "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# If no specific resource type is provided, default to cleaning all.
if ! $CLEAN_CONTAINERS && ! $CLEAN_IMAGES && ! $CLEAN_NETWORKS && ! $CLEAN_VOLUMES; then
    printInfoMsg "No specific resource type selected. Defaulting to all (containers, images, networks, volumes)."
    CLEAN_CONTAINERS=true
    CLEAN_IMAGES=true
    CLEAN_NETWORKS=true
    CLEAN_VOLUMES=true
fi

# --- Validation ---
if ! command -v docker &> /dev/null; then
    printErrMsg "Error: 'docker' command not found. Please ensure Docker is installed and in your PATH."
    exit 1
fi

if $DRY_RUN && $FORCE; then
    printInfoMsg "Warning: --dry-run and --force are mutually exclusive. --dry-run will take precedence."
    FORCE=false
fi

if $DRY_RUN; then
    printBannerColor "${C_YELLOW}" "DRY RUN MODE ENABLED" "No resources will be deleted."
fi

# --- Main Logic ---

step_count=0

# 1. Clean up stopped Docker Containers
if $CLEAN_CONTAINERS; then
    ((++step_count))
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for stopped containers to prune"
    if $DRY_RUN; then
        # 'exited' covers containers that ran and finished. 'created' covers containers that were created but never started.
        stopped_containers=$(docker ps -a --filter "status=exited" --filter "status=created" --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}')
        if [ -n "$stopped_containers" ]; then
            printInfoMsg "The following stopped containers would be removed:"
            echo "$stopped_containers" | column -t -s $'\t'
        else
            printOkMsg "No stopped containers to prune."
        fi
    else
        prune_cmd=("docker" "container" "prune")
        if $FORCE; then
            prune_cmd+=("-f")
        fi
        printMsg "Pruning stopped containers..."
        "${prune_cmd[@]}"
    fi
fi


# 2. Clean up Docker Images
if $CLEAN_IMAGES; then
    ((++step_count))
    image_type=$($ALL_IMAGES && echo "all unused" || echo "dangling")
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for ${image_type} images to prune"

    if $DRY_RUN; then
        filter="dangling=true"
        if $ALL_IMAGES; then
            # `docker image prune -a` removes images without at least one container associated with them.
            # This is a close approximation.
            unused_images=$(docker images -a --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}' | while read -r id repo tag; do
                # Check if the image ID is used by any container (running or stopped)
                if [ -z "$(docker ps -a -q --filter "ancestor=$id")" ]; then
                    echo -e "$id\t$repo\t$tag"
                fi
            done)
            if [ -n "$unused_images" ]; then
                printInfoMsg "The following unused images would be removed:"
                echo "$unused_images" | column -t -s $'\t'
            else
                printOkMsg "No unused images to prune."
            fi
        else
            dangling_images=$(docker images -f "dangling=true" --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}')
            if [ -n "$dangling_images" ]; then
                printInfoMsg "The following dangling images would be removed:"
                echo "$dangling_images" | column -t -s $'\t'
            else
                printOkMsg "No dangling images to prune."
            fi
        fi
    else
        prune_cmd=("docker" "image" "prune")
        if $ALL_IMAGES; then
            prune_cmd+=("-a")
            printMsg "Pruning all unused images (including non-dangling)..."
        else
            printMsg "Pruning dangling images..."
        fi
        if $FORCE; then
            prune_cmd+=("-f")
        fi
        "${prune_cmd[@]}"
    fi
fi

# 3. Clean up Docker Networks
if $CLEAN_NETWORKS; then
    ((++step_count))
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for unused Docker networks to prune"
    if $DRY_RUN; then
        unused_networks=$(docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none)$' | while read -r net; do
            # Check if any container (running or stopped) is using this network.
            if [ -z "$(docker ps -aq --filter network="$net")" ]; then
                echo "$net"
            fi
        done)
        if [ -n "$unused_networks" ]; then
            printInfoMsg "The following unused networks would be removed:"
            echo "$unused_networks" | sed 's/^/  - /'
        else
            printOkMsg "No unused networks to prune."
        fi
    else
        prune_cmd=("docker" "network" "prune")
        if $FORCE; then
            prune_cmd+=("-f")
        fi
        printMsg "Pruning unused networks..."
        "${prune_cmd[@]}"
    fi
fi


# 4. Clean up Docker Volumes
if $CLEAN_VOLUMES; then
    ((++step_count))
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for unused (dangling) Docker volumes to prune"
    if $DRY_RUN; then
        dangling_volumes=$(docker volume ls -f "dangling=true" --format '{{.Name}}')
        if [ -n "$dangling_volumes" ]; then
            printInfoMsg "The following dangling volumes would be removed:"
            echo "$dangling_volumes" | sed 's/^/  - /'
        else
            printOkMsg "No dangling volumes to prune."
        fi
    else
        prune_cmd=("docker" "volume" "prune")
        if $FORCE; then
            prune_cmd+=("-f")
        fi
        printMsg "Pruning unused volumes..."
        "${prune_cmd[@]}"
    fi
fi

printOkMsg "Docker cleanup process finished."

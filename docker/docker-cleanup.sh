#!/bin/bash
set -o pipefail

# --- Embedded TUI Library ---
# Colors
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'
C_L_RED=$'\033[31;1m'
C_L_BLUE=$'\033[34m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'

# Icons
T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"

# Logging
printMsg() { printf '%b\n' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
printInfoMsg() { printMsg "${T_INFO_ICON} ${1}${T_RESET}"; }

# String Utils for Banner
strip_ansi_codes() {
    local s="$1"; local esc=$'\033'
    if [[ "$s" != *"$esc"* ]]; then echo -n "$s"; return; fi
    local pattern="$esc\\[[0-9;]*[a-zA-Z]"
    while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
    echo -n "$s"
}

_truncate_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"; local trunc_char_len=${#trunc_char}
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then echo -n "$input_str"; return; fi
    local truncate_to_len=$(( max_len - trunc_char_len )); local new_str=""; local visible_count=0; local i=0; local in_escape=false
    while (( i < ${#input_str} && visible_count < truncate_to_len )); do
        local char="${input_str:i:1}"; new_str+="$char"
        if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then (( visible_count++ )); fi
        if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi; ((i++))
    done
    echo -n "${new_str}${trunc_char}"
}

printBannerColor() {
    local color="$1"
    local title="$2"
    local subtitle="$3"
    local prefix="┏"; local suffix="┓"

    if [[ -z "$subtitle" ]]; then
        prefix="━"; suffix="━"
    fi

    local total_width=70; local line
    printf -v line '%*s' "$((total_width - 2))"; line="${line// /━}"
    printf '%s' "${color}${prefix}${line}${suffix}${T_RESET}"; printf '\r'
    local text_to_print; text_to_print=$(_truncate_string "$title" $((total_width - 4)))
    printf '%s\n' "${color}${prefix} ${text_to_print} ${T_RESET}"

    if [[ -n "$subtitle" ]]; then
        local truncated_subtitle; truncated_subtitle=$(_truncate_string "$subtitle" $((total_width - 5)))
        local visible_subtitle_len; visible_subtitle_len=$(strip_ansi_codes "$truncated_subtitle" | wc -c)
        local subtitle_line_len=$(( total_width - 4 - visible_subtitle_len ))
        if (( subtitle_line_len < 0 )); then subtitle_line_len=0; fi
        printf -v line '%*s' "$subtitle_line_len"; line="${line// /━}"
        printf '%s\n' "${color}┗ ${truncated_subtitle} ${line}┛${T_RESET}"
    fi
}

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

# If no resource type is provided, default to cleaning all
if ! $CLEAN_CONTAINERS && ! $CLEAN_IMAGES && ! $CLEAN_NETWORKS && ! $CLEAN_VOLUMES; then
    printBannerColor "${C_CYAN}" "No resource selected" "${T_BOLD}Default to ALL (containers, images, networks, volumes)"
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
    printBannerColor "${C_YELLOW}" "DRY RUN MODE ENABLED" "No resources will be deleted"
fi

# --- Main Logic ---

step_count=0

# 1. Clean up stopped Docker Containers
if $CLEAN_CONTAINERS; then
    ((++step_count))
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for stopped containers to prune"
    # 'exited' covers containers that ran and finished. 'created' covers containers that were created but never started.
    stopped_containers=$(docker ps -a --filter "status=exited" --filter "status=created" --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}')

    if [ -z "$stopped_containers" ]; then
        printOkMsg "No stopped containers to prune."
    else
        if $DRY_RUN; then
            printInfoMsg "The following stopped containers would be removed:"
            echo "$stopped_containers" | column -t -s $'\t'
        else
            printInfoMsg "The following stopped containers will be removed:"
            echo "$stopped_containers" | column -t -s $'\t'
            prune_cmd=("docker" "container" "prune")
            $FORCE && prune_cmd+=("-f")
            # printMsg "\nPruning stopped containers..."
            "${prune_cmd[@]}"
        fi
    fi
    echo
fi


# 2. Clean up Docker Images
if $CLEAN_IMAGES; then
    ((++step_count))
    image_type=$($ALL_IMAGES && echo "all unused" || echo "dangling")
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for ${image_type} images to prune"

    images_to_prune=""
    if $ALL_IMAGES; then
        # `docker image prune -a` removes images without at least one container associated with them.
        # This is a close approximation.
        images_to_prune=$(docker images -a --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}' | while read -r id repo tag; do
            # Check if the image ID is used by any container (running or stopped)
            if [ -z "$(docker ps -a -q --filter "ancestor=$id")" ]; then
                echo -e "$id\t$repo\t$tag"
            fi
        done)
    else
        images_to_prune=$(docker images -f "dangling=true" --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}')
    fi

    if [ -z "$images_to_prune" ]; then
        printOkMsg "No ${image_type} images to prune."
    else
        if $DRY_RUN; then
            printInfoMsg "The following ${image_type} images would be removed:"
            echo "$images_to_prune" | column -t -s $'\t'
        else
            printInfoMsg "The following ${image_type} images will be removed:"
            echo "$images_to_prune" | column -t -s $'\t'
            prune_cmd=("docker" "image" "prune")
            if $ALL_IMAGES; then
                prune_cmd+=("-a")
                printMsg "\nPruning all unused images (including non-dangling)..."
            else
                printMsg "\nPruning dangling images..."
            fi
            $FORCE && prune_cmd+=("-f")
            "${prune_cmd[@]}"
        fi
    fi
    echo
fi

# 3. Clean up Docker Networks
if $CLEAN_NETWORKS; then
    ((++step_count))
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for unused Docker networks to prune"
    unused_networks=$(docker network ls --format '{{.Name}}' | grep -v -E '^(bridge|host|none)$' || true | while read -r net; do
        # Check if any container (running or stopped) is using this network.
        if [ -z "$(docker ps -aq --filter network="$net")" ]; then
            echo "$net"
        fi
    done)

    if [ -z "$unused_networks" ]; then
        printOkMsg "No unused networks to prune."
    else
        if $DRY_RUN; then
            printInfoMsg "The following unused networks would be removed:"
            echo "$unused_networks" | sed 's/^/  - /'
        else
            printInfoMsg "The following unused networks will be removed:"
            echo "$unused_networks" | sed 's/^/  - /'
            prune_cmd=("docker" "network" "prune")
            $FORCE && prune_cmd+=("-f")
            # printMsg "\nPruning unused networks..."
            "${prune_cmd[@]}"
        fi
    fi
    echo
fi


# 4. Clean up Docker Volumes
if $CLEAN_VOLUMES; then
    ((++step_count))
    printBannerColor "${C_L_BLUE}" "${step_count}. Checking for unused (dangling) Docker volumes to prune"
    dangling_volumes=$(docker volume ls -f "dangling=true" --format '{{.Name}}')

    if [ -z "$dangling_volumes" ]; then
        printOkMsg "No dangling volumes to prune."
    else
        if $DRY_RUN; then
            printInfoMsg "The following dangling volumes would be removed:"
            echo "$dangling_volumes" | sed 's/^/  - /'
        else
            printInfoMsg "The following dangling volumes will be removed:"
            echo "$dangling_volumes" | sed 's/^/  - /'
            prune_cmd=("docker" "volume" "prune")
            $FORCE && prune_cmd+=("-f")
            # printMsg "\nPruning unused volumes..."
            "${prune_cmd[@]}"
        fi
    fi
    echo
fi

printBannerColor "${C_GREEN}" "Docker cleanup process finished"

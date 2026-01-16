#!/bin/bash
# ==============================================================================
# Script Name: sync-tmux.sh
# Description: Quickly syncs local tmux config and scripts to ~/.config/tmux
#              for rapid development and testing.
# Usage:       ./sync-tmux.sh [-c|--cleanup] [-l|--list] [-h|--help]
# ==============================================================================

set -e

# Colors
C_BLUE=$'\033[1;34m'
C_GREEN=$'\033[32m'
C_RED=$'\033[31m'
C_YELLOW=$'\033[33m'
C_BOLD=$'\033[1m'
T_RESET=$'\033[0m'

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Quickly syncs local tmux config and scripts to ~/.config/tmux
for rapid development and testing.

Options:
  ${C_BLUE}-c, --cleanup${T_RESET}   Remove old backup directories (tmux.bak_*)
  ${C_BLUE}-l, --list${T_RESET}      List existing backup directories
  ${C_BLUE}-h, --help${T_RESET}      Show this help message
EOF
}

# Parse Arguments
CLEANUP=false
LIST_BACKUPS=false
for arg in "$@"; do
    case $arg in
        -c|--cleanup) CLEANUP=true ;;
        -l|--list)    LIST_BACKUPS=true ;;
        -h|--help)    print_usage; exit 0 ;;
        *) print_usage; exit 1 ;;
    esac
done

# Where are we running?
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Paths
SRC_CONF="${SCRIPT_DIR}/.config/tmux/tmux.conf"
SRC_SCRIPTS="${SCRIPT_DIR}/.config/tmux/scripts/dv"

DEST_CONF="${HOME}/.config/tmux/tmux.conf"
DEST_SCRIPTS_DIR="${HOME}/.config/tmux/scripts/dv"
DEST_BASE_DIR="${HOME}/.config/tmux"

if [ "$LIST_BACKUPS" = true ]; then
    echo "${C_BLUE}🔍 Existing backups in ${HOME}/.config:${T_RESET}"
    found_backups=$(find "${HOME}/.config" -maxdepth 1 -type d -name "tmux.bak_*" 2>/dev/null | sort)

    if [ -n "$found_backups" ]; then
        echo "$found_backups" | while read -r line; do
            echo "  - $(basename "$line")"
        done
        count=$(echo "$found_backups" | wc -l)
        echo "  📊 Total: $count"
    else
        echo "  ✨ No backups found."
    fi
    exit 0
fi

if [ "$CLEANUP" = true ]; then
    echo "${C_BLUE}🧹 Cleaning up old backups...${T_RESET}"
    count=$(find "${HOME}/.config" -maxdepth 1 -type d -name "tmux.bak_*" 2>/dev/null | wc -l)

    if [ "$count" -gt 0 ]; then
        read -p "  ❓ Are you sure you want to delete $count backup(s)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            find "${HOME}/.config" -maxdepth 1 -type d -name "tmux.bak_*" -exec rm -rf {} + 2>/dev/null || true
            echo "  ${C_GREEN}✅ Removed $count old backup(s).${T_RESET}"
        else
            echo "  ${C_RED}❌ Cleanup cancelled.${T_RESET}"
        fi
    else
        echo "  ✨ No old backups found."
    fi
    exit 0
fi

echo "${C_BLUE}🔄 Syncing Tmux Configuration...${T_RESET}"

# 0. Backup existing config
if [ -d "$DEST_BASE_DIR" ]; then
    BACKUP_DIR="${DEST_BASE_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "  ${C_YELLOW}📦 Backing up${T_RESET} current config to $BACKUP_DIR..."
    cp -r "$DEST_BASE_DIR" "$BACKUP_DIR"
fi

# 1. Sync tmux.conf
if [ -f "$SRC_CONF" ]; then
    mkdir -p "$(dirname "$DEST_CONF")"
    cp "$SRC_CONF" "$DEST_CONF"
    echo "  ${C_GREEN}✅ Updated:${T_RESET} $DEST_CONF"
else
    echo "  ${C_RED}❌ Error:${T_RESET} Source tmux.conf not found at $SRC_CONF"
fi

# 2. Sync Scripts
if [ -d "$SRC_SCRIPTS" ]; then
    mkdir -p "$DEST_SCRIPTS_DIR"
    cp "$SRC_SCRIPTS"/* "$DEST_SCRIPTS_DIR" 2>/dev/null || true
    chmod +x "$DEST_SCRIPTS_DIR"/*.sh 2>/dev/null || true
    echo "  ${C_GREEN}✅ Updated:${T_RESET} Scripts in $DEST_SCRIPTS_DIR"
    ls -1 "$DEST_SCRIPTS_DIR" | sed 's/^/      - /'
else
    echo "  ${C_RED}❌ Error:${T_RESET} Source scripts directory not found at $SRC_SCRIPTS"
fi

# 3. Reload if in Tmux
if [ -n "$TMUX" ]; then
    tmux source-file "$DEST_CONF"
    tmux display-message "Dev Config Synced & Reloaded!"
    echo "  ${C_GREEN}⚡ Reloaded${T_RESET} active tmux session."
    echo "  ${C_BLUE}🔍 Verifying script bindings:${T_RESET}"

    # Check each script to see if it is bound in the current session
    current_bindings=$(tmux list-keys -a)

    for script in "$SRC_SCRIPTS"/*.sh; do
        [ -e "$script" ] || continue
        script_name=$(basename "$script")

        match=$(echo "$current_bindings" | grep -F "$script_name" | head -n 1)
        if [ -n "$match" ]; then
            # Extract Table
            if [[ "$match" =~ -T[[:space:]]+([^[:space:]]+) ]]; then
                table="${BASH_REMATCH[1]}"
            else
                table="prefix"
            fi

            # Extract Key by stripping known flags
            # 1. Remove 'bind-key' or 'bind' and optional '-r'
            temp=$(echo "$match" | sed -E 's/^(bind-key|bind)[[:space:]]+(-r[[:space:]]+)?//')
            # 2. Remove '-N "Note"' if present (in case it appears in the command string)
            temp=$(echo "$temp" | sed -E "s/-N[[:space:]]+(\"[^\"]*\"|'[^']*')[[:space:]]+//")
            # 3. Remove '-T table' if present
            temp=$(echo "$temp" | sed -E 's/-T[[:space:]]+[^[:space:]]+[[:space:]]+//')
            # 4. The first remaining word is the key
            key=$(echo "$temp" | awk '{print $1}')

            # Fetch Note explicitly using the key and table
            note=$(tmux list-keys -N -T "$table" "$key" 2>/dev/null | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')

            if [ "$table" == "prefix" ]; then
                label="Prefix + $key"
            elif [ "$table" == "root" ]; then
                label="$key"
            else
                label="$table: $key"
            fi
            if [ -n "$note" ]; then
                echo "      ${C_GREEN}✅ $script_name${T_RESET} ($label) → \"$note\""
            else
                echo "      ${C_GREEN}✅ $script_name${T_RESET} ($label)"
            fi
        else
            echo "      ${C_YELLOW}⚠️  $script_name${T_RESET} (Not bound)"
        fi
    done
else
    echo "  ${C_BLUE}Not inside tmux.${T_RESET} Run '${C_BOLD}tmux source ~/.config/tmux/tmux.conf${T_RESET}' to apply."
fi

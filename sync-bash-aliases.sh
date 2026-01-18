#!/bin/bash
# ==============================================================================
# Script Name: sync-bash-aliases.sh
# Description: Quickly syncs local .bash_aliases to ~/.bash_aliases
#              for rapid development and testing.
# Usage:       ./sync-bash-aliases.sh [-c|--cleanup] [-l|--list] [-h|--help]
# ==============================================================================

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

Quickly syncs local .bash_aliases to ~/.bash_aliases
for rapid development and testing.

Options:
  ${C_BLUE}-c, --cleanup${T_RESET}   Remove old backup files (.bash_aliases.bak_*)
  ${C_BLUE}-l, --list${T_RESET}      List existing backup files
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

SRC_FILE="${SCRIPT_DIR}/config/bash/aliases"
DEST_FILE="${HOME}/.bash_aliases"

if [ "$LIST_BACKUPS" = true ]; then
    echo "${C_BLUE}🔍 Existing backups in ${HOME}:${T_RESET}"
    found_backups=$(find "${HOME}" -maxdepth 1 -type f -name ".bash_aliases.bak_*" 2>/dev/null | sort)

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
    count=$(find "${HOME}" -maxdepth 1 -type f -name ".bash_aliases.bak_*" 2>/dev/null | wc -l)

    if [ "$count" -gt 0 ]; then
        read -p "  ❓ Are you sure you want to delete $count backup(s)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            find "${HOME}" -maxdepth 1 -type f -name ".bash_aliases.bak_*" -exec rm {} + 2>/dev/null || true
            echo "  ${C_GREEN}✅ Removed $count old backup(s).${T_RESET}"
        else
            echo "  ${C_RED}❌ Cleanup cancelled.${T_RESET}"
        fi
    else
        echo "  ✨ No old backups found."
    fi
    exit 0
fi

echo "${C_BLUE}🔄 Syncing .bash_aliases...${T_RESET}"

if [ ! -f "$SRC_FILE" ]; then
    echo "  ${C_RED}❌ Error:${T_RESET} Source file not found at $SRC_FILE"
    exit 1
fi

# Backup
if [ -f "$DEST_FILE" ]; then
    BACKUP_FILE="${DEST_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "  ${C_YELLOW}📦 Backing up${T_RESET} current file to $(basename "$BACKUP_FILE")..."
    cp "$DEST_FILE" "$BACKUP_FILE"
fi

# Copy
if cp "$SRC_FILE" "$DEST_FILE"; then
    echo "  ${C_GREEN}✅ Updated:${T_RESET} $DEST_FILE"
else
    echo "  ${C_RED}❌ Error:${T_RESET} Failed to copy file to $DEST_FILE"
    exit 1
fi

echo ""
echo "${C_BOLD}${C_GREEN}Done...${T_RESET}"
echo "    To apply changes to the current session, run:"
echo "      ${C_BLUE}source ~/.bash_aliases${T_RESET}"

# If in Tmux, pre-type the command for the user
if [[ -n "$TMUX" ]] && command -v tmux &>/dev/null; then
    # Use send-keys to populate the prompt
    tmux send-keys -t "$(tmux display-message -p "#{pane_id}")" "source ~/.bash_aliases"
fi

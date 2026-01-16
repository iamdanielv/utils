#!/bin/bash
# ==============================================================================
# Script Name: sync-bash-aliases.sh
# Description: Quickly syncs local .bash_aliases to ~/.bash_aliases
#              for rapid development and testing.
# Usage:       ./sync-bash-aliases.sh
# ==============================================================================

# Colors
C_L_BLUE=$'\033[1;34m'
C_GREEN=$'\033[1;32m'
C_RED=$'\033[1;31m'
C_YELLOW=$'\033[1;33m'
T_RESET=$'\033[0m'

# Where are we running?
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

SRC_FILE="${SCRIPT_DIR}/.bash_aliases"
DEST_FILE="${HOME}/.bash_aliases"

echo "🔄 Syncing .bash_aliases..."

if [ ! -f "$SRC_FILE" ]; then
    echo "  ${C_RED}❌ Error: Source file not found at $SRC_FILE${T_RESET}"
    exit 1
fi

# Backup
if [ -f "$DEST_FILE" ]; then
    BACKUP_FILE="${DEST_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "  📦 Backing up current file to $(basename "$BACKUP_FILE")..."
    cp "$DEST_FILE" "$BACKUP_FILE"
fi

# Copy
if cp "$SRC_FILE" "$DEST_FILE"; then
    echo "  ✅ Updated: $DEST_FILE"
else
    echo "  ${C_RED}❌ Error: Failed to copy file to $DEST_FILE${T_RESET}"
    exit 1
fi

echo ""
echo "${C_GREEN}Done...${T_RESET}"
echo "    To apply changes to the current session, run:"
echo "      ${C_L_BLUE}source ~/.bash_aliases${T_RESET}"

# If in Tmux, pre-type the command for the user
if [[ -n "$TMUX" ]] && command -v tmux &>/dev/null; then
    # Use send-keys to populate the prompt
    tmux send-keys -t "$(tmux display-message -p "#{pane_id}")" "source ~/.bash_aliases"
fi

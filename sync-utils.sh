#!/bin/bash
# ==============================================================================
# Script Name: sync-utils.sh
# Description: Quickly syncs local config (tmux, bash, bin) to system paths
#              for rapid development and testing.
# Usage:       ./sync-utils.sh [-c|--cleanup] [-l|--list] [-h|--help]
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

Quickly syncs local configuration to system paths for rapid development.
Targets:
  - Tmux: ~/.config/tmux
  - Bash: ~/.bash_aliases
  - Bin:  ~/.local/bin

Options:
  ${C_BLUE}-c, --cleanup${T_RESET}   Remove old backup files/directories
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

# Tmux Paths
SRC_TMUX_CONF="${SCRIPT_DIR}/config/tmux/tmux.conf"
SRC_TMUX_SCRIPTS="${SCRIPT_DIR}/config/tmux/scripts/dv"
DEST_TMUX_CONF="${HOME}/.config/tmux/tmux.conf"
DEST_TMUX_SCRIPTS_DIR="${HOME}/.config/tmux/scripts/dv"
DEST_TMUX_BASE_DIR="${HOME}/.config/tmux"

# Bash Paths
SRC_BASH_ALIASES="${SCRIPT_DIR}/config/bash/.bash_aliases"
DEST_BASH_ALIASES="${HOME}/.bash_aliases"

# Bin Paths
SRC_BIN_DIR="${SCRIPT_DIR}/bin"
DEST_BIN_DIR="${HOME}/.local/bin"

if [ "$LIST_BACKUPS" = true ]; then
    echo "${C_BLUE}[i] Existing backups:${T_RESET}"
    # Find tmux backups
    find "${HOME}/.config" -maxdepth 1 -type d -name "tmux.bak_*" 2>/dev/null | sort | sed 's/^/  - /'
    # Find bash backups
    find "${HOME}" -maxdepth 1 -type f -name ".bash_aliases.bak_*" 2>/dev/null | sort | sed 's/^/  - /'

    exit 0
fi

if [ "$CLEANUP" = true ]; then
    echo "${C_BLUE}[i] Cleaning up old backups...${T_RESET}"
    
    tmux_backups=$(find "${HOME}/.config" -maxdepth 1 -type d -name "tmux.bak_*" 2>/dev/null)
    bash_backups=$(find "${HOME}" -maxdepth 1 -type f -name ".bash_aliases.bak_*" 2>/dev/null)
    
    count_tmux=$(echo "$tmux_backups" | grep -v "^$" | wc -l)
    count_bash=$(echo "$bash_backups" | grep -v "^$" | wc -l)
    total_count=$((count_tmux + count_bash))

    if [ "$total_count" -gt 0 ]; then
        read -p "  [?] Are you sure you want to delete $total_count backup(s)? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ "$count_tmux" -gt 0 ]; then
                echo "$tmux_backups" | xargs rm -rf
            fi
            if [ "$count_bash" -gt 0 ]; then
                echo "$bash_backups" | xargs rm -f
            fi
            echo "  ${C_GREEN}[✓] Removed $total_count old backup(s).${T_RESET}"
        else
            echo "  ${C_RED}[✗] Cleanup cancelled.${T_RESET}"
        fi
    else
        echo "  [i] No old backups found."
    fi
    exit 0
fi

# --- 1. Tmux Sync ---
echo "${C_BLUE}[i] Syncing Tmux Configuration...${T_RESET}"

# Backup existing config
if [ -d "$DEST_TMUX_BASE_DIR" ]; then
    BACKUP_DIR="${DEST_TMUX_BASE_DIR}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "  ${C_YELLOW}[i] Backing up${T_RESET} current config to $BACKUP_DIR..."
    cp -r "$DEST_TMUX_BASE_DIR" "$BACKUP_DIR"
fi

# Sync tmux.conf
if [ -f "$SRC_TMUX_CONF" ]; then
    mkdir -p "$(dirname "$DEST_TMUX_CONF")"
    cp "$SRC_TMUX_CONF" "$DEST_TMUX_CONF"
    echo "  ${C_GREEN}[✓] Updated:${T_RESET} $DEST_TMUX_CONF"
else
    echo "  ${C_RED}[✗] Error:${T_RESET} Source tmux.conf not found at $SRC_TMUX_CONF"
fi

# Sync Scripts
if [ -d "$SRC_TMUX_SCRIPTS" ]; then
    mkdir -p "$DEST_TMUX_SCRIPTS_DIR"
    cp "$SRC_TMUX_SCRIPTS"/* "$DEST_TMUX_SCRIPTS_DIR" 2>/dev/null || true
    chmod +x "$DEST_TMUX_SCRIPTS_DIR"/*.sh 2>/dev/null || true
    echo "  ${C_GREEN}[✓] Updated:${T_RESET} Scripts in $DEST_TMUX_SCRIPTS_DIR"
    ls -1 "$DEST_TMUX_SCRIPTS_DIR" | sed 's/^/      - /'
else
    echo "  ${C_RED}[✗] Error:${T_RESET} Source scripts directory not found at $SRC_TMUX_SCRIPTS"
fi

# --- 2. Bash Sync ---
echo ""
echo "${C_BLUE}[i] Syncing Bash Aliases...${T_RESET}"

if [ -f "$DEST_BASH_ALIASES" ]; then
    BACKUP_FILE="${DEST_BASH_ALIASES}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "  ${C_YELLOW}[i] Backing up${T_RESET} current file to $(basename "$BACKUP_FILE")..."
    cp "$DEST_BASH_ALIASES" "$BACKUP_FILE"
fi

if cp "$SRC_BASH_ALIASES" "$DEST_BASH_ALIASES"; then
    echo "  ${C_GREEN}[✓] Updated:${T_RESET} $DEST_BASH_ALIASES"
else
    echo "  ${C_RED}[✗] Error:${T_RESET} Failed to copy file to $DEST_BASH_ALIASES"
fi

# --- 3. Bin Sync ---
echo ""
echo "${C_BLUE}[i] Syncing Binaries...${T_RESET}"
if [ -d "$SRC_BIN_DIR" ]; then
    mkdir -p "$DEST_BIN_DIR"
    cp "$SRC_BIN_DIR"/* "$DEST_BIN_DIR/" 2>/dev/null || true
    chmod +x "$DEST_BIN_DIR"/dv-* 2>/dev/null || true
    echo "  ${C_GREEN}[✓] Updated:${T_RESET} Binaries in $DEST_BIN_DIR"
else
    echo "  ${C_YELLOW}[!] No binaries found in $SRC_BIN_DIR${T_RESET}"
fi

# --- 4. Post-Sync Actions ---
echo ""
if [ -n "$TMUX" ]; then
    tmux source-file "$DEST_TMUX_CONF"
    tmux display-message "Dev Config Synced & Reloaded!"
    echo "  ${C_GREEN}[✓] Reloaded${T_RESET} active tmux session."
    echo "  ${C_BLUE}[i] Verifying script bindings:${T_RESET}"

    # Check each script to see if it is bound in the current session
    current_bindings=$(tmux list-keys -a)

    for script in "$SRC_TMUX_SCRIPTS"/*.sh; do
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
                echo "      ${C_GREEN}[✓] $script_name${T_RESET} ($label) → \"$note\""
            else
                echo "      ${C_GREEN}[✓] $script_name${T_RESET} ($label)"
            fi
        else
            echo "      ${C_YELLOW}[!] $script_name${T_RESET} (Not bound)"
        fi
    done
else
    echo "  ${C_BLUE}Not inside tmux.${T_RESET} Run '${C_BOLD}tmux source ~/.config/tmux/tmux.conf${T_RESET}' to apply."
fi

echo ""
echo "  ${C_BLUE}To apply bash changes:${T_RESET} source ~/.bash_aliases"
# If in Tmux, pre-type the command for the user
if [[ -n "$TMUX" ]] && command -v tmux &>/dev/null; then
    tmux send-keys -t "$(tmux display-message -p "#{pane_id}")" "source ~/.bash_aliases"
fi

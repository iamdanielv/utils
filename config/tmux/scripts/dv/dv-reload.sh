#!/bin/bash
# ==============================================================================
# Script Name: dv-reload.sh
# Description: Reloads the tmux configuration file.
# Keybinding:  Prefix + r
# Config:      bind -N "Reload Tmux Configuration" r run-shell -b "~/.config/tmux/scripts/dv/dv-reload.sh"
# Dependencies: tmux
# ==============================================================================

# --- Safety Check ---
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run within a tmux session."
    exit 1
fi

if [ -f ~/.config/tmux/tmux.conf ]; then
    tmux source-file ~/.config/tmux/tmux.conf
    tmux display-message "Reloaded ~/.config/tmux/tmux.conf ..."
elif [ -f ~/.tmux.conf ]; then
    tmux source-file ~/.tmux.conf
    tmux display-message "Reloaded ~/.tmux.conf ..."
else
    tmux display-message "Error: No config file found!"
fi
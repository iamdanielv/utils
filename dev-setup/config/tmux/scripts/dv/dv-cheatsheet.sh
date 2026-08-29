#!/bin/bash
# ===============
# Script Name: dv-cheatsheet.sh
# Description: Displays a popup with keybinding cheatsheet
# Keybinding:  Prefix + /
# Config:      bind / run-shell -b "~/.config/tmux/scripts/dv/dv-cheatsheet.sh"
# Dependencies: tmux, less
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/common.sh"

# --- Display Logic (Recursive Call) ---
if [[ "$1" == "--show" ]]; then
    # ANSI Colors
    C="$ansi_blue"
    R=$'\033[0m'

    cat <<EOF | less -R
NAVIGATION - Direct
  ${C}C-h/j/k/l${R}    Move between panes (vim-aware)

NAVIGATION - with Prefix
  ${C}C-p / C-n${R}    Previous / Next Window

WINDOWS & PANES
  ${C}- / =${R}        New Split Vertical / Horizontal
  ${C}b${R}            Send Pane to [Current Session] +:New Window
  ${C}j${R}            Join a Pane to [Current Session]
  ${C}k${R}            Send a Pane to [Session] window
  ${C}s${R}            Session Manager
  ${C}S${R}            Choose Tree (Default Session Management)
  ${C}S-Left/Right${R} Swap window position
  ${C}z${R}            Zoom pane

LAYOUT & SYNC
  ${C}C-s${R}          Toggle Sync Panes
  ${C}M-h${R}          Even Horizontal Layout
  ${C}M-v${R}          Even Vertical Layout
  ${C}M-t${R}          Tiled Layout

COPY MODE
  ${C}v${R}            Enter Copy Mode
  ${C}v${R}            Start Selection
  ${C}C-v${R}          Toggle Rectangle
  ${C}y${R}            Yank (Copy)

MISC
  ${C}\`${R}            Popup Scratchpad
  ${C}r${R}            Reload Config
  ${C}?${R}            View all (default) bindings
  ${C}/${R}            View this Cheatsheet
EOF
    exit 0
fi

# --- Main Logic (Launch Popup) ---

tmux display-popup -E -w 70% -h 70% \
  -T "#[bg=$thm_yellow,fg=$thm_bg] Cheatsheet (Prefix: C-a) (q to close) " \
  "$0 --show"
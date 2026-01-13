#!/bin/bash
# ===============
# Script Name: tmux-toggle-scratch.sh
# Description: Smart toggle for scratchpad (Popup vs Window)
# Keybinding:  Prefix + `
# Config:      bind ` run-shell -b "~/.config/tmux/scripts/dv/tmux-toggle-scratch.sh"
# Dependencies: tmux, grep
# ===============

# --- Configuration ---
thm_bg="#1e1e2e"
thm_yellow="#f9e2af"
icon_scratch=""

# --- Helper Functions ---

# Detect if the current client is running inside a popup
is_in_popup() {
    local pid
    pid=$(tmux display-message -p "#{client_pid}")
    if [ -z "$pid" ]; then return 1; fi
    
    # Check the environment variables of the client process for the marker
    # -z handles null-terminated strings in /proc/PID/environ
    if grep -z "TMUX_POPUP=1" "/proc/$pid/environ" 2>/dev/null; then
        return 0
    fi
    return 1
}

# --- Main Logic ---

# 1. Ensure scratch session exists
if ! tmux has-session -t scratch 2>/dev/null; then
    # Create it detached so we don't switch to it yet
    tmux new-session -d -s scratch
fi

current_session=$(tmux display-message -p "#{session_name}")

if is_in_popup; then
    # Case 1: We are inside the popup. Detach (close) it.
    tmux detach-client
elif [ "$current_session" = "scratch" ]; then
    # Case 2: We are in the scratch session as a regular window.
    # Switch back to the last session.
    if ! tmux switch-client -l 2>/dev/null; then
        # Fallback: Switch to next session if no last session exists
        if ! tmux switch-client -n 2>/dev/null; then
            tmux display-message "No other sessions active."
        fi
    fi
else
    # Case 3: We are in a normal session. Open the scratchpad popup.
    # We inject TMUX_POPUP=1 so is_in_popup can detect it later.
    tmux display-popup -E -w 100% -h 50% -d "#{pane_current_path}" \
        -T "#[bg=$thm_yellow,fg=$thm_bg] $icon_scratch Scratch ── (Toggle: C-a \`, Join Pane: C-a j, Send Pane: C-a k) " \
        "TMUX_POPUP=1 tmux attach-session -t scratch"
fi
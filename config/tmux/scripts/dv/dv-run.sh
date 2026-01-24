#!/bin/bash
# ===============
# Script Name: dv-run.sh
# Description: Wrapper to run commands in a popup session with promotion capability.
# Usage:       dv-run.sh <id> <command> <parent_session> [cwd]
# Keybinding:  Inside popup: Alt+w OR Prefix+k to promote to window
# ===============

id="$1"
cmd="$2"
parent_session="$3"
cwd="${4:-$(pwd)}"

session_name="popup-${id}"

# 1. Create session if it doesn't exist
if ! tmux has-session -t "$session_name" 2>/dev/null; then
    # Logic: Run the command. After it finishes, check if the current session is still the popup session.
    # If it IS the popup session, we let the shell exit (closing the popup).
    # If it is NOT the popup session (meaning it was moved/promoted), we start a new shell to keep the window open.
    wrapper_cmd="$cmd; current_session=\$(tmux display-message -p '#{session_name}'); if [ \"\$current_session\" != \"$session_name\" ]; then echo; echo ' [Process exited] Window promoted, dropping to shell...'; exec $SHELL; fi"

    # Create detached session
    # We use $SHELL -c to ensure pipelines and complex commands work
    tmux new-session -d -s "$session_name" -c "$cwd" "$SHELL" -c "$wrapper_cmd"
    
    # Configure session for popup usage
    tmux set-option -t "$session_name" status off
    tmux set-option -t "$session_name" detach-on-destroy on
fi

# Always update the parent reference (in case we re-attach from a different session)
tmux set-option -t "$session_name" "@popup_parent" "$parent_session"

# 2. Attach to the session
tmux attach-session -t "$session_name"
#!/bin/bash
# ===============
# Script Name: dv-tm-popup.sh
# Description: Wrapper to launch tmux popups with consistent styling and behavior.
# Usage:       dv-tm-popup.sh <border_color> <text_color> <icon> <title> <id> <command>
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")

border_color="$1"
text_color="$2"
icon="$3"
title="$4"
id="$5"
cmd="$6"

# Construct the popup title with standard hints
popup_title="#[bg=${border_color},fg=${text_color}] ${icon} ${title} (Promote: Alt-w | Hide: Alt-h) "

# Get current session to pass to dv-run.sh (so it knows where to promote windows to)
parent_session=$(tmux display-message -p "#{session_name}")

# Execute tmux display-popup
# We use -d "#{pane_current_path}" to ensure the popup starts in the current directory
tmux display-popup \
    -E \
    -w 100% \
    -h 90% \
    -d "#{pane_current_path}" \
    -S "fg=${border_color}" \
    -T "${popup_title}" \
    "${script_dir}/dv-run.sh" "${id}" "${cmd}" "${parent_session}"
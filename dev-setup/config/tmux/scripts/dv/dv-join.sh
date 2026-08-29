#!/bin/bash
# ===============
# Script Name: dv-join.sh
# Description: Unified Join (Pull) - Bring a remote pane into the current window.
# Keybinding:  Prefix + j
# Config:      bind j run-shell -b "~/.config/tmux/scripts/dv/dv-join.sh"
# Dependencies: tmux > 3.2, fzf, grep, cut
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/common.sh"


# --- Checks ---
# Ensure we are in a tmux session
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run within a tmux session."
    exit 1
fi

check_deps "fzf" "grep" "cut"

# --- Logic ---

# 1. Get current window ID (to exclude panes from this window)
current_window_id=$(tmux display-message -p "#{window_id}")
current_session_name=$(tmux display-message -p "#{session_name}")


# 2. Generate Pane List
# Format: pane_id<tab>display_text<tab>session<tab>window_index<tab>window_name<tab>pane_index<tab>pane_title
# We use a separator '\t' to handle parsing later.
# Display format: [Session] Window: Pane - Title
tab=$'\t'
panes=$(tmux list-panes -a -F "#{window_id}${tab}#{pane_id}${tab}#{session_name}${tab}#{window_index}${tab}#{window_name}${tab}#{pane_index}${tab}#{pane_title}${tab}#{session_attached}" \
    | grep -v "^${current_window_id}${tab}" \
    | while IFS="$tab" read -r _wid id sn wi wn pi pt attached; do
        # Sanitize fields to prevent delimiter collision
        # Only pane_title needs sanitization as it's the last field and might contain tabs
        pt="${pt//$tab/ }"

        # Icon Logic
        icon=""
        if [ "$sn" = "$current_session_name" ]; then
             icon="${ansi_green}${ansi_fg} "
        elif [ "$attached" -ge 1 ]; then
             icon="${ansi_yellow}${ansi_fg} "
        fi

        # create colored display string
        # Format: ICON [Session] Window: Pane - Title
        display="${icon}${ansi_blue}[${sn}]${ansi_fg} ${ansi_yellow}${wi}:${wn}${ansi_fg} ${ansi_cyan}${pi} - ${pt}${ansi_fg}"

        # Output: ID <tab> Display <tab> Raw Fields (for preview)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$id" "$display" "$sn" "$wi" "$wn" "$pi" "$pt"
      done)

if [ -z "$panes" ]; then
    "$script_dir/dv-input.sh" --message "  No other panes found"
    exit 0
fi

# Prepare FZF header
fzf_header=$(printf "%s\n%s\n%s\n%s" \
    "${ansi_green}ENTER: Join${ansi_fg}" \
    "${ansi_yellow}A-ENT: New Win${ansi_fg}" \
    "${ansi_cyan}C-v/h: Join and Split V/H${ansi_fg}" \
    "${ansi_red}C-x: Kill${ansi_fg}")

# 3. FZF Selection
# We use --tmux to launch in a popup (requires fzf 0.53+ or tmux-fzf)
selected=$(printf '%s\n' "$panes" | dv_run_fzf \
    --exit-0 \
    --tmux 90%,70% \
    --delimiter="\t" \
    --with-nth=2 \
    --prompt="Pane ❯ " \
    --expect=alt-enter,ctrl-v,ctrl-h,ctrl-x \
    --list-label=" 󰁂 Join Pane From " \
    --list-border="top" \
    --list-label-pos='1' \
    --header="$fzf_header" \
    --header-border="top" \
    --header-label="  Commands: " \
    --header-label-pos='1' \
    --preview="tmux capture-pane -e -p -t {1}" \
    --preview-window="right:60%" \
    --preview-label-pos='3' \
    --color "preview-label:regular" \
    --bind "focus:transform-preview-label:printf \"${ansi_blue}[%s]${ansi_yellow} %s:%s ${ansi_cyan}%s - %s \" {3} {4} {5} {6} {7..}")
  
# 4. Handle Result
# Exit if cancelled (fzf returns non-zero)
if [ $? -ne 0 ]; then
    exit 0
fi

# Parse output (first line is key, rest is selection)
key=$(echo "$selected" | head -n1)
selection=$(echo "$selected" | tail -n +2)

# Extract pane ID
target_pane_id=$(echo "$selection" | cut -f1)
target_pane_display=$(echo "$selection" | cut -f2)

if [ -n "$target_pane_id" ]; then
    perform_join() {
        local split_type=$1
        # Check if current window is zoomed and unzoom if necessary
        if [ "$(tmux display-message -p "#{window_zoomed_flag}")" -eq 1 ]; then
            tmux resize-pane -Z
        fi
        tmux join-pane "$split_type" -s "$target_pane_id"
    }

    case "$key" in
        alt-enter)
            # Join
            tmux break-pane -s "$target_pane_id" ;;
        ctrl-v)
            # Split Vertical (side-by-side)
            perform_join "-h" ;;
        ctrl-h)
            # Split Horizontal (top-bottom)
            perform_join "-v" ;;
        ctrl-x)
            if "$script_dir/dv-input.sh" --confirm "Kill ${target_pane_display}?"; then
                tmux kill-pane -t "$target_pane_id"
                tmux display-message "#[fg=${thm_green}]✓ Pane ${target_pane_display} killed"
            else
                tmux display-message "#[fg=${thm_yellow}][i] Kill ${target_pane_display} cancelled"
            fi ;;
        *)
            # Default (Enter) -> Join Horizontal
            perform_join "-h" ;;
    esac
fi
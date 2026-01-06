#!/bin/bash

# tmux-join.sh - Unified Join (Pull) Script
# Goal: Bring a remote pane into the current window.

# --- Colors (Tokyo Night) ---
thm_bg="#1e2030"
thm_fg="#c8d3f5"
thm_cyan="#04a5e5"
thm_black="#1e2030"
thm_gray="#2d3f76"
thm_magenta="#cba6f7"
thm_pink="#ff007c"
thm_red="#ff966c"
thm_green="#c3e88d"
thm_yellow="#ffc777"
thm_blue="#82aaff"
thm_orange="#ff966c"
thm_black4="#444a73"
thm_mauve="#cba6f7"

# --- Checks ---
if ! command -v fzf >/dev/null; then
    tmux display-message "Error: fzf is not installed."
    exit 1
fi

# --- Logic ---

# 1. Get current window ID (to exclude panes from this window)
current_window_id=$(tmux display-message -p "#{window_id}")

# Helper to convert hex color to ANSI escape code
to_ansi() {
    local hex=$1
    hex="${hex/\#/}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf "\033[38;2;%d;%d;%dm" "$r" "$g" "$b"
}

ansi_blue=$(to_ansi "$thm_blue")
ansi_fg=$(to_ansi "$thm_fg")
ansi_yellow=$(to_ansi "$thm_yellow")
ansi_cyan=$(to_ansi "$thm_cyan")

# 2. Generate Pane List
# Format: pane_id|display_text
# We use a separator '|' to handle parsing later.
# Display format: [Session] Window: Pane - Title
panes=$(tmux list-panes -a -F "#{window_id}|#{pane_id}|#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_title}" \
    | grep -v "^${current_window_id}|" \
    | while IFS='|' read -r _wid id sn wi wn pi pt; do
        # Sanitize fields to prevent delimiter collision
        sn="${sn//$'\t'/ }"
        wn="${wn//$'\t'/ }"
        pt="${pt//$'\t'/ }"
        printf "%s\t%s[%s]%s %s%s:%s%s %s%s - %s%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$id" \
            "$ansi_blue" "$sn" "$ansi_fg" \
            "$ansi_yellow" "$wi" "$wn" "$ansi_fg" \
            "$ansi_cyan" "$pi" "$pt" "$ansi_fg" \
            "$sn" "$wi" "$wn" "$pi" "$pt"
      done)

if [ -z "$panes" ]; then
    tmux display-message "No other panes found."
    exit 0
fi

# 3. FZF Selection
# We use --tmux to launch in a popup (requires fzf 0.53+ or tmux-fzf)
selected=$(printf '%s\n' "$panes" | fzf --tmux 90%,60% \
    --ansi \
    --delimiter="\t" \
    --with-nth=2 \
    --reverse \
    --prompt=" Pane ❯ " \
    --header="ENTER: Join" \
    --preview="tmux capture-pane -e -p -t {1}" \
    --preview-window="right:60%" \
    --border-label-pos='3' \
    --border-label=' 󰆏 Join Pane ' \
    --preview-label-pos='3' \
    --bind "focus:transform-preview-label:printf \"${ansi_blue}[%s]${ansi_fg} ${ansi_yellow}%s:%s${ansi_fg} ${ansi_cyan}%s - %s${ansi_fg} \" {3} {4} {5} {6} {7..}" \
    --color "border:${thm_cyan},label:${thm_cyan}:reverse,preview-border:${thm_gray},preview-label:white:regular,header-border:${thm_blue},header-label:${thm_blue},header:${thm_cyan}" \
    --color "bg+:${thm_gray},bg:${thm_bg},gutter:${thm_bg},prompt:${thm_orange}" \
    --exit-0)
  
# 4. Handle Result
# Exit if cancelled (fzf returns non-zero)
if [ $? -ne 0 ]; then
    exit 0
fi

# Extract pane ID
target_pane_id=$(echo "$selected" | cut -f1)

if [ -n "$target_pane_id" ]; then
    # Check if current window is zoomed and unzoom if necessary
    if [ "$(tmux display-message -p "#{window_zoomed_flag}")" -eq 1 ]; then
        tmux resize-pane -Z
    fi
    
    # Join the pane (Split Horizontal by default)
    tmux join-pane -h -s "$target_pane_id"
fi
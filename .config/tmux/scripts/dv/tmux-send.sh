#!/bin/bash

# tmux-send.sh - Unified Send (Push) Script
# Goal: Move the current pane to another window or session.

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
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run within a tmux session."
    exit 1
fi

if ! command -v fzf >/dev/null; then
    tmux display-message "Error: fzf is not installed."
    exit 1
fi

# --- Logic ---

# Get current context
src_pane=$(tmux display-message -p "#{pane_id}")
cur_win_id=$(tmux display-message -p "#{window_id}")

# Helper for colors
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
ansi_red=$(to_ansi "$thm_red")
ansi_green=$(to_ansi "$thm_green")
ansi_magenta=$(to_ansi "$thm_magenta")

# Generate Target List
# Format: TYPE <tab> TARGET <tab> DISPLAY
tab=$'\t'

# 1. Existing Windows
# Filter out current window
windows=$(tmux list-windows -a -F "WIN${tab}#{window_id}${tab}#{session_name}${tab}#{window_name}" \
    | grep -v "${tab}${cur_win_id}${tab}" \
    | while IFS="$tab" read -r type wid sn wn; do
        display="${ansi_blue}[${sn}]${ansi_fg} ${wn}"
        printf "%s\t%s\t%s\n" "$type" "$wid" "$display"
      done)

# 2. New Window in Session
sessions=$(tmux list-sessions -F "SES${tab}#{session_name}${tab}#{session_name}" \
    | while IFS="$tab" read -r type sn _display_sn; do
        display="${ansi_blue}[${sn}]${ansi_fg} ${ansi_yellow}<New Window>${ansi_fg}"
        printf "%s\t%s\t%s\n" "$type" "$sn" "$display"
      done)

# 3. Scratchpad (if not exists)
if ! tmux has-session -t scratch 2>/dev/null; then
    display="${ansi_blue}[scratch]${ansi_fg} ${ansi_yellow}<New Window>${ansi_fg}"
    scratch_item="SES${tab}scratch${tab}${display}"
else
    scratch_item=""
fi

# 4. New Session
new_sess_display="${ansi_magenta}[NEW SESSION]${ansi_fg}"
new_sess_item="NEW${tab}NEW${tab}${new_sess_display}"

# Combine list
targets=$(printf "%s\n%s\n%s\n%s" "$windows" "$sessions" "$scratch_item" "$new_sess_item" | sed '/^$/d')

# FZF Header
fzf_header=$(printf "%s\n%s\n%s" \
    "${ansi_green}ENTER: Move${ansi_fg}" \
    "${ansi_yellow}A-ENT: Follow${ansi_fg}" \
    "${ansi_cyan}C-v/h: Split${ansi_fg}")

# Select
selected=$(printf '%s\n' "$targets" | fzf \
    --tmux 90%,60% \
    --ansi \
    --reverse \
    --layout=reverse-list \
    --exit-0 \
    --delimiter="\t" \
    --with-nth=3 \
    --prompt="Send To ❯ " \
    --expect=alt-enter,ctrl-v,ctrl-h \
    --list-label=" 󰆏 Send Pane " \
    --header="$fzf_header" \
    --header-label=" Commands: " \
    --preview="if [ {1} = 'WIN' ]; then tmux capture-pane -e -p -t {2}; else echo 'Create New Window/Session'; fi" \
    --preview-window="right:60%" \
    --color "border:${thm_cyan},label:${thm_cyan}:reverse,header-border:${thm_blue},header-label:${thm_blue},header:${thm_cyan}" \
    --color "bg+:${thm_gray},bg:${thm_bg},gutter:${thm_bg},prompt:${thm_orange}")

if [ $? -ne 0 ]; then
    exit 0
fi

key=$(echo "$selected" | head -n1)
selection=$(echo "$selected" | tail -n +2)

type=$(echo "$selection" | cut -f1)
target=$(echo "$selection" | cut -f2)

# Determine split flags
split_args=""
case "$key" in
    ctrl-v) split_args="-h" ;;
    ctrl-h) split_args="-v" ;;
esac

# Determine follow behavior
follow=0
if [ "$key" = "alt-enter" ]; then
    follow=1
fi

case "$type" in
    WIN)
        if [ -z "$split_args" ]; then split_args="-h"; fi
        tmux join-pane $split_args -s "$src_pane" -t "$target"
        if [ "$follow" -eq 1 ]; then
            tmux select-window -t "$target"
            tmux select-pane -t "$src_pane"
            tmux switch-client -t "$target"
        fi
        ;;
    SES)
        # Handle Scratchpad creation if it doesn't exist
        if [ "$target" = "scratch" ] && ! tmux has-session -t scratch 2>/dev/null; then
            tmux new-session -d -s scratch -n "temp"
            tmux break-pane -s "$src_pane" -t scratch
            tmux kill-window -t scratch:temp
        else
            tmux break-pane -s "$src_pane" -t "$target"
        fi

        if [ "$follow" -eq 1 ]; then
            tmux switch-client -t "$target"
        fi
        ;;
    NEW)
        tmux display-message "New Session logic Not implemented yet"
        ;;
esac
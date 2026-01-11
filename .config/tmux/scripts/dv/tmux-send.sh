#!/bin/bash
# ===============
# Script Name: tmux-send.sh
# Description: Unified Send (Push) - Move the current pane to another window or session.
# Keybinding:  Prefix + k
# Config:      bind k run-shell -b "~/.config/tmux/scripts/dv/tmux-send.sh"
# Dependencies: tmux > 3.2, fzf, grep, sed, cut
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")

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

# --- Callback Logic (New Session) ---
if [ "$1" = "--new-session" ]; then
    sess_name="$2"
    src_pane="$3"
    follow="$4"

    if [ -z "$sess_name" ]; then exit 0; fi

    show_popup() {
        local header="$1"
        local value="$2"
        tmux display-popup -w 40 -h 6 -E \
            "bash -c \"printf ' $header\033[0m\n   \033[1;34m%s\033[0m\n\n Press any key to continue...' '$value'; read -n 1 -s\""
    }

    if tmux has-session -t "$sess_name" 2>/dev/null; then
        if [ "$follow" -eq 1 ]; then
            tmux switch-client -t "$sess_name"
        fi
        tmux break-pane -s "$src_pane" -t "$sess_name"
        show_popup "\033[1;33m! Session Exists" "$sess_name"
    else
        tmux new-session -d -s "$sess_name"
        if [ "$follow" -eq 1 ]; then
            tmux switch-client -t "$sess_name"
        fi
        tmux join-pane -s "$src_pane" -t "$sess_name:"
        tmux kill-pane -a -t "$src_pane"
        show_popup "\033[1;32m✓ Session Created" "$sess_name"
    fi

    exit 0
fi

# --- Checks ---
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run within a tmux session."
    exit 1
fi

if ! command -v fzf >/dev/null; then
    "$script_dir/tmux-input.sh" --message "Error: fzf is not installed."
    exit 1
fi

# --- Logic ---

# Get current context
src_pane=$(tmux display-message -p "#{pane_id}")
cur_win_id=$(tmux display-message -p "#{window_id}")
cur_sess=$(tmux display-message -p "#{session_name}")
cur_win_panes=$(tmux display-message -p "#{window_panes}")

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
windows=$(tmux list-windows -a -F "WIN${tab}#{window_id}${tab}#{session_name}${tab}#{window_index}${tab}#{window_name}${tab}#{session_attached}" \
    | grep -v "${tab}${cur_win_id}${tab}" \
    | while IFS="$tab" read -r type wid sn wi wn attached; do
        # Sanitize window name to prevent tab collision
        wn="${wn//$tab/ }"
        
        icon=""
        if [ "$sn" = "$cur_sess" ]; then
            icon="${ansi_green}${ansi_fg}"
        elif [ "$attached" -ge 1 ]; then
            icon="${ansi_yellow}${ansi_fg}"
        fi

        display="${icon} ${ansi_blue}${sn}${ansi_fg}: ${ansi_yellow}${wi}:${wn}${ansi_fg}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$type" "$wid" "$display" "$sn" "$wi" "$wn"
      done)

# 2. New Window in Session
sessions=$(tmux list-sessions -F "SES${tab}#{session_name}${tab}#{session_name}${tab}#{session_attached}" \
    | while IFS="$tab" read -r type sn _display_sn attached; do
        # Filter out current session if it's the only pane in the window
        if [ "$sn" = "$cur_sess" ] && [ "$cur_win_panes" -eq 1 ]; then
            continue
        fi

        icon=""
        if [ "$sn" = "$cur_sess" ]; then
            icon="${ansi_green}${ansi_fg}"
        elif [ "$attached" -ge 1 ]; then
            icon="${ansi_yellow}${ansi_fg}"
        fi

        display="${icon} ${ansi_blue}${sn}${ansi_fg}: ${ansi_magenta} New Window${ansi_fg}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$type" "$sn" "$display" "$sn" "+" "New Window"
      done)

# 3. Scratchpad (if not exists)
if ! tmux has-session -t scratch 2>/dev/null; then
    display="${ansi_blue}scratch${ansi_fg}: ${ansi_magenta} New Window${ansi_fg}"
    scratch_item="SES${tab}scratch${tab}${display}${tab}scratch${tab}+${tab}New Window"
else
    scratch_item=""
fi

# 4. New Session
new_sess_display="${ansi_magenta} New Session${ansi_fg}"
new_sess_item="NEW${tab}NEW${tab}${new_sess_display}${tab}NEW${tab}+${tab}New Session"

# Combine list
targets=$(printf "%s\n%s\n%s\n%s" "$windows" "$sessions" "$scratch_item" "$new_sess_item" | sed '/^$/d')

# FZF Header
fzf_header=$(printf "%s\n%s\n%s" \
    "${ansi_green}ENTER: Send${ansi_fg}" \
    "${ansi_yellow}A-ENT: Follow${ansi_fg}" \
    "${ansi_cyan}C-v/h: Send and Split V/H${ansi_fg}")

# Preview Command
preview_cmd="if [ {1} = 'WIN' ]; then \
    tmux capture-pane -e -p -t {2}; \
elif [ {1} = 'SES' ]; then \
    printf '\n${ansi_green}Create New Window in ${ansi_blue}[%s]${ansi_fg}' '{2}'; \
else \
    printf '\n${ansi_magenta}Create a New Session${ansi_fg}'; \
fi"

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
    --list-label=" 󰁜 Send Pane to: " \
    --list-border="top" \
    --list-label-pos='1' \
    --header="$fzf_header" \
    --header-border="top" \
    --header-label=" Commands: " \
    --header-label-pos='1' \
    --preview="$preview_cmd" \
    --preview-window="right:60%" \
    --bind "focus:transform-preview-label:printf \"${ansi_blue}[%s]${ansi_fg} ${ansi_yellow}%s:%s${ansi_fg} \" {4} {5} {6}" \
    --preview-label-pos='3' \
    --color "border:${thm_cyan},label:${thm_cyan}:reverse,preview-border:${thm_gray},preview-label:white:regular,header-border:${thm_blue},header-label:${thm_blue},header:${thm_cyan}" \
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

# Check for last pane in session to prevent client exit
sess_pane_count=$(tmux display-message -p "#{session_panes}")
forced_follow=0
if [ "$sess_pane_count" -eq 1 ] && [ "$follow" -eq 0 ]; then
    follow=1
    forced_follow=1
fi

case "$type" in
    WIN)
        if [ -z "$split_args" ]; then split_args="-h"; fi
        tmux join-pane "$split_args" -s "$src_pane" -t "$target"
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
            if [ "$follow" -eq 1 ]; then
                tmux switch-client -t scratch
            fi
            tmux break-pane -s "$src_pane" -t scratch
            tmux kill-window -t scratch:temp
        else
            if [ "$follow" -eq 1 ]; then
                tmux switch-client -t "$target"
            fi
            tmux break-pane -s "$src_pane" -t "$target"
        fi

        if [ "$forced_follow" -eq 1 ]; then
            tmux display-message "#[fg=${thm_yellow}]! Source session ended; switched to target"
        fi
        ;;
    NEW)
        sess_name=$("$script_dir/tmux-input.sh" --title " New Session " "Enter Name")
        if [ $? -eq 0 ] && [ -n "$sess_name" ]; then
            "$script_path" --new-session "$sess_name" "$src_pane" "$follow"
        else
            tmux display-message "#[fg=${thm_yellow}]! Session creation cancelled"
        fi
        ;;
esac
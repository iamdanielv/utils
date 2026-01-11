#!/bin/bash
# ===============
# Script Name: tmux-session-manager.sh
# Description: Interactive session manager with preview and management actions.
# Keybinding:  Prefix + S
# Config:      bind S run-shell -b "~/.config/tmux/scripts/dv/tmux-session-manager.sh"
# Dependencies: tmux > 3.2, fzf, sed, awk
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
ansi_red=$(to_ansi "$thm_red")
ansi_green=$(to_ansi "$thm_green")
ansi_magenta=$(to_ansi "$thm_magenta")

get_session_list() {
    local tab=$'\t'
    local current_session
    current_session=$(tmux display-message -p "#{session_name}")

    # 1. Special Item
    # Format: RAW_NAME <tab> DISPLAY_TEXT
    printf "NEW%s%s\n" "$tab" "${ansi_green}${ansi_magenta} New Session${ansi_fg}"
    
    # 2. Actual Sessions
    # Format: name <tab> attached <tab> windows
    tmux list-sessions -F "#{session_name}${tab}#{session_attached}${tab}#{session_windows}" 2>/dev/null | \
    while IFS="$tab" read -r name attached windows; do
        local display=""
        if [[ "$name" == "$current_session" ]]; then
            display="${ansi_green}${ansi_fg} "
        elif [[ "$attached" -ge 1 ]]; then
            display="${ansi_yellow}${ansi_fg} "
        fi
        display+="${ansi_blue}${name}${ansi_fg}: ${ansi_cyan}${windows} windows${ansi_fg}"
        printf "%s%s%s\n" "$name" "$tab" "$display"
    done
}

# FZF Header
fzf_header=$(printf "%s" "${ansi_green}ENTER: Switch${ansi_fg}")

# FZF Execution
selected=$(get_session_list | fzf \
    --tmux 80%,70% \
    --ansi \
    --reverse \
    --layout=reverse-list \
    --exit-0 \
    --delimiter="\t" \
    --with-nth=2 \
    --prompt="Session ❯ " \
    --header="$fzf_header" \
    --header-border="top" \
    --header-label=" Commands: " \
    --header-label-pos='1' \
    --border-label=" 󰖲 Session Manager " \
    --border-label-pos='1' \
    --color "border:${thm_cyan},label:${thm_cyan}:reverse,header-border:${thm_blue},header-label:${thm_blue},header:${thm_cyan}" \
    --color "bg+:${thm_gray},bg:${thm_bg},gutter:${thm_bg},prompt:${thm_orange}")

if [ $? -ne 0 ]; then exit 0; fi

target_session=$(echo "$selected" | cut -f1)

if [[ "$target_session" == "NEW" ]]; then
    exit 0 # Placeholder
elif [[ -n "$target_session" ]]; then
    tmux switch-client -t "$target_session"
fi

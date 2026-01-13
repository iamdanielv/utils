#!/bin/bash
# ===============
# Script Name: tmux-session-manager.sh
# Description: Interactive session manager with preview and management actions.
# Keybinding:  Prefix + s
# Config:      bind s run-shell -b "~/.config/tmux/scripts/dv/tmux-session-manager.sh"
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
ansi_gray=$(to_ansi "$thm_gray")

get_preview_label() {
    local target="$1"
    if [[ "$target" == "NEW" ]]; then
        printf "%s  New Session " "${ansi_magenta}"
    else
        printf " 󰖲 Preview: %s " "$target"
    fi
}

preview_session() {
    local target="$1"
    if [[ "$target" == "NEW" ]]; then
        printf "\n  Select this option to\n"
        printf "  %screate a new tmux session" "${ansi_green}"

        return
    fi

    tmux list-windows -t "$target" -F "#{window_index}:#{window_active}:#{window_name}" 2>/dev/null | while IFS=: read -r idx active name; do
        if [[ "$active" == "1" ]]; then
            printf "%s├── [%s] %s (Active)%s\n" "${ansi_green}" "$idx" "$name" "${ansi_fg}"
            tmux capture-pane -e -p -t "${target}:${idx}" 2>/dev/null | head -n 15 | sed "s/^/│  /"
            printf "│  %s...%s\n" "${ansi_gray}" "${ansi_fg}"
        else
            printf "├── [%s] %s\n" "$idx" "$name"
        fi
    done
}

if [[ "$1" == "--preview" ]]; then
    preview_session "$2"
    exit 0
elif [[ "$1" == "--preview-label" ]]; then
    get_preview_label "$2"
    exit 0
fi

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
fzf_header=$(printf "%s  %s\n  %s  %s" "${ansi_green}ENTER: Switch${ansi_fg}" "${ansi_magenta}C-n: New${ansi_fg}" "${ansi_blue}C-r: Rename${ansi_fg}" "${ansi_red}C-x: Kill${ansi_fg}")

while true; do
    # FZF Execution
    selected=$(get_session_list | fzf \
        --tmux 95%,90% \
        --ansi \
        --reverse \
        --layout=reverse-list \
        --exit-0 \
        --delimiter="\t" \
        --with-nth=2 \
        --prompt="Session ❯ " \
        --header="$fzf_header" \
        --header-border="top" \
        --header-label="  Commands: " \
        --header-label-pos='1' \
        --border-label=" 󰖲 Session Manager " \
        --border-label-pos='2' \
        --preview="$script_path --preview {1}" \
        --preview-label-pos='2' \
        --preview-window="right:60%" \
        --bind "focus:transform-preview-label:$script_path --preview-label {1}" \
        --expect=ctrl-x,ctrl-n,ctrl-r \
        --color "border:${thm_cyan},label:${thm_cyan}:reverse,header-border:${thm_blue},header-label:${thm_blue},header:${thm_cyan}" \
        --color "bg+:${thm_gray},bg:${thm_bg},gutter:${thm_bg},prompt:${thm_orange}")

    if [ $? -ne 0 ]; then exit 0; fi

    key=$(echo "$selected" | head -n1)
    line=$(echo "$selected" | tail -n +2)
    target_session=$(echo "$line" | cut -f1)

    if [[ "$key" == "ctrl-x" ]]; then
        if [[ "$target_session" == "NEW" ]]; then
            "$script_dir/tmux-input.sh" --message "Cannot kill the 'New Session' item."
        else
            if "$script_dir/tmux-input.sh" --confirm "Kill session '$target_session'?"; then
                current_session=$(tmux display-message -p "#{session_name}")
                if [[ "$target_session" == "$current_session" ]]; then
                    other_session=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -v "^${target_session}$" | head -n 1)
                    if [[ -n "$other_session" ]]; then
                        tmux switch-client -t "=${other_session}"
                        tmux kill-session -t "=${target_session}"
                        "$script_dir/tmux-input.sh" --message "Session '$target_session' killed. Switched to '$other_session'."
                        continue
                    fi
                fi
                tmux kill-session -t "=${target_session}"
                "$script_dir/tmux-input.sh" --message "Session '$target_session' killed"
            else
                "$script_dir/tmux-input.sh" --message "Kill cancelled"
            fi
        fi
        continue
    elif [[ "$key" == "ctrl-n" ]] || [[ "$target_session" == "NEW" ]]; then
        unset sess_name
        sess_name=$("$script_dir/tmux-input.sh" --title " New Session " "Enter Name")
        if [ $? -eq 0 ] && [ -n "$sess_name" ]; then
            if tmux has-session -t "=${sess_name}" 2>/dev/null; then
                "$script_dir/tmux-input.sh" --message "Session '$sess_name' already exists."
            else
                tmux new-session -d -s "$sess_name"
                tmux switch-client -t "=${sess_name}"
                break
            fi
        fi
        continue
    elif [[ "$key" == "ctrl-r" ]]; then
        if [[ "$target_session" == "NEW" ]]; then
            "$script_dir/tmux-input.sh" --message "Cannot rename the 'New Session' item."
        else
            unset new_name
            new_name=$("$script_dir/tmux-input.sh" --title " Rename Session " "Enter New Name" "$target_session")
            if [ $? -eq 0 ] && [ -n "$new_name" ]; then
                if [[ "$new_name" == "$target_session" ]]; then
                    continue
                elif tmux has-session -t "=${new_name}" 2>/dev/null; then
                    "$script_dir/tmux-input.sh" --message "Session '$new_name' already exists."
                else
                    tmux rename-session -t "=${target_session}" "$new_name"
                fi
            fi
        fi
        continue
    elif [[ -n "$target_session" ]]; then
        tmux switch-client -t "=${target_session}"
        break
    fi
done
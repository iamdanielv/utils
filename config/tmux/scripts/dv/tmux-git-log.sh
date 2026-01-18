#!/bin/bash
# ===============
# Script Name: tmux-git-log.sh
# Description: Interactive Git Log Viewer
# Keybinding:  Prefix + g -> l
# Dependencies: tmux, git, fzf
# ===============

# --- Auto-Launch Tmux ---
if [ -z "$TMUX" ]; then
    script_path=$(readlink -f "$0")
    if tmux has-session -t main 2>/dev/null; then
        tmux new-window -t main -n "git-log" -c "$PWD" "$script_path"
        exec tmux attach-session -t main
    else
        exec tmux new-session -s main -n "git-log" -c "$PWD" "$script_path"
    fi
    exit 0
fi

# --- Configuration ---
_C_RESET=$'\033[0m'
_C_GREEN=$'\033[1;32m'
_C_YELLOW=$'\033[1;33m'
_C_BLUE=$'\033[1;34m'
_C_CYAN=$'\033[1;36m'
_C_BOLD=$'\033[1m'
_C_REVERSE=$'\033[7m'

# Catppuccin Colors (matching tmux.conf/other scripts)
thm_bg="#1e1e2e"
thm_fg="#cdd6f4"
thm_yellow="#f9e2af"

icon_git=""

# FZF Styles
_FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'
_FZF_LBL_RESET="${_C_RESET}"

# Git Log Format
_GIT_LOG_COMPACT_FORMAT='%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)'

# Date shortener
_SED_DATE="sed -E 's/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g'"

# --- Helpers ---
_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Not a git repository"
    read -n 1 -s -r -p "Press any key to exit..."
    exit 1
  fi
}

is_in_popup() {
    [[ -n "$TMUX_POPUP" ]]
}

# --- Main Logic ---

# 1. Popup Context (The FZF Interface)
if is_in_popup; then
    _require_git_repo

    current_branch=$(git branch --show-current)
    [ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

    controls="${_C_BOLD}ENTER${_C_RESET}: View Diff • ${_C_BOLD}CTRL-Y${_C_RESET}: Copy Hash • ${_C_BOLD}ESC${_C_RESET}: Quit"
    header="${_C_GREEN}${_C_REVERSE} Branch: ${current_branch} ${_C_RESET}"$'\n'"${controls}"

    selected=$(git log --color=always --format="${_GIT_LOG_COMPACT_FORMAT}" | \
        eval "$_SED_DATE" | \
        fzf --ansi --reverse --tiebreak=index --header-first \
            --no-sort --no-hscroll \
            --preview-window 'right,60%,border,wrap' \
            --preview-label-pos='3' \
            --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)' \
            --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff' \
            --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7' \
            --header "$header" \
            --prompt='  Log❯ ' \
            --preview "git show --color=always {1}" \
            --bind "enter:execute(git show --color=always {1} | less -R)" \
            --bind "ctrl-y:accept" \
            --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} Diff for [%s] ${_FZF_LBL_RESET}\" {1}")

    if [[ -n "$selected" ]]; then
        hash=$(echo "$selected" | sed $'s/\e\[[0-9;]*m//g' | awk '{print $1}')
        if [[ -n "$hash" ]]; then
            printf "%s" "$hash" | tmux load-buffer -
            tmux display-message "Hash $hash copied to tmux buffer"
        fi
    fi
    exit 0
fi

# 2. Main Context (Launch the Popup)
script_path=$(readlink -f "$0")

tmux display-popup -E -w 95% -h 80% -d "#{pane_current_path}" \
    -T "#[bg=$thm_yellow,fg=$thm_bg,bold] $icon_git Git Log " \
    "TMUX_POPUP=1 $script_path"
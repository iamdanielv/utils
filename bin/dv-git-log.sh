#!/bin/bash
# ===============
# Script Name: dv-git-log.sh
# Description: Interactive Git Log Viewer.
# Keybinding:  Prefix + g -> l
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Configuration ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_REVERSE=$'\033[7m'

icon_git=""

# FZF Styles
FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'
FZF_LBL_RESET="${C_RESET}"

# Git Log Format
_GIT_LOG_COMPACT_FORMAT='%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)'

# Date shortener
_SED_DATE="sed -E 's/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g'"

# --- Main Logic ---

require_git_repo

current_branch=$(git branch --show-current)
[ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

controls="${C_BOLD}ENTER${C_RESET}: View Diff • ${C_BOLD}CTRL-Y${C_RESET}: Copy Hash • ${C_BOLD}ESC${C_RESET}: Quit"
header="${ansi_green}${C_REVERSE} Branch: ${current_branch} ${C_RESET}"$'\n'"${controls}"

selected=$(git log --color=always --format="${_GIT_LOG_COMPACT_FORMAT}" | \
    eval "$_SED_DATE" | \
    dv_run_fzf --tiebreak=index --header-first \
        --no-sort --no-hscroll \
        --preview-window 'right,60%,border,wrap' \
        --preview-label-pos='3' \
        --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)' \
        --border-label=" $icon_git Git Log " \
        --border-label-pos='3' \
        --header "$header" \
        --color "preview-border:${thm_gray},preview-label:white:regular" \
        --prompt='  Log❯ ' \
        --preview "git show --color=always {1}" \
        --bind "enter:execute(git show --color=always {1} | less -R)" \
        --bind "ctrl-y:accept" \
        --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${FZF_LBL_STYLE} Diff for [%s] ${FZF_LBL_RESET}\" {1}")

if [[ -n "$selected" ]]; then
    # If called from fgl (not in a tmux popup), print the raw selected line for _handle_git_hash_selection
    if [[ -z "$TMUX_POPUP" ]]; then
        echo "$selected"
        exit 0
    fi

    # Otherwise (called from tmux popup), copy hash to buffer
    hash=$(echo "$selected" | sed $'s/\e\[[0-9;]*m//g' | awk '{print $1}')
    if [[ -n "$hash" ]]; then
        printf "%s" "$hash" | tmux load-buffer -
        tmux display-message "Hash $hash copied to tmux buffer"
    fi
fi
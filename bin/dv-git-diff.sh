#!/bin/bash
# ===============
# Script Name: dv-git-diff.sh
# Description: Interactive Git Diff Viewer (Unstaged/Staged/All).
# Keybinding:  Prefix + g -> d
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

# --- Actions ---

generate_list() {
    local mode="$1"
    if [[ "$mode" == "staged" ]]; then
        git diff --cached --name-only
    elif [[ "$mode" == "all" ]]; then
        git diff HEAD --name-only
    else
        git diff --name-only
    fi
}

do_preview() {
    local mode="$1"
    local file="$2"
    if [[ "$mode" == "staged" ]]; then
        if command -v delta &>/dev/null; then
            git --no-pager diff --cached -- "$file" | delta --paging=never --file-style=omit
        else
            git --no-pager diff --cached --color=always -- "$file"
        fi
    elif [[ "$mode" == "all" ]]; then
        if command -v delta &>/dev/null; then
            git --no-pager diff HEAD -- "$file" | delta --paging=never --file-style=omit
        else
            git --no-pager diff HEAD --color=always -- "$file"
        fi
    else
        if command -v delta &>/dev/null; then
            git --no-pager diff -- "$file" | delta --paging=never --file-style=omit
        else
            git --no-pager diff --color=always -- "$file"
        fi
    fi
}

# --- Main Dispatch ---

if [[ "$1" == "--preview" ]]; then do_preview "$2" "$3"; exit 0; fi
if [[ "$1" == "--generate" ]]; then generate_list "$2"; exit 0; fi

# --- Main Logic ---

require_git_repo

# Mode handling (default to unstaged)
current_mode="unstaged"
if [[ "$1" == "--mode" ]]; then
    current_mode="$2"
fi

current_branch=$(git branch --show-current)
[ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

# Dynamic Header
case "$current_mode" in
    "staged")   mode_label="${ansi_green}Staged${C_RESET}" ;;
    "all")      mode_label="${ansi_magenta}All (HEAD)${C_RESET}" ;;
    *)          mode_label="${ansi_yellow}Unstaged${C_RESET}" ;;
esac

controls="${C_BOLD}CTRL-S${C_RESET}: Staged • ${C_BOLD}CTRL-U${C_RESET}: Unstaged • ${C_BOLD}CTRL-A${C_RESET}: All • ${C_BOLD}ENTER${C_RESET}: Edit"
header="${ansi_blue}${C_REVERSE} Diff: ${current_branch} ${C_RESET} ${mode_label}"$'\n'"${controls}"

EDITOR_CMD=$(get_editor)

# Generate list and pipe to FZF
# We use 'become' to switch modes because the preview command needs to change
$0 --generate "$current_mode" | dv_run_fzf \
    --tiebreak=index --header-first \
    --no-sort \
    --preview-window 'down,60%,border-top,wrap' \
    --preview-label-pos='3' \
    --bind 'ctrl-/:change-preview-window(right,60%,border,wrap|hidden|)' \
    --border-label=" $icon_git Git Diff " \
    --border-label-pos='3' \
    --header "$header" \
    --prompt="  Diff(${current_mode})❯ " \
    --preview "$0 --preview $current_mode {}" \
    --bind "ctrl-s:become($0 --mode staged)" \
    --bind "ctrl-u:become($0 --mode unstaged)" \
    --bind "ctrl-a:become($0 --mode all)" \
    --bind "enter:become($EDITOR_CMD {})" \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" {}"
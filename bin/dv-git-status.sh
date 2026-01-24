#!/bin/bash
# ===============
# Script Name: dv-git-status.sh
# Description: Interactive Git Status - Stage, Discard, Diff.
# Keybinding:  Prefix + g -> s
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf, bat/batcat
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Configuration ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_REVERSE=$'\033[7m'

icon_git=""

# --- Action Logic ---

# Helper to parse "XY File..." line
get_file() {
    local line="$1"
    local file="${line:3}"
    # Remove surrounding quotes if present (git quotes paths with spaces)
    file="${file%\"}"
    file="${file#\"}"
    echo "$file"
}

get_status() {
    echo "${1:0:2}"
}

do_preview() {
    local line="$1"
    local status=$(get_status "$line")
    local file=$(get_file "$line")

    if [[ "$status" == "??" ]]; then
        echo "Untracked file:"
        if [ -d "$file" ]; then
            ls -la --color=always "$file"
        elif command -v bat &>/dev/null; then
            bat --color=always --style=numbers "$file"
        elif command -v batcat &>/dev/null; then
            batcat --color=always --style=numbers "$file"
        else
            cat "$file"
        fi
    elif [[ "$status" == "M " || "$status" == "A " || "$status" == "D " || "$status" == "R " ]]; then
        echo "Staged changes (git diff --cached):"
        git diff --cached --color=always -- "$file"
    else
        echo "Unstaged changes (git diff):"
        git diff --color=always -- "$file"
    fi
}

do_toggle() {
    local line="$1"
    local status=$(get_status "$line")
    local file=$(get_file "$line")
    local index="${status:0:1}"

    if [[ "$index" != " " && "$index" != "?" ]]; then
        git reset -q HEAD -- "$file"
    else
        git add -- "$file"
    fi
}

do_discard() {
    local line="$1"
    local status=$(get_status "$line")
    local file=$(get_file "$line")
    
    if ! dv_confirm "Discard changes to '$file'?"; then
        return
    fi

    if [[ "$status" == "??" ]]; then
        rm -rf "$file"
    elif [[ "${status:0:1}" != " " && "${status:0:1}" != "?" ]]; then
        git reset -q HEAD -- "$file"
    else
        git checkout -q -- "$file"
    fi
}

# --- Main Dispatch ---

if [[ "$1" == "--preview" ]]; then do_preview "$2"; exit 0; fi
if [[ "$1" == "--toggle" ]]; then do_toggle "$2"; exit 0; fi
if [[ "$1" == "--discard" ]]; then do_discard "$2"; exit 0; fi

# --- Main Logic ---

require_git_repo

current_branch=$(git branch --show-current)
[ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

controls="${C_BOLD}TAB${C_RESET}: Stage/Unstage • ${C_BOLD}CTRL-X${C_RESET}: Discard • ${C_BOLD}ENTER${C_RESET}: Edit"
header="${ansi_green}${C_REVERSE} Status: ${current_branch} ${C_RESET}"$'\n'"${controls}"

EDITOR_CMD=$(get_editor)
LIST_CMD="git status --short"

$LIST_CMD | dv_run_fzf \
    --tiebreak=index --header-first \
    --no-sort \
    --preview-window 'right,60%,border,wrap' \
    --preview-label-pos='3' \
    --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)' \
    --border-label=" $icon_git Git Status " \
    --border-label-pos='3' \
    --header "$header" \
    --prompt='  Status❯ ' \
    --preview "$0 --preview {}" \
    --bind "tab:execute($0 --toggle {})+reload($LIST_CMD)" \
    --bind "ctrl-x:execute($0 --discard {})+reload($LIST_CMD)" \
    --bind "enter:become($EDITOR_CMD \$(echo {} | cut -c 4- | sed 's/^\"//;s/\"$//'))" \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" \$(echo {} | cut -c 4- | sed 's/^\"//;s/\"$//')"

#!/bin/bash
# ===============
# Script Name: dv-git-stash.sh
# Description: Interactive Git Stash Viewer - Apply, Drop.
# Keybinding:  Prefix + g -> t
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf, dv-input.sh
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Configuration ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_REVERSE=$'\033[7m'

icon_git=""

# --- Helpers ---

get_input() {
    local title="$1"
    local prompt="$2"
    local input_script="$HOME/.config/tmux/scripts/dv/dv-input.sh"

    if [[ -n "$TMUX" && -x "$input_script" ]]; then
        "$input_script" --title " $title " "$prompt"
        return $?
    else
        read -r -p "$prompt: " val
        echo "$val"
        return 0
    fi
}

# --- Actions ---

do_apply() {
    local line="$1"
    local stash_id=$(echo "$line" | awk -F: '{print $1}')
    if [[ -z "$stash_id" ]]; then return; fi
    
    if git stash apply "$stash_id"; then
        echo "Applied $stash_id"
        read -n 1 -s -r -p "Press any key to continue..."
    else
        echo "Failed to apply $stash_id"
        read -n 1 -s -r -p "Press any key to continue..."
    fi
}

do_pop() {
    local line="$1"
    local stash_id=$(echo "$line" | awk -F: '{print $1}')
    if [[ -z "$stash_id" ]]; then return; fi
    
    if git stash pop "$stash_id"; then
        echo "Popped $stash_id"
        read -n 1 -s -r -p "Press any key to continue..."
    else
        echo "Failed to pop $stash_id"
        read -n 1 -s -r -p "Press any key to continue..."
    fi
}

do_create() {
    local stash_msg=""
    stash_msg=$(get_input "New Stash" "Message (optional)")
    if [[ $? -ne 0 ]]; then return; fi

    if [[ -n "$stash_msg" ]]; then
        git stash push -m "$stash_msg"
    else
        git stash push
    fi
    # Pause to show git output (e.g. "Saved working directory...")
    read -n 1 -s -r -p "Press any key to continue..."
}

do_branch() {
    local line="$1"
    local stash_id=$(echo "$line" | awk -F: '{print $1}')
    if [[ -z "$stash_id" ]]; then return; fi

    local branch_name=""
    branch_name=$(get_input "Branch from Stash" "Branch Name")
    if [[ $? -ne 0 ]]; then return; fi

    if [[ -n "$branch_name" ]]; then
        if git stash branch "$branch_name" "$stash_id"; then
            echo "Created and checked out branch $branch_name from $stash_id"
            read -n 1 -s -r -p "Press any key to continue..."
        else
            echo "Failed to create branch from stash."
            read -n 1 -s -r -p "Press any key to continue..."
        fi
    fi
}

do_drop() {
    local line="$1"
    local stash_id=$(echo "$line" | awk -F: '{print $1}')
    if [[ -z "$stash_id" ]]; then return; fi

    if ! dv_confirm "Drop stash '$stash_id'?"; then
        return
    fi

    if git stash drop "$stash_id"; then
        echo "Dropped $stash_id"
    else
        echo "Failed to drop $stash_id"
        read -n 1 -s -r -p "Press any key to continue..."
    fi
}

if [[ "$1" == "--apply" ]]; then do_apply "$2"; exit 0; fi
if [[ "$1" == "--pop" ]]; then do_pop "$2"; exit 0; fi
if [[ "$1" == "--create" ]]; then do_create; exit 0; fi
if [[ "$1" == "--branch" ]]; then do_branch "$2"; exit 0; fi
if [[ "$1" == "--drop" ]]; then do_drop "$2"; exit 0; fi

# --- Main Logic ---

require_git_repo

current_branch=$(git branch --show-current)
[ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

controls="${C_BOLD}ENTER${C_RESET}: Apply • ${C_BOLD}CTRL-P${C_RESET}: Pop • ${C_BOLD}CTRL-N${C_RESET}: New • ${C_BOLD}CTRL-B${C_RESET}: Branch • ${C_BOLD}CTRL-X${C_RESET}: Drop"
header="${ansi_green}${C_REVERSE} Stash List: ${current_branch} ${C_RESET}"$'\n'"${controls}"

LIST_CMD="git stash list"

if [ -z "$($LIST_CMD)" ]; then
     echo -e "${ansi_yellow}No stashes found.${C_RESET}"
     if dv_confirm "Create a new stash?"; then
         do_create
         # If still empty (e.g. no changes), exit
         if [ -z "$($LIST_CMD)" ]; then
             read -n 1 -s -r -p "Press any key to exit..."
             exit 0
         fi
     else
         exit 0
     fi
fi

$LIST_CMD | dv_run_fzf \
    --tiebreak=index --header-first \
    --no-sort \
    --preview-window 'down,60%,border-top,wrap' \
    --preview-label-pos='3' \
    --bind 'ctrl-/:change-preview-window(right,60%,border,wrap|hidden|)' \
    --border-label=" $icon_git Git Stash " \
    --border-label-pos='3' \
    --header "$header" \
    --prompt='  Stash❯ ' \
    --preview "git stash show --color=always -p \$(echo {} | awk -F: '{print \$1}')" \
    --bind "enter:execute($0 --apply {})+reload($LIST_CMD)" \
    --bind "ctrl-p:execute($0 --pop {})+reload($LIST_CMD)" \
    --bind "ctrl-n:execute($0 --create)+reload($LIST_CMD)" \
    --bind "ctrl-b:execute($0 --branch {})+reload($LIST_CMD)" \
    --bind "ctrl-x:execute($0 --drop {})+reload($LIST_CMD)" \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" \$(echo {} | awk -F: '{print \$1}')"
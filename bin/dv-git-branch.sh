#!/bin/bash
# ===============
# Script Name: dv-git-branch.sh
# Description: Fuzzy Git Branch - Checkout and Management.
# Keybinding:  Prefix + g -> b
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf, dv-input.sh
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Configuration ---
icon_git=""
icon_log=""

# --- Action Handlers ---

generate_list() {
    local mode="$1" # 'local' or 'all'
    local refs=("refs/heads/")
    
    if [[ "$mode" == "all" ]]; then
        refs+=("refs/remotes/")
    fi

    # Format: BranchName - (RelativeDate) Subject
    git for-each-ref --color=always --sort=-committerdate "${refs[@]}" \
        --format='%(color:green)%(refname:short)%(color:reset) - (%(color:blue)%(committerdate:relative)%(color:reset)) %(color:yellow)%(subject)%(color:reset)' \
        | grep -vF $'/HEAD\e'
}

checkout_branch() {
    local raw_branch="$1"
    local branch
    branch=$(echo "$raw_branch" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')

    if [[ -z "$branch" ]]; then return; fi

    # Handle Remote Branches (e.g., origin/feature -> feature)
    if [[ "$branch" == *"/"* ]] && ! git show-ref --verify --quiet "refs/heads/$branch"; then
        # It's likely a remote branch. Try to checkout the tracking name.
        # Remove the remote name (everything before the first slash)
        local tracking_name="${branch#*/}"
        
        # If local branch doesn't exist, git checkout <tracking_name> will auto-track
        if ! git show-ref --verify --quiet "refs/heads/$tracking_name"; then
            tmux display-message "Tracking remote branch: $tracking_name"
            git checkout "$tracking_name"
            return
        fi
    fi

    # Standard Checkout
    if git checkout "$branch" 2>&1; then
        tmux display-message "Checked out: $branch"
    else
        tmux display-message "Failed to checkout: $branch"
    fi
}

delete_branch() {
    local raw_branch="$1"
    local branch
    branch=$(echo "$raw_branch" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $1}')

    if [[ -z "$branch" ]]; then return; fi

    if ! dv_confirm "Delete branch '$branch'?"; then
        return # Cancelled
    fi

    if git branch -D "$branch"; then
        echo "Deleted $branch"
    else
        echo "Failed to delete $branch"
        # Pause to let user see error
        read -n 1 -s -r -p "Press any key to continue..."
    fi
}

# --- Main Logic ---

# 1. Recursive Entry Points
if [[ "$1" == "--generate" ]]; then
    generate_list "$2"
    exit 0
elif [[ "$1" == "--checkout" ]]; then
    checkout_branch "$2"
    exit 0
elif [[ "$1" == "--delete" ]]; then
    delete_branch "$2"
    exit 0
fi

# 2. Interactive Logic
require_git_repo

# Default to local branches
current_mode="local"
current_branch=$(git branch --show-current)
if [[ -z "$current_branch" ]]; then
    current_branch=$(git rev-parse --short HEAD)
fi

# ANSI Colors for Header (Using common.sh variables)
c_reset=$'\033[0m'
c_reverse=$'\033[7m'
nl=$'\n'

# Dynamic Headers (2-Line Layout)
# Line 1: Context | Line 2: Controls
controls="${ansi_cyan}ENTER${ansi_gray}: Checkout ${ansi_gray}• ${ansi_cyan}CTRL-X${ansi_gray}: Delete ${ansi_gray}• ${ansi_cyan}CTRL-A${ansi_gray}: ${ansi_yellow}All ${ansi_gray}• ${ansi_cyan}CTRL-L${ansi_gray}: ${ansi_green}Local${c_reset}"
header_local="${ansi_green}${c_reverse} Local Branches ${c_reset} ${ansi_gray}Current: ${ansi_yellow}${current_branch}${c_reset}${nl}${controls}"
header_all="${ansi_yellow}${c_reverse}  All Branches  ${c_reset} ${ansi_gray}Current: ${ansi_yellow}${current_branch}${c_reset}${nl}${controls}"

$0 --generate "$current_mode" | dv_run_fzf \
    --info=inline-right --no-scrollbar \
    --header-first \
    --preview-window 'down,60%,border-top,wrap' \
    --border-label="  Git Branches " \
    --border-label-pos='3' \
    --preview-label-pos='2' \
    --bind 'ctrl-/:change-preview-window(right,60%,border,wrap|hidden|)' \
    --header="$header_local" \
    --preview="git log --graph --color=always --format='%C(auto)%h%d %s %C(black)%C(bold)%cr' \$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}') | head -n 20" \
    --bind "enter:become($0 --checkout {1})" \
    --bind "ctrl-x:execute($0 --delete {1})+reload($0 --generate $current_mode)+change-header($header_local)" \
    --bind "ctrl-a:reload($0 --generate all)+change-header($header_all)" \
    --bind "ctrl-l:reload($0 --generate local)+change-header($header_local)" \
    --bind "focus:transform-preview-label:printf \" ${icon_log} Log for [%s] \" \$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}')"

#!/bin/bash
# ===============
# Script Name: dv-git-bulk.sh
# Description: Bulk Git Repository Manager (Status, Fetch, Pull).
# Keybinding:  None
# Config:      None
# Dependencies: git, fzf, awk
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Helpers ---

get_repo_dirs() {
    find . -maxdepth 2 -name .git -type d -prune | sort | while read -r gitdir; do
        dirname "$gitdir"
    done
}

# --- Actions ---

generate_list() {
    # Header for FZF (treated as static by --header-lines)
    printf "%-25s %-20s %-15s %s\n" "REPOSITORY" "BRANCH" "STATUS" "SYNC"

    get_repo_dirs | while read -r repo_dir; do
        repo_name=$(basename "$repo_dir")
        
        # Run checks in subshell to avoid directory hopping issues
        (
            cd "$repo_dir" || exit
            
            branch=$(git branch --show-current)
            [ -z "$branch" ] && branch=$(git rev-parse --short HEAD 2>/dev/null)
            [ -z "$branch" ] && branch="-"

            # Status Check
            if [[ -n $(git status --porcelain 2>/dev/null) ]]; then
                status="${ansi_red}Dirty${ansi_fg}"
            else
                status="${ansi_green}Clean${ansi_fg}"
            fi
            
            # Sync Check
            sync_state=""
            if git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
                counts=$(git rev-list --left-right --count HEAD...@{u} 2>/dev/null)
                ahead=$(echo "$counts" | awk '{print $1}')
                behind=$(echo "$counts" | awk '{print $2}')
                
                if [[ "$ahead" != "0" ]]; then sync_state+="↑$ahead "; fi
                if [[ "$behind" != "0" ]]; then sync_state+="↓$behind"; fi
                
                if [[ -n "$sync_state" ]]; then
                    sync_state="${ansi_yellow}${sync_state}${ansi_fg}"
                else
                    sync_state="${ansi_gray}Synced${ansi_fg}"
                fi
            else
                sync_state="${ansi_gray}No Upstream${ansi_fg}"
            fi
            
            printf "%-25s %-20s %-15s %s\n" "$repo_name" "$branch" "$status" "$sync_state"
        )
    done
}

fetch_all() {
    echo "Fetching all repositories in parallel..."
    pids=()
    while read -r repo_dir; do
        (
            cd "$repo_dir" || exit
            printf "Fetching %s...\n" "$(basename "$repo_dir")"
            git fetch -q --all
        ) &
        pids+=($!)
    done < <(get_repo_dirs)
    
    # Wait for all background fetch jobs
    wait "${pids[@]}"
    echo "Fetch complete."
}

pull_selected() {
    # Input: Selected lines from FZF
    # We process sequentially to handle potential credential prompts or merge conflicts cleanly
    while read -r line; do
        repo_name=$(echo "$line" | awk '{print $1}')
        # Find the directory (assuming name matches directory in current path)
        # We search for it to be safe
        repo_dir=$(find . -maxdepth 2 -type d -name "$repo_name" -print -quit)
        
        if [[ -d "$repo_dir" ]]; then
            echo "------------------------------------------------"
            echo "Pulling $repo_name..."
            (
                cd "$repo_dir" || exit
                git pull
            )
        fi
    done
    echo "------------------------------------------------"
    read -n 1 -s -r -p "Press any key to continue..."
}

open_repo() {
    local line="$1"
    local repo_name=$(echo "$line" | awk '{print $1}')
    local repo_dir=$(find . -maxdepth 2 -type d -name "$repo_name" -print -quit)

    if [[ -d "$repo_dir" ]]; then
        # If dv-git-status is available, use it
        if [[ -x "$script_dir/dv-git-status.sh" ]]; then
            (cd "$repo_dir" && "$script_dir/dv-git-status.sh")
        else
            # Fallback to standard git status
            (cd "$repo_dir" && git status && echo "" && read -n 1 -s -r -p "Press any key to continue...")
        fi
    fi
}

# --- Main Dispatch ---

if [[ "$1" == "--generate" ]]; then generate_list; exit 0; fi
if [[ "$1" == "--fetch-all" ]]; then fetch_all; exit 0; fi
if [[ "$1" == "--pull-selected" ]]; then pull_selected; exit 0; fi
if [[ "$1" == "--open" ]]; then open_repo "$2"; exit 0; fi

# --- Interactive Mode ---

controls="${ansi_cyan}CTRL-F${ansi_gray}: Fetch All ${ansi_gray}• ${ansi_cyan}CTRL-P${ansi_gray}: Pull Selected ${ansi_gray}• ${ansi_cyan}ENTER${ansi_gray}: Status"
header="${ansi_blue}${C_REVERSE} Git Bulk Manager ${C_RESET}"$'\n'"${controls}"

$0 --generate | dv_run_fzf \
    --multi \
    --header-lines=1 \
    --header-first \
    --header "$header" \
    --border-label=" Repositories " \
    --border-label-pos='3' \
    --prompt='  Repo❯ ' \
    --preview 'repo=$(echo {} | awk "{print \$1}"); dir=$(find . -maxdepth 2 -type d -name "$repo" -print -quit); cd "$dir" && git -c color.status=always status -s -b' \
    --preview-window 'bottom,50%,border,wrap' \
    --bind "ctrl-f:execute($0 --fetch-all)+reload($0 --generate)" \
    --bind "ctrl-p:execute(echo {+} | xargs -n1 | $0 --pull-selected)+reload($0 --generate)" \
    --bind "enter:execute($0 --open {})+reload($0 --generate)"

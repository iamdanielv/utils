#!/bin/bash
# ===============
# Script Name: tmux-fgb.sh
# Description: Fuzzy Git Branch - Checkout and Management
# Keybinding:  Prefix + g (via Menu)
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf, tmux-input.sh
# ===============

# --- Configuration ---
thm_bg="#1e1e2e"
thm_fg="#cdd6f4"
thm_yellow="#f9e2af"
thm_red="#f38ba8"
thm_header_bg="#2d3f76"
thm_header_fg="#ffffff"
icon_git=""
icon_log=""

# --- Helper Functions ---

is_in_popup() {
    # Since this script runs directly inside the popup, we can check the env var directly.
    [[ -n "$TMUX_POPUP" ]]
}

# --- Action Handlers ---

generate_list() {
    local mode="$1" # 'local' or 'all'
    local refs=("refs/heads/")
    
    if [[ "$mode" == "all" ]]; then
        refs+=("refs/remotes/")
    fi

    # Format: BranchName - (RelativeDate) Subject
    # Matches .bash_aliases style
    git for-each-ref --sort=-committerdate "${refs[@]}" \
        --format='%(color:green)%(refname:short)%(color:reset) - (%(color:blue)%(committerdate:relative)%(color:reset)) %(color:yellow)%(subject)%(color:reset)' \
        | grep -v "HEAD"
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

    # Use tmux-input.sh for confirmation if available
    local script_dir
    script_dir=$(dirname "$0")
    local confirm_cmd="$script_dir/tmux-input.sh"

    if [[ -x "$confirm_cmd" ]]; then
        if ! "$confirm_cmd" --internal-confirm "Delete branch '$branch'?"; then
            return # Cancelled
        fi
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

# 2. Popup Context (The FZF Interface)
if is_in_popup; then
    # Default to local branches
    current_mode="local"
    current_branch=$(git branch --show-current)
    
    # Label styling (White on Blue)
    lbl_style="\033[38;2;255;255;255;48;2;45;63;118m"
    lbl_reset="\033[0m"
    
    $0 --generate "$current_mode" | fzf \
        --ansi --reverse --tiebreak=index \
        --header-first \
        --preview-window 'down,70%,border-top,wrap' \
        --border-label-pos='3' \
        --preview-label-pos='3' \
        --bind 'ctrl-/:change-preview-window(right,60%,border,wrap|hidden|)' \
        --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#f9e2af,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff' \
        --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7' \
        --header="Current: $current_branch | ENTER: Checkout | CTRL-X: Delete | CTRL-A: All | CTRL-L: Local" \
        --preview="git log --graph --color=always --format='%C(auto)%h%d %s %C(black)%C(bold)%cr' \$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}') | head -n 20" \
        --bind "enter:become($0 --checkout {1})" \
        --bind "ctrl-x:execute($0 --delete {1})+reload($0 --generate $current_mode)" \
        --bind "ctrl-a:reload($0 --generate all)" \
        --bind "ctrl-l:reload($0 --generate local)" \
        --bind "focus:transform-preview-label:printf \"${lbl_style} ${icon_log} Log for [%s] ${lbl_reset}\" \$(echo {} | sed 's/\x1b\[[0-9;]*m//g' | awk '{print \$1}')"
    exit 0
fi

# 3. Main Context (Launch the Popup)
tmux display-popup -E -w 90% -h 70% -d "#{pane_current_path}" \
    -T "#[bg=$thm_yellow,fg=$thm_bg,bold] $icon_git Git Branches " \
    "TMUX_POPUP=1 $0"

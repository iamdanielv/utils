#!/bin/bash
# ===============
# Script Name: tmux-git-stash.sh
# Description: Interactive Git Stash Viewer - Apply, Drop
# Keybinding:  Prefix + g -> t
# Dependencies: tmux, git, fzf
# ===============

# --- Auto-Launch Tmux ---
if [ -z "$TMUX" ]; then
    script_path=$(readlink -f "$0")
    if tmux has-session -t main 2>/dev/null; then
        tmux new-window -t main -n "git-stash" -c "$PWD" "$script_path"
        exec tmux attach-session -t main
    else
        exec tmux new-session -s main -n "git-stash" -c "$PWD" "$script_path"
    fi
    exit 0
fi

# --- Configuration ---
_C_RESET=$'\033[0m'
_C_GREEN=$'\033[1;32m'
_C_YELLOW=$'\033[1;33m'
_C_BOLD=$'\033[1m'
_C_REVERSE=$'\033[7m'

thm_bg="#1e1e2e"
thm_fg="#cdd6f4"
thm_yellow="#f9e2af"

icon_git=""

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
    local script_dir
    script_dir=$(dirname "$0")
    local input_cmd="$script_dir/dv-input"
    local stash_msg=""

    if [[ -x "$input_cmd" ]]; then
        stash_msg=$("$input_cmd" --title " New Stash " "Message (optional)")
        if [[ $? -ne 0 ]]; then return; fi
    fi

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

    local script_dir
    script_dir=$(dirname "$0")
    local input_cmd="$script_dir/dv-input"
    local branch_name=""

    if [[ -x "$input_cmd" ]]; then
        branch_name=$("$input_cmd" --title " Branch from Stash " "Branch Name")
        if [[ $? -ne 0 ]]; then return; fi
    fi

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

    # Confirmation
    local script_dir
    script_dir=$(dirname "$0")
    local confirm_cmd="$script_dir/dv-input"
    
    if [[ -x "$confirm_cmd" ]]; then
        if ! "$confirm_cmd" --internal-confirm "Drop stash '$stash_id'?"; then
            return
        fi
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

# --- Popup Logic ---
if is_in_popup; then
    _require_git_repo
    
    current_branch=$(git branch --show-current)
    [ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

    controls="${_C_BOLD}ENTER${_C_RESET}: Apply • ${_C_BOLD}CTRL-P${_C_RESET}: Pop • ${_C_BOLD}CTRL-N${_C_RESET}: New • ${_C_BOLD}CTRL-B${_C_RESET}: Branch • ${_C_BOLD}CTRL-X${_C_RESET}: Drop"
    header="${_C_GREEN}${_C_REVERSE} Stash List: ${current_branch} ${_C_RESET}"$'\n'"${controls}"

    LIST_CMD="git stash list"
    
    if [ -z "$($LIST_CMD)" ]; then
         echo -e "${_C_YELLOW}No stashes found.${_C_RESET}"
         read -p "Create a new stash? (y/N) " -n 1 -r
         echo
         if [[ $REPLY =~ ^[Yy]$ ]]; then
             read -r -p "${_C_BOLD}Message (optional):${_C_RESET} " stash_msg
             if [[ -n "$stash_msg" ]]; then
                 git stash push -m "$stash_msg"
             else
                 git stash push
             fi
             # If still empty (e.g. no changes), exit
             if [ -z "$($LIST_CMD)" ]; then
                 read -n 1 -s -r -p "Press any key to exit..."
                 exit 0
             fi
         else
             exit 0
         fi
    fi

    $LIST_CMD | fzf \
        --ansi --reverse --tiebreak=index --header-first \
        --no-sort \
        --preview-window 'down,60%,border-top,wrap' \
        --preview-label-pos='3' \
        --bind 'ctrl-/:change-preview-window(right,60%,border,wrap|hidden|)' \
        --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff' \
        --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7' \
        --header "$header" \
        --prompt='  Stash❯ ' \
        --preview "git stash show --color=always -p \$(echo {} | awk -F: '{print \$1}')" \
        --bind "enter:execute($0 --apply {})+reload($LIST_CMD)" \
        --bind "ctrl-p:execute($0 --pop {})+reload($LIST_CMD)" \
        --bind "ctrl-n:execute($0 --create)+reload($LIST_CMD)" \
        --bind "ctrl-b:execute($0 --branch {})+reload($LIST_CMD)" \
        --bind "ctrl-x:execute($0 --drop {})+reload($LIST_CMD)" \
        --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" \$(echo {} | awk -F: '{print \$1}')"
    exit 0
fi

# --- Launch ---
script_path=$(readlink -f "$0")
tmux display-popup -E -w 95% -h 80% -d "#{pane_current_path}" \
    -T "#[bg=$thm_yellow,fg=$thm_bg,bold] $icon_git Git Stash " \
    "TMUX_POPUP=1 $script_path"
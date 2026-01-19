#!/bin/bash
# ===============
# Script Name: dv-git-status.sh
# Description: Interactive Git Status - Stage, Discard, Diff.
# Keybinding:  Prefix + g -> s
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf, bat/batcat
# ===============

# --- Auto-Launch Tmux ---
if [ -z "$TMUX" ]; then
    script_path=$(readlink -f "$0")
    if tmux has-session -t main 2>/dev/null; then
        tmux new-window -t main -n "git-status" -c "$PWD" "$script_path"
        exec tmux attach-session -t main
    else
        exec tmux new-session -s main -n "git-status" -c "$PWD" "$script_path"
    fi
    exit 0
fi

# --- Configuration ---
_C_RESET=$'\033[0m'
_C_GREEN=$'\033[1;32m'
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
    
    # Confirmation
    local script_dir
    script_dir=$(dirname "$0")
    local confirm_cmd="$script_dir/dv-input"
    
    if [[ -x "$confirm_cmd" ]]; then
        if ! "$confirm_cmd" --internal-confirm "Discard changes to '$file'?"; then
            return
        fi
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

# --- Popup Logic ---

if is_in_popup; then
    _require_git_repo
    
    current_branch=$(git branch --show-current)
    [ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

    controls="${_C_BOLD}TAB${_C_RESET}: Stage/Unstage • ${_C_BOLD}CTRL-X${_C_RESET}: Discard • ${_C_BOLD}ENTER${_C_RESET}: Edit"
    header="${_C_GREEN}${_C_REVERSE} Status: ${current_branch} ${_C_RESET}"$'\n'"${controls}"

    EDITOR_CMD="${EDITOR:-vim}"
    if command -v nvim &>/dev/null; then EDITOR_CMD="nvim"; fi
    LIST_CMD="git status --short"
    
    $LIST_CMD | fzf \
        --ansi --reverse --tiebreak=index --header-first \
        --no-sort \
        --preview-window 'right,60%,border,wrap' \
        --preview-label-pos='3' \
        --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)' \
        --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff' \
        --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7' \
        --header "$header" \
        --prompt='  Status❯ ' \
        --preview "$0 --preview {}" \
        --bind "tab:execute($0 --toggle {})+reload($LIST_CMD)" \
        --bind "ctrl-x:execute($0 --discard {})+reload($LIST_CMD)" \
        --bind "enter:become($EDITOR_CMD \$(echo {} | cut -c 4- | sed 's/^\"//;s/\"$//'))" \
        --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" \$(echo {} | cut -c 4- | sed 's/^\"//;s/\"$//')"
    exit 0
fi

# --- Launch ---
script_path=$(readlink -f "$0")
tmux display-popup -E -w 95% -h 80% -d "#{pane_current_path}" \
    -T "#[bg=$thm_yellow,fg=$thm_bg,bold] $icon_git Git Status " \
    "TMUX_POPUP=1 $script_path"

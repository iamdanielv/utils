#!/bin/bash
# ===============
# Script Name: dv-git-diff.sh
# Description: Interactive Git Diff Viewer (Unstaged/Staged/All).
# Keybinding:  Prefix + g -> d
# Config:      bind g display-menu ...
# Dependencies: tmux, git, fzf
# ===============

# --- Auto-Launch Tmux ---
if [ -z "$TMUX" ]; then
    script_path=$(readlink -f "$0")
    if tmux has-session -t main 2>/dev/null; then
        tmux new-window -t main -n "git-diff" -c "$PWD" "$script_path"
        exec tmux attach-session -t main
    else
        exec tmux new-session -s main -n "git-diff" -c "$PWD" "$script_path"
    fi
    exit 0
fi

# --- Configuration ---
_C_RESET=$'\033[0m'
_C_GREEN=$'\033[1;32m'
_C_YELLOW=$'\033[1;33m'
_C_BLUE=$'\033[1;34m'
_C_MAGENTA=$'\033[1;35m'
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
        git diff --cached --color=always -- "$file"
    elif [[ "$mode" == "all" ]]; then
        git diff HEAD --color=always -- "$file"
    else
        git diff --color=always -- "$file"
    fi
}

# --- Main Dispatch ---

if [[ "$1" == "--preview" ]]; then do_preview "$2" "$3"; exit 0; fi
if [[ "$1" == "--generate" ]]; then generate_list "$2"; exit 0; fi

# --- Popup Logic ---

if is_in_popup; then
    _require_git_repo
    
    # Mode handling (default to unstaged)
    current_mode="unstaged"
    if [[ "$1" == "--mode" ]]; then
        current_mode="$2"
    fi

    current_branch=$(git branch --show-current)
    [ -z "$current_branch" ] && current_branch=$(git rev-parse --short HEAD)

    # Dynamic Header
    case "$current_mode" in
        "staged")   mode_label="${_C_GREEN}Staged${_C_RESET}" ;;
        "all")      mode_label="${_C_MAGENTA}All (HEAD)${_C_RESET}" ;;
        *)          mode_label="${_C_YELLOW}Unstaged${_C_RESET}" ;;
    esac

    controls="${_C_BOLD}CTRL-S${_C_RESET}: Staged • ${_C_BOLD}CTRL-U${_C_RESET}: Unstaged • ${_C_BOLD}CTRL-A${_C_RESET}: All • ${_C_BOLD}ENTER${_C_RESET}: Edit"
    header="${_C_BLUE}${_C_REVERSE} Diff: ${current_branch} ${_C_RESET} ${mode_label}"$'\n'"${controls}"

    EDITOR_CMD="${EDITOR:-vim}"
    if command -v nvim &>/dev/null; then EDITOR_CMD="nvim"; fi

    # Generate list and pipe to FZF
    # We use 'become' to switch modes because the preview command needs to change
    $0 --generate "$current_mode" | fzf \
        --ansi --reverse --tiebreak=index --header-first \
        --no-sort \
        --preview-window 'down,60%,border-top,wrap' \
        --preview-label-pos='3' \
        --bind 'ctrl-/:change-preview-window(right,60%,border,wrap|hidden|)' \
        --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff' \
        --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7' \
        --header "$header" \
        --prompt="  Diff(${current_mode})❯ " \
        --preview "$0 --preview $current_mode {}" \
        --bind "ctrl-s:become($0 --mode staged)" \
        --bind "ctrl-u:become($0 --mode unstaged)" \
        --bind "ctrl-a:become($0 --mode all)" \
        --bind "enter:become($EDITOR_CMD {})" \
        --bind "focus:transform-preview-label:[[ -n {} ]] && printf \" Previewing [%s] \" {}"
    
    exit 0
fi

# --- Launch ---
script_path=$(readlink -f "$0")
# Default to unstaged mode when launching
tmux display-popup -E -w 95% -h 80% -d "#{pane_current_path}" \
    -T "#[bg=$thm_yellow,fg=$thm_bg,bold] $icon_git Git Diff " \
    "TMUX_POPUP=1 $script_path --mode unstaged"
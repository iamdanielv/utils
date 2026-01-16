#!/bin/bash
# ===============
# Script Name: tmux-git-file-history.sh
# Description: Interactive file history viewer with nested FZF loops.
# Keybinding:  Prefix + g -> h
# Dependencies: git, fzf, tmux
# ===============

# --- Styles & Constants ---
# Matches .bash_aliases style
_C_RESET=$'\033[0m'
_C_RED=$'\033[1;31m'
_C_BLUE=$'\033[1;34m'
_C_MAGENTA=$'\033[1;35m'
_C_CYAN=$'\033[1;36m'
_C_BOLD=$'\033[1m'

# FZF Styles
_FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'
_FZF_LBL_RESET="${_C_RESET}"

_FZF_COMMON_OPTS=(
  --ansi --reverse --tiebreak=index --header-first --border=top
  --preview-window 'right,60%,border,wrap'
  --border-label-pos='3'
  --preview-label-pos='3'
  --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)'
  --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff'
  --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7'
)

_GIT_LOG_COMPACT_FORMAT='%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)'

# Inline sed command for date shortening to avoid export issues in subshells
_SED_DATE="sed -E 's/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g'"

# Define Preview Commands
_PREVIEW_LIMITED="git log --follow -n 20 --color=always --format=\"${_GIT_LOG_COMPACT_FORMAT}\" -- {} | ${_SED_DATE}"
_PREVIEW_FULL="git log --follow --color=always --format=\"${_GIT_LOG_COMPACT_FORMAT}\" -- {} | ${_SED_DATE}"

# --- Helpers ---

_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    printf "%b✗ Error:%b Not a git repository\n" "${_C_RED}" "${_C_RESET}"
    read -r -n 1 -s -p "Press any key to exit..."
    exit 1
  fi
}

# --- Main Logic ---

_require_git_repo

while true; do
  # 1. Select File
  # Preview limited to 20 commits for performance optimization
  selected_file=$(git ls-files | fzf "${_FZF_COMMON_OPTS[@]}" \
    --header $'ENTER: inspect commits | ESC: quit\nCTRL-F: full history | CTRL-L: limited (20)' \
    --border-label=' File History Explorer ' \
    --preview "${_PREVIEW_LIMITED}" \
    --prompt='  File❯ ' \
    --bind "ctrl-f:change-preview(${_PREVIEW_FULL})" \
    --bind "ctrl-l:change-preview(${_PREVIEW_LIMITED})" \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} History for [%s] ${_FZF_LBL_RESET}\" {}")

  if [[ -z "$selected_file" ]]; then
    break
  fi

  # 2. Select Commit
  # Full history is shown here for the specific file
  selected_commit=$(git log --follow --color=always \
        --format="${_GIT_LOG_COMPACT_FORMAT}" -- "$selected_file" |
        eval "$_SED_DATE" | fzf "${_FZF_COMMON_OPTS[@]}" --no-sort --no-hscroll \
        --header $'ENTER: view diff | ESC: back to files\nCTRL-Y: copy hash | CTRL-/: view' \
        --border-label " History for $selected_file " \
        --bind "enter:execute(git show --color=always {1} -- \"$selected_file\" | less -R)" \
        --bind 'ctrl-y:accept' \
        --preview "git show --color=always {1} -- \"$selected_file\"" \
        --prompt='  Commit❯ ' \
        --input-label ' Filter Commits ' \
        --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${_FZF_LBL_STYLE} Diff for [%s] ${_FZF_LBL_RESET}\" {1}")

  if [[ -n "$selected_commit" ]]; then
      # Extract hash (strip ANSI codes)
      hash=$(echo "$selected_commit" | sed $'s/\e\[[0-9;]*m//g' | awk '{print $1}')
      
      if [[ -n "$hash" ]]; then
          # Copy to tmux clipboard since we are likely in a popup
          if [[ -n "$TMUX" ]]; then
              printf "%s" "$hash" | tmux load-buffer -
              tmux display-message "Hash $hash copied to tmux buffer"
          else
              printf "Selected Hash: %s\n" "$hash"
          fi
      fi
  fi
done
#!/bin/bash
# ===============
# Script Name: dv-git-history.sh
# Description: Interactive file history viewer with nested FZF loops.
# Keybinding:  Prefix + g -> h
# Config:      bind g display-menu ...
# Dependencies: git, fzf, tmux
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/dv-common.sh"

# --- Configuration ---
C_RESET=$'\033[0m'
icon_git=""

# FZF Styles
FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'
FZF_LBL_RESET="${C_RESET}"

_GIT_LOG_COMPACT_FORMAT='%C(yellow)%h%C(reset) %C(green)(%cr)%C(reset)%C(bold cyan)%d%C(reset) %s %C(blue)<%an>%C(reset)'

# Inline sed command for date shortening to avoid export issues in subshells
_SED_DATE="sed -E 's/ months? ago/ mon/g; s/ weeks? ago/ wk/g; s/ days? ago/ day/g; s/ hours? ago/ hr/g; s/ minutes? ago/ min/g; s/ seconds? ago/ sec/g'"

# Define Preview Commands
_PREVIEW_LIMITED="git log --follow -n 20 --color=always --format=\"${_GIT_LOG_COMPACT_FORMAT}\" -- {} | ${_SED_DATE}"
_PREVIEW_FULL="git log --follow --color=always --format=\"${_GIT_LOG_COMPACT_FORMAT}\" -- {} | ${_SED_DATE}"

# --- Main Logic ---

require_git_repo

while true; do
  # 1. Select File
  # Preview limited to 20 commits for performance optimization
  selected_file=$(git ls-files | dv_run_fzf \
    --tiebreak=index --header-first \
    --header "ENTER: inspect commits | ESC: quit"$'\n'"CTRL-F: ${ansi_green}full history${C_RESET} | CTRL-L: ${ansi_yellow}limited (20)${C_RESET}" \
    --border-label=" $icon_git File History ${ansi_yellow}(Limited)${C_RESET} " \
    --border-label-pos='3' \
    --preview-label-pos='3' \
    --preview-window 'right,60%,border,wrap' \
    --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)' \
    --preview "${_PREVIEW_LIMITED}" \
    --prompt='  File❯ ' \
    --bind "ctrl-f:change-preview(${_PREVIEW_FULL})+change-border-label( $icon_git File History ${ansi_green}(Full)${C_RESET} )" \
    --bind "ctrl-l:change-preview(${_PREVIEW_LIMITED})+change-border-label( $icon_git File History ${ansi_yellow}(Limited)${C_RESET} )" \
    --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${FZF_LBL_STYLE} History for [%s] ${FZF_LBL_RESET}\" {}")

  if [[ -z "$selected_file" ]]; then
    break
  fi

  if command -v delta &>/dev/null; then
      _SHOW_PREVIEW="git show {1} -- \"$selected_file\" | delta --paging=never"
      _SHOW_ENTER="git show {1} -- \"$selected_file\" | delta"
  else
      _SHOW_PREVIEW="git show --color=always {1} -- \"$selected_file\""
      _SHOW_ENTER="git show --color=always {1} -- \"$selected_file\" | less -R"
  fi

  # 2. Select Commit
  # Full history is shown here for the specific file
  selected_commit=$(git log --follow --color=always \
        --format="${_GIT_LOG_COMPACT_FORMAT}" -- "$selected_file" |
        eval "$_SED_DATE" | dv_run_fzf --no-sort --no-hscroll \
        --tiebreak=index --header-first \
        --header $'ENTER: view diff | ESC: back to files\nCTRL-Y: copy hash | CTRL-/: view' \
        --border-label " History for $selected_file " \
        --border-label-pos='3' \
        --preview-label-pos='3' \
        --preview-window 'right,60%,border,wrap' \
        --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)' \
        --bind "enter:execute($_SHOW_ENTER)" \
        --bind 'ctrl-y:accept' \
        --preview "$_SHOW_PREVIEW" \
        --prompt='  Commit❯ ' \
        --input-label ' Filter Commits ' \
        --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${FZF_LBL_STYLE} Diff for [%s] ${FZF_LBL_RESET}\" {1}")

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
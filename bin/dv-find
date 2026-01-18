#!/bin/bash
# ==============================================================================
# Script Name: dv-find
# Description: Find a file and open it in Neovim.
# Usage:       dv-find
# ==============================================================================

# --- Configuration ---
C_RESET=$'\033[0m'
FZF_LBL_STYLE=$'\033[38;2;255;255;255;48;2;45;63;118m'

FZF_COMMON_OPTS=(
  --ansi --reverse --tiebreak=index --header-first --border=top
  --preview-window 'right,60%,border,wrap'
  --border-label-pos='3'
  --preview-label-pos='3'
  --bind 'ctrl-/:change-preview-window(down,70%,border-top|hidden|)'
  --color 'border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff'
  --color 'bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7'
)

# Use fd if available for better performance
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --hidden --follow --exclude ".git"'
fi

fzf "${FZF_COMMON_OPTS[@]}" --exact \
  --border-label=' File Finder ' \
  --prompt='  Open❯ ' \
  --header $'ENTER: open | ESC: quit\nCTRL-/: view' \
  --preview 'fzf-preview.sh {}' \
  --bind "enter:become(nvim {})" \
  --bind "focus:transform-preview-label:[[ -n {} ]] && printf \"${FZF_LBL_STYLE} Previewing [%s] ${C_RESET}\" {}"

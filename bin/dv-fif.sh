#!/bin/bash
# ===============
# Script Name: dv-fif.sh
# Description: Interactive search of file contents using ripgrep and fzf.
# Keybinding:  Alt+x f
# Config:      alias fif='dv-fif.sh'
# Dependencies: rg, fzf, bat/batcat
# ===============

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

BAT_CMD="cat"
if command -v batcat &>/dev/null; then BAT_CMD="batcat"; elif command -v bat &>/dev/null; then BAT_CMD="bat"; fi

# --- Main Logic ---
initial_query="$1"
rg_cmd="rg --column --line-number --no-heading --color=always --smart-case"

fzf "${FZF_COMMON_OPTS[@]}" \
  --disabled --ansi \
  --bind "start:reload:$rg_cmd {q}" \
  --bind "change:reload:sleep 0.1; $rg_cmd {q} || true" \
  --delimiter : \
  --header 'Type to search content | ENTER: open | CTRL-/: view' \
  --border-label=' Find in Files ' \
  --prompt='  Search❯ ' \
  --preview "${BAT_CMD} --style=numbers --color=always --highlight-line {2} {1}" \
  --preview-window 'right,60%,border,wrap,+{2}-/2' \
  --bind 'enter:become(nvim {1} +{2})' \
  --query "$initial_query"
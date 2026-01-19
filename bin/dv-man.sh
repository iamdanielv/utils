#!/bin/bash
# ===============
# Script Name: dv-man.sh
# Description: Interactively search and open man pages.
# Keybinding:  Alt+x m
# Config:      alias fman='dv-man.sh'
# Dependencies: man, fzf, bat/batcat
# ===============

# --- Configuration ---
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

man -k . | sort | \
  fzf "${FZF_COMMON_OPTS[@]}" \
  --tiebreak=begin \
  --border-label=' Manual Pages ' \
  --prompt='  Man❯ ' \
  --header 'ENTER: open | CTRL-/: view' \
  --preview "sec=\$(echo {2} | tr -d '()'); MANWIDTH=\$FZF_PREVIEW_COLUMNS man -P cat \"\$sec\" {1} 2>/dev/null | col -bx | ${BAT_CMD} -l man -p --color=always" \
  --preview-window 'right,60%,border,wrap' \
  --bind "enter:become(sec=\$(echo {2} | tr -d '()'); man \"\$sec\" {1})"
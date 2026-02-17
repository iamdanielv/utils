#!/bin/bash
# ===============
# Script Name: dv-history.sh
# Description: Interactively search and select commands from history.
# Keybinding:  Alt+x r (via .bash_aliases)
# Config:      None
# Dependencies: fzf, tac
# ===============

set -o pipefail

# --- Configuration ---
# Colors matching .bash_aliases FZF theme
FZF_COLORS='bg+:#2d3f76,bg:#1e2030,gutter:#1e2030,prompt:#cba6f7,border:#99ccff,label:#99ccff:reverse,preview-border:#2d3f76,preview-label:white:regular,header-border:#6699cc,header-label:#99ccff'

FZF_OPTS=(
  --ansi 
  --reverse 
  --tiebreak=index 
  --header-first 
  --border=top
  --color "$FZF_COLORS"
  --no-sort
  --border-label=' Command History '
  --border-label-pos='2'
  --prompt='  History❯ '
  --header 'ENTER: Select | CTRL-E: Execute | CTRL-/: View'
  --expect=ctrl-e
  --preview 'echo {} | sed -E "s/^[ ]*[0-9]+[ ]*//"'
  --preview-window='down,20%,border,wrap,hidden'
  --bind 'ctrl-/:change-preview-window(down,20%,border,wrap|hidden)'
)

# Optional: Accept initial query as argument
QUERY="$1"
if [[ -n "$QUERY" ]]; then
  FZF_OPTS+=(--query "$QUERY")
fi

# --- Input Handling ---
get_input() {
  if [ -p /dev/stdin ]; then
    # Input is piped (e.g. `history | dv-history.sh`)
    cat
  else
    # Fallback to history file
    local hist_file="${HISTFILE:-$HOME/.bash_history}"
    if [ -f "$hist_file" ]; then
      cat "$hist_file"
    fi
  fi
}

# Run FZF
# We use `tac` to reverse the stream so newest commands appear first.
output=$(get_input | tac | fzf "${FZF_OPTS[@]}")
exit_code=$?

[[ $exit_code -ne 0 ]] && exit $exit_code

# --- Output Parsing ---
# FZF with --expect prints the key on the first line, then the selection.
key=$(head -1 <<< "$output")
line=$(tail -n +2 <<< "$output")

if [[ -n "$line" ]]; then
  # Clean up: Remove history numbers (e.g. "  123  ls") and trim leading whitespace
  cmd=$(echo "$line" | sed -E 's/^[ ]*[0-9]+[ ]*//' | sed -E 's/^[ ]+//')
  printf "%s\n%s\n" "$key" "$cmd"
fi
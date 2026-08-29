#!/bin/bash
# ===============
# Script Name: dv-keys.sh
# Description: FZF Keybinding Lookup
# Keybinding:  Prefix + ?
# Config:      bind ? run-shell -b "~/.config/tmux/scripts/dv/dv-keys.sh"
# Dependencies: tmux, fzf, awk
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/common.sh"

# --- 1. AWK Formatting Logic ---
# Extracts key (first 12 chars) and command (rest), inserting a separator with color
# shellcheck disable=SC2016
awk_cmd='{
    key=substr($0,1,12);
    cmd=substr($0,13);
    printf "\033[1;34m%s\033[38;2;30;32;48m@@@%s\033[0m\n", key, cmd
}'

# --- 2. Preview Logic ---
# Formats the selected line for the preview window
preview_cmd='echo {} \
    | sed -E "s/^[[:space:]]*(.*)[[:space:]]*@@@(.*)/\1:\n  \2/" \
    | sed -E "s/[[:space:]]+:/:/"'

check_deps "fzf" "awk"

# --- 3. Execution ---
tmux list-keys -Na \
  | awk "$awk_cmd" \
  | dv_run_fzf \
      -e \
      --tmux 90%,80% \
      --no-hscroll \
      --border-label=" TMUX KEY BINDINGS " \
      --border-label-pos=3 \
      --preview="$preview_cmd" \
      --preview-window="right:70%:wrap:border-left" \
      --color "hl:-1,hl+:-1" \
      > /dev/null 2>&1 || true

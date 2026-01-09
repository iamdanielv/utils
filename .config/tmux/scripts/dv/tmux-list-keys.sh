#!/bin/bash
# FZF Keybinding Lookup

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

# --- 3. FZF Options ---
fzf_opts=(
    "-e"
    "--tmux" "90%,80%"
    "--color" "hl:-1,hl+:-1"
    "--no-hscroll" "--ansi"
    "--layout=reverse"
    "--border=rounded"
    "--border-label= TMUX KEY BINDINGS "
    --preview="$preview_cmd"
    "--preview-window=right:70%:wrap:border-left"
    "--border-label-pos=3"
    "--color=bg+:#2d3f76" "--color=bg:#1e2030"
    "--color=border:#f9e2af"
    "--color=label:#f9e2af:reverse"
    "--color=fg:#c8d3f5"
    "--color=gutter:#1e2030"
    "--color=header:#ff966c"
    "--color=info:#545c7e"
    "--color=marker:#ff007c"
    "--color=pointer:#ff007c"
    "--color=prompt:#65bcff"
    "--color=query:#c8d3f5:regular"
    "--color=scrollbar:#589ed7"
    "--color=separator:#ff966c"
    "--color=spinner:#ff007c"
)

# --- 4. Execution ---
tmux list-keys -Na \
  | awk "$awk_cmd" \
  | fzf "${fzf_opts[@]}" > /dev/null 2>&1 || true
#!/bin/bash
# ===============
# Script Name: common.sh
# Description: Shared library for dv-tmux scripts (Colors, Helpers, FZF)
# Dependencies: tmux, fzf
# ===============

# --- Theme: Tokyo Night ---
thm_bg="#1e2030"
thm_fg="#c8d3f5"
thm_cyan="#04a5e5"
thm_black="#1e2030"
thm_gray="#2d3f76"
thm_magenta="#cba6f7"
thm_pink="#ff007c"
thm_red="#ff966c"
thm_green="#c3e88d"
thm_yellow="#ffc777"
thm_blue="#82aaff"
thm_orange="#ff966c"
thm_black4="#444a73"
thm_mauve="#cba6f7"

# --- ANSI Helpers ---
to_ansi() {
    local hex=$1
    hex="${hex/\#/}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf "\033[38;2;%d;%d;%dm" "$r" "$g" "$b"
}

strip_ansi() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Pre-calculated ANSI colors for scripts
ansi_blue=$(to_ansi "$thm_blue")
ansi_fg=$(to_ansi "$thm_fg")
ansi_yellow=$(to_ansi "$thm_yellow")
ansi_cyan=$(to_ansi "$thm_cyan")
ansi_red=$(to_ansi "$thm_red")
ansi_green=$(to_ansi "$thm_green")
ansi_magenta=$(to_ansi "$thm_magenta")
ansi_gray=$(to_ansi "$thm_gray")

# --- Utilities ---

log_debug() {
    local msg="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" >> /tmp/dv-tmux.log
}

check_deps() {
    for dep in "$@"; do
        if ! command -v "$dep" >/dev/null; then
            echo "Error: Dependency '$dep' not found."
            exit 1
        fi
    done
}

get_auto_geometry() {
    local text="$1"
    local mode="$2" # "input" or "msg"
    
    local clean_text
    clean_text=$(strip_ansi "$text")
    local len=${#clean_text}
    
    local term_cols
    term_cols=$(tput cols 2>/dev/null || echo 80)
    
    local max_w=$(( term_cols * 80 / 100 ))
    if (( max_w > 120 )); then max_w=120; fi
    local min_w=40
    
    local w=$(( len + 8 ))
    if (( w < min_w )); then w=$min_w; fi
    if (( w > max_w )); then w=$max_w; fi
    
    local h=8
    if [[ "$mode" == "msg" ]]; then
        local inner_w=$(( w - 6 ))
        if (( inner_w < 1 )); then inner_w=1; fi
        local lines=$(( len / inner_w + 1 ))
        h=$(( lines + 6 ))
    fi
    echo "$w $h"
}

# --- FZF Wrapper ---
dv_run_fzf() {
    # Standardized FZF options (Theme & Layout)
    fzf \
        --tmux 90%,70% \
        --ansi \
        --reverse \
        --layout=reverse-list \
        --border=rounded \
        --color "border:${thm_cyan},label:${thm_cyan}:reverse,header-border:${thm_blue},header-label:${thm_blue},header:${thm_cyan}" \
        --color "bg+:${thm_gray},bg:${thm_bg},gutter:${thm_bg},prompt:${thm_orange}" \
        "$@"
}
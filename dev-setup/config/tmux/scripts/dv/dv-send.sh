#!/bin/bash
# ===============
# Script Name: dv-send.sh
# Description: Unified Send (Push) - Move the current pane to another window or session.
# Keybinding:  Prefix + k
# Config:      bind k run-shell -b "~/.config/tmux/scripts/dv/dv-send.sh"
# Dependencies: tmux > 3.2, fzf, grep, sed, cut
# ===============

script_path=$(readlink -f "$0")
script_dir=$(dirname "$script_path")
source "$script_dir/common.sh"


# --- Callback Logic (New Session) ---
if [ "$1" = "--new-session" ]; then
    sess_name="$2"
    src_pane="$3"
    follow="$4"

    if [ -z "$sess_name" ]; then exit 0; fi

    if tmux has-session -t "=${sess_name}" 2>/dev/null; then
        if [ "$follow" -eq 1 ]; then
            tmux switch-client -t "=${sess_name}"
        fi
        tmux break-pane -s "$src_pane" -t "=${sess_name}"
        "$script_dir/dv-input.sh" --type warning --message "Session Exists: ${ansi_blue}${sess_name}"
    else
        tmux new-session -d -s "$sess_name"
        if [ "$follow" -eq 1 ]; then
            tmux switch-client -t "=${sess_name}"
        fi
        tmux join-pane -s "$src_pane" -t "=${sess_name}:"
        tmux kill-pane -a -t "$src_pane"
        "$script_dir/dv-input.sh" --type success --message "Session Created: ${ansi_blue}${sess_name}"
    fi

    exit 0
fi

# --- Checks ---
if [ -z "$TMUX" ]; then
    echo "Error: This script must be run within a tmux session."
    exit 1
fi

check_deps "fzf" "grep" "sed" "cut"

# --- Logic ---

# Get current context
src_pane=$(tmux display-message -p "#{pane_id}")
cur_win_id=$(tmux display-message -p "#{window_id}")
cur_sess=$(tmux display-message -p "#{session_name}")
cur_win_panes=$(tmux display-message -p "#{window_panes}")

# Generate Target List
# Format: TYPE <tab> TARGET <tab> DISPLAY
tab=$'\t'

# 1. Existing Windows
# Filter out current window
windows=$(tmux list-windows -a -F "WIN${tab}#{window_id}${tab}#{session_name}${tab}#{window_index}${tab}#{window_name}${tab}#{session_attached}" \
    | grep -v "${tab}${cur_win_id}${tab}" \
    | while IFS="$tab" read -r type wid sn wi wn attached; do
        # Sanitize window name to prevent tab collision
        wn="${wn//$tab/ }"
        
        icon=""
        if [ "$sn" = "$cur_sess" ]; then
            icon="${ansi_green}${ansi_fg} "
        elif [ "$attached" -ge 1 ]; then
            icon="${ansi_yellow}${ansi_fg} "
        fi

        display="${icon}${ansi_blue}${sn}${ansi_fg}: ${ansi_yellow}${wi}:${wn}${ansi_fg}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$type" "$wid" "$display" "$sn" "$wi" "$wn"
      done)

# 2. New Window in Session
sessions=$(tmux list-sessions -F "SES${tab}#{session_name}${tab}#{session_name}${tab}#{session_attached}" \
    | while IFS="$tab" read -r type sn _display_sn attached; do
        # Filter out current session if it's the only pane in the window
        if [ "$sn" = "$cur_sess" ] && [ "$cur_win_panes" -eq 1 ]; then
            continue
        fi

        # Filter out popup sessions
        if [[ "$sn" == popup-* ]]; then
            continue
        fi

        icon=""
        if [ "$sn" = "$cur_sess" ]; then
            icon="${ansi_green}${ansi_fg} "
        elif [ "$attached" -ge 1 ]; then
            icon="${ansi_yellow}${ansi_fg} "
        fi

        display="${icon}${ansi_blue}${sn}${ansi_fg}: ${ansi_magenta} New Window${ansi_fg}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$type" "$sn" "$display" "$sn" "+" "New Window"
      done)

# 3. Scratchpad (if not exists)
if ! tmux has-session -t =scratch 2>/dev/null; then
    display="${ansi_blue}scratch${ansi_fg}: ${ansi_magenta} New Window${ansi_fg}"
    scratch_item="SES${tab}scratch${tab}${display}${tab}scratch${tab}+${tab}New Window"
else
    scratch_item=""
fi

# 4. New Session
new_sess_display="${ansi_magenta} New Session${ansi_fg}"
new_sess_item="NEW${tab}NEW${tab}${new_sess_display}${tab}NEW${tab}+${tab}New Session"

# Combine list
targets=$(printf "%s\n%s\n%s\n%s" "$windows" "$sessions" "$scratch_item" "$new_sess_item" | sed '/^$/d')

# FZF Header
fzf_header=$(printf "%s\n%s\n%s" \
    "${ansi_green}ENTER: Send${ansi_fg}" \
    "${ansi_yellow}A-ENT: Follow${ansi_fg}" \
    "${ansi_cyan}C-v/h: Send and Split V/H${ansi_fg}")

# Preview Command
preview_cmd="if [ {1} = 'WIN' ]; then \
    tmux capture-pane -e -p -t {2}; \
elif [ {1} = 'SES' ]; then \
    printf '\n${ansi_green}Create New Window in ${ansi_blue}[%s]${ansi_fg}' '{2}'; \
else \
    printf '\n${ansi_magenta}Create a New Session${ansi_fg}'; \
fi"

# Select
selected=$(printf '%s\n' "$targets" | dv_run_fzf \
    --exit-0 \
    --tmux 90%,70% \
    --delimiter="\t" \
    --with-nth=3 \
    --prompt="Send To ❯ " \
    --expect=alt-enter,ctrl-v,ctrl-h \
    --list-label=" 󰁜 Send Pane to: " \
    --list-border="top" \
    --list-label-pos='1' \
    --header="$fzf_header" \
    --header-border="top" \
    --header-label=" Commands: " \
    --header-label-pos='1' \
    --preview="$preview_cmd" \
    --preview-window="right:60%" \
    --bind "focus:transform-preview-label:printf \"${ansi_blue}[%s]${ansi_fg} ${ansi_yellow}%s:%s${ansi_fg} \" {4} {5} {6}" \
    --preview-label-pos='3' \
    --color "preview-label:white:regular,preview-border:${thm_gray}")

if [ $? -ne 0 ]; then
    exit 0
fi

key=$(echo "$selected" | head -n1)
selection=$(echo "$selected" | tail -n +2)

type=$(echo "$selection" | cut -f1)
target=$(echo "$selection" | cut -f2)

# Determine split flags
split_args=""
case "$key" in
    ctrl-v) split_args="-h" ;;
    ctrl-h) split_args="-v" ;;
esac

# Determine follow behavior
follow=0
if [ "$key" = "alt-enter" ]; then
    follow=1
fi

# Debug logging
# debug_log() {
#     echo "[$(date '+%H:%M:%S')] $1" >> /tmp/tmux-send.log
# }

# Check for last pane in session to prevent client exit
sess_pane_count=$(tmux list-panes -s -t "$src_pane" | wc -l)
# debug_log "Src: $src_pane | Type: $type | Target: $target | Count: $sess_pane_count | Follow: $follow"

forced_follow=0
if [ "${sess_pane_count:-0}" -eq 1 ] && [ "$follow" -eq 0 ]; then
    follow=1
    forced_follow=1
#     debug_log "Forced follow activated (Last pane)"
fi

case "$type" in
    WIN)
        if [ -z "$split_args" ]; then split_args="-h"; fi
        if [ "$follow" -eq 1 ]; then
            target_sess=$(tmux display-message -p -t "$target" "#{session_name}")
#             debug_log "Switching client to session: $target_sess"
            tmux switch-client -t "=${target_sess}"
        fi
        tmux join-pane "$split_args" -s "$src_pane" -t "$target"
        if [ "$follow" -eq 1 ]; then
            tmux select-window -t "$target"
            tmux select-pane -t "$src_pane"
        fi
        if [ "$forced_follow" -eq 1 ]; then
            msg="${ansi_blue}${cur_sess}${ansi_yellow} has no more panes,"
            msg+=$'\n'
            msg+="  ${ansi_green}moving to ${target_sess}${ansi_yellow}."
            "$script_dir/dv-input.sh" --type info --message "$msg"
            tmux display-message "#[fg=${thm_yellow}][!] '${cur_sess}' ended; moved to '${target_sess}'"
        fi
        ;;
    SES)
        # Handle Scratchpad creation if it doesn't exist
        if [ "$target" = "scratch" ] && ! tmux has-session -t =scratch 2>/dev/null; then
            tmux new-session -d -s scratch -n "temp"
            if [ "$follow" -eq 1 ]; then
                tmux switch-client -t =scratch
            fi
            tmux break-pane -s "$src_pane" -t =scratch
            tmux kill-window -t scratch:temp
        else
            if [ "$follow" -eq 1 ]; then
                tmux switch-client -t "=${target}"
            fi
            tmux break-pane -s "$src_pane" -t "=${target}"
        fi

        if [ "$forced_follow" -eq 1 ]; then
            msg="${ansi_blue}${cur_sess}${ansi_yellow} has no more panes,"
            msg+=$'\n'
            msg+="  ${ansi_green}moving to ${target}${ansi_yellow}."
            "$script_dir/dv-input.sh" --type info --message "$msg"
            tmux display-message "#[fg=${thm_yellow}][!] '${cur_sess}' ended; moved to '${target}'"
        fi
        ;;
    NEW)
        sess_name=$("$script_dir/dv-input.sh" --title " New Session " "Enter Name")
        if [ $? -eq 0 ] && [ -n "$sess_name" ]; then
            "$script_path" --new-session "$sess_name" "$src_pane" "$follow"
        else
            tmux display-message "#[fg=${thm_yellow}][!] Session creation cancelled"
        fi
        ;;
esac
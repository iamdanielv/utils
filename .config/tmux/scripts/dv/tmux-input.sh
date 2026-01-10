#!/bin/bash
# ===============
# Script Name: tmux-input.sh
# Description: Modal input popup with custom event loop.
# Usage:       result=$(tmux-input.sh "Prompt Text" ["Default Value"])
# Exit Code:   0 on success, 1 on cancel.
# ===============

# --- Constants ---
KEY_ESC=$'\033'
KEY_ENTER="ENTER"
KEY_BACKSPACE=$'\x7f'
KEY_LEFT=$'\033[D'
KEY_RIGHT=$'\033[C'
KEY_HOME=$'\033[H'
KEY_END=$'\033[F'
KEY_HOME_ALT=$'\033[1~'
KEY_END_ALT=$'\033[4~'
KEY_DELETE=$'\033[3~'

# --- Functions ---

# Adapted from tui.lib.sh to handle key inputs robustly
read_single_char() {
    local char; local seq; IFS= read -rsn1 char < /dev/tty
    if [[ -z "$char" ]]; then echo "$KEY_ENTER"; return; fi
    if [[ "$char" == "$KEY_ESC" ]]; then
        # Peek next char with tiny timeout to see if it's a sequence (like arrow keys)
        if IFS= read -rsn1 -t 0.001 seq < /dev/tty; then
            char+="$seq"
            if [[ "$seq" == "[" || "$seq" == "O" ]]; then
                # Read until we hit a terminator (letter or ~)
                while IFS= read -rsn1 -t 0.001 seq < /dev/tty; do
                    char+="$seq"
                    if [[ "$seq" =~ [a-zA-Z~] ]]; then break; fi
                done
            fi
        fi
    fi
    echo "$char"
}

# --- Internal Mode (TUI Loop) ---
run_internal() {
    local prompt="$1"
    local default="$2"
    local out_file="$3"
    local input="$default"
    local cursor_pos=${#input}

    # Hide cursor
    # printf '\033[?25l'
    # Trap to restore cursor on exit
    # trap 'printf "\033[?25h"' EXIT

    # --- Draw Static UI ---
    # Clear screen
    printf '\033[H\033[2J'
    # Prompt (Blue)
    printf "\n  \033[1;34m%s\033[0m\n" "${prompt}"
    # Instructions (Grey)
    printf "  \033[90m(Enter to submit, Esc to cancel)\033[0m\n"
    # Spacer
    printf "\n"
    # Save cursor position for input line
    printf "\033[s"

    _draw_input() {
        # Restore cursor, clear line, print input
        printf "\033[u\033[K  ❯ %s" "${input}"
        # Move cursor back to correct position if needed
        local len=${#input}
        local diff=$(( len - cursor_pos ))
        if (( diff > 0 )); then
            printf "\033[%dD" "$diff"
        fi
    }

    _draw_input

    while true; do
        local key
        key=$(read_single_char)

        case "$key" in
            "$KEY_ENTER")
                printf "%s" "$input" > "$out_file"
                exit 0
                ;;
            "$KEY_ESC")
                exit 1
                ;;
            "$KEY_BACKSPACE")
                if (( cursor_pos > 0 )); then
                    input="${input:0:cursor_pos-1}${input:cursor_pos}"
                    ((cursor_pos--))
                    _draw_input
                fi
                ;;
            "$KEY_DELETE")
                if (( cursor_pos < ${#input} )); then
                    input="${input:0:cursor_pos}${input:cursor_pos+1}"
                    _draw_input
                fi
                ;;
            "$KEY_LEFT")
                if (( cursor_pos > 0 )); then ((cursor_pos--)); _draw_input; fi
                ;;
            "$KEY_RIGHT")
                if (( cursor_pos < ${#input} )); then ((cursor_pos++)); _draw_input; fi
                ;;
            "$KEY_HOME"|"$KEY_HOME_ALT")
                cursor_pos=0; _draw_input
                ;;
            "$KEY_END"|"$KEY_END_ALT")
                cursor_pos=${#input}; _draw_input
                ;;
            *)
                # Append if printable and length 1
                if [[ ${#key} -eq 1 && "$key" =~ [[:print:]] ]]; then
                    input="${input:0:cursor_pos}${key}${input:cursor_pos}"
                    ((cursor_pos++))
                    _draw_input
                fi
                ;;
        esac
    done
}

# --- Test Mode ---
run_color_test() {
    local colors=("34" "1;34" "32" "33" "35" "36" "90" "37")
    local names=("Blue" "Bold Blue" "Green" "Yellow" "Magenta" "Cyan" "Grey" "White")
    local idx=0

    # Hide cursor
    printf '\033[?25l'
    trap 'printf "\033[?25h"' EXIT

    while true; do
        local c="${colors[idx]}"
        local n="${names[idx]}"
        
        printf '\033[H\033[2J'
        printf "\n  \033[%sm%s\033[0m\n" "$c" "Prompt Text ($n)"
        printf "  \033[90m(Enter to submit, Esc to cancel)\033[0m\n"
        printf "\n  > User Input"
        
        printf "\n\n  \033[90m[SPACE] Next Color  [q] Quit\033[0m"
        
        local key
        key=$(read_single_char)
        
        if [[ "$key" == "q" || "$key" == "$KEY_ESC" ]]; then break; fi
        idx=$(( (idx + 1) % ${#colors[@]} ))
    done
}

# --- Launcher Mode ---
main() {
    # Check for internal flag to switch modes
    if [[ "$1" == "--test-colors" ]]; then
        run_color_test
        exit 0
    fi

    if [[ "$1" == "-i" ]]; then
        run_internal "$2" "$3" "$4"
        exit $?
    fi

    local prompt="${1:-Input}"
    local default="${2:-}"
    local tmp_file
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT

    local script_path
    script_path=$(readlink -f "$0")
    
    # Escape arguments for the inner command line
    local safe_prompt=$(printf '%q' "$prompt")
    local safe_default=$(printf '%q' "$default")
    local safe_tmp=$(printf '%q' "$tmp_file")

    # Launch Popup calling this script in internal mode
    if tmux display-popup -E -w 50 -h 8 -b rounded -T "#[bg=${thm_yellow},fg=${thm_bg}] Input " \
        "$script_path -i $safe_prompt $safe_default $safe_tmp"; then
        
        if [[ -s "$tmp_file" ]]; then
            cat "$tmp_file"
            exit 0
        fi
    fi
    
    exit 1
}

main "$@"

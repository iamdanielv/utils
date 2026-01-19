#!/bin/bash
# ===============
# Script Name: dv-input.sh
# Description: Modal input popup with custom event loop.
# Keybinding:  None (Helper Script)
# Config:      None
# Dependencies: tmux
# ===============
# Usage:       dv-input [OPTIONS] [PROMPT] [DEFAULT_VALUE]
# Exit Code:   0 on success, 1 on cancel.
#
# Options:
#   --title <text>         Set the popup title (default: " Input ")
#   --width <num>          Set popup width (default: 50)
#   --height <num>         Set popup height (default: 8)
#   --regex <pattern>      Regex validation pattern
#   --val-error-msg <msg>  Custom error message on validation failure
#   --message <text>       Display a simple message popup (no input)
#   --confirm <text>       Display a Yes/No confirmation popup
#
# Common Validation Patterns (--regex):
#   Digits only:       ^[0-9]+$
#   No spaces:         ^[^ ]+$
#   Alphanumeric:      ^[a-zA-Z0-9]+$
#   Filename (safe):   ^[a-zA-Z0-9._-]+$
#
# Examples:
#   result=$(dv-input "Enter Name" "John Doe")
#   dv-input --title " Rename " --width 30 "New Name"
#   if dv-input --confirm "Are you sure?"; then echo "Yes"; fi
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

# --- Colors ---
thm_bg="#1e2030"
thm_yellow="#ffc777"

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

# --- Internal Message Mode ---
run_internal_msg() {
    local msg="$1"
    # Clear screen
    printf '\033[H\033[2J'
    # Message (Yellow)
    printf "\n\n  \033[1;33m%s\033[0m\n" "$msg"
    # Footer
    printf "\n  \033[90m(Press any key)\033[0m"
    read_single_char >/dev/null
}

# --- Internal Confirmation Mode ---
run_internal_confirm() {
    local prompt="$1"
    local selection=1 # 0=Yes, 1=No (Default to No for safety)

    _draw_confirm() {
        # Clear screen
        printf '\033[H\033[2J'
        # Prompt (Blue)
        printf "\n  \033[1;34m%s\033[0m\n\n" "$prompt"
        
        local y_style="32" # Green
        local n_style="31" # Red
        
        if [[ $selection -eq 0 ]]; then y_style="1;32;7"; fi # Highlight Yes (Reverse)
        if [[ $selection -eq 1 ]]; then n_style="1;31;7"; fi # Highlight No (Reverse)
        
        printf "      \033[%sm ✓ Yes \033[0m      \033[%sm ✗ No \033[0m\n" "$y_style" "$n_style"
    }

    _draw_confirm

    while true; do
        local key
        key=$(read_single_char)
        case "$key" in
            "$KEY_LEFT"|"$KEY_RIGHT"|"h"|"l") selection=$((1 - selection)); _draw_confirm ;;
            "$KEY_ENTER") exit "$selection" ;;
            "y"|"Y") exit 0 ;;
            "n"|"N") exit 1 ;;
            "$KEY_ESC"|"q") exit 1 ;;
        esac
    done
}

# --- Internal Mode (TUI Loop) ---
run_internal() {
    local prompt="$1"
    local default="$2"
    local out_file="$3"
    local regex="$4"
    local val_error_msg="$5"
    local input="$default"
    local cursor_pos=${#input}
    local status_msg=""

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
        
        # Draw Status Line (Next line)
        printf "\n\033[K"
        if [[ -n "$status_msg" ]]; then
            printf "  \033[31m%s\033[0m" "$status_msg"
        fi

        # Restore cursor to input position
        # Move up 1 line (from status line)
        printf "\033[1A"
        
        # Move to correct column: 2 spaces + 1 char (❯) + 1 space + cursor_pos + 1 (1-based)
        # "  ❯ " is 4 visual columns
        local col=$(( 4 + cursor_pos + 1 ))
        if (( col > 1 )); then
            printf "\033[%dG" "$col"
        fi
    }

    _draw_input

    while true; do
        local key
        key=$(read_single_char)

        case "$key" in
            "$KEY_ENTER")
                # Validation
                if [[ -n "$regex" ]]; then
                    if ! [[ "$input" =~ $regex ]]; then
                        status_msg="${val_error_msg:-Invalid input format.}"
                        _draw_input
                        continue
                    fi
                fi
                printf "%s" "$input" > "$out_file"
                exit 0
                ;;
            "$KEY_ESC")
                exit 1
                ;;
            "$KEY_BACKSPACE")
                if (( cursor_pos > 0 )); then
                    status_msg=""
                    input="${input:0:cursor_pos-1}${input:cursor_pos}"
                    ((cursor_pos--))
                    _draw_input
                fi
                ;;
            "$KEY_DELETE")
                if (( cursor_pos < ${#input} )); then
                    status_msg=""
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
                    status_msg=""
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

    if [[ "$1" == "--internal-msg" ]]; then
        run_internal_msg "$2"
        exit 0
    fi

    if [[ "$1" == "--internal-confirm" ]]; then
        run_internal_confirm "$2"
        exit $?
    fi

    if [[ "$1" == "-i" ]]; then
        run_internal "$2" "$3" "$4" "$5" "$6"
        exit $?
    fi

    local prompt=""
    local default=""
    local regex=""
    local val_error_msg=""
    local title=" Input "
    local width="50"
    local height="8"
    local tmp_file
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message)
                local msg="$2"
                local script_path
                script_path=$(readlink -f "$0")
                local safe_msg=$(printf '%q' "$msg")
                tmux display-popup -E -w 60 -h 10 -b rounded -T "#[bg=${thm_yellow},fg=${thm_bg}] Info " \
                    "$script_path --internal-msg $safe_msg"
                exit 0
                ;;
            --confirm)
                local msg="$2"
                local script_path
                script_path=$(readlink -f "$0")
                local safe_msg=$(printf '%q' "$msg")
                tmux display-popup -E -w 60 -h 10 -b rounded -T "#[bg=${thm_yellow},fg=${thm_bg}] Confirm " \
                    "$script_path --internal-confirm $safe_msg"
                exit $?
                ;;
            --regex)
                regex="$2"
                shift 2
                ;;
            --val-error-msg)
                val_error_msg="$2"
                shift 2
                ;;
            --title)
                title="$2"
                shift 2
                ;;
            --width)
                width="$2"
                shift 2
                ;;
            --height)
                height="$2"
                shift 2
                ;;
            *)
                if [[ -z "$prompt" ]]; then
                    prompt="$1"
                elif [[ -z "$default" ]]; then
                    default="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$prompt" ]]; then prompt="Input"; fi

    local script_path
    script_path=$(readlink -f "$0")
    
    # Escape arguments for the inner command line
    local safe_prompt=$(printf '%q' "$prompt")
    local safe_default=$(printf '%q' "$default")
    local safe_tmp=$(printf '%q' "$tmp_file")
    local safe_regex=$(printf '%q' "$regex")
    local safe_val_error_msg=$(printf '%q' "$val_error_msg")

    # Launch Popup calling this script in internal mode
    if tmux display-popup -E -w "$width" -h "$height" -b rounded -T "#[bg=${thm_yellow},fg=${thm_bg}]${title}" \
        "$script_path -i $safe_prompt $safe_default $safe_tmp $safe_regex $safe_val_error_msg"; then
        
        cat "$tmp_file"
        exit 0
    fi
    
    exit 1
}

main "$@"

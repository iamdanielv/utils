#!/bin/bash
#
# manage-env.sh
#
# An interactive TUI for managing environment variables in a .env file.
# It supports adding, editing, and deleting variables, along with special
# comments in the format: ##@ <VAR> comment text
#

set -o pipefail

# Colors & Styles
declare -rx C_RED=$'\033[31m'
declare -rx C_GREEN=$'\033[32m'
declare -rx C_YELLOW=$'\033[33m'
declare -rx C_BLUE=$'\033[34m'
declare -rx C_MAGENTA=$'\033[35m'
declare -rx C_CYAN=$'\033[36m'
declare -rx C_WHITE=$'\033[37m'
declare -rx C_GRAY=$'\033[38;5;244m'
declare -rx C_ORANGE=$'\033[38;5;216m'
declare -rx C_MAUVE=$'\033[38;5;99m'

# Legacy/Compat colors (keep for now)
readonly C_L_RED=$'\033[31;1m'
readonly C_L_GREEN=$'\033[32m'
readonly C_L_YELLOW=$'\033[33m'
readonly C_L_BLUE=$'\033[34m'
readonly C_L_MAGENTA=$'\033[35m'
readonly C_L_CYAN=$'\033[36m'
readonly C_L_WHITE=$'\033[37;1m'

readonly T_RESET=$'\033[0m'
readonly T_BOLD=$'\033[1m'
readonly T_ULINE=$'\033[4m'
readonly T_REVERSE=$'\033[7m'
readonly T_CLEAR_LINE=$'\033[K'
readonly T_CURSOR_HIDE=$'\033[?25l'
readonly T_CURSOR_SHOW=$'\033[?25h'
readonly T_FG_RESET=$'\033[39m'
readonly T_NO_REVERSE=$'\033[27m'
readonly T_CLEAR_WHOLE_LINE=$'\033[2K'
readonly T_CURSOR_HOME=$'\033[H'
readonly T_CLEAR_SCREEN_DOWN=$'\033[J'
readonly T_CURSOR_UP=$'\033[1A'
readonly T_CURSOR_DOWN=$'\033[1B'
readonly T_CURSOR_LEFT=$'\033[1D'
readonly T_CURSOR_RIGHT=$'\033[1C'

# Icons
readonly ICON_ERR="[${T_BOLD}${C_RED}✗${T_RESET}]"
readonly ICON_OK="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
readonly ICON_INFO="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
readonly ICON_WARN="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
readonly ICON_QST="[${T_BOLD}${C_CYAN}?${T_RESET}]"

DIV="──────────────────────────────────────────────────────────────────────"

# Key Codes
KEY_ESC=$'\033'
KEY_UP=$'\033[A'
KEY_DOWN=$'\033[B'
KEY_RIGHT=$'\033[C'
KEY_LEFT=$'\033[D'
KEY_ENTER="ENTER"
KEY_BACKSPACE=$'\x7f'
KEY_HOME=$'\033[H'
KEY_END=$'\033[F'
KEY_DELETE=$'\033[3~'
KEY_PGUP=$'\033[5~'
KEY_PGDN=$'\033[6~'

# Logging
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${ICON_ERR}${T_BOLD}${C_RED} ${1} ${T_RESET}"; }
printOkMsg() { printMsg "${ICON_OK} ${1}${T_RESET}"; }

# Banner Utils
strip_ansi_codes() {
    local s="$1"; local esc=$'\033'
    if [[ "$s" != *"$esc"* ]]; then echo -n "$s"; return; fi
    local pattern="$esc\\[[0-9;]*[a-zA-Z]"
    while [[ $s =~ $pattern ]]; do s="${s/${BASH_REMATCH[0]}/}"; done
    echo -n "$s"
}

_truncate_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"; local trunc_char_len=${#trunc_char}
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then echo -n "$input_str"; return; fi
    local truncate_to_len=$(( max_len - trunc_char_len )); local new_str=""; local visible_count=0; local i=0; local in_escape=false
    while (( i < ${#input_str} && visible_count < truncate_to_len )); do
        local char="${input_str:i:1}"; new_str+="$char"
        if [[ "$char" == $'\033' ]]; then in_escape=true; elif ! $in_escape; then (( visible_count++ )); fi
        if $in_escape && [[ "$char" =~ [a-zA-Z] ]]; then in_escape=false; fi; ((i++))
    done
    echo -n "${new_str}${trunc_char}"
}

_format_fixed_width_string() {
    local input_str="$1"; local max_len="$2"; local trunc_char="${3:-…}"
    local stripped_str; stripped_str=$(strip_ansi_codes "$input_str"); local len=${#stripped_str}
    if (( len <= max_len )); then local padding_needed=$(( max_len - len )); printf "%s%*s" "$input_str" "$padding_needed" ""
    else _truncate_string "$input_str" "$max_len" "$trunc_char"; fi
}

printBanner() {
    local msg="$1"
    local color="${2:-$C_BLUE}"
    local line="────────────────────────────────────────────────────────────────────────"
    printf "${color}${line}${T_RESET}\r${color}╭─${msg}${T_RESET}"
}

# Terminal Control
clear_screen() { printf "${T_CURSOR_HOME}${T_CLEAR_SCREEN_DOWN}" >/dev/tty; }
clear_current_line() { printf "${T_CLEAR_WHOLE_LINE}\r" >/dev/tty; }
clear_lines_up() { local lines=${1:-1}; for ((i = 0; i < lines; i++)); do printf "${T_CURSOR_UP}${T_CLEAR_WHOLE_LINE}"; done; printf '\r'; } >/dev/tty
move_cursor_up() { local lines=${1:-1}; if (( lines > 0 )); then for ((i = 0; i < lines; i++)); do printf "${T_CURSOR_UP}"; done; fi; printf '\r'; } >/dev/tty
render_buffer() { printf "${T_CURSOR_HOME}%b${T_CLEAR_SCREEN_DOWN}" "$1"; }

# User Input
read_single_char() {
    local char; local seq; IFS= read -rsn1 char < /dev/tty
    if [[ -z "$char" ]]; then echo "$KEY_ENTER"; return; fi
    if [[ "$char" == "$KEY_ESC" ]]; then
        if IFS= read -rsn1 -t 0.001 seq < /dev/tty; then char+="$seq"; if [[ "$seq" == "[" || "$seq" == "O" ]]; then while IFS= read -rsn1 -t 0.001 seq < /dev/tty; do char+="$seq"; if [[ "$seq" =~ [a-zA-Z~] ]]; then break; fi; done; fi; fi
    fi
    echo "$char"
}

show_timed_message() {
    local message="$1"
    local duration="${2:-1.8}"
    
    local color="${C_YELLOW}"
    local title="${ICON_INFO} Info"
    
    if [[ "$message" == *"${ICON_ERR}"* ]]; then
        color="${C_RED}"; title="${ICON_ERR} Error"
    elif [[ "$message" == *"${ICON_WARN}"* ]]; then
        color="${C_YELLOW}"; title="${ICON_WARN} Warning"
    elif [[ "$message" == *"${ICON_OK}"* ]]; then
        color="${C_GREEN}"; title="${ICON_OK} Success"
    fi

    local buffer=""
    buffer+=$(printBanner "${T_RESET}${title} " "${color}")
    buffer+="\n"
    buffer+="${color}╰${T_RESET} ${message}"
    
    printMsg "$buffer" >/dev/tty
    sleep "$duration"
    
    local lines_to_clear
    lines_to_clear=$(echo -e "$buffer" | wc -l)
    clear_lines_up "$lines_to_clear" >/dev/tty
}

show_action_summary() {
    local label="$1"; local value="$2"; local total_width=70; local icon_len; icon_len=$(strip_ansi_codes "${ICON_QST} " | wc -c)
    local separator_len=2; local available_width=$(( total_width - icon_len - separator_len ))
    local label_width=$(( available_width / 3 )); local value_width=$(( available_width - label_width ))
    local truncated_label; truncated_label=$(_truncate_string "$label" "$label_width")
    local truncated_value; truncated_value=$(_truncate_string "${C_GREEN}${value}${T_RESET}" "$value_width")
    printMsg "${ICON_QST} ${truncated_label}: ${truncated_value}" >/dev/tty
}

prompt_yes_no() {
    local question="$1"; local default_answer="${2:-}"; local answer; local prompt_suffix
    if [[ "$default_answer" == "y" ]]; then prompt_suffix="(Y/n)"; elif [[ "$default_answer" == "n" ]]; then prompt_suffix="(y/N)"; else prompt_suffix="(y/n)"; fi

    local buffer=""
    buffer+=$(printBanner "Confirmation" "${C_YELLOW}")
    buffer+="\n"
    buffer+="${C_YELLOW}╰${T_RESET} ${T_BOLD}${question} ${prompt_suffix}${T_RESET}"
    printMsgNoNewline "$buffer" >/dev/tty

    while true; do
        answer=$(read_single_char); if [[ "$answer" == "$KEY_ENTER" ]]; then answer="$default_answer"; fi
        case "$answer" in
            [Yy]|[Nn]) if [[ "$answer" =~ [Yy] ]]; then return 0; else return 1; fi ;;
            "$KEY_ESC"|"q") return 2 ;;
        esac
    done
}

prompt_for_input() {
    local prompt_text="$1"; local -n var_ref="$2"; local default_val="${3:-}"; local allow_empty="${4:-false}"; local lines_to_replace="${5:-0}"
    
    if (( lines_to_replace == 0 )); then 
        clear_screen
    elif (( lines_to_replace > 0 )); then
        clear_lines_up "$lines_to_replace"
    fi

    printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty
    
    local buffer=""
    buffer+=$(printBanner "Input - ${prompt_text}" "${C_CYAN}")
    buffer+="\n"
    buffer+="${C_CYAN}╰❱${T_RESET} "
    printMsgNoNewline "$buffer" >/dev/tty

    # Calculate prefix length for cursor positioning: "╰❱ " (3 chars)
    local prefix_len=3
    
    local input_str="$default_val"; local cursor_pos=${#input_str}; local view_start=0; local key

    _prompt_for_input_redraw() {
        printf '\r\033[%sC' "$prefix_len" >/dev/tty
        local term_width; term_width=$(tput cols)
        local available_width=$(( term_width - prefix_len ))
        if (( available_width < 1 )); then available_width=1; fi
        
        if (( cursor_pos < view_start )); then view_start=$cursor_pos; fi
        if (( cursor_pos >= view_start + available_width )); then view_start=$(( cursor_pos - available_width + 1 )); fi
        
        local display_str="${input_str:$view_start:$available_width}"; local total_len=${#input_str}; local ellipsis="…"
        if (( total_len > available_width )); then 
            if (( view_start > 0 )); then display_str="${ellipsis}${display_str:1}"; fi
            if (( view_start + available_width < total_len )); then display_str="${display_str:0:${#display_str}-1}${ellipsis}"; fi
        fi
        
        printMsgNoNewline "${display_str}${T_CLEAR_LINE}" >/dev/tty
        printf '\r\033[%sC' "$prefix_len" >/dev/tty
        
        local display_cursor_pos=$(( cursor_pos - view_start ))
        if (( view_start > 0 )); then ((display_cursor_pos++)); fi
        if (( display_cursor_pos > 0 )); then printf '\033[%sC' "$display_cursor_pos" >/dev/tty; fi
    }
    while true; do
        _prompt_for_input_redraw; key=$(read_single_char)
        case "$key" in
            "$KEY_ENTER") 
                if [[ -n "$input_str" || "$allow_empty" == "true" ]]; then 
                    var_ref="$input_str"
                    clear_current_line >/dev/tty; clear_lines_up 1 >/dev/tty
                    show_action_summary "$prompt_text" "$var_ref"
                    printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
                    return 0
                fi 
                ;;
            "$KEY_ESC") 
                clear_current_line >/dev/tty; clear_lines_up 1 >/dev/tty
                show_timed_message "${ICON_INFO} Input cancelled" 1
                printMsgNoNewline "${T_CURSOR_HIDE}" >/dev/tty
                return 1 
                ;;
            "$KEY_BACKSPACE") if (( cursor_pos > 0 )); then input_str="${input_str:0:cursor_pos-1}${input_str:cursor_pos}"; ((cursor_pos--)); fi ;;
            "$KEY_DELETE") if (( cursor_pos < ${#input_str} )); then input_str="${input_str:0:cursor_pos}${input_str:cursor_pos+1}"; fi ;;
            "$KEY_LEFT") if (( cursor_pos > 0 )); then ((cursor_pos--)); fi ;;
            "$KEY_RIGHT") if (( cursor_pos < ${#input_str} )); then ((cursor_pos++)); fi ;;
            "$KEY_HOME") cursor_pos=0 ;;
            "$KEY_END") cursor_pos=${#input_str} ;;
            *) if (( ${#key} == 1 )) && [[ "$key" =~ [[:print:]] ]]; then input_str="${input_str:0:cursor_pos}${key}${input_str:cursor_pos}"; ((cursor_pos++)); fi ;;
        esac
    done
}

_interactive_editor_loop() {
    local mode="$1" banner_text="$2" draw_func="$3" field_handler_func="$4" change_checker_func="$5" reset_func="$6"
    clear_screen; printBanner "$banner_text" "${C_CYAN}"; echo; "$draw_func"
    while true; do
        local key; key=$(read_single_char); local redraw=false
        case "$key" in
            'c'|'C'|'d'|'D') clear_current_line; clear_lines_up 1; local question="Discard all pending changes?"; if [[ "$mode" == "add" || "$mode" == "clone" ]]; then question="Discard all changes and reset fields?"; fi; clear_lines_up 1; if prompt_yes_no "$question" "y"; then "$reset_func"; clear_current_line; clear_lines_up 1; show_timed_message "${ICON_INFO} Changes discarded"; fi; redraw=true ;;
            's'|'S') return 0 ;;
            'q'|'Q'|"$KEY_ESC") if "$change_checker_func"; then clear_current_line; clear_lines_up 2; if prompt_yes_no "You have unsaved changes. Quit without saving?" "n"; then return 1; else redraw=true; fi; else clear_current_line; clear_lines_up 2; show_timed_message "${ICON_INFO} Edit cancelled. No changes were made."; return 1; fi ;;
            *) if "$field_handler_func" "$key"; then redraw=true; fi ;;
        esac
        if [[ "$redraw" == "true" ]]; then clear_screen; printBanner "$banner_text"; echo; "$draw_func"; fi
    done
}

_apply_highlight() {
    local content="$1"; local highlighted_content=""
    while IFS= read -r line; do
        local highlight_restore="${T_RESET}${T_REVERSE}${C_L_BLUE}"
        local highlighted_line="${line//${T_RESET}/${highlight_restore}}"
        highlighted_line="${highlighted_line//${T_FG_RESET}/${C_L_BLUE}}"
        if [[ -n "$highlighted_content" ]]; then highlighted_content+=$'\n'; fi
        highlighted_content+="$highlighted_line"
    done <<< "$content"
    printf "%s%s%s%s" "${T_REVERSE}${C_L_BLUE}" "$highlighted_content" "${T_CLEAR_LINE}" "${T_RESET}"
}

_get_menu_item_prefix() {
    local is_current="$1" is_selected="$2" is_multi_select="$3"
    local pointer=" "; if [[ "$is_current" == "true" ]]; then pointer="${T_BOLD}${C_L_MAGENTA}❯${T_FG_RESET}"; fi
    local checkbox="   "; if [[ "$is_multi_select" == "true" ]]; then checkbox="[ ]"; if [[ "$is_selected" == "true" ]]; then checkbox="${T_BOLD}${C_GREEN}[✓]"; fi; fi
    echo "${pointer}${checkbox}"
}

_draw_menu_item() {
    local is_current="$1" is_selected="$2" is_multi_select="$3" option_text="$4"; local -n output_ref="$5"
    local prefix; prefix=$(_get_menu_item_prefix "$is_current" "$is_selected" "$is_multi_select")
    local item_output=""; if [[ -n "$option_text" ]]; then
        local line_prefix=" "
        if [[ "$is_current" == "true" ]]; then local highlighted_line; highlighted_line=$(_apply_highlight "${line_prefix}${option_text}${T_CLEAR_LINE}"); item_output+=$(printf "%s%s" "$prefix" "$highlighted_line")
        else item_output+=$(printf "%s%s%s%s%s" "$prefix" "$line_prefix" "$option_text" "${T_CLEAR_LINE}" "${T_RESET}"); fi
    fi
    output_ref+=$item_output
}


script_exit_handler() { printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; }
trap 'script_exit_handler' EXIT
script_interrupt_handler() { trap - INT; printMsgNoNewline "${T_CURSOR_SHOW}" >/dev/tty; stty echo >/dev/tty; clear_screen; printMsg "${ICON_WARN} ${C_YELLOW}Operation cancelled by user.${T_RESET}"; exit 130; }
trap 'script_interrupt_handler' INT

# --- Script Globals ---
declare -A ENV_VARS # Associative array to hold variable values
declare -A ENV_COMMENTS # Associative array to hold comments
declare -a ENV_ORDER # Array to maintain the original order of variables
declare -a DISPLAY_ORDER # Filtered array for TUI display

FILE_PATH="" # Path to the .env file being edited
ERROR_MESSAGE="" # Holds the current validation error message

# --- Core Logic ---

# Parses the specified .env file into the global arrays.
# It handles variables, comments, and blank lines, preserving order.
function parse_env_file() {
    local file_to_parse="$1"
    # Reset state
    ENV_VARS=()
    ENV_COMMENTS=()
    ENV_ORDER=()
    DISPLAY_ORDER=()
    ERROR_MESSAGE=""
    local -A PENDING_COMMENTS

    if [[ ! -f "$file_to_parse" ]]; then
        # File doesn't exist, which is fine. We'll create it on save.
        return
    fi

    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((line_num++))
        local trimmed_line="${line#"${line%%[![:space:]]*}"}"
        trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"

        if [[ -z "$trimmed_line" ]]; then
            ENV_ORDER+=("BLANK_LINE_${line_num}")
            continue
        fi

        # Handle special comments: ##@ VAR ...
        if [[ "$trimmed_line" =~ ^##@[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+(.*) ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local comment_text="${BASH_REMATCH[2]}"
            PENDING_COMMENTS["$var_name"]="$comment_text"
            continue
        fi

        # Handle regular comments
        if [[ "$trimmed_line" =~ ^# ]]; then
            ENV_ORDER+=("COMMENT_LINE_${line_num}")
            ENV_VARS["COMMENT_LINE_${line_num}"]="$line"
            continue
        fi

        # Handle variable assignments
        if [[ "$trimmed_line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Handle bash-specific $'' syntax for C-style escapes
            local ansi_pattern="^\\$'(.*)'$"
            if [[ "$value" =~ $ansi_pattern ]]; then
                # The inner content is in BASH_REMATCH[1]. Let printf interpret it.
                value=$(printf '%b' "${BASH_REMATCH[1]}")
            
            # Best Practice: Unquote values for internal storage. Quotes are for file representation.
            elif [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            # Handle duplicates by appending a unique suffix
            local storage_key="$key"
            local dup_count=1
            while [[ -n "${ENV_VARS[$storage_key]}" ]]; do
                storage_key="${key}__DUPLICATE_KEY_${dup_count}"
                ((dup_count++))
            done

            if [[ -n "${PENDING_COMMENTS[$key]}" ]]; then
                ENV_COMMENTS["$storage_key"]="${PENDING_COMMENTS[$key]}"
                unset "PENDING_COMMENTS[$key]"
            fi

            ENV_VARS["$storage_key"]="$value"
            ENV_ORDER+=("$storage_key")
        else
            ERROR_MESSAGE="Error: Invalid format ${T_RESET}on line $line_num: '$line'"
            return 1
        fi
    done < "$file_to_parse"
}

# Saves the current state from the global arrays back to the .env file.
function save_env_file() {
    local file_to_save="$1"
    local mode="${2:-save}" # "save" or "get_content"
    local temp_file; temp_file=$(mktemp)
    # Ensure temp file is cleaned up on script exit or interrupt
    # Only set the trap if we are in save mode, to avoid conflicts when just getting content.
    if [[ "$mode" == "save" ]]; then
        trap 'rm -f "$temp_file"' EXIT
    fi

    for key in "${ENV_ORDER[@]}"; do
        if [[ "$key" =~ ^BLANK_LINE_ ]]; then
            printf "\n" >> "$temp_file"
        elif [[ "$key" =~ ^COMMENT_LINE_ ]]; then
            printf "%s\n" "${ENV_VARS[$key]}" >> "$temp_file"
        else
            local real_key="${key%%__DUPLICATE_KEY_*}"
            # This is a regular variable. Check if it has a special comment.
            if [[ -n "${ENV_COMMENTS[$key]}" ]]; then
                printf "##@ %s %s\n" "$real_key" "${ENV_COMMENTS[$key]}" >> "$temp_file"
            fi

            # Best Practice: Add quotes only if the value contains spaces or is empty.
            local value="${ENV_VARS[$key]}"
            # If the value contains an escape character, format it for bash sourcing.
            if [[ "$value" == *$'\033'* ]]; then
                # Replace the raw ESC character with the literal string '\033'
                local bash_formatted_value="${value//$'\033'/\\033}"
                printf "%s=\$'%s'\n" "$real_key" "$bash_formatted_value" >> "$temp_file"
            elif [[ "$value" == *[[:space:]]* || -z "$value" ]]; then
                printf "%s=\"%s\"\n" "$real_key" "$value" >> "$temp_file"
            else
                printf "%s=%s\n" "$real_key" "$value" >> "$temp_file"
            fi
        fi
    done

    if [[ "$mode" == "get_content" ]]; then
        cat "$temp_file"
        rm -f "$temp_file"
        return 0
    fi

    # Create a backup of the existing file
    if [[ -f "$file_to_save" ]]; then
        cp "$file_to_save" "${file_to_save}.bak"
    fi

    # Safely overwrite the original file
    if mv "$temp_file" "$file_to_save"; then
        local relative_path="$file_to_save"

        clear_current_line
        clear_lines_up 1
        show_timed_message "${ICON_OK} Saved changes to ${C_BLUE}${relative_path}${T_RESET} (Backup created)" 1.5
        return 0
    else
        rm -f "$temp_file"
        clear_lines_up 1
        show_timed_message "${ICON_ERR} Failed to save changes to ${C_BLUE}${relative_path}${T_RESET}" 2.5
        return 1
    fi
}

# (Private) Checks if there are any pending changes by comparing the current
# in-memory state with a fresh parse of the original file.
_has_pending_changes() {
    local original_content=""
    # Only read the file if it exists. If not, original content is empty.
    if [[ -f "$FILE_PATH" ]]; then
        original_content=$(<"$FILE_PATH")
    fi
    local current_content; current_content=$(save_env_file "" "get_content")

    if [[ "$original_content" != "$current_content" ]]; then
        return 0 # Has changes
    else
        return 1 # No changes
    fi
}

# --- TUI Components ---

function show_help() {
    clear_screen
    local buffer=""
    buffer+=$(printBanner "Help & Shortcuts" "${C_CYAN}")
    buffer+="\n"

    buffer+=$(printBanner "Navigation" "${C_ORANGE}")
    buffer+="\n"
    buffer+="  ${C_CYAN}↑${T_RESET}/${C_CYAN}↓${T_RESET} or ${C_CYAN}k${T_RESET}/${C_CYAN}j${T_RESET}  Select variable\n"
    buffer+="  ${C_CYAN}PgUp${T_RESET}/${C_CYAN}PgDn${T_RESET}     Scroll page\n"
    buffer+="  ${C_CYAN}Home${T_RESET}/${C_CYAN}End${T_RESET}      Jump to start/end\n"

    buffer+=$(printBanner "Variable Actions" "${C_ORANGE}")
    buffer+="\n"
    buffer+="  ${C_BLUE}E${T_RESET}              Edit selected variable\n"
    buffer+="  ${C_GREEN}A${T_RESET}              Add new variable\n"
    buffer+="  ${C_RED}D${T_RESET}              Delete selected variable\n"
    buffer+="  ${C_YELLOW}C${T_RESET}              Clone selected variable\n"

    buffer+=$(printBanner "File & View" "${C_ORANGE}")
    buffer+="\n"
    buffer+="  ${C_GREEN}S${T_RESET}              Save changes to .env file\n"
    buffer+="  ${C_MAGENTA}O${T_RESET}              Open file in external editor (\$EDITOR)\n"
    buffer+="  ${C_GREEN}I${T_RESET}              Import from system environment\n"
    buffer+="  ${C_YELLOW}V${T_RESET}              Toggle value visibility\n"
    buffer+="  ${C_MAGENTA}/${T_RESET}              Filter variables\n"

    buffer+=$(printBanner "General" "${C_ORANGE}")
    buffer+="\n"
    buffer+="  ${C_CYAN}?${T_RESET}/${C_CYAN}h${T_RESET}            Show this help\n"
    buffer+="  ${C_RED}Q${T_RESET}              Quit\n"

    buffer+="\n${C_BLUE}Press any key to return...${T_RESET}\n"

    render_buffer "$buffer"
    read_single_char >/dev/null
    clear_screen
}

# (Private) Draws the UI for the variable editor screen.
_draw_variable_editor() {
    local current_key="$1"
    local pending_key="$2"
    local current_value="$3"
    local pending_value="$4"
    local current_comment="$5"
    local pending_comment="$6"

    # Use the combined display helper to show pending changes with an arrow.
    local name_display; name_display=$(_get_combined_display "name" "$current_key" "$pending_key")
    local value_display; value_display=$(_get_combined_display "value" "$current_value" "$pending_value")
    local comment_display; comment_display=$(_get_combined_display "comment" "$current_comment" "$pending_comment")

    printf "${C_CYAN}│${T_RESET} ${C_WHITE}${T_BOLD}${T_ULINE}Choose an option to configure:${T_RESET}\n"
    _print_menu_item "1" "Name" "$name_display"
    _print_menu_item "2" "Value" "$value_display"
    _print_menu_item "3" "Comment" "$comment_display"

    printf "${C_CYAN}│\n╰ ${C_GREEN}S)${T_RESET} Stage | ${C_YELLOW}D)${T_RESET} Discard | ${C_RED}Q)${T_RESET} Quit"
    printf "\n  ${C_YELLOW}What is your choice?\n"
}

# (Private) Gets a formatted display string for a given setting value.
# This is a simplified version of the one in config-ollama.sh.
_get_setting_display() {
    local setting_type="$1"
    local value="$2"

    case "$setting_type" in
        "name")
            if [[ -n "$value" ]]; then echo "${C_L_BLUE}${value}${T_RESET}"; else echo "${C_GRAY}(empty)${T_RESET}"; fi
            ;;
        "value")
            if [[ -n "$value" ]]; then
                local display_val="$value"
                display_val="${display_val//$'\033'/\\\\\\\\033}"
                display_val="${display_val//$'\n'/^J}"
                display_val="${display_val//$'\r'/^M}"
                display_val="${display_val//$'\t'/^I}"
                echo "${C_L_CYAN}${display_val}${T_RESET}"
            else echo "${C_GRAY}(empty)${T_RESET}"; fi
            ;;
        "comment")
            if [[ -n "$value" ]]; then echo "${C_GRAY}${value}${T_RESET}"; else echo "${C_GRAY}(none)${T_RESET}"; fi
            ;;
        *)
            if [[ -n "$value" ]]; then echo "$value"; else echo "${C_GRAY}(default)${T_RESET}"; fi
            ;;
    esac
}

# (Private) Gets a display string showing current and pending states if they differ.
_get_combined_display() {
    local setting_type="$1"
    local current_val="$2"
    local pending_val="$3"

    local pending_display; pending_display=$(_get_setting_display "$setting_type" "$pending_val")

    if [[ "$current_val" != "$pending_val" ]]; then
        local current_display; current_display=$(_get_setting_display "$setting_type" "$current_val")
        echo -e "${current_display} ${C_WHITE}→${T_RESET} ${pending_display}"
    else
        echo -e "$pending_display"
    fi
}

# (Private) Helper to print a formatted menu item for the editor.
_print_menu_item() {
    local key="$1"
    local text1="$2"
    local text2="$3"

    if [[ -n "$text2" ]]; then
        printf "${C_CYAN}│ ${T_BOLD}${key})${T_RESET} %-7s : %b${T_CLEAR_LINE}\n" "$text1" "$text2"
    else
        printf "${C_CYAN}│ ${T_BOLD}${key})${T_RESET} %b${T_CLEAR_LINE}\n" "$text1"
    fi
}

# (Private) Sanitizes a value for display by escaping control characters and truncating.
# Modifies the variable in-place to avoid subshell overhead.
_sanitize_and_truncate_value() {
    local -n _val_ref="$1"
    local max_len="$2"

    _val_ref="${_val_ref:0:$((max_len + 1))}"

    # Escape special characters to prevent display corruption but keep them visible
    if [[ "$_val_ref" == *$'\n'* ]]; then _val_ref="${_val_ref//$'\n'/^J}"; fi
    if [[ "$_val_ref" == *$'\r'* ]]; then _val_ref="${_val_ref//$'\r'/^M}"; fi
    if [[ "$_val_ref" == *$'\t'* ]]; then _val_ref="${_val_ref//$'\t'/^I}"; fi
    if [[ "$_val_ref" == *$'\033'* ]]; then _val_ref="${_val_ref//$'\033'/\\\\\\\\033}"; fi

    if (( ${#_val_ref} > max_len )); then
        _val_ref="${_val_ref:0:$((max_len - 1))}…"
    fi
}

# (Private) Generates a color preview block if the value is an ANSI color code.
# Usage: _get_color_preview_string <value> <is_current> color_preview_ref preview_len_ref
_get_color_preview_string() {
    local value="$1"
    local is_current="$2"
    local -n color_preview_ref="$3"
    local -n preview_len_ref="$4"

    local esc=$'\033'
    local ansi_color_pattern="^$esc\\[[0-9;]*m$"
    if [[ "$value" =~ $ansi_color_pattern ]]; then
        local display_code="$value"
        local inner="${value#*$esc[}"
        inner="${inner%m}"
        local -a code_arr
        IFS=';' read -ra code_arr <<< "$inner"
        local is_bg_color=false
        for code in "${code_arr[@]}"; do
            if [[ "$code" =~ ^(4[0-9]|10[0-9]|48)$ ]]; then
                is_bg_color=true
                break
            fi
        done

        if [[ "$is_bg_color" == "true" && "$is_current" != "true" ]]; then
            display_code="${value}${T_REVERSE}"
        elif [[ "$is_bg_color" == "false" && "$is_current" == "true" ]]; then
            display_code="${T_NO_REVERSE}${value}" # ANSI "Not Reversed"
        fi
        color_preview_ref=$(printf "   %s██%s" "$display_code" "$T_RESET")
        preview_len_ref=5 # Visible length of "   ██"
    fi
}

# Draws the main list of environment variables.
function draw_var_list() {
    local -n current_option_ref=$1
    local -n list_offset_ref=$2
    local viewport_height=$3
    local show_values="${4:-true}"

    local list_content=""
    local start_index=$list_offset_ref
    local lines_used=0

    if [[ ${#DISPLAY_ORDER[@]} -gt 0 ]]; then
        for (( i=start_index; i<${#DISPLAY_ORDER[@]}; i++ )); do
            local key="${DISPLAY_ORDER[i]}"
            
            local item_height=1
            if [[ ! "$key" =~ ^(BLANK_LINE_|COMMENT_LINE_) && -n "${ENV_COMMENTS[$key]}" ]]; then
                item_height=2
            fi
            
            if (( lines_used + item_height > viewport_height )); then break; fi
            lines_used=$((lines_used + item_height))

            local is_current="false"; if (( i == current_option_ref )); then is_current="true"; fi
            
            local cursor="${C_CYAN}│${T_RESET} "
            local line_bg="${T_RESET}"
            if [[ "$is_current" == "true" ]]; then
                cursor="${C_CYAN}│❱${T_RESET}"
                line_bg="${T_BOLD}${C_BLUE}${T_REVERSE}"
            fi

            local item_output=""

            if [[ "$key" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
                local raw_text="${ENV_VARS[$key]}"
                if [[ "$key" =~ ^BLANK_LINE_ ]]; then raw_text=""; fi
                local display_text="${raw_text:-(Blank Line)}"
                local display_text_trunc; display_text_trunc=$(_truncate_string "$display_text" 68)
                
                local text_color="${C_GRAY}"
                if [[ "$is_current" == "true" ]]; then text_color=""; fi
                
                local padded_text
                printf -v padded_text "%-68s" "$display_text_trunc"
                item_output="${cursor}${line_bg}${text_color}${padded_text}${T_RESET}${T_CLEAR_LINE}"
            else
                local display_key="${key%%__DUPLICATE_KEY_*}"
                local value="${ENV_VARS[$key]}"
                local comment="${ENV_COMMENTS[$key]:-}"
                
                local color_preview=""
                local preview_visible_len=0

                if [[ "$show_values" == "false" ]]; then
                    value="*****"
                else
                    _get_color_preview_string "$value" "$is_current" color_preview preview_visible_len
                fi

                local max_len=$(( 45 - preview_visible_len ))
                local value_display_sanitized
                value_display_sanitized="$value"
                _sanitize_and_truncate_value value_display_sanitized "$max_len"
                local final_display="${value_display_sanitized}${color_preview}"
                
                local visible_len=$(( ${#value_display_sanitized} + preview_visible_len ))
                local padding_needed=$(( 45 - visible_len )); if (( padding_needed < 0 )); then padding_needed=0; fi
                local val_padding=""; printf -v val_padding "%*s" "$padding_needed" ""

                if [[ "$is_current" == "true" ]]; then
                    local line_str
                    printf -v line_str "%-22s %s%s" "${display_key}" "${final_display}" "${val_padding}"
                    item_output="${cursor}${line_bg}${line_str}${T_RESET}${T_CLEAR_LINE}"
                    if [[ -n "$comment" ]]; then
                        local comment_trunc; comment_trunc=$(_truncate_string "$comment" 62)
                        local comment_line; printf -v comment_line "└ %-66s" "$comment_trunc"
                        item_output+=$'\n'
                        item_output+="${C_CYAN}│${T_RESET} ${T_REVERSE}${C_GRAY}${comment_line}${T_RESET}${T_CLEAR_LINE}"
                    fi
                else
                    local key_padded; printf -v key_padded "%-22s" "${display_key}"
                    item_output="${cursor}${key_padded}${T_RESET} ${C_CYAN}${final_display}${T_RESET}${val_padding}${T_CLEAR_LINE}"
                    if [[ -n "$comment" ]]; then
                        local comment_trunc; comment_trunc=$(_truncate_string "$comment" 62)
                        item_output+=$'\n'
                        item_output+="${C_CYAN}│${T_RESET} ${C_GRAY}└ ${comment_trunc}${T_RESET}${T_CLEAR_LINE}"
                    fi
                fi
            fi

            if [[ ${#list_content} -gt 0 ]]; then
                list_content+=$'\n'
            fi
            list_content+="${item_output}"
        done
    else
        list_content+=$(printf "${C_CYAN}│${T_RESET}  %s" "${C_GRAY}(No variables found. Press 'A' to add one.)${T_CLEAR_LINE}${T_RESET}")
        lines_used=1
    fi

    # Fill remaining viewport with blank lines
    local lines_to_fill=$(( viewport_height - lines_used ))
    if (( lines_to_fill > 0 )); then
        for ((j=0; j<lines_to_fill; j++)); do list_content+=$(printf '\n%s%s' "${C_CYAN}│${T_RESET}" "${T_CLEAR_LINE}"); done
    fi

    printf "%b" "$list_content"
}

# Draws the header for the variable list.
function draw_header() {
    printf "${C_CYAN}│${T_RESET} ${T_BOLD}${T_ULINE}%-22s${T_RESET} ${T_BOLD}${T_ULINE}%-45s${T_RESET}" "VARIABLE" "VALUE"
}

# Draws the footer with keybindings and error messages.
function draw_footer() {
    local filter_text="$1"
    if [[ -n "$filter_text" ]]; then
        local dash_fill="────────────────────────────────────────────────────────────────────────"
        local constructed="${C_CYAN}├─Controls:┬ ${T_RESET}${T_BOLD}${C_YELLOW}[${C_MAGENTA}/${C_YELLOW}] Filter: ${C_CYAN}${filter_text} ${dash_fill}"
        local header_line; header_line=$(_truncate_string "$constructed" 72 "─")
        printf "%s${T_RESET}\n" "$header_line"
    else
        printf "${C_CYAN}├─Controls:┬──────────┬────────┬──────────┬───────────┬────────┬────────${T_RESET}\n"
    fi

    local sep="${C_CYAN}│${C_GRAY}"
    
    printf "${C_CYAN}│${C_GRAY} [${T_BOLD}${C_CYAN}↑↓${C_GRAY}]Move ${sep} [${T_BOLD}${C_BLUE}E${C_GRAY}]dit   ${sep} [${T_BOLD}${C_GREEN}A${C_GRAY}]dd  ${sep} [${T_BOLD}${C_RED}D${C_GRAY}]elete ${sep} [${T_BOLD}${C_YELLOW}C${C_GRAY}]lone   ${sep} [${T_BOLD}${C_MAGENTA}O${C_GRAY}]pen ${sep} [${T_BOLD}${C_CYAN}?${C_GRAY}]Help${T_CLEAR_LINE}\n"
    printf "${C_CYAN}╰${C_GRAY} [${T_BOLD}${C_CYAN}jk${C_GRAY}]Move ${sep} [${T_BOLD}${C_GREEN}I${C_GRAY}]mport ${sep} [${T_BOLD}${C_GREEN}S${C_GRAY}]ave ${sep} [${T_BOLD}${C_YELLOW}V${C_GRAY}]alues ${sep} [${T_BOLD}${C_MAGENTA}/${C_GRAY}]Filter ${sep}        ${sep} [${T_BOLD}${C_RED}Q${C_GRAY}]uit${T_CLEAR_LINE}"
}

# Handles editing an existing variable or adding a new one.
function edit_variable() {
    local -n current_option_idx_ref=$1
    local mode="$2" # "add" or "edit"
    # Optional arguments for pre-populating 'add' mode (used for cloning)
    local initial_key="${3:-}"
    local initial_value="${4:-}"
    local initial_comment="${5:-}"

    local key value comment
    local original_key original_value original_comment
    local pending_key pending_value pending_comment

    if [[ "$mode" == "edit" ]] && [[ ${#DISPLAY_ORDER[@]} -gt 0 ]]; then
        original_key="${DISPLAY_ORDER[current_option_idx_ref]}"
        # Disallow editing of comments/blank lines
        if [[ "$original_key" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
            clear_lines_up 2
            show_timed_message "${ICON_WARN} Cannot edit blank lines or comments." 1.5
            return 2 # Signal no change
        fi
        local display_name="${original_key%%__DUPLICATE_KEY_*}"
        key="$display_name"
        original_value="${ENV_VARS[$original_key]}"
        original_comment="${ENV_COMMENTS[$original_key]}"
        pending_key="$display_name"
        pending_value="$original_value"
        pending_comment="$original_comment"
    else
        mode="add" # Force add mode if list is empty
    fi

    # --- Add Mode Initialization ---
    if [[ "$mode" == "add" ]]; then
        key="${initial_key:-NEW_VARIABLE}"
        # For 'add' mode, originals are empty
        original_value=""
        pending_key="${initial_key:-NEW_VARIABLE}"
        original_comment=""
        pending_value="${initial_value:-}"
        pending_comment="${initial_comment:-}"
    fi

    # --- Define functions for the generic editor loop ---

    _editor_draw_func() {
        local original_display_name="${original_key%%__DUPLICATE_KEY_*}"
        _draw_variable_editor "$original_display_name" "$pending_key" "$original_value" "$pending_value" "$original_comment" "$pending_comment"
    }

    _editor_field_handler() {
        local key_pressed="$1"
        case "$key_pressed" in
            1)
                if ! prompt_for_input "${C_YELLOW}New Name " pending_key "$pending_key" "false" 2; then return 0; fi
                if ! [[ "$pending_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                    show_timed_message "${ICON_ERR} Invalid variable name. Must be alphanumeric and start with a letter or underscore." 3
                    pending_key="${key:-$original_key}" # Revert
                fi
                return 0 ;;
            2)
                local edit_val="${pending_value//$'\033'/\\033}"
                if prompt_for_input "${C_YELLOW}New Value " edit_val "$edit_val" "true" 2; then
                    if [[ "$edit_val" == *\\033* ]]; then
                        pending_value=$(printf '%b' "$edit_val")
                    else
                        pending_value="$edit_val"
                    fi
                fi
                return 0 ;;
            3)
                prompt_for_input "${C_YELLOW}New Comment " pending_comment "$pending_comment" "true" 2
                return 0 ;;
            *) return 1 ;; # Not handled
        esac
    }

    _editor_change_checker() {
        local original_display_name="${original_key%%__DUPLICATE_KEY_*}"
        if [[ "$pending_key" != "$original_display_name" || "$pending_value" != "$original_value" || "$pending_comment" != "$original_comment" ]]; then
            return 0 # Has changes
        else
            return 1 # No changes
        fi
    }

    _editor_reset_func() {
        pending_key="${original_key%%__DUPLICATE_KEY_*}"
        pending_value="$original_value"
        pending_comment="$original_comment"
    }

    local banner_text="Variable Editor: ${C_YELLOW}${key} "
    if _interactive_editor_loop "$mode" "$banner_text" _editor_draw_func _editor_field_handler _editor_change_checker _editor_reset_func; then
        # Calculate final storage key to handle duplicates
        local final_storage_key="$pending_key"
        local original_display_name="${original_key%%__DUPLICATE_KEY_*}"

        if [[ "$pending_key" == "$original_display_name" ]]; then
             final_storage_key="$original_key"
        else
             local dup_count=1
             local check_key="$pending_key"
             while [[ -n "${ENV_VARS[$check_key]}" && "$check_key" != "$original_key" ]]; do
                  check_key="${pending_key}__DUPLICATE_KEY_${dup_count}"
                  ((dup_count++))
             done
             final_storage_key="$check_key"
        fi

        # Save was chosen, apply changes
        if [[ "$mode" == "edit" && "$final_storage_key" != "$original_key" ]]; then
            unset "ENV_VARS[$original_key]"
            unset "ENV_COMMENTS[$original_key]"
            for i in "${!ENV_ORDER[@]}"; do [[ "${ENV_ORDER[i]}" == "$original_key" ]] && ENV_ORDER[i]="$final_storage_key" && break; done
        fi

        ENV_VARS["$final_storage_key"]="$pending_value"
        if [[ -n "$pending_comment" ]]; then ENV_COMMENTS["$final_storage_key"]="$pending_comment"; else unset "ENV_COMMENTS[$final_storage_key]"; fi
        if [[ "$mode" == "add" ]]; then ENV_ORDER+=("$final_storage_key"); fi
        return 0 # Success
    else
        return 2 # No change
    fi
}

# Deletes the variable at the current cursor position.
function delete_variable() {
    local -n current_option_idx_ref=$1
    local key_to_delete="${DISPLAY_ORDER[current_option_idx_ref]}"

    if [[ "$key_to_delete" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
        clear_lines_up 2
        show_timed_message "${ICON_WARN} Cannot delete blank lines or comments this way." 1.5
        return 2 # No refresh needed
    fi
    
    clear_current_line
    clear_lines_up 2
    if prompt_yes_no "Delete variable '${C_RED}${key_to_delete}${T_RESET}'?" "n"; then
        # Remove from all state arrays
        unset "ENV_VARS[$key_to_delete]"
        unset "ENV_COMMENTS[$key_to_delete]"

        local new_env_order=()
        for item in "${ENV_ORDER[@]}"; do
            if [[ "$item" != "$key_to_delete" ]]; then
                new_env_order+=("$item")
            fi
        done
        ENV_ORDER=("${new_env_order[@]}")

        return 0 # Needs refresh
    fi
    return 2 # No refresh needed
}

# (Private) A helper to launch the default editor for the current .env file.
# It suspends the TUI, runs the editor, and relies on the caller to refresh.
_launch_editor_for_file() {
    local editor="${EDITOR:-nvim}"
    if ! command -v "${editor}" &>/dev/null; then
        show_timed_message "${ICON_ERR} Editor '${editor}' not found. Set the EDITOR environment variable." 3
        return 1
    fi

    # Suspend TUI drawing by hiding cursor and clearing screen
    printMsgNoNewline "${T_CURSOR_SHOW}"
    #clear

    # Run the editor (blocking)
    "${editor}" "${FILE_PATH}"
    return 0
}

# --- System Environment Integration ---

declare -A SYS_ENV_VARS
declare -a SYS_ENV_ORDER
declare -a SYS_ENV_DISPLAY_ORDER

# Loads system environment variables into global arrays.
function load_system_env() {
    SYS_ENV_VARS=()
    SYS_ENV_ORDER=()
    local var_names
    # Use compgen to get exported variables, sort them
    mapfile -t var_names < <(compgen -e | sort)

    for name in "${var_names[@]}"; do
        # Skip internal bash variables or functions if they appear
        if [[ ! "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then continue; fi
        
        SYS_ENV_VARS["$name"]="${!name}"
        SYS_ENV_ORDER+=("$name")
    done
    SYS_ENV_DISPLAY_ORDER=("${SYS_ENV_ORDER[@]}")
}

# Draws the list of system environment variables.
function draw_sys_env_list() {
    local -n current_option_ref=$1
    local -n list_offset_ref=$2
    local viewport_height=$3
    local show_values="${4:-true}"

    local list_content=""
    local start_index=$list_offset_ref
    local end_index=$(( list_offset_ref + viewport_height - 1 ))
    if (( end_index >= ${#SYS_ENV_DISPLAY_ORDER[@]} )); then end_index=$(( ${#SYS_ENV_DISPLAY_ORDER[@]} - 1 )); fi

    if [[ ${#SYS_ENV_DISPLAY_ORDER[@]} -gt 0 ]]; then
        for (( i=start_index; i<=end_index; i++ )); do
            local key="${SYS_ENV_DISPLAY_ORDER[i]}"
            local is_current="false"; if (( i == current_option_ref )); then is_current="true"; fi
            local line_output=""

            local value="${SYS_ENV_VARS[$key]}"
            local color_preview=""
            local preview_visible_len=0

            if [[ "$show_values" == "false" ]]; then
                value="*****"
            else
                _get_color_preview_string "$value" "$is_current" color_preview preview_visible_len
            fi

            local max_len=$(( 43 - preview_visible_len ))
            local value_display_sanitized
            value_display_sanitized="$value"
            _sanitize_and_truncate_value value_display_sanitized "$max_len"
            local final_display="${value_display_sanitized}${color_preview}"
            
            # Check if exists in .env
            local status_indicator=" "
            if [[ -n "${ENV_VARS[$key]+x}" ]]; then
                status_indicator="${C_L_GREEN}*${T_RESET}" # Exists
            fi

            local key_display="${key}"
            if (( ${#key_display} > 20 )); then
                key_display="${key_display:0:19}…"
            fi

            local visible_len=$(( ${#value_display_sanitized} + preview_visible_len ))
            local padding_needed=$(( 43 - visible_len )); if (( padding_needed < 0 )); then padding_needed=0; fi
            line_output=$(printf "%b${C_L_CYAN}%-20s${T_FG_RESET} ${C_L_WHITE}%s%*s${T_FG_RESET}" "$status_indicator" "${key_display}" "$final_display" "$padding_needed" "")

            local item_content=""
            _draw_menu_item "$is_current" "false" "false" "$line_output" item_content
            if [[ ${#list_content} -gt 0 ]]; then list_content+=$'\n'; fi
            list_content+="${item_content}"
        done
    else
        list_content+=$(printf "    %s" "${C_GRAY}(No system variables found)${T_CLEAR_LINE}${T_RESET}")
    fi

    # Fill blank lines
    local list_draw_height=0
    if [[ ${#SYS_ENV_DISPLAY_ORDER[@]} -gt 0 ]]; then
        list_draw_height=$(( end_index - start_index + 1 ))
    fi
    if (( ${#SYS_ENV_DISPLAY_ORDER[@]} <= 0 )); then list_draw_height=1; fi
    local lines_to_fill=$(( viewport_height - list_draw_height ))
    if (( lines_to_fill > 0 )); then
        for ((j=0; j<lines_to_fill; j++)); do list_content+=$(printf '\n%s' "${T_CLEAR_LINE}"); done
    fi

    printf "%b" "$list_content"
}

# Manages the system environment variable view.
function system_env_manager() {
    load_system_env
    local current_option=0
    local list_offset=0
    local search_query=""
    local status_msg=""

    _apply_filter() {
        if [[ -z "$search_query" ]]; then
            SYS_ENV_DISPLAY_ORDER=("${SYS_ENV_ORDER[@]}")
        else
            SYS_ENV_DISPLAY_ORDER=()
            for key in "${SYS_ENV_ORDER[@]}"; do
                local val="${SYS_ENV_VARS[$key]}"
                if [[ "${key,,}" == *"${search_query,,}"* ]] || [[ "${val,,}" == *"${search_query,,}"* ]]; then
                    SYS_ENV_DISPLAY_ORDER+=("$key")
                fi
            done
        fi
    }

    # Helper for viewport
    _sys_viewport_calc() {
        local term_height; term_height=$(tput lines)
        local extra=5
        if [[ -n "$search_query" ]]; then extra=6; fi
        echo $(( term_height - extra ))
    }

    printMsgNoNewline "${T_CURSOR_HIDE}"
    
    local viewport_height
    local _tui_resized=0
    trap '_tui_resized=1' WINCH

    while true; do
        viewport_height=$(_sys_viewport_calc)
        local num_options=${#SYS_ENV_DISPLAY_ORDER[@]}

        # Scroll logic
        if (( current_option >= list_offset + viewport_height )); then list_offset=$(( current_option - viewport_height + 1 )); fi
        if (( current_option < list_offset )); then list_offset=$current_option; fi
        local max_offset=$(( num_options - viewport_height )); if (( max_offset < 0 )); then max_offset=0; fi
        if (( list_offset > max_offset )); then list_offset=$max_offset; fi
        if (( num_options < viewport_height )); then list_offset=0; fi

        local screen_buffer=""
        screen_buffer+=$(printBanner "${C_YELLOW}System Environment Variables" "${C_CYAN}")
        screen_buffer+=$'\n'
        screen_buffer+=$(printf "${C_CYAN}│${T_RESET} ${T_BOLD}${T_ULINE}%-22s${T_RESET} ${T_BOLD}${T_ULINE}%-43s${T_RESET}" "VARIABLE" "VALUE")
        screen_buffer+=$'\n'
        screen_buffer+=$(draw_sys_env_list current_option list_offset "$viewport_height" "$SHOW_VALUES")
        screen_buffer+=$'\n'
        screen_buffer+="${C_GRAY}${DIV}${T_RESET}${T_CLEAR_LINE}\n"
        
        local help_nav=" ${C_CYAN}↑↓${C_WHITE} Move | ${C_GREEN}(I) Toggle${C_WHITE} | ${C_YELLOW}(V)alues${C_WHITE} | ${C_MAGENTA}(/) Filter${C_WHITE} | ${C_YELLOW}(Q)uit/Back${C_WHITE}"
        local info_line=" ${ICON_INFO} ${C_GREEN}*${C_GRAY} indicates variable exists in .env"
        if [[ -n "$status_msg" ]]; then
            info_line=" $status_msg"
            status_msg=""
        fi
        screen_buffer+=$(printf " %s${T_CLEAR_LINE}\n%s${T_CLEAR_LINE}" "$help_nav" "$info_line")

        if [[ -n "$search_query" ]]; then
             screen_buffer+=$(printf "\n ${ICON_INFO} Filter: ${C_CYAN}%s${T_RESET}${T_CLEAR_LINE}" "$search_query")
        fi
        
        printf '\033[H%b' "$screen_buffer"

        local key; key=$(read_single_char)
        
        if [[ $_tui_resized -eq 1 ]]; then _tui_resized=0; continue; fi

        case "$key" in
            "$KEY_UP"|"k") if (( num_options > 0 )); then current_option=$(( (current_option - 1 + num_options) % num_options )); fi ;;
            "$KEY_DOWN"|"j") if (( num_options > 0 )); then current_option=$(( (current_option + 1) % num_options )); fi ;;
            "$KEY_PGUP") if (( num_options > 0 )); then current_option=$(( current_option - viewport_height )); if (( current_option < 0 )); then current_option=0; fi; fi ;;
            "$KEY_PGDN") if (( num_options > 0 )); then current_option=$(( current_option + viewport_height )); if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi; fi ;;
            "$KEY_HOME") if (( num_options > 0 )); then current_option=0; fi ;;
            "$KEY_END") if (( num_options > 0 )); then current_option=$(( num_options - 1 )); fi ;;
            'q'|'Q'|"$KEY_ESC"|"$KEY_LEFT")
                break
                ;;
            '/')
                # To create an inline prompt, we manually clear the footer area
                # and then call prompt_for_input, telling it how many lines to occupy
                # so it doesn't clear the whole screen.
                local footer_height=2
                if [[ -n "$search_query" ]]; then footer_height=3; fi
                #clear_current_line
                clear_lines_up "$((footer_height - 1))"
                #move_cursor_up "$((footer_height - 1))"
                #printf "${T_CLEAR_SCREEN_DOWN}" >/dev/tty # Clear from cursor to end of screen

                local new_query="$search_query"
                if prompt_for_input "$((footer_height - 1)) ${C_MAGENTA}Filter variables" new_query "$search_query" "true" "1"; then
                    search_query="$new_query"
                    _apply_filter
                    current_option=0
                    list_offset=0
                fi
                ;;
            'i'|'I')
                if [[ ${#SYS_ENV_DISPLAY_ORDER[@]} -eq 0 ]]; then continue; fi
                local selected_key="${SYS_ENV_DISPLAY_ORDER[current_option]}"
                local selected_value="${SYS_ENV_VARS[$selected_key]}"

                if [[ -n "${ENV_VARS[$selected_key]+x}" ]]; then
                    # Variable exists, this is a destructive action (removal). Ask for confirmation.
                    clear_current_line
                    prompt_yes_no "'${C_BLUE}${selected_key}${T_RESET}' already exists. Remove it from .env?" "y"
                    local prompt_ret=$?

                    if [[ $prompt_ret -eq 0 ]]; then # Yes, remove it
                        unset "ENV_VARS[$selected_key]"
                        unset "ENV_COMMENTS[$selected_key]"

                        # Rebuild arrays to remove the key
                        local new_order=()
                        local new_display=()
                        for k in "${ENV_ORDER[@]}"; do [[ "$k" != "$selected_key" ]] && new_order+=("$k"); done
                        for k in "${DISPLAY_ORDER[@]}"; do [[ "$k" != "$selected_key" ]] && new_display+=("$k"); done
                        ENV_ORDER=("${new_order[@]}")
                        DISPLAY_ORDER=("${new_display[@]}")

                        status_msg="${ICON_OK} Removed '${C_BLUE}${selected_key}${T_RESET}'"
                    elif [[ $prompt_ret -eq 1 ]]; then # No
                        status_msg="${ICON_INFO} Action cancelled for '${C_BLUE}${selected_key}${T_RESET}'."
                    fi
                    # On cancel (ret=2), prompt_yes_no shows a timed message, so we do nothing.
                else
                    # Variable does not exist, import it (toggle on) - non-destructive
                    ENV_VARS["$selected_key"]="$selected_value"
                    ENV_COMMENTS["$selected_key"]="Imported from system"

                    ENV_ORDER+=("$selected_key")
                    DISPLAY_ORDER+=("$selected_key")
                    status_msg="${ICON_OK} Imported '${C_BLUE}${selected_key}${T_RESET}'"
                fi
                ;;
            'v'|'V')
                if [[ "$SHOW_VALUES" == "true" ]]; then SHOW_VALUES="false"; else SHOW_VALUES="true"; fi
                ;;
        esac
    done
}

# --- TUI Main Loop ---

SHOW_VALUES=true

function interactive_manager() {
    local current_option=0
    local list_offset=0
    local search_query=""

    _apply_filter() {
        DISPLAY_ORDER=()
        if [[ -z "$search_query" ]]; then
            # No filter, show all items from ENV_ORDER
            DISPLAY_ORDER=("${ENV_ORDER[@]}")
        else
            # Filter is active, only show matching variables
            for key in "${ENV_ORDER[@]}"; do
                if [[ "$key" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then continue; fi
                local val="${ENV_VARS[$key]}"
                if [[ "${key,,}" == *"${search_query,,}"* ]] || [[ "${val,,}" == *"${search_query,,}"* ]]; then
                    DISPLAY_ORDER+=("$key")
                fi
            done
        fi
    }

    # --- TUI Helper Functions ---
    _header_func() { draw_header; }
    _footer_func() { draw_footer "$search_query"; }
    _refresh_func() {
        # This is a dummy refresh function for the generic TUI loop.
        # Data is managed locally in this script.
        :
    }
    _viewport_calc_func() {
        # Calculate available height for the list
        local term_height; term_height=$(tput lines)
        # banner(1) + header(1) + list(...) + div(1) + footer(3) + filter_status(1 if active)
        local extra=6
        echo $(( term_height - extra ))
    }

    # --- Key Handler ---
    _key_handler() {
        local key="$1"
        local -n current_option_ref="$2"
        local -n num_options_ref="$3"
        local -n handler_result_ref="$4"

        case "$key" in
            'q'|'Q'|"$KEY_ESC")
                if _has_pending_changes; then
                    clear_current_line
                    clear_lines_up 2
                    if prompt_yes_no "You have unsaved changes. Quit without saving?" "n"; then
                        handler_result_ref="exit"
                    else
                        handler_result_ref="redraw" # User cancelled, so redraw the menu
                    fi
                else
                    handler_result_ref="exit" # No changes, exit immediately
                fi
                ;;
            's'|'S')
                if ! _has_pending_changes; then
                    clear_current_line
                    clear_lines_up 2
                    show_timed_message "${ICON_INFO} No changes to save." 1.5
                    handler_result_ref="redraw"
                else
                    clear_current_line
                    clear_lines_up 2
                    if prompt_yes_no "Are you sure you want to save these changes?" "y"; then
                        save_env_file "$FILE_PATH"
                        handler_result_ref="refresh_data" # Re-parse file after saving
                    fi
                    handler_result_ref="redraw" # Redraw whether saved or cancelled
                fi
                ;;
            'a'|'A')
                local edit_result
                edit_variable current_option_ref "add"
                edit_result=$?
                if [[ $edit_result -eq 0 ]]; then
                    handler_result_ref="refresh_data"
                elif [[ $edit_result -eq 2 ]]; then
                    handler_result_ref="redraw"
                fi
                ;;
            'e'|'E')
                # If there are no variables, treat 'edit' as 'add'.
                local mode="edit"
                if [[ ${num_options_ref} -eq 0 ]]; then
                    mode="add" # edit_variable will handle this
                fi

                local edit_result
                edit_variable current_option_ref "$mode"
                edit_result=$?
                if [[ $edit_result -eq 0 ]]; then
                    handler_result_ref="refresh_data"
                elif [[ $edit_result -eq 2 ]]; then
                    handler_result_ref="redraw"
                fi
                ;;
            'd'|'D')
                if delete_variable current_option_ref; then
                    handler_result_ref="refresh_data"
                else
                    handler_result_ref="redraw"
                fi
                ;;
            'o'|'O')
                local proceed=true
                if _has_pending_changes; then
                    clear_current_line
                    clear_lines_up 2
                    prompt_yes_no "You have unsaved changes. Save before opening editor?" "y"
                    local ret=$?
                    if [[ $ret -eq 0 ]]; then
                        if ! save_env_file "$FILE_PATH"; then
                            proceed=false
                            handler_result_ref="redraw"
                        fi
                    elif [[ $ret -eq 2 ]]; then
                        proceed=false
                        handler_result_ref="redraw"
                    fi
                fi

                if [[ "$proceed" == "true" ]]; then
                    if _launch_editor_for_file; then
                        # After editor closes, force a re-parse and redraw
                        handler_result_ref="refresh_data"
                    else
                        handler_result_ref="redraw"
                    fi
                fi
                ;;
            'i'|'I')
                system_env_manager
                handler_result_ref="redraw"
                ;;
            'v'|'V')
                if [[ "$SHOW_VALUES" == "true" ]]; then SHOW_VALUES="false"; else SHOW_VALUES="true"; fi
                handler_result_ref="redraw"
                ;;
            'c'|'C')
                # Clone
                if [[ ${num_options_ref} -gt 0 ]]; then
                    local selected_key="${DISPLAY_ORDER[current_option_ref]}"
                    if [[ "$selected_key" =~ ^(BLANK_LINE_|COMMENT_LINE_) ]]; then
                        clear_current_line
                        clear_lines_up 2
                        show_timed_message "${ICON_WARN} Cannot clone blank lines or comments." 1.5
                        handler_result_ref="redraw"
                    else
                        # Prepare data for clone
                        local source_value="${ENV_VARS[$selected_key]}"
                        local source_comment="${ENV_COMMENTS[$selected_key]:-}"

                        # Find a unique name for the clone
                        local new_key="${selected_key}_COPY"
                        local i=1
                        while [[ -n "${ENV_VARS[$new_key]+x}" ]]; do
                            new_key="${selected_key}_COPY_${i}"
                            ((i++))
                        done

                        # Call the editor in "add" mode with pre-filled data
                        local edit_result
                        edit_variable current_option_ref "add" "$new_key" "$source_value" "$source_comment"
                        edit_result=$?
                        if [[ $edit_result -eq 0 ]]; then
                            handler_result_ref="refresh_data"
                        elif [[ $edit_result -eq 2 ]]; then
                            handler_result_ref="redraw"
                        fi
                    fi
                else
                    # No items in list, do nothing
                    handler_result_ref="noop"
                fi
                ;;
            '/')
                local footer_height=2
                
                clear_current_line
                clear_lines_up "$((footer_height - 1))"
                
                local new_query="$search_query"
                if prompt_for_input "${C_MAGENTA}Filter by " new_query "$search_query" "true" "1"; then
                    search_query="$new_query"
                    handler_result_ref="refresh_data"
                    
                else
                    # User cancelled, just redraw to clean up the prompt area
                    handler_result_ref="redraw"
                fi
                ;;
            '?'|'h'|'H')
                show_help
                handler_result_ref="redraw"
                ;;
            *)
                handler_result_ref="noop"
                ;;
        esac
    }

    # --- Custom List View Loop ---
    # This is a simplified version of _interactive_list_view from tui.lib.sh
    # to better handle local state management.
    printMsgNoNewline "${T_CURSOR_HIDE}"
    # The global EXIT trap in tui.lib.sh will handle showing the cursor.
    local viewport_height

    _apply_filter # Initial population of DISPLAY_ORDER

    local _tui_resized=0
    trap '_tui_resized=1' WINCH
    while true; do
            # --- Recalculate and Redraw ---
            viewport_height=$(_viewport_calc_func)
            num_options=${#DISPLAY_ORDER[@]}

            # Adjust scroll offset
            if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi
            if (( current_option < 0 )); then current_option=0; fi

            if (( current_option < list_offset )); then list_offset=$current_option; fi

            # Calculate height from list_offset to current_option to ensure cursor visibility
            local height_acc=0
            for (( idx=list_offset; idx<=current_option; idx++ )); do
                local key="${DISPLAY_ORDER[idx]}"
                ((height_acc++))
                if [[ ! "$key" =~ ^(BLANK_LINE_|COMMENT_LINE_) && -n "${ENV_COMMENTS[$key]}" ]]; then ((height_acc++)); fi
            done
            while (( height_acc > viewport_height )); do
                local key="${DISPLAY_ORDER[list_offset]}"
                ((height_acc--))
                if [[ ! "$key" =~ ^(BLANK_LINE_|COMMENT_LINE_) && -n "${ENV_COMMENTS[$key]}" ]]; then ((height_acc--)); fi
                ((list_offset++))
            done

            # --- Double-buffer drawing ---
            local screen_buffer=""
            local relative_path="$FILE_PATH"

            # Max width for banner content (70 chars line - 2 chars for "╭─")
            local max_banner_width=68
            local status_text=""
            if [[ -n "$ERROR_MESSAGE" ]]; then
                status_text=" - ${ICON_ERR} ${C_RED}${ERROR_MESSAGE} ${T_RESET}"
            else
                status_text=" - ${ICON_OK} ${C_GREEN}Valid ${T_RESET}"
            fi
            local banner_text="Editing: ${C_YELLOW}${relative_path}${T_RESET}${status_text}"
            banner_text=$(_truncate_string "$banner_text" "$max_banner_width")
            screen_buffer+=$(printBanner "$banner_text" "${C_CYAN}")
            screen_buffer+=$'\n'
            screen_buffer+=$(_header_func)
            screen_buffer+=$'\n'
            screen_buffer+=$(draw_var_list current_option list_offset "$viewport_height" "$SHOW_VALUES")
            screen_buffer+=$'\n'
            screen_buffer+=$(_footer_func)
            render_buffer "$screen_buffer"

            # --- Handle Input ---
            local key; key=$(read_single_char)
            local handler_result="noop"

            if [[ $_tui_resized -eq 1 ]]; then
                _tui_resized=0
                handler_result="redraw"
            fi

            case "$key" in
                "$KEY_UP"|"k") if (( num_options > 0 )); then current_option=$(( (current_option - 1 + num_options) % num_options )); handler_result="redraw"; fi ;;
                "$KEY_DOWN"|"j") if (( num_options > 0 )); then current_option=$(( (current_option + 1) % num_options )); handler_result="redraw"; fi ;;
                "$KEY_PGUP") if (( num_options > 0 )); then current_option=$(( current_option - viewport_height )); if (( current_option < 0 )); then current_option=0; fi; handler_result="redraw"; fi ;;
                "$KEY_PGDN") if (( num_options > 0 )); then current_option=$(( current_option + viewport_height )); if (( current_option >= num_options )); then current_option=$(( num_options - 1 )); fi; handler_result="redraw"; fi ;;
                "$KEY_HOME") if (( num_options > 0 )); then current_option=0; handler_result="redraw"; fi ;;
                "$KEY_END") if (( num_options > 0 )); then current_option=$(( num_options - 1 )); handler_result="redraw"; fi ;;
                *)
                    _key_handler "$key" current_option num_options handler_result
                    ;;
            esac

            # If the save key was pressed, the key handler shows its own prompt.
            # We should skip redrawing the main UI to avoid output collision.
            case "$key" in
                's'|'S') continue ;;
            esac

            if [[ "$handler_result" == "exit" ]]; then
                break
            elif [[ "$handler_result" == "refresh_data" ]]; then
                # After a save, we re-parse the file to get a clean state.
                if [[ "$key" == "s" || "$key" == "S" || "$key" == "o" || "$key" == "O" ]]; then
                    parse_env_file "$FILE_PATH"
                fi
                # For any data change (add, edit, delete, save, filter), we rebuild the display list.
                _apply_filter
                # After filtering, the list size may change, so reset cursor.
                if (( current_option >= ${#DISPLAY_ORDER[@]} )); then current_option=$(( ${#DISPLAY_ORDER[@]} - 1 )); fi
                if (( current_option < 0 )); then current_option=0; fi
                # The main loop will handle redrawing.
            fi
        done
    clear
}

# --- Main Execution ---

main() {
    # --- Argument Parsing ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -H|--hide-values)
                SHOW_VALUES="false"
                shift
                ;;
            *)
                FILE_PATH="$1"
                shift
                ;;
        esac
    done

    # Determine the target .env file if not set
    if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH=".env"
    fi

    # Ensure the directory for the .env file exists
    local file_dir; file_dir=$(dirname "$FILE_PATH")
    if [[ ! -d "$file_dir" ]]; then
        if prompt_yes_no "Directory '${file_dir}' does not exist. Create it?" "y"; then
            mkdir -p "$file_dir"
        else
            printInfoMsg "Operation cancelled."
            exit 1
        fi
    fi

    # Initial parse of the .env file
    if ! parse_env_file "$FILE_PATH"; then
        # An error occurred during parsing, but we can still open the editor
        # The error will be displayed in the footer.
        :
    fi

    # Launch the interactive TUI
    interactive_manager

    printOkMsg "Exited .env manager."
}

main "$@"

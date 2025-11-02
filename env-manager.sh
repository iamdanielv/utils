#!/bin/bash
# An interactive TUI for managing variables in a .env file.

# Exit immediately if a command exits with a non-zero status.
set -e
# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Global Variables ---
ENV_FILE_PATH=""

# --- Script Functions ---

print_usage() {
    printBanner "Environment Variable Manager"
    printMsg "An interactive TUI to manage variables in a .env file."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [path_to_env_file]"
    printMsg "\nIf no path is provided, it will look for '.env' in the current directory."
    printMsg "\n${T_ULINE}Features:${T_RESET}"
    printMsg "  - List all variables in a formatted table."
    printMsg "  - Add new variables with validation."
    printMsg "  - Edit existing variable values."
    printMsg "  - Add or edit comments for variables."
    printMsg "  - Copy an existing variable to a new name."
    printMsg "  - Remove one or more variables."
    printMsg "  - Automatically creates the .env file if it doesn't exist."
}

# Reads the .env file and loads variables into an associative array.
# Also returns an ordered list of keys.
# Usage:
#   declare -A vars
#   local -a ordered_keys
#   declare -A comments
#   read_env_file vars ordered_keys comments
read_env_file() {
    local -n out_vars_map=$1
    local -n out_ordered_keys=$2
    local -n out_comments_map=$3

    # Clear output arrays before populating
    out_vars_map=()
    out_ordered_keys=()
    out_comments_map=()

    if [[ ! -f "$ENV_FILE_PATH" ]]; then
        return # File doesn't exist, arrays will be empty
    fi

    # Validate file format before reading
    if ! _validate_env_file "$ENV_FILE_PATH"; then
        printErrMsg "Cannot proceed with invalid .env file. Please fix the errors above."
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        local trimmed_line
        trimmed_line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        # Handle special comments: ##@ KEY comment text
        if [[ "$trimmed_line" =~ ^##@[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local comment="${BASH_REMATCH[2]}"
            out_comments_map["$key"]="$comment"
            continue
        fi

        # Skip empty lines and regular comments
        if [[ -z "$trimmed_line" || "$trimmed_line" =~ ^# ]]; then
            continue
        fi

        local key="${trimmed_line%%=*}"
        local value="${trimmed_line#*=}"
        out_vars_map["$key"]=$value # No quotes to handle values that might have them
        out_ordered_keys+=("$key")
    done <"$ENV_FILE_PATH"
}

# Writes the in-memory variables back to the .env file, preserving order.
# Usage:
#   declare -A vars_to_write
#   local -a keys_to_write
#   declare -A comments_to_write
write_env_file() {
    local -n vars_to_write=$1
    local -n keys_to_write=$2
    local -n comments_to_write=$3
    local temp_file
    temp_file=$(mktemp)

    for key in "${keys_to_write[@]}"; do
        # Check if the key exists in the map before writing
        if [[ -n "${vars_to_write[$key]+_}" ]]; then
            # If there's a comment for this key, write it first
            if [[ -n "${comments_to_write[$key]}" ]]; then
                echo "##@ ${key} ${comments_to_write[$key]}" >>"$temp_file"
            fi
            echo "${key}=${vars_to_write[$key]}" >>"$temp_file"
        fi
    done

    # Atomically replace the original file
    mv "$temp_file" "$ENV_FILE_PATH"
    chmod 600 "$ENV_FILE_PATH"
}

# Displays all current environment variables in a table.
list_variables() {
    printBanner "Current Variables in ${ENV_FILE_PATH}"
    declare -A vars
    declare -A comments
    local -a ordered_keys
    read_env_file vars ordered_keys comments || return 1

    if [[ ${#ordered_keys[@]} -eq 0 ]]; then
        printInfoMsg "No variables found."
        return
    fi

    # Prepare data for the table formatter
    local tsv_data="VARIABLE\tVALUE\tCOMMENT\n"
    for key in "${ordered_keys[@]}"; do
        local comment_text="${comments[$key]:-"-"}"
        tsv_data+="${C_L_CYAN}${key}${T_RESET}\t${vars[$key]}\t${C_GRAY}${comment_text}${T_RESET}\n"
    done

    # Print the formatted table
    echo -e "$tsv_data" | format_tsv_as_table "  "
}

# Prompts the user to add a new variable.
add_variable() {
    printBanner "Add New Variable"
    declare -A vars
    declare -A comments
    local -a ordered_keys
    read_env_file vars ordered_keys comments || return 1

    local new_key
    while true; do
        # If the user cancels here, exit the function.
        prompt_for_input "Enter new variable name (e.g., 'API_KEY')" new_key || { printInfoMsg "Variable creation cancelled."; return; }

        if [[ ! "$new_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            printErrMsg "Invalid variable name. Use only letters, numbers, and underscores. Must not start with a number."
        elif [[ -n "${vars[$new_key]+_}" ]]; then
            printErrMsg "Variable '${new_key}' already exists."
        else
            # The key is valid and unique, break the loop.
            break
        fi
    done

    local new_value
    prompt_for_input "Enter value for '${new_key}'" new_value "" "true" || { printInfoMsg "Variable creation cancelled."; return; }

    local new_comment
    prompt_for_input "Enter comment for '${new_key}' (optional)" new_comment "" "true" || { printInfoMsg "Variable creation cancelled."; return; }

    vars["$new_key"]="$new_value"
    [[ -n "$new_comment" ]] && comments["$new_key"]="$new_comment"
    ordered_keys+=("$new_key")

    write_env_file vars ordered_keys comments
    printOkMsg "Variable '${C_L_CYAN}${new_key}${T_RESET}' added successfully."
}

# Prompts the user to select and edit an existing variable.
edit_variable() {
    printBanner "Edit Variable"
    declare -A vars
    local -a ordered_keys
    declare -A comments
    read_env_file vars ordered_keys comments || return 1
    
    if [[ ${#ordered_keys[@]} -eq 0 ]]; then
        printInfoMsg "No variables to edit."
        return
    fi

    local selected_idx
    selected_idx=$(interactive_single_select_menu "Select a variable to edit:" "${ordered_keys[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }

    local key_to_edit="${ordered_keys[$selected_idx]}"
    local current_value="${vars[$key_to_edit]}"
    local current_comment="${comments[$key_to_edit]:-}"

    local new_value
    prompt_for_input "Enter new value for '${key_to_edit}'" new_value "$current_value" "true" || { printInfoMsg "Edit cancelled."; return; }

    local new_comment
    prompt_for_input "Enter new comment for '${key_to_edit}'" new_comment "$current_comment" "true" || { printInfoMsg "Edit cancelled."; return; }

    vars["$key_to_edit"]="$new_value"
    if [[ -n "$new_comment" ]]; then
        comments["$key_to_edit"]="$new_comment"
    else
        unset 'comments[$key_to_edit]' # Remove comment if it's made blank
    fi

    write_env_file vars ordered_keys comments
    printOkMsg "Variable '${C_L_CYAN}${key_to_edit}${T_RESET}' updated."
}

# Prompts the user to select a variable and edit only its comment.
edit_comment() {
    printBanner "Edit Variable Comment"
    declare -A vars
    local -a ordered_keys
    declare -A comments
    read_env_file vars ordered_keys comments || return 1

    if [[ ${#ordered_keys[@]} -eq 0 ]]; then
        printInfoMsg "No variables found."
        return
    fi

    local selected_idx
    selected_idx=$(interactive_single_select_menu "Select a variable to edit its comment:" "${ordered_keys[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }

    local key_to_edit="${ordered_keys[$selected_idx]}"
    local current_comment="${comments[$key_to_edit]:-}"

    prompt_for_input "Enter new comment for '${key_to_edit}'" comments["$key_to_edit"] "$current_comment" "true" || return
    write_env_file vars ordered_keys comments
    printOkMsg "Comment for '${C_L_CYAN}${key_to_edit}${T_RESET}' updated."
}

# Prompts the user to copy an existing variable to a new one.
copy_variable() {
    printBanner "Copy Variable"
    declare -A vars
    local -a ordered_keys
    read_env_file vars ordered_keys || return 1
    # We don't need comments for this, as they are not copied.
    
    if [[ ${#ordered_keys[@]} -eq 0 ]]; then
        printInfoMsg "No variables to copy."
        return
    fi

    # 1. Select variable to copy from
    local selected_idx
    selected_idx=$(interactive_single_select_menu "Select a variable to copy:" "${ordered_keys[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }

    local key_to_copy="${ordered_keys[$selected_idx]}"
    local value_to_copy="${vars[$key_to_copy]}"

    printInfoMsg "Copying value from '${C_L_CYAN}${key_to_copy}${T_RESET}'."

    # 2. Prompt for new variable name (reuse logic from add_variable)
    local new_key
    while true; do
        prompt_for_input "Enter the new variable name" new_key || return
        if [[ ! "$new_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            printErrMsg "Invalid variable name. Use only letters, numbers, and underscores. Must not start with a number."
        elif [[ -n "${vars[$new_key]+_}" ]]; then
            printErrMsg "Variable '${new_key}' already exists."
        else
            break
        fi
    done

    vars["$new_key"]="$value_to_copy"
    ordered_keys+=("$new_key")
    write_env_file vars ordered_keys # This will write without a comment for the new key
    printOkMsg "Variable '${key_to_copy}' copied to '${new_key}' successfully."
}

# Prompts the user to select and remove one or more variables.
remove_variable() {
    printBanner "Remove Variables"
    declare -A vars
    local -a ordered_keys
    declare -A comments
    read_env_file vars ordered_keys comments || return 1
    
    if [[ ${#ordered_keys[@]} -eq 0 ]]; then
        printInfoMsg "No variables to remove."
        return
    fi

    local menu_output
    menu_output=$(interactive_multi_select_menu "Select variables to remove (space to toggle):" "All" "${ordered_keys[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }

    mapfile -t selected_indices < <(echo "$menu_output")
    if [[ ${#selected_indices[@]} -eq 0 ]]; then
        printInfoMsg "No variables selected for removal."
        return
    fi

    local -a keys_to_remove
    for index in "${selected_indices[@]}"; do
        if ((index > 0)); then # Skip "All" at index 0
            keys_to_remove+=("${ordered_keys[index - 1]}")
        fi
    done

    if ! prompt_yes_no "Are you sure you want to remove ${#keys_to_remove[@]} variable(s)?" "n"; then
        printInfoMsg "Removal cancelled."
        return
    fi

    for key in "${keys_to_remove[@]}"; do
        unset 'vars[$key]'
        unset 'comments[$key]'
    done

    write_env_file vars ordered_keys comments
    printOkMsg "${#keys_to_remove[@]} variable(s) removed."
}

# Main application loop.
main_loop() {
    while true; do
        clear
        printBanner "Manage .env file: ${C_L_BLUE}${ENV_FILE_PATH}${T_RESET}"
        local -a menu_options=(
            "List Variables"
            "Add Variable"
            "Edit Variable"
            "Edit Comment Only"
            "Copy Variable"
            "Remove Variable"
            "Exit"
        )

        local selected_index
        selected_index=$(interactive_single_select_menu "Select an action:" "${menu_options[@]}")
        [[ $? -ne 0 ]] && break

        clear
        case "${menu_options[$selected_index]}" in
        "List Variables") list_variables ;;
        "Add Variable") add_variable ;;
        "Edit Variable") edit_variable ;;
        "Edit Comment Only") edit_comment ;;
        "Copy Variable") copy_variable ;;
        "Remove Variable") remove_variable ;;
        "Exit") break ;;
        esac
        prompt_to_continue
    done

    clear
    printOkMsg "Goodbye!"
}

main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage
        exit 0
    fi

    ENV_FILE_PATH="${1:-./.env}"

    # If the file doesn't exist, ask to create it.
    if [[ ! -f "$ENV_FILE_PATH" ]]; then
        if prompt_yes_no "File '${ENV_FILE_PATH}' does not exist. Create it?" "y"; then
            touch "$ENV_FILE_PATH"
            printOkMsg "File created."
        else
            printInfoMsg "Operation cancelled."
            exit 0
        fi
    fi

    main_loop
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
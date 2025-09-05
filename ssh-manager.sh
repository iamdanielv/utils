#!/bin/bash
# An interactive TUI for managing and connecting to SSH hosts.

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "$0")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Constants ---
readonly SSH_DIR="${HOME}/.ssh"
readonly SSH_CONFIG_PATH="${SSH_DIR}/config"

# --- Script Functions ---

print_usage() {
    printBanner "SSH Connection Manager"
    printMsg "An interactive TUI to manage and connect to SSH hosts defined in ${SSH_CONFIG_PATH}."
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [-h]"
    printMsg "\nThis script is fully interactive. Just run it without arguments."
}

# Parses the SSH config file to extract host aliases.
# Ignores wildcard hosts like '*'.
get_ssh_hosts() {
    if [[ ! -f "$SSH_CONFIG_PATH" ]]; then
        return
    fi
    # Use awk to find lines starting with "Host", print the second field,
    # and ignore any hosts that are just "*".
    awk '/^[Hh]ost / && $2 != "*" {print $2}' "$SSH_CONFIG_PATH"
}

# Gets a specific config value for a given host by using `ssh -G`.
# This is the most robust method as it uses ssh itself to evaluate the config.
# It correctly handles the "first value wins" rule for duplicate keys, as well
# as Match blocks and include directives.
# Usage: get_ssh_config_value <host_alias> <config_key>
get_ssh_config_value() {
    local host_alias="$1"
    local key="$2"
    local key_lower
    key_lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')

    # `ssh -G` prints the fully resolved configuration for a host.
    ssh -G "$host_alias" 2>/dev/null | awk -v key="$key_lower" '
        $1 == key {
            # The value is the rest of the line. This handles values with spaces.
            val = ""
            for (i = 2; i <= NF; i++) {
                val = (val ? val " " : "") $i
            }
            print val
            exit
        }
    '
}

# Generates a list of formatted strings for the interactive menu,
# showing details for each SSH host.
# Populates an array whose name is passed as the first argument.
# Usage:
#   local -a my_menu_options
#   get_detailed_ssh_hosts_menu_options my_menu_options
get_detailed_ssh_hosts_menu_options() {
    local -n out_array=$1 # Use nameref to populate the caller's array
    local -a hosts
    mapfile -t hosts < <(get_ssh_hosts)

    out_array=() # Clear the output array

    if [[ ${#hosts[@]} -eq 0 ]]; then
        return 0 # Not an error, just no hosts
    fi

    for host_alias in "${hosts[@]}"; do
        local hostname user identity_file
        hostname=$(get_ssh_config_value "$host_alias" "HostName")
        user=$(get_ssh_config_value "$host_alias" "User")
        identity_file=$(get_ssh_config_value "$host_alias" "IdentityFile")

        # Clean up identity file path for display
        local key_info=""
        if [[ -n "$identity_file" ]]; then
            # Using #$HOME is safer than a simple string replacement
            key_info="(${C_WHITE}${identity_file/#$HOME/\~}${T_RESET})"
        fi

        local formatted_string
        formatted_string=$(printf "%s - ${C_L_CYAN}%s@%s ${T_RESET}%s" \
            "${host_alias}" \
            "${user:-?}" \
            "${hostname:-?}" \
            "${key_info}"
        )
        out_array+=("$formatted_string")
    done
}

# Presents an interactive menu for the user to select an SSH host.
# Returns the selected host alias via stdout.
# Returns exit code 1 if no host is selected or none exist.
# Usage:
#   local selected_host
#   selected_host=$(select_ssh_host "Select a host to connect to:")
#   if [[ $? -eq 0 ]]; then ...
select_ssh_host() {
    local prompt="$1"
    mapfile -t hosts < <(get_ssh_hosts)
    if [[ ${#hosts[@]} -eq 0 ]]; then
        printInfoMsg "No hosts found in your SSH config file."
        return 1
    fi

    local -a menu_options
    get_detailed_ssh_hosts_menu_options menu_options

    local selected_index
    selected_index=$(interactive_single_select_menu "$prompt" "${menu_options[@]}")
    if [[ $? -ne 0 ]]; then
        printInfoMsg "Operation cancelled."
        return 1
    fi

    echo "${hosts[$selected_index]}"
    return 0
}

# Prompts user to select a host and a key, then copies the key.
copy_ssh_id() {
    printBanner "Copy SSH Key to Server"

    local selected_host
    selected_host=$(select_ssh_host "Select a host to copy a key to:")
    [[ $? -ne 0 ]] && return # select_ssh_host prints messages

    # Find all public keys in the SSH directory
    local -a pub_keys
    mapfile -t pub_keys < <(find "$SSH_DIR" -maxdepth 1 -type f -name "*.pub")
    if [[ ${#pub_keys[@]} -eq 0 ]]; then
        printInfoMsg "No public SSH keys (.pub files) found in ${SSH_DIR}."
        return
    fi

    local key_idx
    key_idx=$(interactive_single_select_menu "Select the public key to copy:" "${pub_keys[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }
    local selected_key="${pub_keys[$key_idx]}"

    copy_ssh_id_for_host "$selected_host" "$selected_key"
}

# Helper function that does the actual ssh-copy-id work
copy_ssh_id_for_host() {
    local host_alias="$1"
    local key_file="$2"

    local user
    user=$(get_ssh_config_value "$host_alias" "User")
    local hostname
    hostname=$(get_ssh_config_value "$host_alias" "HostName")

    if [[ -z "$user" || -z "$hostname" ]]; then
        printErrMsg "Could not find User and HostName for '${host_alias}' in your SSH config."
        printInfoMsg "Please ensure the entry for '${host_alias}' has 'User' and 'HostName' directives."
        return 1
    fi

    printInfoMsg "Attempting to copy key to ${user}@${hostname}..."
    printMsg "You may be prompted for the password for '${user}' on the remote server."

    # ssh-copy-id is interactive, so we run it directly in the foreground.
    if ssh-copy-id -i "$key_file" "${user}@${hostname}"; then
        printOkMsg "Key successfully copied to '${host_alias}'."
    else
        printErrMsg "Failed to copy key to '${host_alias}'."
        printInfoMsg "Check your network connection, password, and server's SSH configuration."
        return 1
    fi
}

# Prompts for user input and assigns it to a variable.
# Usage: prompt_for_input "Prompt text" "variable_name" ["default_value"] ["allow_empty"]
prompt_for_input() {
    local prompt_text="$1"
    local -n var_ref="$2" # Use nameref to assign to caller's variable
    local default_val="${3:-}"
    local allow_empty="${4:-false}"
    local input

    local prompt_suffix=""
    if [[ -n "$default_val" ]]; then
        prompt_suffix=" [${C_L_CYAN}${default_val}${T_RESET}]"
    fi

    while true; do
        printMsgNoNewline "${T_QST_ICON} ${prompt_text}${prompt_suffix}: " >/dev/tty
        read -r input </dev/tty
        input=${input:-$default_val}
        if [[ -n "$input" || "$allow_empty" == "true" ]]; then
            var_ref="$input"
            break
        else
            printErrMsg "This field cannot be empty." >/dev/tty
        fi
    done
}

# Prompts user for details and adds a new host to the SSH config.
add_ssh_host() {
    printBanner "Add New SSH Host"

    local host_alias host_name user identity_file

    prompt_for_input "Enter a short alias for the host (e.g., 'prod-server')" host_alias

    # Check if host alias already exists
    if [[ -f "$SSH_CONFIG_PATH" ]]; then
        if grep -q -E "^\s*Host\s+${host_alias}\s*$" "$SSH_CONFIG_PATH"; then
            printErrMsg "Host alias '${host_alias}' already exists in your SSH config."
            return 1
        fi
    fi

    prompt_for_input "Enter the HostName (IP address or FQDN)" host_name
    prompt_for_input "Enter the remote User" user "${USER}"

    if prompt_yes_no "Generate a dedicated SSH key (ed25519) for this host?" "n"; then
        identity_file="${SSH_DIR}/${host_alias}_id_ed25519"
        if [[ -f "$identity_file" ]]; then
            if ! prompt_yes_no "Key file '${identity_file}' already exists. Overwrite it?" "n"; then
                printInfoMsg "Using existing key file: ${identity_file}"
            else
                run_with_spinner "Generating new ed25519 key for ${host_alias}..." \
                    ssh-keygen -t ed25519 -f "$identity_file" -N "" -C "${user}@${host_name}"
            fi
        else
            run_with_spinner "Generating new ed25519 key for ${host_alias}..." \
                ssh-keygen -t ed25519 -f "$identity_file" -N "" -C "${user}@${host_name}"
        fi

        {
            echo ""
            echo "Host ${host_alias}"
            echo "    HostName ${host_name}"
            echo "    User ${user}"
            echo "    IdentityFile ${identity_file}"
            echo "    IdentitiesOnly yes"
        } >>"$SSH_CONFIG_PATH"

        printOkMsg "Host '${host_alias}' added to ${SSH_CONFIG_PATH} with a dedicated key."

        if prompt_yes_no "Do you want to copy the new public key to the server now?" "y"; then
            copy_ssh_id_for_host "$host_alias" "${identity_file}.pub"
        fi
    else
        {
            echo ""
            echo "Host ${host_alias}"
            echo "    HostName ${host_name}"
            echo "    User ${user}"
        } >>"$SSH_CONFIG_PATH"
        printOkMsg "Host '${host_alias}' added to ${SSH_CONFIG_PATH}."
    fi
}

# (Private) Reads the SSH config and prints a new version with a specified host block removed.
# Used for both removing and editing hosts.
# Usage:
#   local new_config
#   new_config=$(_remove_host_block_from_config "my-host")
#   echo "$new_config" > "$SSH_CONFIG_PATH"
_remove_host_block_from_config() {
    local host_to_remove="$1"

    # This awk script processes the config line-by-line to robustly identify and
    # remove the correct host block, even with non-standard formatting.
    # It is more reliable than using blank lines as a record separator.
    awk -v host_to_remove="$host_to_remove" '
        # Function to print the buffered block if it is not the target.
        function flush_block() {
            if (block != "" && !is_target_block) {
                # Use printf to avoid adding an extra trailing newline.
                printf "%s\n", block
            }
        }

        # Match a new Host block definition.
        # The regex is for a line starting with optional whitespace, then "Host"
        # (case-insensitive), then more whitespace.
        /^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/ {
            # A new block starts, so flush the previously buffered one.
            flush_block()

            # Reset state for the new block.
            block = $0
            is_target_block = 0

            # Check if this new block is the one we want to remove.
            # Create a temporary string containing just the host patterns.
            line_content = $0
            sub(/^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/, "", line_content)

            # Split the patterns by whitespace to check each one individually.
            n = split(line_content, patterns, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                # Stop checking at comments.
                if (patterns[i] ~ /^#/) break
                if (patterns[i] == host_to_remove) {
                    is_target_block = 1
                    break
                }
            }
            # Continue to the next line of the input file.
            next
        }

        # For any other line (part of a block, a comment, or a blank line):
        {
            # If we are inside a block, append the line.
            if (block != "") {
                block = block "\n" $0
            } else {
                # If we are not in a block, it means this is content
                # before the first Host definition. Print it directly.
                print $0
            }
        }

        # At the end of the file, flush the last remaining block.
        END {
            flush_block()
        }
    ' "$SSH_CONFIG_PATH"
}

# (Private) Reads an SSH config file and prints the block for a specific host.
# Usage:
#   local block
#   block=$(_get_host_block_from_config "my-host" "/path/to/config")
_get_host_block_from_config() {
    local host_to_find="$1"
    local config_file="$2"

    # This awk script is similar to _remove_host_block_from_config, but it
    # prints the block that IS the target.
    awk -v host_to_find="$host_to_find" '
        function flush_block() {
            if (block != "" && is_target_block) {
                printf "%s\n", block
            }
        }
        /^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/ {
            flush_block()
            block = $0
            is_target_block = 0
            line_content = $0
            sub(/^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/, "", line_content)
            n = split(line_content, patterns, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                if (patterns[i] ~ /^#/) break
                if (patterns[i] == host_to_find) {
                    is_target_block = 1
                    break
                }
            }
            next
        }
        { if (block != "") { block = block "\n" $0 } }
        END { flush_block() }
    ' "$config_file"
}

# Edits an existing host in the SSH config.
edit_ssh_host() {
    printBanner "Edit SSH Host"

    local host_to_edit
    host_to_edit=$(select_ssh_host "Select a host to edit:")
    [[ $? -ne 0 ]] && return

    printInfoMsg "Editing configuration for: ${C_L_CYAN}${host_to_edit}${T_RESET}"
    printMsg "${C_GRAY}(Press Enter to keep the current value)${T_RESET}"

    # Get current values to use as defaults in prompts
    local current_hostname
    current_hostname=$(get_ssh_config_value "$host_to_edit" "HostName")
    local current_user
    current_user=$(get_ssh_config_value "$host_to_edit" "User")
    local current_identityfile
    current_identityfile=$(get_ssh_config_value "$host_to_edit" "IdentityFile")

    # Prompt for new values
    local new_hostname new_user new_identityfile
    prompt_for_input "HostName" new_hostname "$current_hostname"
    prompt_for_input "User" new_user "$current_user"
    prompt_for_input "IdentityFile (optional, leave blank to remove)" new_identityfile "$current_identityfile" "true"

    # Get the config content without the old host block
    local config_without_host
    config_without_host=$(_remove_host_block_from_config "$host_to_edit")

    # Build the new host block as a string
    local new_host_block
    new_host_block=$(
        # Use a subshell to capture the output of multiple echo commands
        {
            echo "" # Start with a newline to separate from previous block
            echo "Host ${host_to_edit}"
            echo "    HostName ${new_hostname}"
            echo "    User ${new_user}"
            if [[ -n "$new_identityfile" ]]; then
                echo "    IdentityFile ${new_identityfile}"
                echo "    IdentitiesOnly yes"
            fi
        }
    )

    # Combine the existing config (minus the old block) with the new block and write to the file
    echo "${config_without_host}${new_host_block}" | cat -s > "$SSH_CONFIG_PATH"

    printOkMsg "Host '${host_to_edit}' has been updated."
}

# Removes a host entry from the SSH config file.
remove_ssh_host() {
    printBanner "Remove SSH Host"

    local host_to_remove
    host_to_remove=$(select_ssh_host "Select a host to remove:")
    [[ $? -ne 0 ]] && return

    if ! prompt_yes_no "Are you sure you want to remove '${host_to_remove}' from your SSH config?" "n"; then
        printInfoMsg "Removal cancelled."
        return
    fi

    # Get the config content without the specified host block
    local new_config_content
    new_config_content=$(_remove_host_block_from_config "$host_to_remove")

    # Overwrite the config file with the new content, squeezing blank lines
    echo "$new_config_content" | cat -s > "$SSH_CONFIG_PATH"

    printOkMsg "Host '${host_to_remove}' has been removed."

    local key_file_private="${SSH_DIR}/${host_to_remove}_id_ed25519"
    if [[ -f "$key_file_private" ]]; then
        if prompt_yes_no "Found associated key file. Remove it and its .pub file?" "y"; then
            rm -f "${key_file_private}" "${key_file_private}.pub"
            printOkMsg "Removed key files."
        fi
    fi
}

# Exports selected SSH host configurations to a file.
export_ssh_hosts() {
    printBanner "Export SSH Hosts"

    mapfile -t hosts < <(get_ssh_hosts)
    if [[ ${#hosts[@]} -eq 0 ]]; then
        printInfoMsg "No hosts found to export."
        return
    fi

    # The menu will show the actual host aliases for selection.
    # The "All" option is a feature of interactive_multi_select_menu.
    local menu_output
    menu_output=$(interactive_multi_select_menu "Select hosts to export (space to toggle, enter to confirm):" "All" "${hosts[@]}")
    if [[ $? -ne 0 ]]; then
        printInfoMsg "Export cancelled."
        return
    fi

    mapfile -t selected_indices < <(echo "$menu_output")

    if [[ ${#selected_indices[@]} -eq 0 ]]; then
        printInfoMsg "No hosts selected for export."
        return
    fi

    local -a hosts_to_export
    for index in "${selected_indices[@]}"; do
        # The menu options are "All", then hosts[0], hosts[1], ...
        # So index 1 from menu corresponds to hosts[0].
        if (( index > 0 )); then
            hosts_to_export+=("${hosts[index-1]}")
        fi
    done

    if [[ ${#hosts_to_export[@]} -eq 0 ]]; then
        printInfoMsg "No hosts selected for export."
        return
    fi

    local export_file
    prompt_for_input "Enter path for export file" export_file "ssh_hosts_export.conf"

    # Clear the file or create it
    > "$export_file"

    printInfoMsg "Exporting ${#hosts_to_export[@]} host(s)..."
    for host in "${hosts_to_export[@]}"; do
        # Get the block for the host and append it to the export file
        echo "" >> "$export_file" # Add a newline for separation
        _get_host_block_from_config "$host" "$SSH_CONFIG_PATH" >> "$export_file"
    done

    # Clean up potential leading newline from the first entry
    sed -i '1{/^$/d;}' "$export_file"

    printOkMsg "Successfully exported ${#hosts_to_export[@]} host(s) to ${C_L_BLUE}${export_file}${T_RESET}."
}

# Imports SSH host configurations from a file.
import_ssh_hosts() {
    printBanner "Import SSH Hosts"

    local import_file
    prompt_for_input "Enter path of file to import from" import_file

    if [[ ! -f "$import_file" ]]; then
        printErrMsg "Import file not found: ${import_file}"
        return 1
    fi

    # Get hosts from the import file
    local -a hosts_to_import
    mapfile -t hosts_to_import < <(awk '/^[Hh]ost / && $2 != "*" {for (i=2; i<=NF; i++) print $i}' "$import_file")

    if [[ ${#hosts_to_import[@]} -eq 0 ]]; then
        printInfoMsg "No valid 'Host' entries found in ${import_file}."
        return
    fi

    printInfoMsg "Found ${#hosts_to_import[@]} host(s) to import: ${C_L_CYAN}${hosts_to_import[*]}${T_RESET}"

    local imported_count=0 overwritten_count=0 skipped_count=0

    for host in "${hosts_to_import[@]}"; do
        local should_add=false
        if grep -q -E "^\s*Host\s+${host}\s*$" "$SSH_CONFIG_PATH"; then
            if prompt_yes_no "Host '${host}' already exists. Overwrite it?" "n"; then
                local temp_config; temp_config=$(_remove_host_block_from_config "$host")
                echo "$temp_config" | cat -s > "$SSH_CONFIG_PATH"
                ((overwritten_count++)); should_add=true
            else
                printInfoMsg "Skipping existing host '${host}'."; ((skipped_count++)); should_add=false
            fi
        else
            ((imported_count++)); should_add=true
        fi

        if [[ "$should_add" == "true" ]]; then
            echo "" >> "$SSH_CONFIG_PATH"; _get_host_block_from_config "$host" "$import_file" >> "$SSH_CONFIG_PATH"
        fi
    done

    local summary="Import complete. Added: ${imported_count}, Overwrote: ${overwritten_count}, Skipped: ${skipped_count}."
    printOkMsg "$summary"
}

# Tests the SSH connection to a selected server.
test_ssh_connection() {
    printBanner "Test SSH Connection"

    local host_to_test
    host_to_test=$(select_ssh_host "Select a host to test:")
    [[ $? -ne 0 ]] && return

    # -o BatchMode=yes: Never ask for passwords. Fails if one is needed.
    # -o ConnectTimeout=10: Fail if connection is not established in 10 seconds.
    # 'exit' is a simple command that immediately closes the connection.
    if run_with_spinner "Testing connection to '${host_to_test}'..." \
        ssh -o BatchMode=yes -o ConnectTimeout=10 "${host_to_test}" 'exit'
    then
        # remove the spinner output to reduce visual clutter
        clear_lines_up 1
        printOkMsg "Connection to '${host_to_test}' was ${BG_GREEN}${C_BLACK} successful ${T_RESET}"
    else
        # run_with_spinner prints the error details from ssh
        printInfoMsg "Check your SSH config, network, firewall rules, and ensure your public key is on the server."
    fi
}

# Backs up the SSH config file to a timestamped file.
backup_ssh_config() {
    printBanner "Backup SSH Config"

    local backup_dir="${SSH_DIR}/backups"
    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local backup_file="${backup_dir}/config_${timestamp}.bak"

    if run_with_spinner "Creating backup of ${SSH_CONFIG_PATH}..." \
        cp "$SSH_CONFIG_PATH" "$backup_file"
    then
        # The spinner already prints a success message. We can add more detail.
        printInfoMsg "Backup saved to: ${C_L_BLUE}${backup_file}${T_RESET}"
    else
        # The spinner will print the error from `cp`.
        printErrMsg "Failed to create backup."
    fi
}

# Helper to run a menu action, clearing the screen before and after,
# and pausing for the user to see the result.
run_menu_action() {
    local action_func="$1"
    shift # The rest of the arguments are for the action function
    clear
    # Call the function that was passed as an argument
    "$action_func" "$@"
    prompt_to_continue
    clear
}

# Main application loop.
main_loop() {
    #printf "\033[H\033[J" # Clear screen
    clear
    printBanner "SSH Manager"
    local -a menu_options=(
        "Connect to a server"
        "Test connection to a server"
        "Add a new server"
        "Edit a server's configuration"
        "Remove a server"
        "Copy an SSH key to a server"
        "Open SSH config in editor"
        "Backup SSH config"
        "Export hosts to a file"
        "Import hosts from a file"
        "Exit"
    )

    while true; do
        local selected_index
        selected_index=$(interactive_single_select_menu "What would you like to do?" "${menu_options[@]}")
        [[ $? -ne 0 ]] && { break; }

        case "${menu_options[$selected_index]}" in
        "Connect to a server")
            clear
            printBanner "Connect to a server"
            local selected_host
            selected_host=$(select_ssh_host "Select a host to connect to:")
            if [[ $? -eq 0 ]]; then
                # Use 'exec' to replace the current script process with the ssh client.
                # This ensures that after the ssh session ends, the script exits instead of returning to the menu.
                exec ssh "$selected_host"
            else
                clear
            fi
            ;;
        "Test connection to a server") run_menu_action test_ssh_connection ;;
        "Add a new server") run_menu_action add_ssh_host ;;
        "Edit a server's configuration") run_menu_action edit_ssh_host ;;
        "Remove a server") run_menu_action remove_ssh_host ;;
        "Copy an SSH key to a server") run_menu_action copy_ssh_id ;;
        "Open SSH config in editor")
            local editor="${EDITOR:-nvim}"
            if ! command -v "${editor}" &>/dev/null; then
                printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."
                prompt_to_continue
                clear
            else
                # printInfoMsg "Opening ${SSH_CONFIG_PATH} with '${editor}'..."
                "${editor}" "${SSH_CONFIG_PATH}"
                clear
            fi
            ;;
        "Export hosts to a file") run_menu_action export_ssh_hosts ;;
        "Import hosts from a file") run_menu_action import_ssh_hosts ;;
        "Backup SSH config") run_menu_action backup_ssh_config ;;
        "Exit") break ;;
        esac
    done

    printOkMsg "Goodbye!"    
}

main() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print_usage; exit 0
    fi

    prereq_checks "ssh" "ssh-keygen" "ssh-copy-id" "awk" "cat" "grep" "rm" "mktemp" "cp" "date"

    # Ensure SSH directory and config file exist with correct permissions
    mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
    touch "$SSH_CONFIG_PATH"; chmod 600 "$SSH_CONFIG_PATH"

    main_loop
}

main "$@"
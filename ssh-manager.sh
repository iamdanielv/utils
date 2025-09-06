#!/bin/bash
# An interactive TUI for managing and connecting to SSH hosts.

# The return value of a pipeline is the status of the last command to exit with a non-zero status.
set -o pipefail

# Source common utilities for colors and functions
# shellcheck source=./shared.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/shared.sh"; then
    echo "Error: Could not source shared.sh. Make sure it's in the same directory." >&2
    exit 1
fi

# --- Constants ---
SSH_DIR="${SSH_DIR:-${HOME}/.ssh}"
SSH_CONFIG_PATH="${SSH_CONFIG_PATH:-${SSH_DIR}/config}"

# --- Script Functions ---

print_usage() {
    printBanner "SSH Connection Manager"
    printMsg "An interactive TUI to manage and connect to SSH hosts in:\n ${C_L_BLUE}${SSH_CONFIG_PATH}${T_RESET}"
    printMsg "\n${T_ULINE}Usage:${T_RESET}"
    printMsg "  $(basename "$0") [option]"
    printMsg "\nThis script is fully interactive.\nRun without arguments to launch the main menu."
    printMsg "\n${T_ULINE}Options:${T_RESET}"
    printMsg "  ${C_L_BLUE}-c, --connect${T_RESET}  Go directly to host selection for connecting"
    printMsg "  ${C_L_BLUE}-a, --add${T_RESET}      Go directly to the 'Add a new server' menu"
    printMsg "  ${C_L_BLUE}-t, --test [host|all]${T_RESET}  Test connection to a host, all hosts, or show menu"
    printMsg "  ${C_L_BLUE}-h, --help${T_RESET}     Show this help message"
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
        # Call ssh -G once per host and parse all required values in a single awk command.
        # This is much more efficient than calling ssh -G four times for each host.
        local details
        details=$(ssh -G "$host_alias" 2>/dev/null | awk '
            # Map ssh -G output keys to the shell variable names we want to use.
            BEGIN {
                keys["hostname"] = "hostname"
                keys["user"] = "user"
                keys["identityfile"] = "identity_file"
                keys["port"] = "port"
            }
            # If the first field is one of our target keys, process it.
            $1 in keys {
                var_name = keys[$1]
                # Reconstruct the value, which might contain spaces.
                val = ""
                for (i = 2; i <= NF; i++) {
                    val = (val ? val " " : "") $i
                }
                # Print in KEY="VALUE" format for safe evaluation in the shell.
                printf "%s=\"%s\"\n", var_name, val
            }
        ')

        # Declare local variables and use eval to populate them from the awk output.
        # This is safe because the input is controlled (from ssh -G) and the awk script
        # only processes specific, known keys.
        local hostname user identity_file port
        eval "$details"
        # Clean up identity file path for display
        local key_info=""
        if [[ -n "$identity_file" ]]; then
            # Using #$HOME is safer than a simple string replacement
            key_info=" (${C_WHITE}${identity_file/#$HOME/\~}${T_RESET})"
        fi

        # Format port info, only show if not the default port 22
        local port_info=""
        if [[ -n "$port" && "$port" != "22" ]]; then
            port_info=":${C_L_YELLOW}${port}${T_RESET}"
        fi

        local formatted_string
        formatted_string=$(printf "%-20s - ${C_L_CYAN}%s@%s%s${T_RESET}%s" \
            "${host_alias}" \
            "${user:-?}" \
            "${hostname:-?}" \
            "${port_info}" \
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
    
    # By using the host_alias directly, ssh-copy-id will respect all settings
    # in the ~/.ssh/config file for that host, including User, HostName, and Port.
    # This is more robust than manually extracting values.
    printInfoMsg "Attempting to copy key to '${host_alias}'..."
    printMsg "You may be prompted for the password for the remote user."

    # ssh-copy-id is interactive, so we run it directly in the foreground.
    if ssh-copy-id -i "$key_file" "$host_alias"; then
        printOkMsg "Key successfully copied to '${host_alias}'."
    else
        printErrMsg "Failed to copy key to '${host_alias}'."
        printInfoMsg "Check your network connection, password, and server's SSH configuration."
        return 1
    fi
}

# Generates a new SSH key pair without associating it with a host.
generate_ssh_key() {
    printBanner "Generate New SSH Key"

    local -a key_types=("ed25519 (recommended)" "rsa (legacy, 4096 bits)")
    local selected_index
    selected_index=$(interactive_single_select_menu "Select the type of key to generate:" "${key_types[@]}")
    [[ $? -ne 0 ]] && { printInfoMsg "Operation cancelled."; return; }

    local key_type_selection="${key_types[$selected_index]}"
    local key_type="ed25519" # Default
    local key_bits_arg=""
    if [[ "$key_type_selection" == "rsa (legacy, 4096 bits)" ]]; then
        key_type="rsa"
        key_bits_arg="-b 4096"
    fi

    local key_filename
    prompt_for_input "Enter filename for the new key (in ${SSH_DIR})" key_filename "id_${key_type}" || return
    local full_key_path="${SSH_DIR}/${key_filename}"

    if [[ -f "$full_key_path" ]]; then
        if ! prompt_yes_no "Key file '${full_key_path}' already exists. Overwrite it?" "n"; then
            printInfoMsg "Key generation cancelled."
            return
        fi
    fi

    local key_comment
    prompt_for_input "Enter a comment for the key" key_comment "${USER}@$(hostname)" || return

    if run_with_spinner "Generating new ${key_type} key..." \
        ssh-keygen -t "${key_type}" ${key_bits_arg} -f "${full_key_path}" -N "" -C "${key_comment}"; then
        printInfoMsg "Key pair created:"
        printMsg "  Private key: ${C_L_BLUE}${full_key_path}${T_RESET}"
        printMsg "  Public key:  ${C_L_BLUE}${full_key_path}.pub${T_RESET}"
    else
        # run_with_spinner already prints the error details.
        printErrMsg "Failed to generate SSH key."
    fi
}

# An interactive prompt for user input that supports cancellation.
# It reads input character-by-character to provide a responsive feel
# and handles ESC for cancellation.
# Usage: prompt_for_input "Prompt text" "variable_name" ["default_value"] ["allow_empty"]
# Returns 0 on success (Enter), 1 on cancellation (ESC).
prompt_for_input() {
    local prompt_text="$1"
    local -n var_ref="$2" # Use nameref to assign to caller's variable
    local default_val="${3:-}"
    local allow_empty="${4:-false}"

    # Pre-fill the input string with the default value to allow editing/clearing it.
    local input_str="$default_val"
    local key

    while true; do
        # Draw the prompt and current input string, with the cursor visible at the end.
        clear_current_line >/dev/tty
        printMsgNoNewline "${T_QST_ICON} ${prompt_text}: ${C_L_CYAN}${input_str}${T_RESET}" >/dev/tty

        key=$(read_single_char </dev/tty)

        case "$key" in
            "$KEY_ENTER")
                # The final value is whatever is in the input buffer.
                # This allows the user to backspace to clear a default value.
                local final_input="$input_str"
                if [[ -n "$final_input" || "$allow_empty" == "true" ]]; then
                    var_ref="$final_input"
                    clear_current_line >/dev/tty
                    # Show the prompt again with the final selected value.
                    printMsg "${T_QST_ICON} ${prompt_text}: ${C_L_GREEN}${final_input}${T_RESET}"
                    return 0 # Success
                fi
                # If not valid, loop continues, waiting for more input or ESC.
                ;;
            "$KEY_ESC")
                clear_current_line >/dev/tty
                printMsg "${T_QST_ICON} ${prompt_text}:\n ${C_L_YELLOW}-- cancelled --${T_RESET}"
                return 1 # Cancelled
                ;;
            "$KEY_BACKSPACE")
                [[ -n "$input_str" ]] && input_str="${input_str%?}"
                ;;
            *)
                # Append single, printable characters. Ignore control sequences.
                (( ${#key} == 1 )) && [[ "$key" =~ [[:print:]] ]] && input_str+="$key"
                ;;
        esac
    done
}

# (Private) Prompts for a new, unique SSH host alias.
# It allows the user to re-enter the same alias when renaming, which is treated as a no-op.
# Uses a nameref to return the value.
# Usage: _prompt_for_unique_host_alias alias_var [prompt_text] [old_alias_to_allow]
# Returns 0 on success, 1 on cancellation.
_prompt_for_unique_host_alias() {
    local -n out_alias_var="$1"
    local prompt_text="${2:-Enter a short alias for the host}"
    local old_alias_to_allow="${3:-}"

    while true; do
        prompt_for_input "$prompt_text" out_alias_var || return 1

        # If renaming and the user entered the old name, it's a valid "no-op" choice.
        if [[ -n "$old_alias_to_allow" && "$out_alias_var" == "$old_alias_to_allow" ]]; then
            return 0
        fi

        # Check if host alias already exists in the main config file.
        if [[ -f "$SSH_CONFIG_PATH" ]] && grep -q -E "^\s*Host\s+${out_alias_var}\s*$" "$SSH_CONFIG_PATH"; then
            printErrMsg "Host alias '${out_alias_var}' already exists. Please choose another."
        else
            return 0 # Alias is unique, success
        fi
    done
}

# (Private) Prompts the user for the core details of a new SSH host.
# It handles validating the alias is unique and uses namerefs to return values.
# Usage: _prompt_for_host_details host_alias_var host_name_var user_var [default_hostname] [default_user]
# Returns 0 on success, 1 on cancellation.
_prompt_for_host_details() {
    local -n out_alias="$1"
    local -n out_hostname="$2"
    local -n out_user="$3"
    local -n out_port="$4"
    local default_hostname="${5:-}"
    local default_user="${6:-$USER}"
    local default_port="${7:-22}"

    _prompt_for_unique_host_alias out_alias "Enter a short alias for the host (e.g., 'prod-server')" || return 1
    prompt_for_input "Enter the HostName (IP address or FQDN)" out_hostname "$default_hostname" || return 1
    prompt_for_input "Enter the remote User" out_user "$default_user" || return 1
    prompt_for_input "Enter the Port" out_port "$default_port" || return 1

    return 0
}

# (Private) Handles the logic for generating a new dedicated key for a host.
# Returns the path to the new key via a nameref.
# Usage: _generate_and_get_dedicated_key identity_file_var host_alias user host_name
# Returns 0 on success, 1 on cancellation/failure.
_generate_and_get_dedicated_key() {
    local -n out_identity_file="$1"
    local host_alias="$2"
    local user="$3"
    local host_name="$4"

    local new_key_path="${SSH_DIR}/${host_alias}_id_ed25519"
    local should_generate=true
    if [[ -f "$new_key_path" ]]; then
        prompt_yes_no "Key file '${new_key_path}' already exists. Overwrite it?" "n"
        local overwrite_choice=$?
        if [[ $overwrite_choice -eq 1 ]]; then # No
            should_generate=false
            printInfoMsg "Using existing key file: ${new_key_path}"
        elif [[ $overwrite_choice -eq 2 ]]; then # Cancel
            return 1
        fi
    fi

    if [[ "$should_generate" == "true" ]]; then
        run_with_spinner "Generating new ed25519 key for ${host_alias}..." \
            ssh-keygen -t ed25519 -f "$new_key_path" -N "" -C "${user}@${host_name}" || return 1
    fi

    out_identity_file="$new_key_path"
    return 0
}

# (Private) Handles the logic for selecting an existing key.
# Returns the path to the selected key via a nameref.
# Usage: _select_and_get_existing_key identity_file_var
# Returns 0 on success, 1 on cancellation/failure.
_select_and_get_existing_key() {
    local -n out_identity_file="$1"
    local -a pub_keys
    mapfile -t pub_keys < <(find "$SSH_DIR" -maxdepth 1 -type f -name "*.pub")
    if [[ ${#pub_keys[@]} -eq 0 ]]; then
        printErrMsg "No existing SSH keys (.pub files) found in ${SSH_DIR}."
        return 1
    fi

    local -a private_key_paths
    for pub_key in "${pub_keys[@]}"; do private_key_paths+=("${pub_key%.pub}"); done

    local key_idx
    key_idx=$(interactive_single_select_menu "Select the private key to use:" "${private_key_paths[@]}") || return 1
    out_identity_file="${private_key_paths[$key_idx]}"
    return 0
}

# (Private) Manages the SSH key selection and creation process for a new host.
# It returns the path to the selected/created IdentityFile via a nameref.
# It also handles the post-creation action of copying the key to the server.
# Usage: _handle_ssh_key_for_new_host identity_file_var host_alias host_name user [cloned_host] [cloned_key_path]
# Returns 0 on success, 1 on cancellation/failure.
_get_identity_file_for_new_host() {
    local -n out_identity_file="$1"
    local host_alias="$2"
    local host_name="$3"
    local user="$4"
    local cloned_host="${5:-}"
    local cloned_key_path="${6:-}"

    out_identity_file="" # Default to no key

    local -a key_options=(
        "Generate a new dedicated key (ed25519) for this host"
        "Select an existing key"
        "Do not specify a key (use SSH defaults)"
    )

    if [[ -n "$cloned_key_path" ]]; then
        key_options=("Use same key as '${cloned_host}' (${cloned_key_path/#$HOME/\~})" "${key_options[@]}")
    fi

    local key_choice_idx
    key_choice_idx=$(interactive_single_select_menu "How do you want to handle the SSH key for this host?" "${key_options[@]}")
    if [[ $? -ne 0 ]]; then return 1; fi
    local selected_key_option="${key_options[$key_choice_idx]}"

    case "$selected_key_option" in
        "Use same key as "*) # Use a glob to match the dynamic part
            out_identity_file="$cloned_key_path"
            ;;
        "Generate a new dedicated key (ed25519) for this host")
            _generate_and_get_dedicated_key out_identity_file "$host_alias" "$user" "$host_name" || return 1
            ;;
        "Select an existing key")
            _select_and_get_existing_key out_identity_file || {
                # If it fails, provide a helpful message.
                printInfoMsg "You can generate a key from the main menu first."
                return 1
            }
            ;;
        "Do not specify a key (use SSH defaults)")
            # out_identity_file is already empty
            ;;
    esac
    return 0
}

# (Private) Appends a fully formed host block to the SSH config file.
# Usage: _append_host_to_config <alias> <hostname> <user> [identity_file]
_append_host_to_config() {
    local host_alias="$1"
    local host_name="$2"
    local user="$3"
    local port="$4"
    local identity_file="${5:-}"

    # Use a subshell and a here-document for cleaner block creation.
    (
        echo "" # Separator
        echo "Host ${host_alias}"
        echo "    HostName ${host_name}"
        echo "    User ${user}"
        if [[ -n "$port" && "$port" != "22" ]]; then
            echo "    Port ${port}"
        fi
        if [[ -n "$identity_file" ]]; then
            echo "    IdentityFile ${identity_file}"
            echo "    IdentitiesOnly yes"
        fi
    ) >> "$SSH_CONFIG_PATH"

    local key_msg=""
    if [[ -n "$identity_file" ]]; then
        key_msg=" with key ${identity_file/#$HOME/\~}"
    fi
    printOkMsg "Host '${host_alias}' added to ${SSH_CONFIG_PATH}${key_msg}."
}

# Prompts user for details and adds a new host to the SSH config.
add_ssh_host() {
    printBanner "Add New SSH Host"

    local host_alias host_name user port identity_file
    local default_hostname="" default_user="${USER}" default_port="22" default_identity_file=""
    local host_to_clone=""

    # --- Step 1: Choose to create from scratch or clone ---
    local -a add_options=("Create a new host from scratch" "Clone settings from an existing host")
    local add_choice_idx
    add_choice_idx=$(interactive_single_select_menu "How would you like to add the new host?" "${add_options[@]}")
    if [[ $? -ne 0 ]]; then
        printInfoMsg "Host creation cancelled."
        return
    fi

    if [[ "${add_options[$add_choice_idx]}" == "Clone settings from an existing host" ]]; then
        host_to_clone=$(select_ssh_host "Select a host to clone settings from:")
        if [[ $? -ne 0 ]]; then return; fi # select_ssh_host prints its own message

        printInfoMsg "Cloning settings from '${C_L_CYAN}${host_to_clone}${T_RESET}'."
        default_hostname=$(get_ssh_config_value "$host_to_clone" "HostName")
        default_user=$(get_ssh_config_value "$host_to_clone" "User")
        default_port=$(get_ssh_config_value "$host_to_clone" "Port")
        default_identity_file=$(get_ssh_config_value "$host_to_clone" "IdentityFile")
    fi

    # --- Step 2: Get host details ---
    if ! _prompt_for_host_details host_alias host_name user port "$default_hostname" "$default_user" "${default_port:-22}"; then
        # _prompt_for_host_details prints cancellation message
        return
    fi

    # --- Step 3: Handle SSH key ---
    if ! _get_identity_file_for_new_host identity_file "$host_alias" "$host_name" "$user" "$host_to_clone" "$default_identity_file"; then
        printInfoMsg "Host creation cancelled during key selection."
        return
    fi

    # --- Step 4: Write to config file FIRST ---
    # This ensures the host exists for subsequent actions like ssh-copy-id.
    _append_host_to_config "$host_alias" "$host_name" "$user" "$port" "$identity_file"

    # --- Step 3.5: Ask to copy the key (if one was selected/created) ---
    if [[ -n "$identity_file" ]]; then
        # Default to 'y' if a new key was generated, 'n' otherwise.
        local default_copy="n"
        [[ "${add_options[$add_choice_idx]}" == "Create a new host from scratch" ]] && default_copy="y"
        if prompt_yes_no "Do you want to copy the public key to the server now?" "$default_copy"; then
            copy_ssh_id_for_host "$host_alias" "${identity_file}.pub" # This will now work as the host exists
        fi
    fi

    # --- Step 5: Post-creation actions ---
    if prompt_yes_no "Do you want to test the connection to '${host_alias}' now?" "y"; then
        echo # Add a newline for spacing
        _test_connection_for_host "$host_alias"
    fi
}

# (Private) Generic function to process an SSH config file, filtering host blocks.
# It can either keep only the matching block or remove it and keep everything else.
# Usage: _process_ssh_config_blocks <target_host> <config_file> <mode>
#   mode: 'keep' - prints only the block matching the target_host.
#   mode: 'remove' - prints the entire file except for the matching block.
_process_ssh_config_blocks() {
    local target_host="$1"
    local config_file="$2"
    local mode="$3" # 'keep' or 'remove'

    if [[ "$mode" != "keep" && "$mode" != "remove" ]]; then
        printErrMsg "Invalid mode '${mode}' for _process_ssh_config_blocks" >&2
        return 1
    fi

    awk -v target_host="$target_host" -v mode="$mode" '
        # Flushes the buffered block based on whether it matches the target and the desired mode.
        function flush_block() {
            if (block != "") {
                if ((mode == "keep" && is_target_block) || (mode == "remove" && !is_target_block)) {
                    printf "%s\n", block
                }
            }
        }

        # Match a new Host block definition.
        /^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/ {
            flush_block() # Flush the previous block.

            # Reset state for the new block.
            block = $0
            is_target_block = 0

            # Check if this new block is the one we are looking for.
            line_content = $0
            sub(/^[ \t]*[Hh][Oo][Ss][Tt][ \t]+/, "", line_content)
            n = split(line_content, patterns, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                if (patterns[i] ~ /^#/) break
                if (patterns[i] == target_host) {
                    is_target_block = 1
                    break
                }
            }
            next
        }

        # For any other line (part of a block, a comment, or a blank line):
        {
            if (block != "") {
                block = block "\n" $0
            } else {
                # This is content before the first Host definition.
                # It is never a target block, so print it only in "remove" mode.
                if (mode == "remove") {
                    print $0
                }
            }
        }

        # At the end of the file, flush the last remaining block.
        END {
            flush_block()
        }
    ' "$config_file"
}

# (Private) Reads the SSH config and returns a new version with a specified host block removed.
# Usage:
#   local new_config
#   new_config=$(_remove_host_block_from_config "my-host")
#   echo "$new_config" > "$SSH_CONFIG_PATH"
_remove_host_block_from_config() {
    local host_to_remove="$1"
    _process_ssh_config_blocks "$host_to_remove" "$SSH_CONFIG_PATH" "remove"
}

# (Private) Reads an SSH config file and returns the block for a specific host.
# Usage:
#   local block
#   block=$(_get_host_block_from_config "my-host" "/path/to/config")
_get_host_block_from_config() {
    local host_to_find="$1"
    local config_file="$2"
    _process_ssh_config_blocks "$host_to_find" "$config_file" "keep"
}

# Edits an existing host in the SSH config.
edit_ssh_host() {
    printBanner "Edit SSH Host"

    local host_to_edit
    host_to_edit=$(select_ssh_host "Select a host to edit:")
    [[ $? -ne 0 ]] && return

    printInfoMsg "Editing configuration for: ${C_L_CYAN}${host_to_edit}${T_RESET}"
    printMsg "${C_L_GRAY}(Press Enter to keep the current value)${T_RESET}"

    # Get current values to use as defaults in prompts
    local current_hostname
    current_hostname=$(get_ssh_config_value "$host_to_edit" "HostName")
    local current_user current_port current_identityfile
    current_user=$(get_ssh_config_value "$host_to_edit" "User")
    current_port=$(get_ssh_config_value "$host_to_edit" "Port")
    current_identityfile=$(get_ssh_config_value "$host_to_edit" "IdentityFile")

    # Prompt for new values
    local new_hostname new_user new_port new_identityfile
    prompt_for_input "HostName" new_hostname "$current_hostname" || return
    prompt_for_input "User" new_user "$current_user" || return
    prompt_for_input "Port" new_port "${current_port:-22}" || return
    prompt_for_input "IdentityFile (optional, leave blank to remove)" new_identityfile "$current_identityfile" "true" || return

    # Check if any changes were actually made before rewriting the file.
    # This provides better feedback and avoids unnecessary file I/O.
    if [[ "$new_hostname" == "$current_hostname" && \
          "$new_user" == "$current_user" && \
          "$new_port" == "${current_port:-22}" && \
          "$new_identityfile" == "$current_identityfile" ]]; then
        printInfoMsg "No changes detected. Host configuration remains unchanged."
        return
    fi

    # Validate the IdentityFile path if one was provided.
    if [[ -n "$new_identityfile" ]]; then
        # Expand tilde (~) to the user's home directory for path validation.
        local expanded_identityfile="${new_identityfile/#\~/$HOME}"
        if [[ ! -f "$expanded_identityfile" ]]; then
            printErrMsg "The specified IdentityFile does not exist: ${new_identityfile}"
            return 1 # Return to the main menu
        fi
    fi

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
            if [[ -n "$new_port" && "$new_port" != "22" ]]; then
                echo "    Port ${new_port}"
            fi
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

# Allows advanced editing of a host's config block directly in $EDITOR.
edit_ssh_host_in_editor() {
    printBanner "Edit Host Block in Editor"

    local host_to_edit
    host_to_edit=$(select_ssh_host "Select a host to edit:")
    [[ $? -ne 0 ]] && return # select_ssh_host prints messages

    # Get the original block content
    local original_block
    original_block=$(_get_host_block_from_config "$host_to_edit" "$SSH_CONFIG_PATH")

    if [[ -z "$original_block" ]]; then
        printErrMsg "Could not find a configuration block for '${host_to_edit}'."
        return 1
    fi

    # Create a temporary file to hold the block for editing
    local temp_file
    temp_file=$(mktemp)
    # Ensure temp file is cleaned up on exit or interrupt
    trap 'rm -f "$temp_file"' RETURN

    echo "$original_block" > "$temp_file"

    # Determine the editor to use
    local editor="${EDITOR:-nvim}"
    if ! command -v "${editor}" &>/dev/null; then
        printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."
        return 1
    fi

    printInfoMsg "Opening '${host_to_edit}' in '${editor}'..."
    printInfoMsg "(Save and close the editor to apply changes,\n    or exit without saving to cancel)"
    # Give the user a moment to read the message before launching the editor.
    prompt_to_continue

    # clear out the instructions
    clear_lines_up 3
    # Open the temp file in the editor. This is a blocking call.
    "${editor}" "$temp_file"

    # Read the potentially modified content
    local new_block
    new_block=$(<"$temp_file")

    # Compare the new content with the original.
    if [[ "$new_block" == "$original_block" ]]; then
        printInfoMsg "No changes detected. Configuration for '${host_to_edit}' remains unchanged."
        return
    fi

    # Get the config content without the old host block and append the new one
    local config_without_host
    config_without_host=$(_remove_host_block_from_config "$host_to_edit")
    echo -e "${config_without_host}\n${new_block}" | cat -s > "$SSH_CONFIG_PATH"

    printOkMsg "Host '${host_to_edit}' has been updated from editor."
}

# Clones an existing SSH host configuration to a new alias.
clone_ssh_host() {
    printBanner "Clone SSH Host"

    local host_to_clone
    host_to_clone=$(select_ssh_host "Select a host to clone:")
    [[ $? -ne 0 ]] && return # select_ssh_host prints messages

    local new_alias
    _prompt_for_unique_host_alias new_alias "Enter the new alias for the cloned host" || return

    local original_block
    original_block=$(_get_host_block_from_config "$host_to_clone" "$SSH_CONFIG_PATH")

    if [[ -z "$original_block" ]]; then
        printErrMsg "Could not find configuration block for '${host_to_clone}'."
        return 1
    fi

    # Replace the original 'Host ...' line with the new one.
    # Use printf to avoid `echo` adding an extra newline before piping to sed.
    local new_block
    new_block=$(printf '%s' "$original_block" | sed -E "s/^[[:space:]]*[Hh]ost[[:space:]].*/Host ${new_alias}/")

    # Append the new block to the config file, ensuring separation.
    echo -e "\n${new_block}" >> "$SSH_CONFIG_PATH"

    printOkMsg "Host '${host_to_clone}' successfully cloned to '${new_alias}'."
}

# Renames an SSH host alias and optionally its associated key file.
rename_ssh_host() {
    printBanner "Rename SSH Host Alias"

    local host_to_rename
    host_to_rename=$(select_ssh_host "Select a host to rename:")
    [[ $? -ne 0 ]] && return # select_ssh_host prints messages

    local new_alias; new_alias="$host_to_rename" # Default to old name for the prompt
    _prompt_for_unique_host_alias new_alias "Enter the new alias for '${host_to_rename}'" "$host_to_rename" || return

    if [[ "$new_alias" == "$host_to_rename" ]]; then
        printInfoMsg "The new alias is the same as the old one. No changes made."
        return
    fi

    # --- Config Block Modification ---
    local original_block
    original_block=$(_get_host_block_from_config "$host_to_rename" "$SSH_CONFIG_PATH")
    if [[ -z "$original_block" ]]; then
        printErrMsg "Could not find configuration block for '${host_to_rename}'."
        return 1
    fi

    # Create a new block with the 'Host' line updated.
    local new_block
    new_block=$(printf '%s' "$original_block" | sed -E "s/^[[:space:]]*[Hh]ost[[:space:]].*/Host ${new_alias}/")

    # --- Key File Renaming Logic ---
    local old_key_path_convention="${SSH_DIR}/${host_to_rename}_id_ed25519"
    local new_key_path_convention="${SSH_DIR}/${new_alias}_id_ed25519"
    local current_identity_file; current_identity_file=$(get_ssh_config_value "$host_to_rename" "IdentityFile")
    local expanded_identity_file="${current_identity_file/#\~/$HOME}"

    # Check if a conventionally named key exists AND it's the one being used in the config.
    if [[ -f "$old_key_path_convention" && "$expanded_identity_file" == "$old_key_path_convention" ]]; then
        if prompt_yes_no "Found associated key file. Rename it to match the new alias?" "y"; then
            if [[ -f "$new_key_path_convention" ]]; then
                printErrMsg "Cannot rename key: target file '${new_key_path_convention}' already exists."
            elif run_with_spinner "Renaming key files..." mv "$old_key_path_convention" "$new_key_path_convention" && mv "${old_key_path_convention}.pub" "${new_key_path_convention}.pub"; then
                # Update the IdentityFile path in the new config block.
                new_block=$(printf '%s' "$new_block" | sed -E "s|([[:space:]]*IdentityFile[[:space:]]+).*|\1${new_key_path_convention}|")
            else
                printErrMsg "Failed to rename key files. The host alias was not changed."
                return 1 # Abort the whole operation
            fi
        fi
    fi

    # --- Finalize Config Update ---
    local config_without_host; config_without_host=$(_remove_host_block_from_config "$host_to_rename")
    echo -e "${config_without_host}\n${new_block}" | cat -s > "$SSH_CONFIG_PATH"
    printOkMsg "Host '${host_to_rename}' successfully renamed to '${new_alias}'."
}

# (Private) Checks for and offers to remove an orphaned key file.
# An orphaned key is one that is no longer referenced by any host in the SSH config.
# This is typically called after a host has been removed from the config.
# Usage: _cleanup_orphaned_key <path_to_key_file>
_cleanup_orphaned_key() {
    local key_file_path="$1"

    # 1. If no key file was associated with the host, there's nothing to do.
    if [[ -z "$key_file_path" ]]; then
        return
    fi

    # 2. Expand tilde to full path for checks.
    local expanded_key_path="${key_file_path/#\~/$HOME}"

    # 3. Check if the key file actually exists.
    if [[ ! -f "$expanded_key_path" ]]; then
        return
    fi

    # 4. Check if any other host in the *current* config uses this key.
    mapfile -t remaining_hosts < <(get_ssh_hosts)
    for host in "${remaining_hosts[@]}"; do
        local host_key_file; host_key_file=$(get_ssh_config_value "$host" "IdentityFile")
        local expanded_host_key_file="${host_key_file/#\~/$HOME}"

        if [[ "$expanded_host_key_file" == "$expanded_key_path" ]]; then
            printInfoMsg "The key '${key_file_path}' is still in use by host '${host}'. It will not be removed."
            return # Key is in use, so we're done.
        fi
    done

    # 5. If we get here, the key is not used by any other host. Prompt for deletion.
    if prompt_yes_no "The key '${key_file_path}' is no longer referenced by any host. Remove it and its .pub file?" "n"; then
        rm -f "${expanded_key_path}" "${expanded_key_path}.pub"
        printOkMsg "Removed key files."
    fi
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

    # Get the IdentityFile path *before* removing the host from the config.
    local identity_file_to_check
    identity_file_to_check=$(get_ssh_config_value "$host_to_remove" "IdentityFile")

    # Get the config content without the specified host block
    local new_config_content
    new_config_content=$(_remove_host_block_from_config "$host_to_remove")

    # Overwrite the config file with the new content, squeezing blank lines
    echo "$new_config_content" | cat -s > "$SSH_CONFIG_PATH"

    printOkMsg "Host '${host_to_remove}' has been removed."

    # Pass the actual key file path to the cleanup function.
    _cleanup_orphaned_key "$identity_file_to_check"
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
    true > "$export_file"

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
            prompt_yes_no "Host '${host}' already exists. Overwrite it?" "n"
            local choice=$?
            case $choice in
                0) # Yes
                    # Atomically replace the host block
                    local config_without_host; config_without_host=$(_remove_host_block_from_config "$host")
                    local new_block; new_block=$(_get_host_block_from_config "$host" "$import_file")
                    echo -e "${config_without_host}\n${new_block}" | cat -s > "$SSH_CONFIG_PATH"
                    ((overwritten_count++))
                    ;;
                1) # No
                    printInfoMsg "Skipping existing host '${host}'."; ((skipped_count++))
                    ;;
                2) # Cancel
                    printInfoMsg "Import operation cancelled by user."
                    # Break out of the for loop
                    break
                    ;;
            esac
        else
            # Host is new, so append it.
            echo "" >> "$SSH_CONFIG_PATH"; _get_host_block_from_config "$host" "$import_file" >> "$SSH_CONFIG_PATH"
            ((imported_count++))
        fi
    done

    local summary="Import complete. Added: ${imported_count}, Overwrote: ${overwritten_count}, Skipped: ${skipped_count}."
    printOkMsg "$summary"
}

# (Private) Helper to test connection to a specific host using BatchMode.
# Usage: _test_connection_for_host <host_alias>
_test_connection_for_host() {
    local host_to_test="$1"
    # -o BatchMode=yes: Never ask for passwords. Fails if one is needed.
    # -o ConnectTimeout=10: Fail if connection is not established in 10 seconds.
    # 'exit' is a simple command that immediately closes the connection.
    if run_with_spinner "Testing connection to '${host_to_test}'..." \
        ssh -o BatchMode=yes -o ConnectTimeout=10 "${host_to_test}" 'exit'
    then
        # remove the spinner output to reduce visual clutter
        clear_lines_up 1
        printOkMsg "Connection to '${host_to_test}' was ${BG_GREEN}${C_BLACK} successful ${T_RESET}"
        return 0
    else
        # run_with_spinner prints the error details from ssh
        printInfoMsg "Check your SSH config, network, firewall rules, and ensure your public key is on the server."
        return 1
    fi
}

# Tests the SSH connection to a selected server.
test_ssh_connection() {
    printBanner "Test SSH Connection"

    local host_to_test
    host_to_test=$(select_ssh_host "Select a host to test:")
    [[ $? -ne 0 ]] && return

    _test_connection_for_host "$host_to_test"
}

# (Private) The actual test logic for a single host, run in the background.
# It writes its result to a file in a temporary directory.
# Usage: _test_single_host_in_background <host> <result_dir>
_test_single_host_in_background() {
    local host_to_test="$1"
    local result_dir="$2"
    # The result file is named after the host, with slashes replaced to be safe.
    local result_file="${result_dir}/${host_to_test//\//_}"

    if ssh -o BatchMode=yes -o ConnectTimeout=10 "${host_to_test}" 'exit' &>/dev/null; then
        echo "success" > "$result_file"
    else
        # Capture the error message from SSH for later display.
        local error_output
        error_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${host_to_test}" 'exit' 2>&1)
        # If the file is empty (e.g., timeout), write a generic error.
        if [[ -z "$error_output" ]]; then
            echo "Connection timed out or failed without error message." > "$result_file"
        else
            echo "$error_output" > "$result_file"
        fi
    fi
}

# Tests all configured SSH hosts in parallel.
test_all_ssh_connections() {
    printBanner "Test All SSH Connections"

    mapfile -t hosts < <(get_ssh_hosts)
    if [[ ${#hosts[@]} -eq 0 ]]; then
        printInfoMsg "No hosts found in your SSH config file to test."
        return
    fi

    local result_dir
    result_dir=$(mktemp -d)
    # Ensure temp directory is cleaned up on exit or interrupt.
    trap 'rm -rf "$result_dir"' RETURN INT TERM

    local -a pids
    printInfoMsg "Starting tests for ${#hosts[@]} hosts in parallel..."
    for host in "${hosts[@]}"; do
        # Run the test for each host in the background.
        _test_single_host_in_background "$host" "$result_dir" &
        pids+=($!)
    done

    # Wait for all background jobs to complete, with a spinner.
    wait_for_pids_with_spinner "Running all connection tests" "${pids[@]}"

    # --- Print Summary ---
    printMsg "\n${T_ULINE}Test Results:${T_RESET}"
    local success_count=0
    local failure_count=0

    for host in "${hosts[@]}"; do
        local result_file="${result_dir}/${host//\//_}"
        local result
        result=$(<"$result_file")

        if [[ "$result" == "success" ]]; then
            ((success_count++))
            printOkMsg "Connection to '${host}' was ${BG_GREEN}${C_BLACK} successful ${T_RESET}"
        else
            ((failure_count++))
            printErrMsg "${host}"
            # Indent the error message for readability.
            while IFS= read -r line; do
                printMsg "    ${C_GRAY}${line}${T_RESET}"
            done <<< "$result"
        fi
    done

    # Final summary line
    echo
    local summary_msg
    if (( failure_count > 0 )); then
        summary_msg="Summary: ${C_L_GREEN}${success_count} successful${T_RESET}, ${C_L_RED}${failure_count} failed${T_RESET}."
        printErrMsg "$summary_msg"
    else
        summary_msg="Summary: ${C_L_GREEN}${success_count} successful${T_RESET}, ${C_GRAY}${failure_count} failed${T_RESET}."
        printOkMsg "$summary_msg"
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

# --- Main Menu Sub-loops ---

# (Private) Generic function to display and handle a submenu loop.
# It takes a banner title, an array of ordered options, and a map of options to actions.
# Usage: _run_submenu <banner_title> <ordered_options_array_name> <actions_map_name>
_run_submenu() {
    local banner_title="$1"
    local -n options_ref="$2"
    local -n actions_ref="$3"

    # Add the 'Back' option to the list for display
    local -a menu_options=("${options_ref[@]}" "Back to main menu")

    while true; do
        clear
        printBanner "$banner_title"

        local selected_index
        selected_index=$(interactive_single_select_menu "Select an action:" "${menu_options[@]}")
        [[ $? -ne 0 ]] && break # ESC/q from menu returns to the previous menu

        local selected_option="${menu_options[$selected_index]}"

        if [[ "$selected_option" == "Back to main menu" ]]; then
            break
        fi

        # Get the action from the map.
        local action="${actions_ref[$selected_option]}"

        # Handle special actions identified by a "SPECIAL_" prefix.
        if [[ "$action" == "SPECIAL_CONNECT" ]]; then
            clear
            printBanner "Connect to a server"
            local selected_host
            selected_host=$(select_ssh_host "Select a host to connect to:")
            if [[ $? -eq 0 ]]; then
                # Replace the script process with the ssh client.
                exec ssh "$selected_host"
            fi
            # If connection is cancelled, the loop continues.
        elif [[ "$action" == "SPECIAL_EDIT_CONFIG" ]]; then
            local editor="${EDITOR:-nvim}"
            if ! command -v "${editor}" &>/dev/null; then
                printErrMsg "Editor '${editor}' not found. Please set the EDITOR environment variable."
                prompt_to_continue
            else
                "${editor}" "${SSH_CONFIG_PATH}"
            fi
        else
            # This is the standard case: a function name to be passed to run_menu_action.
            if [[ -n "$action" ]]; then
                run_menu_action "$action"
            else
                printErrMsg "Internal error: No action defined for '${selected_option}'."
                prompt_to_continue
            fi
        fi
    done
}

server_menu() {
    local -a ordered_options=(
        "Connect to a server"
        "Test connection to a single server"
        "Test connection to ALL servers"
        "Add a new server"
        "Edit a server's configuration"
        "Remove a server"
    )
    local -A actions_map=(
        ["Connect to a server"]="SPECIAL_CONNECT"
        ["Test connection to a single server"]="test_ssh_connection"
        ["Test connection to ALL servers"]="test_all_ssh_connections"
        ["Add a new server"]="add_ssh_host"
        ["Edit a server's configuration"]="edit_ssh_host"
        ["Remove a server"]="remove_ssh_host"
    )
    _run_submenu "Server Management" ordered_options actions_map
}

key_menu() {
    local -a ordered_options=(
        "Copy an SSH key to a server"
        "Generate a new SSH key"
    )
    local -A actions_map=(
        ["Copy an SSH key to a server"]="copy_ssh_id"
        ["Generate a new SSH key"]="generate_ssh_key"
    )
    _run_submenu "Key Management" ordered_options actions_map
}

advanced_menu() {
    local -a ordered_options=(
        "Open SSH config in editor"
        "Edit host block in editor"
        "Rename a host alias"
        "Clone an existing host"
        "Backup SSH config"
        "Export hosts to a file"
        "Import hosts from a file"
    )
    local -A actions_map=(
        ["Open SSH config in editor"]="SPECIAL_EDIT_CONFIG"
        ["Edit host block in editor"]="edit_ssh_host_in_editor"
        ["Rename a host alias"]="rename_ssh_host"
        ["Clone an existing host"]="clone_ssh_host"
        ["Backup SSH config"]="backup_ssh_config"
        ["Export hosts to a file"]="export_ssh_hosts"
        ["Import hosts from a file"]="import_ssh_hosts"
    )
    _run_submenu "Advanced Tools" ordered_options actions_map
}

# Bypasses the main menu and goes directly to the host selection for a direct connection.
direct_connect() {
    local selected_host
    selected_host=$(select_ssh_host "Select a host to connect to:")
    if [[ $? -eq 0 ]]; then
        # Replace the script process with the ssh client.
        exec ssh "$selected_host"
    fi
    # If selection is cancelled, the script will just exit.
    # select_ssh_host prints a cancellation message, so we exit with a non-zero status
    # to indicate the requested action was not completed.
    exit 1
}

# Bypasses the main menu and goes directly to testing connections.
# Handles interactive selection, a specific host, or all hosts.
direct_test() {
    local target="$1"

    if [[ -z "$target" ]]; then
        # No target specified, run interactive selection.
        # This function already has a banner, so we just call it.
        test_ssh_connection
        return
    fi

    if [[ "$target" == "all" ]]; then
        # Target is 'all', test all connections.
        test_all_ssh_connections
        return
    fi

    # Target is a specific host. First, validate it exists.
    local host_exists=false
    while IFS= read -r host; do
        if [[ "$host" == "$target" ]]; then
            host_exists=true
            break
        fi
    done < <(get_ssh_hosts)

    if [[ "$host_exists" == "true" ]]; then
        printBanner "Test SSH Connection"
        _test_connection_for_host "$target"
    else
        printErrMsg "Host '${target}' not found in your SSH config."
        return 1
    fi
}

# (Private) Ensures prerequisites are met and SSH directory/config are set up.
# Usage: _setup_environment "cmd1" "cmd2" ...
_setup_environment() {
    prereq_checks "$@"
    mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
    touch "$SSH_CONFIG_PATH"; chmod 600 "$SSH_CONFIG_PATH"
}

# Main application loop.
main_loop() {
    while true; do
        clear
        printBanner "SSH Manager"
        local -a menu_options=(
            "Server Management"
            "Key Management"
            "Advanced Tools"
            "Exit"
        )

        local selected_index
        selected_index=$(interactive_single_select_menu "What would you like to do?" "${menu_options[@]}")
        [[ $? -ne 0 ]] && { break; }

        case "${menu_options[$selected_index]}" in
        "Server Management") server_menu ;;
        "Key Management") key_menu ;;
        "Advanced Tools") advanced_menu ;;
        "Exit") break ;;
        esac
    done

    clear
    printOkMsg "Goodbye!"
}

main() {
    # Handle flags first
    if [[ $# -gt 0 ]]; then
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -a|--add)
                # Prereqs for add mode
                _setup_environment "ssh" "ssh-keygen" "ssh-copy-id" "awk" "grep"
                # The add_ssh_host function is fully interactive and self-contained.
                add_ssh_host
                exit 0
                ;;
            -c|--connect | -t|--test)
                # Prereqs for connect and test modes are the same
                _setup_environment "ssh" "awk" "grep"
                if [[ "$1" == "-c" || "$1" == "--connect" ]]; then
                    direct_connect
                    # direct_connect either execs or exits, so we shouldn't get here.
                    exit 1
                else
                    # The second argument ($2) is the target for the test.
                    direct_test "$2"
                    exit $?
                fi
                ;;
            *)
                print_usage
                echo
                printErrMsg "Unknown option: $1"
                exit 1
                ;;
        esac
    fi

    # Default interactive mode (no flags)
    _setup_environment "ssh" "ssh-keygen" "ssh-copy-id" "awk" "cat" "grep" "rm" "mktemp" "cp" "date"

    main_loop
}

# This block will only run when the script is executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
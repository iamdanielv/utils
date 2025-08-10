#!/bin/bash
export C_RED='\e[31m'
export C_GREEN='\e[32m'
export C_YELLOW='\e[33m'
export C_BLUE='\e[34m'
export C_MAGENTA='\e[35m'
export C_CYAN='\e[36m'
export C_WHITE='\e[37m'
export C_GRAY='\e[30;1m'
export C_L_RED='\e[31;1m'
export C_L_GREEN='\e[32;1m'
export C_L_YELLOW='\e[33;1m'
export C_L_BLUE='\e[34;1m'
export C_L_MAGENTA='\e[35;1m'
export C_L_CYAN='\e[36;1m'
export C_L_WHITE='\e[37;1m'

# Background Colors
export BG_RED='\e[41;1m'
export BG_GREEN='\e[42;1m'
export BG_YELLOW='\e[43;1m'
export BG_BLUE='\e[44;1m'

# Text Colors
export C_BLACK='\e[30;1m'

export T_RESET='\e[0m'
export T_BOLD='\e[1m'
export T_ULINE='\e[4m'

export T_ERR="${T_BOLD}\e[31;1m"
export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
export T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"

export DIV="-------------------------------------------------------------------------------"

function printMsg() {
  echo -e "${1}"
}

function printMsgNoNewline() {
  echo -n -e "${1}"
}

function printDatedMsgNoNewLine() {
  echo -n -e "$(getPrettyDate) ${1}"
}

function printErrMsg() {
  printMsg "${T_ERR_ICON}${T_ERR} ${1} ${T_RESET}"
}

function printOkMsg() {
  printMsg "${T_OK_ICON} ${1}${T_RESET}"
}

function printInfoMsg() {
  printMsg "${T_INFO_ICON} ${1}${T_RESET}"
}

function printWarnMsg() {
  printMsg "${T_WARN_ICON} ${1}${T_RESET}"
}

function getFormattedDate() {
  date +"%Y-%m-%d %I:%M:%S"
}

function getPrettyDate() {
  echo "${C_BLUE}$(getFormattedDate)${T_RESET}"
}

function printBanner() {
  printMsg "${C_BLUE}${DIV}"
  printMsg " ${1}"
  printMsg "${DIV}${T_RESET}"
}

# Clears the current line and returns the cursor to the start.
clear_current_line() {
    # \e[2K: clear entire line
    # \r: move cursor to beginning of the line
    echo -ne "\e[2K\r"
}

# Clears a specified number of lines above the current cursor position.
# Usage: clear_lines_up [number_of_lines]
clear_lines_up() {
    local lines=${1:-1} # Default to 1 line if no argument is provided
    for ((i=0; i<lines; i++)); do
        # \e[1A: move cursor up one line
        # \e[2K: clear entire line
        echo -ne "\e[1A\e[2K"
    done
    echo -ne "\r" # Move cursor to the beginning of the line
}

# --- Error Handling & Traps ---

# Centralized error handler function.
# This function is triggered by the 'trap' command on any error when 'set -e' is active.
script_error_handler() {
    local exit_code=$? # Capture the exit code immediately!
    trap - ERR # Disable the trap to prevent recursion if the handler itself fails.
    local line_number=$1
    local command="$2"
    # BASH_SOURCE[1] is the path to the script that sourced this file.
    local script_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
    local script_name
    script_name=$(basename "$script_path")

    echo # Add a newline for better formatting before the error.
    printErrMsg "A fatal error occurred."
    printMsg "    Script:     ${C_L_BLUE}${script_name}${T_RESET}"
    printMsg "    Line:       ${C_L_YELLOW}${line_number}${T_RESET}"
    printMsg "    Command:    ${C_L_CYAN}${command}${T_RESET}"
    printMsg "    Exit Code:  ${C_RED}${exit_code}${T_RESET}"
    echo
}

# Function to handle Ctrl+C (SIGINT)
script_interrupt_handler() {
    trap - INT # Disable the trap to prevent recursion.
    echo # Add a newline for better formatting.
    printMsg "${T_WARN_ICON} ${C_L_YELLOW}Operation cancelled by user.${T_RESET}"
    # Exit with a status code indicating cancellation (130 is common for Ctrl+C).
    exit 130
}

# Set the trap. This will call our handler function whenever a command fails.
# The arguments passed to the handler are the line number and the command that failed.
trap 'script_error_handler $LINENO "$BASH_COMMAND"' ERR
trap 'script_interrupt_handler' INT

# --- Prerequisite & Sanity Checks ---

# Checks for command-line tools
# Exits with an error if any of the specified commands are not found.
# Usage: prereq_checks "command1" "command2" "..."
prereq_checks() {
    local missing_commands=()
    printMsgNoNewline "${T_INFO_ICON} Running prereq checks"
    for cmd in "$@"; do
        echo -n "${C_L_BLUE}.${T_RESET}"
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    echo # Newline after the dots

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        clear_lines_up 1
        printErrMsg "Prerequisite checks failed. Missing commands:"
        for cmd in "${missing_commands[@]}"; do
            printMsg "    - ${C_L_YELLOW}${cmd}${T_RESET}"
        done
        printMsg "${T_INFO_ICON} Please install the missing commands and try again."
        exit 1
    fi
    clear_lines_up 1
}

# Gets the correct Docker Compose command ('docker compose' or 'docker-compose').
# Assumes prerequisites have been checked by check_docker_prerequisites.
# Usage:
#   local compose_cmd
#   compose_cmd=$(get_docker_compose_cmd)
#   $compose_cmd up -d
get_docker_compose_cmd() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        echo "docker compose"
    elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
    else
        # This case should not be reached if check_docker_prerequisites was called.
        printErrMsg "Could not determine Docker Compose command." >&2
        exit 1
    fi
}

# Prompts the user with a Yes/No question and returns an exit code.
# Usage:
#   if prompt_yes_no "Do you want to proceed?"; then
#       # User said Yes
#   else
#       # User said No
#   fi
#   if prompt_yes_no "Do you want to proceed?" "y"; then
#       # User said Yes (or pressed Enter for default Yes)
#   else
#       # User said No (or pressed Enter for default No)
#   fi
# Arguments:
#   $1 - The question to ask the user.
#   $2 - The default answer ('y' or 'n'). Optional.
# Returns:
#   0 (success) if the user answers Yes (or default is 'y' and user presses Enter).
#   1 (failure) if the user answers No (or default is 'n' and user presses Enter).
prompt_yes_no() {
    local question="$1"
    local default_answer="${2:-}" # Optional second argument
    local prompt_suffix
    local answer

    # Determine the prompt suffix based on the default
    if [[ "$default_answer" == "y" ]]; then
        prompt_suffix="(Y/n)"
    elif [[ "$default_answer" == "n" ]]; then
        prompt_suffix="(y/N)"
    else
        prompt_suffix="(y/n)"
    fi

    while true; do
        # The -r option to read prevents backslash interpretation.
        read -p "$(echo -e "${T_QST_ICON} ${question} ${prompt_suffix} ")" -r answer

        # If the answer is empty, use the default
        if [[ -z "$answer" ]]; then
            answer="$default_answer"
        fi

        case "$answer" in
            [Yy] | [Yy][Ee][Ss])
                #echo # Add a newline for cleaner output after the prompt.
                clear_lines_up 1
                return 0
                ;;
            [Nn] | [Nn][Oo])
                #echo # Add a newline for cleaner output after the prompt.
                clear_lines_up 1
                return 1
                ;;
            *)
                # We need to move the cursor up one line to overwrite the invalid prompt.
                #echo -e "\e[1A\e[2K\r"
                clear_lines_up 1
                printErrMsg "Invalid input. Please enter 'y' or 'n'."
                ;;
        esac
    done
}

# Ensures the script is running from its own directory.
# This is useful for scripts that need to find relative files (e.g., docker-compose.yml).
# It uses BASH_SOURCE[1] to get the path of the calling script.
ensure_script_dir() {
    # BASH_SOURCE[1] is the path to the calling script.
    # This is more robust than passing BASH_SOURCE[0] as an argument.
    local SCRIPT_DIR
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[1]}" )" &> /dev/null && pwd )
    if [[ "$PWD" != "$SCRIPT_DIR" ]]; then
        printMsg "${T_INFO_ICON} Changing to script directory: ${C_L_BLUE}${SCRIPT_DIR}${T_RESET}"
        cd "$SCRIPT_DIR"
    fi
}

# Sources the project's .env file if it exists.
# This is intended for scripts in the project root that need to access
# configuration defined in an .env file
load_project_env() {
    # BASH_SOURCE[1] is the path to the script that called this function.
    local SCRIPT_DIR
    SCRIPT_DIR=$(dirname -- "${BASH_SOURCE[1]}")
    local ENV_FILE="${SCRIPT_DIR}/.env"

    if [[ -f "$ENV_FILE" ]]; then
        printMsg "${T_INFO_ICON} Sourcing configuration from ${C_L_BLUE}openwebui/.env${T_RESET}"
        set -a
        # shellcheck source=/dev/null
        source "$ENV_FILE"
        set +a
    fi
}

# Checks if the script is run as root. If not, it prints a message
# and re-executes the script with sudo.
# Usage: ensure_root "Reason why root is needed." "$@"
ensure_root() {
    local reason_msg="$1"
    shift # The rest of "$@" are the original script arguments.
    if [[ $EUID -ne 0 ]]; then
        printMsg "${T_INFO_ICON} ${reason_msg}"
        #printMsg "    ${C_L_BLUE}Attempting to re-run with sudo...${T_RESET}"
        exec sudo bash "${BASH_SOURCE[1]}" "$@"
    fi
}

# Helper to show systemd logs and exit on failure.
show_logs_and_exit() {
    local message="$1"
    printErrMsg "$message"
    # Check if journalctl is available before trying to use it
    if command -v journalctl &> /dev/null; then
        printMsg "    ${T_INFO_ICON} Preview of system log:"
        # Indent the journalctl output for readability
        journalctl -u ollama.service -n 10 --no-pager | sed 's/^/    /'
    else
        printMsg "    ${T_WARN_ICON} 'journalctl' not found. Cannot display logs."
    fi
    exit 1
}

# Polls a given URL until it gets a successful HTTP response or times out.
# Usage: poll_service <url> <service_name> [timeout_seconds]
poll_service() {
    local url="$1"
    local service_name="$2"
    # The number of tries is based on the timeout in seconds.
    # We poll once per second.
    local tries=${3:-10} # Default to 10 tries (10 seconds)

    local desc="Waiting for ${service_name} to respond at ${url}"

    # We need to run the loop in a subshell so that `run_with_spinner` can treat it
    # as a single command. The subshell will exit with 0 on success and 1 on failure.
    # We pass 'url' and 'tries' as arguments to the subshell to avoid quoting issues.
    if run_with_spinner "${desc}" bash -c '
        url="$1"
        tries="$2"
        for ((j=0; j<tries; j++)); do
            # Use a short connect timeout for each attempt
            if curl --silent --fail --head --connect-timeout 2 "$url" &>/dev/null; then
                exit 0 # Success
            fi
            sleep 1
        done
        exit 1 # Failure
    ' -- "$url" "$tries"; then
        clear_lines_up 1
        return 0
    else
        printErrMsg "${service_name} is not responding at ${url}"
        return 1
    fi
}

# Checks if an endpoint is responsive without writing to terminal
# Returns 0 on success, 1 on failure.
# Usage: check_endpoint_status <url> [timeout_seconds]
check_endpoint_status() {
    local url="$1"
    local timeout=${2:-5} # A shorter default timeout is fine for a status check.
    # Use --connect-timeout to fail fast if the port isn't open.
    # Use --max-time for the total operation.
    if curl --silent --fail --head --connect-timeout 2 --max-time "$timeout" "$url" &>/dev/null; then
        return 0 # Success
    else
        return 1 # Failure
    fi
}

# Cached check to see if this is a systemd-based system.
# The result is stored in a global variable to avoid repeated checks.
# Returns 0 if systemd, 1 otherwise.
_is_systemd_system() {
    # If the check has been run, return the cached result.
    if [[ -n "$_IS_SYSTEMD" ]]; then
        return "$_IS_SYSTEMD"
    fi

    # Check for the presence of systemctl and that systemd is the init process.
    # `is-system-running` can fail on a "degraded" system, which is still usable.
    # Checking for the /run/systemd/system directory is a more reliable way to detect systemd.
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        _IS_SYSTEMD=0 # true
    else
        _IS_SYSTEMD=1 # false
    fi
    return "$_IS_SYSTEMD"
}

# Checks if a given service is known to systemd.
# Assumes _is_systemd_system() has been checked.
# Usage: _is_systemd_service_known <service_name>
# Returns 0 if found, 1 otherwise.
_is_systemd_service_known() {
    local service_name="$1"
    # 'systemctl cat' is a direct way to check if a service exists
    # It will return a non-zero exit code if the service doesn't exist.
    # We redirect stdout and stderr to /dev/null to suppress all output.
    if systemctl cat "${service_name}" &>/dev/null; then
        return 0 # Found
    else
        return 1 # Not found
    fi
}

# Public-facing check if a given systemd service exists.
# Usage: check_systemd_service_exists <service_name>
# Returns 0 if it exists, 1 otherwise.
check_systemd_service_exists() {
    local service_name="$1"
    if ! _is_systemd_system || ! _is_systemd_service_known "${service_name}"; then
        return 1
    fi
    return 0
}

# A function to display a spinner while a command runs in the background.
# It detects if it's running in an interactive terminal and disables the
# spinner animation if it's not, falling back to simpler output.
# Usage: run_with_spinner "Description of task..." "command_to_run" "arg1" "arg2" ...
# The command's stdout and stderr will be captured.
# The function returns the exit code of the command.
# The captured stdout is stored in the global variable SPINNER_OUTPUT.
export SPINNER_OUTPUT=""
run_with_spinner() {
    local desc="$1"
    shift
    local cmd=("$@")
    local temp_output_file
    temp_output_file=$(mktemp)

    # --- Non-Interactive Mode ---
    # If not in an interactive terminal (e.g., in a script or CI/CD),
    # run the command without the spinner animation for cleaner logs.
    if [[ ! -t 1 ]]; then
        printMsgNoNewline "    ${T_INFO_ICON} ${desc}... "
        # Run the command in the foreground, capturing its output.
        if SPINNER_OUTPUT=$("${cmd[@]}" 2>&1); then
            # Using echo -e to process potential backspaces from the previous line
            echo -e "${C_L_GREEN}Done.${T_RESET}"
            rm "$temp_output_file"
            return 0
        else
            local exit_code=$?
            echo -e "${C_RED}Failed.${T_RESET}"
            rm "$temp_output_file"
            # The error message will be printed by the calling context if needed
            # based on the non-zero exit code.
            return $exit_code
        fi
    fi

    # --- Interactive Mode ---
    local spinner_chars="⣾⣷⣯⣟⡿⢿⣻⣽"
    local i=0

    # Run the command in the background, redirecting its output to the temp file.
    "${cmd[@]}" &> "$temp_output_file" &
    local pid=$!

    # Hide cursor and set a trap to restore it on exit or interrupt.
tput civis
trap 'tput cnorm; rm -f "$temp_output_file"; exit 130' INT TERM

    # Initial spinner print
    printMsgNoNewline "    ${C_L_BLUE}${spinner_chars:0:1}${T_RESET} ${desc}"

    while ps -p $pid > /dev/null; do
        # Move cursor to the beginning of the line, print spinner, and stay on the same line
        echo -ne "\r    ${C_L_BLUE}${spinner_chars:$i:1}${T_RESET} ${desc}"
        i=$(((i + 1) % ${#spinner_chars}))
        sleep 0.1
    done

    # Wait for the command to finish and get its exit code
    wait $pid
    local exit_code=$?

    # Read the output from the temp file into the global variable
    SPINNER_OUTPUT=$(<"$temp_output_file")
    rm "$temp_output_file"

    # Show cursor again and clear the trap
    tput cnorm
    trap - INT TERM

    # Overwrite the spinner line with the final status message
    clear_current_line
    if [[ $exit_code -eq 0 ]]; then
        printOkMsg "${desc}"
    else
        # In case of failure, the spinner line is already cleared.
        # We print the error message on a new line for clarity.
        printErrMsg "Task failed: ${desc}"
        # Indent the captured output for readability
        echo -e "${SPINNER_OUTPUT}" | sed 's/^/    /'
    fi

    return $exit_code
}

# --- Test Framework ---
# These are not 'local' so the helper functions can access them.
test_count=0
failures=0

# Helper to run a single string comparison test case.
# Usage: _run_string_test "actual_output" "expected_output" "description"
_run_string_test() {
    local actual="$1"
    local expected="$2"
    local description="$3"
    ((test_count++))

    printMsgNoNewline "  Test: ${description}... "
    if [[ "$actual" == "$expected" ]]; then
        printMsg "${C_L_GREEN}PASSED${T_RESET}"
    else
        printMsg "${C_RED}FAILED${T_RESET}"
        echo "    Expected: '$expected'"
        echo "    Got:      '$actual'"
        ((failures++))
    fi
}

# Helper to run a single return code test case.
# Usage: _run_test "command_to_run" <expected_code> "description"
_run_test() {
    local cmd_string="$1"
    local expected_code="$2"
    local description="$3"
    ((test_count++))

    printMsgNoNewline "  Test: ${description}... "
    # Run command in a subshell to not affect the test script's state
    (eval "$cmd_string")
    local actual_code=$?
    if [[ $actual_code -eq $expected_code ]]; then
        printMsg "${C_L_GREEN}PASSED${T_RESET}"
    else
        printMsg "${C_RED}FAILED${T_RESET} (Expected: $expected_code, Got: $actual_code)"
        ((failures++))
    fi
}

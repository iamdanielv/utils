#!/bin/bash
# tests/test-setup-cli.sh
# Description: Verifies the CLI argument parsing and execution flow of setup-dev-machine.sh.

set -e

# 1. Locate the setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: setup-dev-machine.sh not found at $SETUP_SCRIPT"
    exit 1
fi

# Source the script to load variables and helpers, but we need to prevent it from running main immediately.
# The script has a check `if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi` which handles this.
source "$SETUP_SCRIPT"

# 2. Mock Environment
# We source the script but override the phase functions to just log their execution.
# This allows us to verify the flow without actually installing anything.

# Create a temp file to log execution
LOG_FILE=$(mktemp)
trap 'rm -f "$LOG_FILE"' EXIT

log_phase() {
    echo "$1" >> "$LOG_FILE"
}

# Override functions
detect_system() { log_phase "detect_system"; }
phase_bootstrap() { log_phase "phase_bootstrap"; }
phase_system_tools() { log_phase "phase_system_tools"; }
phase_user_binaries() { log_phase "phase_user_binaries"; }
phase_language_runtimes() { log_phase "phase_language_runtimes"; }
phase_configuration() { log_phase "phase_configuration"; }
phase_neovim_binary() { log_phase "phase_neovim_binary"; }
phase_neovim_setup() { log_phase "phase_neovim_setup"; }
phase_neovim_dependencies() { log_phase "phase_neovim_dependencies"; }
install_nerd_fonts() { log_phase "install_nerd_fonts"; }

# Mock prompt to always say yes
prompt_yes_no() { return 0; }

# 3. Test Runner

run_test_case() {
    local test_name="$1"
    local args="$2"
    local expected_phases="$3"

    echo "Test: $test_name"
    echo "  Args: $args"
    
    # Clear log
    > "$LOG_FILE"
    
    # Run main with args
    # We run in a subshell so the exit 0 in main doesn't kill the test script
    (main $args) >/dev/null 2>&1
    
    # Read log
    local actual_phases
    actual_phases=$(cat "$LOG_FILE" | tr '\n' ' ')
    
    # Check if all expected phases ran
    local failed=false
    for phase in $expected_phases; do
        if ! grep -q "$phase" "$LOG_FILE"; then
            printErrMsg "Missing phase: $phase"
            failed=true
        fi
    done
    
    # Check for unexpected phases
    # For simplicity, we just check the count or specific exclusions based on the test case
    
    if [ "$failed" = false ]; then
        printOkMsg "${C_L_GREEN}${T_BOLD}PASS${T_RESET}"
    else
        printErrMsg "FAIL"
        echo "  Actual: $actual_phases"
    fi
    echo "--------------------------------"
}

echo "=== CLI Argument Tests ==="

# Test 1: Default (No Args)
# Should run everything EXCEPT phase_neovim_dependencies (which is for --only-vim)
EXPECTED_DEFAULT="detect_system phase_bootstrap phase_system_tools phase_user_binaries phase_language_runtimes phase_configuration phase_neovim_binary phase_neovim_setup"
run_test_case "Default Execution" "" "$EXPECTED_DEFAULT"

# Test 2: --no-vim
# Should run standard phases BUT NOT neovim binary or setup
EXPECTED_NO_VIM="detect_system phase_bootstrap phase_system_tools phase_user_binaries phase_language_runtimes phase_configuration"
run_test_case "No Vim" "--no-vim" "$EXPECTED_NO_VIM"

# Verify exclusion
if grep -q "phase_neovim_binary" "$LOG_FILE" || grep -q "phase_neovim_setup" "$LOG_FILE"; then
    printErrMsg "FAIL: Neovim phases ran despite --no-vim"
fi

# Test 3: --only-vim
# Should run ONLY neovim phases + dependencies + fonts
EXPECTED_ONLY_VIM="phase_neovim_dependencies phase_neovim_binary install_nerd_fonts phase_neovim_setup"
run_test_case "Only Vim" "--only-vim" "$EXPECTED_ONLY_VIM"

# Verify exclusion of standard phases
if grep -q "phase_bootstrap" "$LOG_FILE" || grep -q "phase_system_tools" "$LOG_FILE"; then
    printErrMsg "FAIL: Standard phases ran despite --only-vim"
fi

echo ""
echo "CLI tests completed"

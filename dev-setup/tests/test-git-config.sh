#!/bin/bash
# tests/test-git-config.sh
# Description: Verifies the configure_git_delta helper.

set -e

# 1. Locate the setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: setup-dev-machine.sh not found at $SETUP_SCRIPT"
    exit 1
fi

# Source the script to load functions
source "$SETUP_SCRIPT"

# 2. Mock User Interaction
prompt_yes_no() {
    return 0 # Always yes
}

# 3. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export HOME="$TEST_DIR"
export XDG_BIN_HOME="${HOME}/.local/bin"
mkdir -p "$XDG_BIN_HOME"

# Mock delta binary so the check passes
touch "$XDG_BIN_HOME/delta"
chmod +x "$XDG_BIN_HOME/delta"

# Sanitize PATH
REQUIRED_TOOLS="git grep sed cat cp mv rm mkdir touch date ls head tail wc awk basename dirname mktemp printf echo sleep tput chmod"
CLEAN_BIN_DIR="$TEST_DIR/sys-bin"
mkdir -p "$CLEAN_BIN_DIR"
for tool in $REQUIRED_TOOLS; do
    if tool_path=$(command -v "$tool"); then
        ln -sf "$tool_path" "$CLEAN_BIN_DIR/$tool"
    fi
done
export PATH="$CLEAN_BIN_DIR"

printBanner "Testing configure_git_delta"

# --- Test Case 1: Configure ---
echo ""
printMsg "${T_BOLD}Test Case 1: Initial Configuration${T_RESET}"

configure_git_delta

if grep -q "pager = delta" "$HOME/.gitconfig"; then
    printOkMsg "core.pager set to delta."
else
    printErrMsg "core.pager NOT set."
    cat "$HOME/.gitconfig"
    exit 1
fi

# --- Test Case 2: Idempotency ---
echo ""
printMsg "${T_BOLD}Test Case 2: Idempotency${T_RESET}"
# It should detect it's already set and skip (printing info message)
configure_git_delta

echo ""
printOkMsg "${C_L_GREEN}All git config tests passed!${T_RESET}"
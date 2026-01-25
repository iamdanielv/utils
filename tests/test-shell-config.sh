#!/bin/bash
# tests/test-shell-config.sh
# Description: Verifies the configure_shell_environment helper.

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
# Override prompt_yes_no to always return 0 (yes)
prompt_yes_no() {
    return 0
}

# 3. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Override HOME so the function modifies our temp .bashrc instead of the real one
export HOME="$TEST_DIR"
# Update XDG_BIN_HOME to match the test HOME so we can mock tools there
export XDG_BIN_HOME="${HOME}/.local/bin"
BASHRC="$HOME/.bashrc"

# Sanitize PATH to prevent system tools (like zoxide/starship) from interfering
# We need standard utilities for the script logic (sed, grep, etc.)
REQUIRED_TOOLS="grep sed cat cp mv rm mkdir touch date ls head tail wc awk basename dirname mktemp printf echo sleep tput chmod"
CLEAN_BIN_DIR="$TEST_DIR/sys-bin"
mkdir -p "$CLEAN_BIN_DIR"

for tool in $REQUIRED_TOOLS; do
    if tool_path=$(command -v "$tool"); then
        ln -sf "$tool_path" "$CLEAN_BIN_DIR/$tool"
    fi
done
export PATH="$CLEAN_BIN_DIR"

# Create a dummy .bashrc with some existing content
echo "# Existing user content" > "$BASHRC"
echo "alias foo='bar'" >> "$BASHRC"

# Create mock tools so the configuration helper detects them
mkdir -p "$XDG_BIN_HOME"
touch "$XDG_BIN_HOME/zoxide" "$XDG_BIN_HOME/starship"
chmod +x "$XDG_BIN_HOME/zoxide" "$XDG_BIN_HOME/starship"

printBanner "Testing configure_shell_environment"
printInfoMsg "Test Home: $HOME"

# 4. Run Tests

# --- Test Case 1: Injection ---
echo ""
printMsg "${T_BOLD}Test Case 1: First Run (Injection)${T_RESET}"
configure_shell_environment

if grep -q "# --- DEV MACHINE SETUP START ---" "$BASHRC"; then
    printOkMsg "Configuration block marker found."
else
    printErrMsg "Configuration block marker NOT found."
    cat "$BASHRC"
    exit 1
fi

if grep -q "export PATH=\"\$HOME/.local/bin:\$PATH\"" "$BASHRC"; then
    printOkMsg "PATH export found."
else
    printErrMsg "PATH export NOT found."
    exit 1
fi

if grep -q "zoxide init bash" "$BASHRC"; then
    printOkMsg "Zoxide init found."
else
    printErrMsg "Zoxide init NOT found."
    exit 1
fi

if grep -q "starship init bash" "$BASHRC"; then
    printOkMsg "Starship init found."
else
    printErrMsg "Starship init NOT found."
    exit 1
fi

# --- Test Case 2: Idempotency ---
echo ""
printMsg "${T_BOLD}Test Case 2: Idempotency (Second Run)${T_RESET}"

# Count occurrences of the start marker
count=$(grep -c "# --- DEV MACHINE SETUP START ---" "$BASHRC")
if [[ "$count" -ne 1 ]]; then
    printErrMsg "Pre-check failed: Marker found $count times (expected 1)."
    exit 1
fi

# Run it again
configure_shell_environment

# Count again
count_after=$(grep -c "# --- DEV MACHINE SETUP START ---" "$BASHRC")
if [[ "$count_after" -eq 1 ]]; then
    printOkMsg "Marker count remains 1 (Idempotency verified)."
else
    printErrMsg "Idempotency failed! Marker found $count_after times."
    exit 1
fi

# --- Test Case 3: Backup Verification ---
echo ""
printMsg "${T_BOLD}Test Case 3: Backup Verification${T_RESET}"
if ls "$BASHRC".bak_* 1> /dev/null 2>&1; then
    printOkMsg "Backup file found."
else
    printErrMsg "Backup file NOT found."
    ls -la "$TEST_DIR"
    exit 1
fi

# --- Test Case 4: Update Verification ---
echo ""
printMsg "${T_BOLD}Test Case 4: Update (Content Change)${T_RESET}"
# Manually add a dummy line inside the block to make it "out of date"
dummy_line="#--DUMMY-LINE-FOR-TEST--#"
sed -i "/# --- DEV MACHINE SETUP START ---/a ${dummy_line}" "$BASHRC"

if ! grep -q "$dummy_line" "$BASHRC"; then
    printErrMsg "Setup failed: Could not inject dummy line for update test."
    exit 1
fi
printInfoMsg "Injected dummy line into config block."

# Run the configuration again. It should detect the change and replace the block.
configure_shell_environment

if grep -q "$dummy_line" "$BASHRC"; then
    printErrMsg "Update failed: Dummy line still exists in .bashrc."
    exit 1
fi
printOkMsg "Dummy line was removed (Update/Replace verified)."

# --- Test Case 5: Dynamic Update (Tools Removed) ---
echo ""
printMsg "${T_BOLD}Test Case 5: Dynamic Update (Tools Removed)${T_RESET}"
# Remove the mocks. The helper should detect this and remove the init lines.
rm "$XDG_BIN_HOME/zoxide" "$XDG_BIN_HOME/starship"

configure_shell_environment

if grep -q "zoxide init bash" "$BASHRC" || grep -q "starship init bash" "$BASHRC"; then
    printErrMsg "Update failed: Tool init lines still exist after tools were removed."
    cat "$BASHRC"
    exit 1
else
    printOkMsg "Tool init lines removed (Dynamic update verified)."
fi


echo ""
printOkMsg "${C_L_GREEN}All shell config tests passed!${T_RESET}"
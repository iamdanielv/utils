#!/bin/bash
# tests/test-lazyvim-setup.sh
# Description: Verifies the setup_lazyvim function.

set -e

# 1. Locate the setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: setup-dev-machine.sh not found at $SETUP_SCRIPT"
    exit 1
fi

echo "Loading setup-dev-machine.sh functions..."
source "$SETUP_SCRIPT"

# 2. Mock User Interaction
prompt_yes_no() {
    # Default to yes for tests
    return 0
}

# 3. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export XDG_CONFIG_HOME="$TEST_DIR/config"
mkdir -p "$XDG_CONFIG_HOME"

# Sanitize PATH
# We need 'git' for the clone. We will mock it.
REQUIRED_TOOLS="mkdir rm mv date grep sed awk head tail wc cat ls bash sh chmod mktemp ps tr sleep touch"
CLEAN_BIN_DIR="$TEST_DIR/sys-bin"
mkdir -p "$CLEAN_BIN_DIR"

for tool in $REQUIRED_TOOLS; do
    if tool_path=$(command -v "$tool"); then
        ln -sf "$tool_path" "$CLEAN_BIN_DIR/$tool"
    fi
done

# Create mock git
echo '#!/bin/bash' > "$CLEAN_BIN_DIR/git"
echo 'if [[ "$1" == "clone" ]]; then mkdir -p "$3"; echo "Mock clone to $3"; exit 0; fi' >> "$CLEAN_BIN_DIR/git"
chmod +x "$CLEAN_BIN_DIR/git"

export PATH="$CLEAN_BIN_DIR"

echo "Test Environment Configured:"
echo "  Config Dir: $XDG_CONFIG_HOME"

# 4. Test Scenarios

printBanner "Testing setup_lazyvim"

# Scenario 1: Clean Install
echo ""
printMsg "${T_BOLD}Scenario 1: Clean Install${T_RESET}"
if setup_lazyvim; then
    if [[ -d "$XDG_CONFIG_HOME/nvim" ]]; then
        printOkMsg "LazyVim cloned successfully."
    else
        printErrMsg "LazyVim directory not found."
        exit 1
    fi
else
    printErrMsg "Scenario 1 Failed"
    exit 1
fi

# Scenario 2: Idempotency (Already Installed)
echo ""
printMsg "${T_BOLD}Scenario 2: Idempotency${T_RESET}"
# Create the marker file
touch "$XDG_CONFIG_HOME/nvim/lazyvim.json"
if setup_lazyvim; then
    printOkMsg "Idempotency check passed."
else
    printErrMsg "Scenario 2 Failed"
    exit 1
fi

# Scenario 3: Backup existing config
echo ""
printMsg "${T_BOLD}Scenario 3: Backup Existing Config${T_RESET}"
# Reset
rm -rf "$XDG_CONFIG_HOME/nvim"
mkdir -p "$XDG_CONFIG_HOME/nvim"
echo "some config" > "$XDG_CONFIG_HOME/nvim/init.lua"

if setup_lazyvim; then
    if [[ -d "$XDG_CONFIG_HOME/nvim" ]]; then
        printOkMsg "New config created."
    else
        printErrMsg "New config missing."
        exit 1
    fi
    # Check for backup
    if ls -d "$XDG_CONFIG_HOME/nvim.bak_"* 1> /dev/null 2>&1; then
        printOkMsg "Backup found."
    else
        printErrMsg "Backup NOT found."
        ls -la "$XDG_CONFIG_HOME"
        exit 1
    fi
else
    printErrMsg "Scenario 3 Failed"
    exit 1
fi

echo ""
printOkMsg "${C_L_GREEN}All LazyVim setup tests passed successfully!${T_RESET}"
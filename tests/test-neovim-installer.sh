#!/bin/bash
# tests/test-neovim-installer.sh
# Description: Verifies the install_neovim function.

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
    local question="$1"
    echo "  [MOCK PROMPT] $question -> Auto-answering YES"
    return 0
}

# 3. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export XDG_BIN_HOME="$TEST_DIR/bin"
export XDG_STATE_HOME="$TEST_DIR/state"
mkdir -p "$XDG_BIN_HOME" "$XDG_STATE_HOME"

# Sanitize PATH
REQUIRED_TOOLS="curl jq tar gzip grep sed awk head mv chmod rm mktemp uname find file cat unzip basename ls mkdir wc sleep ps tail tr cut bash sh ln dirname readlink"
CLEAN_BIN_DIR="$TEST_DIR/sys-bin"
mkdir -p "$CLEAN_BIN_DIR"

for tool in $REQUIRED_TOOLS; do
    if tool_path=$(command -v "$tool"); then
        ln -sf "$tool_path" "$CLEAN_BIN_DIR/$tool"
    fi
done

export PATH="$CLEAN_BIN_DIR:$XDG_BIN_HOME"

echo "Test Environment Configured:"
echo "  Bin Dir: $XDG_BIN_HOME"

# 4. Helper Functions
verify_install() {
    local binary="nvim"
    if [[ -f "$XDG_BIN_HOME/$binary" ]]; then
        # Check if it's a symlink
        if [[ ! -L "$XDG_BIN_HOME/$binary" ]]; then
             printErrMsg "Verification Failed: $binary is not a symlink."
             return 1
        fi
        local target
        target=$(readlink "$XDG_BIN_HOME/$binary")
        if [[ ! -f "$target" ]]; then
             printErrMsg "Verification Failed: Symlink target $target does not exist."
             return 1
        fi
        printOkMsg "${C_L_GREEN}Verification: Neovim installed at $XDG_BIN_HOME/$binary -> $target${T_RESET}"
        
        # Check version file
        if [[ -f "$XDG_STATE_HOME/nvim-version" ]]; then
             printOkMsg "Version file exists: $(cat "$XDG_STATE_HOME/nvim-version")"
        else
             printErrMsg "Version file missing."
             return 1
        fi
    else
        printErrMsg "Verification Failed: Binary not found."
        return 1
    fi
}

# 5. Test Scenarios
printBanner "Testing Tool: neovim"

# Scenario 1: Not Installed
echo ""
printMsg "${T_BOLD}Scenario 1: Clean Install (Not Installed)${T_RESET}"
if install_neovim; then
    verify_install
else
    printErrMsg "Scenario 1 Failed"
    exit 1
fi

# Scenario 2: Idempotency
echo ""
printMsg "${T_BOLD}Scenario 2: Idempotency (Already Installed)${T_RESET}"
if install_neovim; then
    verify_install
else
    printErrMsg "Scenario 2 Failed"
    exit 1
fi

# Scenario 3: Update (Mock older version)
echo ""
printMsg "${T_BOLD}Scenario 3: Update (Lower Version Installed)${T_RESET}"
echo "0.0.0" > "$XDG_STATE_HOME/nvim-version"
if install_neovim; then
    verify_install
else
    printErrMsg "Scenario 3 Failed"
    exit 1
fi

echo ""
printOkMsg "${C_L_GREEN}All neovim tests passed successfully!${T_RESET}"
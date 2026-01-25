#!/bin/bash
# tests/manual_test_github_installer.sh
# Description: Verifies the install_github_binary helper by installing tools to a temp dir.

set -e

# 1. Locate the setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: setup-dev-machine.sh not found at $SETUP_SCRIPT"
    exit 1
fi

echo "Loading setup-dev-machine.sh functions..."
# Source the script to load functions but do not execute main (guarded by if check in setup script)
source "$SETUP_SCRIPT"

# 2. Mock User Interaction
# We override prompt_yes_no to always return 0 (yes) so the test runs non-interactively
prompt_yes_no() {
    local question="$1"
    echo "  [MOCK PROMPT] $question -> Auto-answering YES"
    return 0
}

# 3. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Override the installation directory to the temp dir
# We must do this AFTER sourcing, as the script sets defaults
export XDG_BIN_HOME="$TEST_DIR"
mkdir -p "$XDG_BIN_HOME"

echo "Test Environment Configured:"
echo "  Bin Dir: $XDG_BIN_HOME"

# 4. Run Tests

run_test_case() {
    local repo="$1"
    local binary="$2"
    local regex="$3"
    
    echo ""
    echo "=== Testing: $binary from $repo ==="
    
    if install_github_binary "$repo" "$binary" "$regex"; then
        if [[ -f "$XDG_BIN_HOME/$binary" ]]; then
            echo "✅ Verification: Binary found at $XDG_BIN_HOME/$binary"
            # Try running it to ensure it's executable and valid
            echo "   Version Output: $("$XDG_BIN_HOME/$binary" --version | head -n 1)"
        else
            echo "❌ Verification: Binary NOT found at $XDG_BIN_HOME/$binary"
            exit 1
        fi
    else
        echo "❌ Function returned failure status."
        exit 1
    fi
}

# Test 1: Lazygit (Standard Go binary, usually tar.gz)
run_test_case "jesseduffield/lazygit" "lazygit"

echo ""
echo "🎉 All tests passed successfully!"
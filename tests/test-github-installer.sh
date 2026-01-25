#!/bin/bash
# tests/test-github-installer.sh
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

# Sanitize PATH to exclude user paths where lazygit might be installed (e.g. ~/.local/bin)
# while keeping system paths for essential tools.
# We create a temporary directory with symlinks to required system tools to ensure a clean environment.
REQUIRED_TOOLS="curl jq tar gzip grep sed awk head mv chmod rm mktemp uname find file cat unzip basename ls mkdir wc sleep ps tail tr cut"
CLEAN_BIN_DIR="$TEST_DIR/sys-bin"
mkdir -p "$CLEAN_BIN_DIR"

for tool in $REQUIRED_TOOLS; do
    if tool_path=$(command -v "$tool"); then
        ln -sf "$tool_path" "$CLEAN_BIN_DIR/$tool"
    fi
done

export PATH="$CLEAN_BIN_DIR:$XDG_BIN_HOME"
mkdir -p "$XDG_BIN_HOME"

if command -v lazygit &>/dev/null; then
    echo "⚠️  Warning: 'lazygit' still found in sanitized PATH. 'Not Installed' test may show system version."
fi

echo "Test Environment Configured:"
echo "  Bin Dir: $XDG_BIN_HOME"

# 4. Helper Functions

create_mock_binary() {
    local name="$1"
    local output="$2"
    local path="$XDG_BIN_HOME/$name"
    echo "#!/bin/bash" > "$path"
    echo "echo \"$output\"" >> "$path"
    chmod +x "$path"
}

verify_install() {
    local binary="$1"
    if [[ -f "$XDG_BIN_HOME/$binary" ]]; then
        # Check if it's a real binary (not our bash mock)
        # 'file' command output usually contains "ELF" for binaries or "shell script" for mocks
        if file "$XDG_BIN_HOME/$binary" | grep -q "shell script"; then
             printErrMsg "Verification Failed: File is still the mock script."
             return 1
        fi
        printOkMsg "Verification: Real binary installed at $XDG_BIN_HOME/$binary"
        echo "   Version Output: $("$XDG_BIN_HOME/$binary" --version | head -n 1)"
    else
        printErrMsg "Verification Failed: Binary not found."
        return 1
    fi
}

# 5. Run Test Cases

REPO="jesseduffield/lazygit"
BINARY="lazygit"

echo ""
echo "=== Test Case 1: Application Not Installed ==="
# Ensure clean state
rm -f "$XDG_BIN_HOME/$BINARY"

if install_github_binary "$REPO" "$BINARY"; then
    verify_install "$BINARY"
else
    printErrMsg "Function returned failure."
    exit 1
fi

echo ""
echo "=== Test Case 2: Older Version Installed ==="
# Create a mock that reports an old version
create_mock_binary "$BINARY" "commit=123 version=0.0.1 os=linux"
echo "   [Setup] Created mock $BINARY v0.0.1"

if install_github_binary "$REPO" "$BINARY"; then
    # Should overwrite the mock with the real binary
    verify_install "$BINARY"
else
    printErrMsg "Function returned failure."
    exit 1
fi

echo ""
echo "=== Test Case 3: Unknown/Garbage Version Installed ==="
# Create a mock that reports garbage
create_mock_binary "$BINARY" "Error: unknown command mock"
echo "   [Setup] Created mock $BINARY with invalid version output"

if install_github_binary "$REPO" "$BINARY"; then
    verify_install "$BINARY"
else
    printErrMsg "Function returned failure."
    exit 1
fi

echo ""
printOkMsg "${C_L_GREEN}All tests passed successfully!${T_RESET}"
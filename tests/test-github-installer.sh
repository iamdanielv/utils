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
if command -v lazydocker &>/dev/null; then
    echo "⚠️  Warning: 'lazydocker' still found in sanitized PATH. 'Not Installed' test may show system version."
fi
if command -v delta &>/dev/null; then
    echo "⚠️  Warning: 'delta' still found in sanitized PATH. 'Not Installed' test may show system version."
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
        printOkMsg "${C_L_GREEN}Verification: Real binary installed at $XDG_BIN_HOME/$binary${T_RESET}"
        echo "    Version Output: $("$XDG_BIN_HOME/$binary" --version | head -n 1)"
    else
        printErrMsg "Verification Failed: Binary not found."
        return 1
    fi
}

# 5. Test Runner Logic

run_tool_tests() {
    local repo="$1"
    local binary="$2"
    
    echo ""
    printBanner "Testing Tool: $binary"
    printInfoMsg "Repository: $repo"

    # Scenario 1: Not Installed
    echo ""
    printMsg "${T_BOLD}Scenario 1: Clean Install (Not Installed)${T_RESET}"
    rm -f "$XDG_BIN_HOME/$binary"
    if install_github_binary "$repo" "$binary"; then
        verify_install "$binary"
    else
        printErrMsg "Scenario 1 Failed"
        exit 1
    fi

    # Scenario 2: Current Version (Idempotency)
    echo ""
    printMsg "${T_BOLD}Scenario 2: Idempotency (Already Installed)${T_RESET}"
    # Binary exists from step 1.
    if install_github_binary "$repo" "$binary"; then
        verify_install "$binary"
    else
        printErrMsg "Scenario 2 Failed"
        exit 1
    fi

    # Scenario 3: Lower Version (Update)
    echo ""
    printMsg "${T_BOLD}Scenario 3: Update (Lower Version Installed)${T_RESET}"
    create_mock_binary "$binary" "version=0.0.1"
    if install_github_binary "$repo" "$binary"; then
        verify_install "$binary"
    else
        printErrMsg "Scenario 3 Failed"
        exit 1
    fi

    # Scenario 4: Corrupt/Unknown Version
    echo ""
    printMsg "${T_BOLD}Scenario 4: Recovery (Corrupt/Unknown Version)${T_RESET}"
    create_mock_binary "$binary" "Error: some error"
    if install_github_binary "$repo" "$binary"; then
        verify_install "$binary"
    else
        printErrMsg "Scenario 4 Failed"
        exit 1
    fi
}

# 6. Execute Tests

TOOLS_TO_TEST=(
    "jesseduffield/lazygit:lazygit"
    "jesseduffield/lazydocker:lazydocker"
    "dandavison/delta:delta"
    "BurntSushi/ripgrep:rg"
    "sharkdp/fd:fd"
    "sharkdp/bat:bat"
    "eza-community/eza:eza"
)

for tool_spec in "${TOOLS_TO_TEST[@]}"; do
    IFS=':' read -r repo binary <<< "$tool_spec"
    run_tool_tests "$repo" "$binary"
done

echo ""
printOkMsg "${C_L_GREEN}All tests passed successfully!${T_RESET}"
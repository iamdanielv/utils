#!/bin/bash
# tests/test-setup-verify.sh
# Description: Verifies the --verify mode of setup-dev-machine.sh by mocking the environment.

set -e

# 1. Locate and Source the setup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"

if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: setup-dev-machine.sh not found at $SETUP_SCRIPT"
    exit 1
fi

# Source the script to load functions but NOT run main (guarded by if check in script)
source "$SETUP_SCRIPT"
# Redefine SCRIPT_DIR because sourcing setup-dev-machine.sh overrides it to empty
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Mock Helpers
# Override GitHub API helper to return a fixed version
_gh_get_latest_version() {
    echo "v1.0.0"
}

# Override curl to mock Go version check
curl() {
    if [[ "$*" == *"go.dev"* ]]; then
        echo '[{"version": "go1.0.0"}]'
    else
        echo ""
    fi
}

# 3. Setup Test Environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Redirect XDG paths to temp dir
export HOME="$TEST_DIR"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_BIN_HOME="$HOME/.local/bin"

# Sanitize PATH to exclude user paths where zoxide/starship might be installed
REQUIRED_TOOLS="curl jq tar gzip grep sed awk head mv chmod rm mktemp uname find file cat unzip basename ls mkdir wc sleep ps tail tr cut cmp date touch dirname printf echo git cp"
CLEAN_BIN_DIR="$TEST_DIR/sys-bin"
mkdir -p "$CLEAN_BIN_DIR"

for tool in $REQUIRED_TOOLS; do
    if tool_path=$(command -v "$tool"); then
        ln -sf "$tool_path" "$CLEAN_BIN_DIR/$tool"
    fi
done

export PATH="$XDG_BIN_HOME:$CLEAN_BIN_DIR"

mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_BIN_HOME"

# Create a blank .bashrc so grep doesn't fail or warn
touch "$HOME/.bashrc"

# Helper to create mock binaries in the test PATH
create_mock_bin() {
    local name="$1"
    local version_output="$2"
    local path="$XDG_BIN_HOME/$name"
    echo "#!/bin/bash" > "$path"
    echo "echo '$version_output'" >> "$path"
    chmod +x "$path"
}

# 4. Run Tests

printBanner "Test 1: Clean Environment (Expect Missing)"
# Run main in verify mode
OUTPUT=$(main --verify)

if echo "$OUTPUT" | grep -q "zoxide.*Missing"; then
    printOkMsg "Clean env: zoxide missing detected."
else
    printErrMsg "Clean env: zoxide missing NOT detected."
    echo "$OUTPUT"
    exit 1
fi

printBanner "Test 2: Installed & Synced (Expect Installed)"
# Setup "Installed" state matching our mocks
create_mock_bin "zoxide" "zoxide v1.0.0"
create_mock_bin "starship" "starship 1.0.0"
create_mock_bin "go" "go version go1.0.0 linux/amd64"

# Setup "Synced" config (Copy real config to test home)
mkdir -p "$XDG_CONFIG_HOME/tmux"
cp "$SCRIPT_DIR/../config/tmux/tmux.conf" "$XDG_CONFIG_HOME/tmux/tmux.conf"

OUTPUT=$(main --verify)

if echo "$OUTPUT" | grep -q "zoxide.*Installed"; then
    printOkMsg "Installed env: zoxide installed detected."
else
    printErrMsg "Installed env: zoxide installed NOT detected."
    echo "$OUTPUT"
    exit 1
fi

if echo "$OUTPUT" | grep -q "tmux.conf.*Synced"; then
    printOkMsg "Config: tmux.conf synced detected."
else
    printErrMsg "Config: tmux.conf synced NOT detected."
    echo "$OUTPUT"
    exit 1
fi

printBanner "Test 3: Outdated & Differs (Expect Warnings)"
# Setup "Outdated" state (v0.9.0 vs v1.0.0 mocked latest)
create_mock_bin "zoxide" "zoxide v0.9.0"

# Setup "Differs" config
echo "different content" > "$XDG_CONFIG_HOME/tmux/tmux.conf"

OUTPUT=$(main --verify)

if echo "$OUTPUT" | grep -q "zoxide.*Outdated"; then
    printOkMsg "Outdated env: zoxide outdated detected."
else
    printErrMsg "Outdated env: zoxide outdated NOT detected."
    echo "$OUTPUT"
    exit 1
fi

if echo "$OUTPUT" | grep -q "tmux.conf.*Differs"; then
    printOkMsg "Config: tmux.conf differs detected."
else
    printErrMsg "Config: tmux.conf differs NOT detected."
    echo "$OUTPUT"
    exit 1
fi

echo ""
printOkMsg "All verify tests passed!"
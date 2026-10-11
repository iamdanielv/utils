#!/bin/bash
# tests/test-neovim-installer.sh
# Description: Verifies Neovim installer behavior without network access.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"
source "$SETUP_SCRIPT"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export XDG_BIN_HOME="$TEST_DIR/bin"
export XDG_STATE_HOME="$TEST_DIR/state"
mkdir -p "$XDG_BIN_HOME" "$XDG_STATE_HOME"

SUMMARY_ENABLED=true
declare -A SUMMARY_RESULTS
SUMMARY_ORDER=()
declare -A VERIFY_RESULTS
VERIFY_ORDER=()

LATEST_VERSION="v2.0.0"
PROMPT_RESULT=0
PROMPT_CALLS=0
PROMPT_TEXT=""
RUN_RESULT=0
RUN_CALLS=0
RUN_DESCRIPTION=""
RUN_COMMAND=()
CALL_LOG=$(mktemp)
trap 'rm -rf "$TEST_DIR"; rm -f "$CALL_LOG"' EXIT

_gh_get_latest_version() {
    printf '%s\n' "latest:$1" >> "$CALL_LOG"
    printf '%s\n' "$LATEST_VERSION"
}

prompt_yes_no() {
    PROMPT_CALLS=$((PROMPT_CALLS + 1))
    PROMPT_TEXT="$1"
    return "$PROMPT_RESULT"
}

run_with_spinner() {
    RUN_CALLS=$((RUN_CALLS + 1))
    RUN_DESCRIPTION="$1"
    shift
    RUN_COMMAND=("$@")

    if [[ "$RUN_RESULT" -eq 0 ]]; then
        local previous=""
        local argument
        for argument in "${RUN_COMMAND[@]}"; do
            if [[ "$previous" == "-o" ]]; then
                : > "$argument"
                break
            fi
            previous="$argument"
        done
    fi
    return "$RUN_RESULT"
}

fail() {
    printErrMsg "$1"
    exit 1
}

reset_test_state() {
    VERIFY_MODE=false
    SETUP_FAILED=false
    SUMMARY_RESULTS=()
    SUMMARY_ORDER=()
    VERIFY_RESULTS=()
    VERIFY_ORDER=()
    : > "$CALL_LOG"
    rm -f "$XDG_BIN_HOME/nvim" "$XDG_BIN_HOME/nvim-linux-x86_64.appimage" "$XDG_STATE_HOME/nvim-version"
    LATEST_VERSION="v2.0.0"
    PROMPT_RESULT=0
    PROMPT_CALLS=0
    PROMPT_TEXT=""
    RUN_RESULT=0
    RUN_CALLS=0
    RUN_DESCRIPTION=""
    RUN_COMMAND=()
}

count_calls() {
    local call_name="$1"
    local count
    count=$(awk -F: -v name="$call_name" '$1 == name { count++ } END { print count + 0 }' "$CALL_LOG")
    printf '%s\n' "$count"
}

assert_summary_status() {
    local expected_status="$1"
    local actual="${SUMMARY_RESULTS[Neovim]:-}"
    if [[ "${actual%%|*}" != "$expected_status" ]]; then
        fail "Expected Neovim summary status ${expected_status}; got ${actual:-no summary}"
    fi
}

reset_test_state
echo "2.0.0" > "$XDG_STATE_HOME/nvim-version"
install_neovim || fail "Current-version check returned failure."
assert_summary_status "Current"
[[ "$(count_calls latest)" -eq 1 && "$PROMPT_CALLS" -eq 0 && "$RUN_CALLS" -eq 0 ]] || fail "Current version prompted or attempted download."

reset_test_state
echo "1.0.0" > "$XDG_STATE_HOME/nvim-version"
install_neovim || fail "Approved update returned failure."
assert_summary_status "Updated"
[[ "$PROMPT_CALLS" -eq 1 && "$PROMPT_TEXT" == *"update Neovim from v1.0.0 to v2.0.0"* ]] || fail "Update prompt was missing or incorrect."
[[ "$RUN_CALLS" -eq 1 && "$RUN_DESCRIPTION" == "Downloading Neovim AppImage v2.0.0..." ]] || fail "Approved update did not download the AppImage."
[[ "${RUN_COMMAND[0]}" == "curl" && "${RUN_COMMAND[1]}" == "-L" && "${RUN_COMMAND[2]}" == "-f" && "${RUN_COMMAND[3]}" == "https://github.com/neovim/neovim/releases/download/v2.0.0/nvim-linux-x86_64.appimage" && "${RUN_COMMAND[4]}" == "-o" ]] || fail "Neovim AppImage download command changed."
[[ -L "$XDG_BIN_HOME/nvim" && -f "$XDG_BIN_HOME/nvim-linux-x86_64.appimage" ]] || fail "Neovim AppImage or symlink was not installed."
[[ "$(<"$XDG_STATE_HOME/nvim-version")" == "2.0.0" ]] || fail "Neovim version state was not updated."

reset_test_state
install_neovim || fail "Approved clean install returned failure."
assert_summary_status "Installed"
[[ "$PROMPT_TEXT" == *"install Neovim version v2.0.0"* && "$RUN_CALLS" -eq 1 ]] || fail "Approved clean install did not prompt and download."

reset_test_state
echo "1.0.0" > "$XDG_STATE_HOME/nvim-version"
PROMPT_RESULT=1
install_neovim || fail "Declined update returned failure."
assert_summary_status "Skipped"
[[ "$PROMPT_CALLS" -eq 1 && "$RUN_CALLS" -eq 0 && "$(<"$XDG_STATE_HOME/nvim-version")" == "1.0.0" ]] || fail "Declined update attempted download or changed local version state."

for unavailable_version in "$GH_API_RATE_LIMITED" "$GH_API_UNAVAILABLE" "" "null"; do
    reset_test_state
    LATEST_VERSION="$unavailable_version"
    install_neovim || fail "Unavailable release metadata returned failure."
    assert_summary_status "Unavailable"
    [[ "$PROMPT_CALLS" -eq 0 && "$RUN_CALLS" -eq 0 ]] || fail "Unavailable release metadata continued to prompt or download."
    [[ "$SETUP_FAILED" == "false" ]] || fail "Unavailable release metadata marked setup as failed."
done

reset_test_state
echo "1.0.0" > "$XDG_STATE_HOME/nvim-version"
RUN_RESULT=1
if install_neovim; then
    fail "Failed Neovim download returned success."
fi
assert_summary_status "Failed"
[[ "$RUN_CALLS" -eq 1 && "$(<"$XDG_STATE_HOME/nvim-version")" == "1.0.0" ]] || fail "Failed download changed version state or was not attempted."

reset_test_state
VERIFY_MODE=true
echo "2.0.0" > "$XDG_STATE_HOME/nvim-version"
install_neovim || fail "Verification returned failure."
[[ "${VERIFY_RESULTS[Neovim]%%|*}" == "Installed" ]] || fail "Verification did not report installed Neovim."
[[ "$(count_calls latest)" -eq 0 && "$PROMPT_CALLS" -eq 0 && "$RUN_CALLS" -eq 0 ]] || fail "Verification queried GitHub, prompted, or attempted download."
[[ "$(<"$XDG_STATE_HOME/nvim-version")" == "2.0.0" ]] || fail "Verification modified local version state."

printOkMsg "Neovim installer behavior is deterministic and network-free."
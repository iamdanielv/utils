#!/bin/bash
# tests/test-zoxide-installer.sh
# Description: Verifies zoxide installer behavior without network access.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"
source "$SETUP_SCRIPT"

SUMMARY_ENABLED=true
declare -A SUMMARY_RESULTS
SUMMARY_ORDER=()
declare -A VERIFY_RESULTS
VERIFY_ORDER=()

LATEST_VERSION="v2.0.0"
INSTALLED_VERSION=""
PROMPT_RESULT=0
PROMPT_CALLS=0
PROMPT_TEXT=""
INSTALL_RESULT=0
INSTALL_CALLS=0
INSTALL_DESCRIPTION=""
INSTALL_COMMAND=()
CALL_LOG=$(mktemp)
trap 'rm -f "$CALL_LOG"' EXIT

_gh_get_latest_version() {
    printf '%s\n' "latest:$1" >> "$CALL_LOG"
    printf '%s\n' "$LATEST_VERSION"
}

_gh_get_installed_version() {
    printf '%s\n' "installed:$1" >> "$CALL_LOG"
    printf '%s\n' "$INSTALLED_VERSION"
}

prompt_yes_no() {
    PROMPT_CALLS=$((PROMPT_CALLS + 1))
    PROMPT_TEXT="$1"
    return "$PROMPT_RESULT"
}

run_with_spinner() {
    INSTALL_CALLS=$((INSTALL_CALLS + 1))
    INSTALL_DESCRIPTION="$1"
    shift
    INSTALL_COMMAND=("$@")
    return "$INSTALL_RESULT"
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
    LATEST_VERSION="v2.0.0"
    INSTALLED_VERSION=""
    PROMPT_RESULT=0
    PROMPT_CALLS=0
    PROMPT_TEXT=""
    INSTALL_RESULT=0
    INSTALL_CALLS=0
    INSTALL_DESCRIPTION=""
    INSTALL_COMMAND=()
}

count_calls() {
    local call_name="$1"
    local count
    count=$(awk -F: -v name="$call_name" '$1 == name { count++ } END { print count + 0 }' "$CALL_LOG")
    printf '%s\n' "$count"
}

assert_summary_status() {
    local expected_status="$1"
    local actual="${SUMMARY_RESULTS[zoxide]:-}"
    if [[ "${actual%%|*}" != "$expected_status" ]]; then
        fail "Expected zoxide summary status ${expected_status}; got ${actual:-no summary}"
    fi
}

reset_test_state
INSTALLED_VERSION="2.0.0"
install_zoxide || fail "Current-version check returned failure."
assert_summary_status "Current"
[[ "$(count_calls latest)" -eq 1 && "$(count_calls installed)" -eq 1 ]] || fail "Expected release and installed versions to be checked."
[[ "$PROMPT_CALLS" -eq 0 && "$INSTALL_CALLS" -eq 0 ]] || fail "Current version prompted or attempted installation."

reset_test_state
INSTALLED_VERSION="1.0.0"
install_zoxide || fail "Approved update returned failure."
assert_summary_status "Updated"
[[ "$PROMPT_CALLS" -eq 1 && "$PROMPT_TEXT" == *"update zoxide from 1.0.0 to v2.0.0"* ]] || fail "Update prompt was missing or incorrect."
[[ "$INSTALL_CALLS" -eq 1 && "$INSTALL_DESCRIPTION" == "Installing zoxide via official script..." ]] || fail "Approved update did not use the existing zoxide installer."
[[ "${INSTALL_COMMAND[0]}" == "bash" && "${INSTALL_COMMAND[1]}" == "-c" && "${INSTALL_COMMAND[2]}" == *"ajeetdsouza/zoxide/main/install.sh"* ]] || fail "Existing official zoxide install command changed."

reset_test_state
INSTALLED_VERSION="Not installed"
install_zoxide || fail "Approved clean install returned failure."
assert_summary_status "Installed"
[[ "$PROMPT_TEXT" == *"install zoxide version v2.0.0"* && "$INSTALL_CALLS" -eq 1 ]] || fail "Approved clean install did not prompt and invoke installer."

reset_test_state
INSTALLED_VERSION="1.0.0"
PROMPT_RESULT=1
install_zoxide || fail "Declined update returned failure."
assert_summary_status "Skipped"
[[ "$PROMPT_CALLS" -eq 1 && "$INSTALL_CALLS" -eq 0 ]] || fail "Declined update attempted installation."

for unavailable_version in "$GH_API_RATE_LIMITED" "$GH_API_UNAVAILABLE" "" "null"; do
    reset_test_state
    LATEST_VERSION="$unavailable_version"
    install_zoxide || fail "Unavailable release metadata returned failure."
    assert_summary_status "Unavailable"
    [[ "$PROMPT_CALLS" -eq 0 && "$INSTALL_CALLS" -eq 0 ]] || fail "Unavailable release metadata continued to prompt or installation."
    [[ "$SETUP_FAILED" == "false" ]] || fail "Unavailable release metadata marked setup as failed."
done

reset_test_state
INSTALLED_VERSION="1.0.0"
INSTALL_RESULT=1
if install_zoxide; then
    fail "Failed zoxide installation returned success."
fi
assert_summary_status "Failed"
[[ "$INSTALL_CALLS" -eq 1 ]] || fail "Expected one failed zoxide installation attempt."

reset_test_state
VERIFY_MODE=true
INSTALLED_VERSION="2.0.0"
install_zoxide || fail "Verification returned failure."
[[ "${VERIFY_RESULTS[zoxide]%%|*}" == "Installed" ]] || fail "Verification did not report installed zoxide."
[[ "$(count_calls installed)" -eq 1 && "$(count_calls latest)" -eq 0 && "$PROMPT_CALLS" -eq 0 && "$INSTALL_CALLS" -eq 0 ]] || fail "Verification queried GitHub, prompted, or attempted installation."

printOkMsg "Zoxide installer behavior is deterministic and network-free."
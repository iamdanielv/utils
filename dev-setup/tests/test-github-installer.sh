#!/bin/bash
# tests/test-github-installer.sh
# Description: Verifies GitHub release installer behavior without network access.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"
source "$SETUP_SCRIPT"

SUMMARY_ENABLED=true
declare -A SUMMARY_RESULTS
SUMMARY_ORDER=()
declare -A VERIFY_RESULTS
VERIFY_ORDER=()

LATEST_API_RESPONSE='{"tag_name":"v2.0.0"}'
ASSET_API_RESPONSE='{"assets":[{"name":"tool_linux_amd64.tar.gz","browser_download_url":"https://example.invalid/tool_linux_amd64.tar.gz"},{"name":"tool_windows_amd64.zip","browser_download_url":"https://example.invalid/tool_windows_amd64.zip"}]}'
LATEST_API_STATUS=0
ASSET_API_STATUS=0
INSTALLED_VERSION=""
PROMPT_RESULT=0
INSTALL_RESULT=0
PROMPT_CALLS=0
INSTALL_CALLS=0
INSTALL_URL=""
INSTALL_VERSION=""
CALL_LOG=$(mktemp)
trap 'rm -f "$CALL_LOG"' EXIT

_gh_api_request() {
    printf '%s\n' "request:$1" >> "$CALL_LOG"
    if [[ "$(count_calls request)" -eq 1 ]]; then
        printf '%s\n' "$LATEST_API_RESPONSE"
        return "$LATEST_API_STATUS"
    fi
    printf '%s\n' "$ASSET_API_RESPONSE"
    return "$ASSET_API_STATUS"
}

_gh_get_installed_version() {
    printf '%s\n' "installed:$1" >> "$CALL_LOG"
    printf '%s\n' "$INSTALLED_VERSION"
}

prompt_yes_no() {
    PROMPT_CALLS=$((PROMPT_CALLS + 1))
    return "$PROMPT_RESULT"
}

_gh_download_and_install() {
    INSTALL_CALLS=$((INSTALL_CALLS + 1))
    INSTALL_URL="$1"
    INSTALL_VERSION="$3"
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
    LATEST_API_RESPONSE='{"tag_name":"v2.0.0"}'
    ASSET_API_RESPONSE='{"assets":[{"name":"tool_linux_amd64.tar.gz","browser_download_url":"https://example.invalid/tool_linux_amd64.tar.gz"},{"name":"tool_windows_amd64.zip","browser_download_url":"https://example.invalid/tool_windows_amd64.zip"}]}'
    LATEST_API_STATUS=0
    ASSET_API_STATUS=0
    INSTALLED_VERSION=""
    PROMPT_RESULT=0
    INSTALL_RESULT=0
    PROMPT_CALLS=0
    INSTALL_CALLS=0
    INSTALL_URL=""
    INSTALL_VERSION=""
}

count_calls() {
    local call_name="$1"
    local count
    count=$(awk -F: -v name="$call_name" '$1 == name { count++ } END { print count + 0 }' "$CALL_LOG")
    printf '%s\n' "$count"
}

assert_summary_status() {
    local tool="$1"
    local expected_status="$2"
    local actual="${SUMMARY_RESULTS[$tool]:-}"
    if [[ "${actual%%|*}" != "$expected_status" ]]; then
        fail "Expected ${tool} summary status ${expected_status}; got ${actual:-no summary}"
    fi
}

reset_test_state
LATEST_API_RESPONSE='{"tag_name":"v1.2.3"}'
INSTALLED_VERSION="1.2.3"
install_github_binary example/tool tool || fail "Current-version check returned failure."
assert_summary_status tool "Latest"
[[ "$(count_calls request)" -eq 1 ]] || fail "Expected one latest-version request."
[[ "$(count_calls installed)" -eq 1 ]] || fail "Expected installed version to be checked."
[[ "$PROMPT_CALLS" -eq 0 && "$INSTALL_CALLS" -eq 0 ]] || fail "Current version prompted or attempted installation."

reset_test_state
INSTALLED_VERSION="1.0.0"
install_github_binary example/tool tool || fail "Approved update returned failure."
assert_summary_status tool "Updated"
[[ "$PROMPT_CALLS" -eq 1 && "$(count_calls request)" -eq 2 && "$INSTALL_CALLS" -eq 1 ]] || fail "Approved update did not prompt, resolve an asset, and install exactly once."
[[ "$INSTALL_URL" == "https://example.invalid/tool_linux_amd64.tar.gz" && "$INSTALL_VERSION" == "v2.0.0" ]] || fail "Installer did not receive the selected Linux asset URL and latest version."

reset_test_state
INSTALLED_VERSION="Not installed"
install_github_binary example/tool tool || fail "Approved clean install returned failure."
assert_summary_status tool "Installed"
[[ "$PROMPT_CALLS" -eq 1 && "$INSTALL_CALLS" -eq 1 ]] || fail "Approved clean install did not prompt and install."

reset_test_state
INSTALLED_VERSION="1.0.0"
PROMPT_RESULT=1
install_github_binary example/tool tool || fail "Declined update returned failure."
assert_summary_status tool "Skipped"
[[ "$PROMPT_CALLS" -eq 1 && "$(count_calls request)" -eq 1 && "$INSTALL_CALLS" -eq 0 ]] || fail "Declined update continued to asset lookup or installation."

for unavailable_response in rate_limited unavailable empty null; do
    reset_test_state
    case "$unavailable_response" in
        rate_limited) LATEST_API_RESPONSE="$GH_API_RATE_LIMITED"; LATEST_API_STATUS=1 ;;
        unavailable) LATEST_API_RESPONSE="$GH_API_UNAVAILABLE"; LATEST_API_STATUS=1 ;;
        empty) LATEST_API_RESPONSE='{"tag_name":""}' ;;
        null) LATEST_API_RESPONSE='{"tag_name":null}' ;;
    esac
    install_github_binary example/tool tool || fail "Unavailable release metadata returned failure."
    assert_summary_status tool "Unavailable"
    [[ "$PROMPT_CALLS" -eq 0 && "$(count_calls request)" -eq 1 && "$INSTALL_CALLS" -eq 0 ]] || fail "Unavailable release metadata continued to prompt or installation."
    [[ "$SETUP_FAILED" == "false" ]] || fail "Unavailable release metadata marked setup as failed."
done

reset_test_state
INSTALLED_VERSION="1.0.0"
ASSET_API_RESPONSE="$GH_API_RATE_LIMITED"
ASSET_API_STATUS=1
install_github_binary example/tool tool || fail "Rate-limited asset lookup returned failure."
assert_summary_status tool "Unavailable"
[[ "$(count_calls request)" -eq 2 && "$INSTALL_CALLS" -eq 0 ]] || fail "Rate-limited asset lookup attempted installation."

reset_test_state
INSTALLED_VERSION="1.0.0"
INSTALL_RESULT=1
if install_github_binary example/tool tool; then
    fail "Failed binary installation returned success."
fi
assert_summary_status tool "Failed"
[[ "$INSTALL_CALLS" -eq 1 ]] || fail "Expected one failed installation attempt."

reset_test_state
VERIFY_MODE=true
INSTALLED_VERSION="1.2.3"
install_github_binary example/tool tool || fail "Verification returned failure."
[[ "${VERIFY_RESULTS[tool]%%|*}" == "Installed" ]] || fail "Verification did not report the installed tool."
[[ "$(count_calls installed)" -eq 1 && "$(count_calls request)" -eq 0 && "$PROMPT_CALLS" -eq 0 && "$INSTALL_CALLS" -eq 0 ]] || fail "Verification queried GitHub, prompted, or attempted installation."

printOkMsg "GitHub binary installer behavior is deterministic and network-free."
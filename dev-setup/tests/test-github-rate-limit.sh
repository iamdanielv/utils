#!/bin/bash
# tests/test-github-rate-limit.sh
# Description: Verifies that unavailable GitHub release metadata is non-fatal.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/../setup-dev-machine.sh"
source "$SETUP_SCRIPT"

SUMMARY_ENABLED=true
VERIFY_MODE=false
SETUP_FAILED=false
SUMMARY_RESULTS=()
declare -A SUMMARY_RESULTS
SUMMARY_ORDER=()

curl() {
    local output_file=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "-o" ]]; then
            output_file="$2"
            shift 2
        else
            shift
        fi
    done
    printf '%s\n' '{"message":"API rate limit exceeded"}' > "$output_file"
    printf '403'
}

api_result=$(_gh_api_request "https://api.github.com/test") || API_STATUS=$?
if [[ "${api_result}" != "$GH_API_RATE_LIMITED" || "${API_STATUS:-0}" -eq 0 ]]; then
    printErrMsg "HTTP rate-limit response was not classified correctly."
    exit 1
fi

_gh_get_latest_version() {
    echo "$GH_API_RATE_LIMITED"
}

if install_github_binary example/lazygit lazygit; then
    :
else
    printErrMsg "Rate-limited release lookup returned failure."
    exit 1
fi

result="${SUMMARY_RESULTS[lazygit]}"
if [[ "${result%%|*}" != "Unavailable" ]]; then
    printErrMsg "Expected lazygit to be marked Unavailable."
    exit 1
fi

if [[ "$SETUP_FAILED" == "true" ]]; then
    printErrMsg "Rate-limited release lookup marked setup as failed."
    exit 1
fi

printOkMsg "Rate-limited release lookup is non-fatal and visible."
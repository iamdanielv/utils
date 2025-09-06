#!/bin/bash
set -o pipefail

# This script must be run from the root of the `utils` directory.

# --- Test Setup ---

# Override config paths BEFORE sourcing the scripts.
# The `ssh-manager.sh` script will use these variables if they are set.
export TEST_DIR
TEST_DIR=$(mktemp -d)
export HOME="$TEST_DIR" # Set HOME to test dir for predictable ~ expansion
export SSH_DIR="${TEST_DIR}/.ssh"
export SSH_CONFIG_PATH="${SSH_DIR}/config"

# Source the scripts under test
# Source common utilities for colors and functions
# shellcheck source=../shared.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/../shared.sh"; then
    echo "Error: Could not source shared.sh." >&2
    exit 1
fi

# Source the script we are testing
# shellcheck source=../ssh-manager.sh
if ! source "$(dirname "${BASH_SOURCE[0]}")/../ssh-manager.sh"; then
    echo "Error: Could not source ssh-manager.sh." >&2
    exit 1
fi

# --- Mocks & Test State ---

# Mock for the `ssh` command. We only need to mock `ssh -G` for now.
ssh() {
    if [[ "$1" == "-G" ]]; then
        local host_alias="$2"
        case "$host_alias" in
        "test-server-1")
            echo "hostname 192.168.1.101"
            echo "user user1"
            echo "port 2222"
            echo "identityfile ~/.ssh/id_test1"
            ;;
        "test-server-2")
            echo "hostname server2.example.com"
            echo "user user2"
            echo "port 22"
            ;;
        *) return 1 ;; # Return error for unmocked hosts
        esac
        return 0
    fi
    # If called for anything else, print an error to fail tests unexpectedly using it.
    echo "ERROR: Unmocked call to ssh with args: $*" >&2
    return 127
}

# Mock for `rm`. It will record what it was called with.
MOCK_RM_CALLS=()
rm() {
    MOCK_RM_CALLS+=("$*")
}

# Mock for `prompt_yes_no`.
# Usage: MOCK_PROMPT_RESULT=0 (yes), 1 (no), 2 (cancel)
MOCK_PROMPT_RESULT=0
prompt_yes_no() {
    # Just return the pre-configured result.
    return "$MOCK_PROMPT_RESULT"
}

# --- Test Harness ---

setup() {
    # Reset counters for the test suite
    initialize_test_suite

    # Create the fake .ssh directory and a dummy config file
    mkdir -p "$SSH_DIR"
    cat >"$SSH_CONFIG_PATH" <<'EOF'
Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key
EOF
}

teardown() {
    # Clean up the temporary directory
    if [[ -d "$TEST_DIR" ]]; then
        # Use the real `rm` command, not the mock, to ensure cleanup.
        # The mock `rm` is still active when this EXIT trap runs.
        /bin/rm -rf "$TEST_DIR"
    fi
}

# --- Test Cases ---

test_get_ssh_hosts() {
    printTestSectionHeader "Testing get_ssh_hosts"
    local expected_hosts="test-server-1
test-server-2
test-server-3"
    local actual_hosts
    actual_hosts=$(get_ssh_hosts)
    _run_string_test "$actual_hosts" "$expected_hosts" "Should correctly parse all host aliases from config"
}

test_get_ssh_config_value() {
    printTestSectionHeader "Testing get_ssh_config_value (with mocked ssh -G)"
    local actual
    actual=$(get_ssh_config_value "test-server-1" "HostName")
    _run_string_test "$actual" "192.168.1.101" "Should get HostName for test-server-1"

    actual=$(get_ssh_config_value "test-server-1" "Port")
    _run_string_test "$actual" "2222" "Should get non-default Port for test-server-1"

    actual=$(get_ssh_config_value "test-server-2" "Port")
    _run_string_test "$actual" "22" "Should get default Port for test-server-2"

    actual=$(get_ssh_config_value "test-server-1" "IdentityFile")
    _run_string_test "$actual" "~/.ssh/id_test1" "Should get IdentityFile for test-server-1"

    actual=$(get_ssh_config_value "test-server-2" "IdentityFile")
    _run_string_test "$actual" "" "Should get empty IdentityFile for test-server-2"
}

test_process_ssh_config_blocks() {
    printTestSectionHeader "Testing _process_ssh_config_blocks and wrappers"

    # Test _get_host_block_from_config
    local expected_block
    expected_block=$(
        cat <<'EOF'
Host test-server-2
    HostName server2.example.com
    User user2
    # No port, should default to 22
EOF
    )
    local actual_block
    actual_block=$(_get_host_block_from_config "test-server-2" "$SSH_CONFIG_PATH")
    _run_string_test "$actual_block" "$expected_block" "_get_host_block_from_config should extract the correct block"

    # Test _remove_host_block_from_config
    local expected_config_after_remove
    expected_config_after_remove=$(
        cat <<'EOF'
Host test-server-1
    HostName 192.168.1.101
    User user1
    Port 2222
    IdentityFile ~/.ssh/id_test1

Host test-server-3
    HostName 192.168.1.103
    User user3
    IdentityFile /absolute/path/to/key
EOF
    )
    local actual_config_after_remove
    # The function should now preserve the blank line between blocks correctly.
    actual_config_after_remove=$(_remove_host_block_from_config "test-server-2")
    # The awk script adds a final newline, which is desired. The heredoc for expected_config_after_remove also includes one.
    _run_string_test "$actual_config_after_remove" "$expected_config_after_remove" "_remove_host_block_from_config should remove the correct block"
}

test_remove_host() {
    # Reset the config file to a known state for this test function
    setup

    printTestSectionHeader "Testing remove_ssh_host and _cleanup_orphaned_key"

    # Create a dummy key file that will be orphaned
    touch "${SSH_DIR}/id_test1"
    touch "${SSH_DIR}/id_test1.pub"

    # --- Case 1: Key is still in use by a host, so it should not be removed ---
    MOCK_RM_CALLS=() # Reset rm call log
    # At this point, the config still has test-server-1, which uses id_test1.
    # _cleanup_orphaned_key should see this and not attempt to remove the key.
    _cleanup_orphaned_key "~/.ssh/id_test1"
    _run_string_test "${#MOCK_RM_CALLS[@]}" "0" "Should not attempt to remove a key that is still in use"

    # --- Now, actually orphan the key by removing the host from the config ---
    local config_without_host
    config_without_host=$(_remove_host_block_from_config "test-server-1")
    echo "$config_without_host" > "$SSH_CONFIG_PATH"

    # --- Case 2: Key is orphaned, but user answers 'no' to removal prompt ---
    MOCK_PROMPT_RESULT=1 # Answer "no"
    MOCK_RM_CALLS=()
    _cleanup_orphaned_key "~/.ssh/id_test1"
    _run_string_test "${#MOCK_RM_CALLS[@]}" "0" "Should not call 'rm' when user answers 'no' to cleanup"

    # --- Case 3: Key is orphaned, and user answers 'yes' to removal prompt ---
    MOCK_PROMPT_RESULT=0 # Answer "yes"
    MOCK_RM_CALLS=()
    _cleanup_orphaned_key "~/.ssh/id_test1"

    local expected_rm_call_1="-f ${SSH_DIR}/id_test1 ${SSH_DIR}/id_test1.pub"
    _run_string_test "${MOCK_RM_CALLS[0]}" "$expected_rm_call_1" "Should call 'rm' with correct private and public key paths"
}

# --- Main Test Runner ---

main() {
    # Ensure cleanup happens even if tests fail
    trap teardown EXIT

    # Run setup once
    setup

    # Execute all test functions
    test_get_ssh_hosts
    test_get_ssh_config_value
    test_process_ssh_config_blocks
    test_remove_host

    # Print summary and exit with appropriate code
    print_test_summary "ssh" "rm" "prompt_yes_no"
}

main
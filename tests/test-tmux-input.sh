#!/bin/bash
# Test script for tmux-input.sh
# Run this inside a tmux session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Adjust path to point to the script in the parent directory structure
TMUX_INPUT="$SCRIPT_DIR/../.config/tmux/scripts/dv/tmux-input.sh"

if [ -z "$TMUX" ]; then
    echo "Error: This script must be run inside tmux."
    exit 1
fi

if [ ! -f "$TMUX_INPUT" ]; then
    echo "Error: Could not find tmux-input.sh at $TMUX_INPUT"
    exit 1
fi

# Helper function to run tests and verify exit codes
run_test() {
    local description="$1"
    local expected_code="$2"
    local expected_output="$3"
    shift 3
    # Remaining arguments are the command to run
    
    echo "Test: $description"
    
    # Run the command and capture output and exit code
    # We capture stderr too, just in case of script errors
    result=$("$@" 2>&1)
    exit_code=$?
    
    echo "Output: $result"
    
    if [ "$exit_code" -eq "$expected_code" ] && [ "$result" == "$expected_output" ]; then
        echo "✅ PASS"
    else
        echo "❌ FAIL"
        echo "   Expected Code: $expected_code, Got: $exit_code"
        echo "   Expected Output: '$expected_output', Got: '$result'"
    fi
    echo "--------------------------------"
}

echo "--------------------------------"
echo "Starting tmux-input.sh Tests"
echo "--------------------------------"

# Test: Basic Success (User types specific input)
run_test "Basic Input" 0 "test" "$TMUX_INPUT" "Remove default and type 'test' then Enter" "default"

# Test: Default Value
run_test "Default Value" 0 "this is a test" "$TMUX_INPUT" "Press ENTER to accept default" "this is a test"

# Test: Custom Title
run_test "Custom Title" 0 "title" "$TMUX_INPUT" --title " Custom Title " "Press ENTER" "title"

# Test: Custom Dimensions
run_test "Custom Dimensions" 0 "dim" "$TMUX_INPUT" --width 30 --height 5 "Press ENTER" "dim"

# Test: Complex Args (Accept Default)
# Here we instruct user to just press Enter to verify default value return
run_test "Complex Args (Default Value)" 0 "Complex Default" "$TMUX_INPUT" --title " Big & Bold " --width 60 --height 10 "Press ENTER to accept default" "Complex Default"

# Test: Cancellation
# Expected output is empty string for cancellation
run_test "Cancellation" 1 "" "$TMUX_INPUT" --title " Cancel Me " "Press ESC"

# Test: Regex - Digits Only
run_test "Regex: Digits Only" 0 "123" "$TMUX_INPUT" --regex "^[0-9]+$" --val-error-msg "Digits only!" "Type '123' and Enter"

# Test: Regex - No Spaces
run_test "Regex: No Spaces" 0 "nospace" "$TMUX_INPUT" --regex "^[^ ]+$" --val-error-msg "No spaces allowed!" "Type 'nospace' and Enter"

# Test: Regex - Alphanumeric
run_test "Regex: Alphanumeric" 0 "Alpha1" "$TMUX_INPUT" --regex "^[a-zA-Z0-9]+$" "Type 'Alpha1' and Enter"

# Test: Regex - Filename Safe
run_test "Regex: Filename Safe" 0 "my_file.txt" "$TMUX_INPUT" --regex "^[a-zA-Z0-9._-]+$" "Type 'my_file.txt' and Enter"

# Test: Message Mode
run_test "Message Mode" 0 "" "$TMUX_INPUT" --message "This is a test message. Press any key to close."

# echo "Test: Color Test Mode"
# echo "Action: Verify colors look correct. Press 'q' to exit."
# "$TMUX_INPUT" --test-colors
# echo "Color test completed."
# echo "--------------------------------"

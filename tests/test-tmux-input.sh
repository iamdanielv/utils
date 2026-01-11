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
    shift 2
    # Remaining arguments are the command to run
    
    echo "Test: $description"
    
    # Run the command and capture output and exit code
    result=$("$@" 2>&1)
    exit_code=$?
    
    echo "Output: $result"
    
    if [ "$exit_code" -eq "$expected_code" ]; then
        echo "✅ PASS (Exit Code: $exit_code)"
    else
        echo "❌ FAIL (Expected: $expected_code, Got: $exit_code)"
    fi
    echo "--------------------------------"
}

echo "--------------------------------"
echo "Starting tmux-input.sh Tests"
echo "--------------------------------"

# Test 1: Basic Success
run_test "Basic Input (Press ENTER)" 0 "$TMUX_INPUT" "Press ENTER to pass" "default"

# Test 2: Custom Title
run_test "Custom Title (Press ENTER)" 0 "$TMUX_INPUT" --title " Custom Title " "Press ENTER to pass"

# Test 3: Custom Dimensions
run_test "Custom Dimensions (Press ENTER)" 0 "$TMUX_INPUT" --width 30 --height 5 "Press ENTER"

# Test 4: Complex Args
run_test "All Combined (Press ENTER)" 0 "$TMUX_INPUT" --title " Big & Bold " --width 60 --height 10 "Press ENTER" "Complex Default"

# Test 5: Cancellation
run_test "Cancellation (Press ESC)" 1 "$TMUX_INPUT" --title " Cancel Me " "Press ESC to pass"

# echo "Test 6: Color Test Mode"
# echo "Action: Verify colors look correct. Press 'q' to exit."
# "$TMUX_INPUT" --test-colors
# echo "Color test completed."
# echo "--------------------------------"

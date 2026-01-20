#!/bin/bash
# Test script for dv-input.sh
# Run this inside a tmux session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Adjust path to point to the script in the parent directory structure
TMUX_INPUT="$SCRIPT_DIR/../config/tmux/scripts/dv/dv-input.sh"

if [ -z "$TMUX" ]; then
    echo "Error: This script must be run inside tmux."
    exit 1
fi

if [ ! -f "$TMUX_INPUT" ]; then
    echo "Error: Could not find dv-input.sh at $TMUX_INPUT"
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

test_basic() {
    echo "=== Basic Input Tests ==="
    # Test: Basic Success (User types specific input)
    run_test "Basic Input" 0 "test" "$TMUX_INPUT" "Remove default and type 'test' then Enter" "default"
    # Test: Default Value
    run_test "Default Value" 0 "this is a test" "$TMUX_INPUT" "Press ENTER to accept default" "this is a test"
    # Test: Custom Title
    run_test "Custom Title" 0 "title" "$TMUX_INPUT" --title " Custom Title " "Press ENTER" "title"
    # Test: Custom Dimensions
    run_test "Custom Dimensions" 0 "dim" "$TMUX_INPUT" --width 30 --height 5 "Press ENTER" "dim"
    # Test: Complex Args (Accept Default)
    run_test "Complex Args (Default Value)" 0 "Complex Default" "$TMUX_INPUT" --title " Big & Bold " --width 60 --height 10 "Press ENTER to accept default" "Complex Default"
    # Test: Cancellation
    run_test "Cancellation" 1 "" "$TMUX_INPUT" --title " Cancel Me " "Press ESC"
}

test_validation() {
    echo "=== Validation Tests ==="
    # Test: Regex - Digits Only
    run_test "Regex: Digits Only" 0 "123" "$TMUX_INPUT" --regex "^[0-9]+$" --val-error-msg "Digits only!" "Type '123' and Enter"
    # Test: Regex - No Spaces
    run_test "Regex: No Spaces" 0 "nospace" "$TMUX_INPUT" --regex "^[^ ]+$" --val-error-msg "No spaces allowed!" "Type 'nospace' and Enter"
    # Test: Regex - Alphanumeric
    run_test "Regex: Alphanumeric" 0 "Alpha1" "$TMUX_INPUT" --regex "^[a-zA-Z0-9]+$" "Type 'Alpha1' and Enter"
    # Test: Regex - Filename Safe
    run_test "Regex: Filename Safe" 0 "my_file.txt" "$TMUX_INPUT" --regex "^[a-zA-Z0-9._-]+$" "Type 'my_file.txt' and Enter"
}

test_message() {
    echo "=== Message & Auto-size Tests ==="
    # Test: Message Mode
    run_test "Message Mode" 0 "" "$TMUX_INPUT" --message "This is a test message. Press any key to close."
    # Test: Auto-size (Short Message)
    run_test "Auto-size: Short Message" 0 "" "$TMUX_INPUT" --message "Short message."
    # Test: Auto-size (Long Message)
    run_test "Auto-size: Long Message" 0 "" "$TMUX_INPUT" --message "This is a longer message that should trigger a wider popup window calculation."
    # Test: Auto-size (Wrapping Message)
    run_test "Auto-size: Wrapping Message" 0 "" "$TMUX_INPUT" --message "This is a very long message that is intended to exceed the maximum width of the popup window. It should wrap to multiple lines and increase the height of the popup accordingly. Please verify visually."
}

test_enhanced_msg() {
    echo "=== Enhanced Message Styling Tests ==="
    # Test: Info
    run_test "Type: Info" 0 "" "$TMUX_INPUT" --type info --message "This is an INFO message."
    # Test: Success
    run_test "Type: Success" 0 "" "$TMUX_INPUT" --type success --message "This is a SUCCESS message."
    # Test: Warning
    run_test "Type: Warning" 0 "" "$TMUX_INPUT" --type warning --message "This is a WARNING message."
    # Test: Error
    run_test "Type: Error" 0 "" "$TMUX_INPUT" --type error --message "This is an ERROR message."
}

test_confirm() {
    echo "=== Confirmation Tests ==="
    # Test: Confirmation Mode (Yes)
    run_test "Confirmation (Yes)" 0 "" "$TMUX_INPUT" --confirm "Select Yes (Left Arrow + Enter)"
    # Test: Confirmation Mode (No)
    run_test "Confirmation (No)" 1 "" "$TMUX_INPUT" --confirm "Select No (Enter or Esc)"
}

test_colors() {
    echo "=== Color Test ==="
    echo "Action: Verify colors look correct. Press 'q' to exit."
    "$TMUX_INPUT" --test-colors
    echo "Color test completed."
}

echo "--------------------------------"
echo "dv-input.sh Test Suite"
echo "--------------------------------"

PS3="Select a test group: "
options=("Basic Input" "Validation" "Message/Auto-size" "Enhanced Styling" "Confirmation" "Color Test" "Run All" "Quit")
while true; do
    select opt in "${options[@]}"; do
        case $opt in
            "Basic Input") test_basic; break ;;
            "Validation") test_validation; break ;;
            "Message/Auto-size") test_message; break ;;
            "Enhanced Styling") test_enhanced_msg; break ;;
            "Confirmation") test_confirm; break ;;
            "Color Test") test_colors; break ;;
            "Run All")
                test_basic
                test_validation
                test_message
                test_enhanced_msg
                test_confirm
                break
                ;;
            "Quit") exit 0 ;;
            *) echo "Invalid option $REPLY"; break ;;
        esac
    done
    echo ""
    echo "--------------------------------"
done

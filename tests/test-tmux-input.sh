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

echo "Test 1: Basic Input (Default)"
echo "Press Enter to accept default, or type something."
result=$("$TMUX_INPUT" "Enter something basic" "default")
echo "Result: $result"
echo "--------------------------------"

echo "Test 2: Custom Title"
echo "Check if title is ' Custom Title '"
result=$("$TMUX_INPUT" --title " Custom Title " "Enter something with custom title")
echo "Result: $result"
echo "--------------------------------"

echo "Test 3: Custom Dimensions (Small: 30x5)"
result=$("$TMUX_INPUT" --width 30 --height 5 "Small Popup")
echo "Result: $result"
echo "--------------------------------"

echo "Test 4: All Combined (Title: Big & Bold, 60x10)"
result=$("$TMUX_INPUT" --title " Big & Bold " --width 60 --height 10 "Enter complex data" "Complex Default")
echo "Result: $result"
echo "--------------------------------"
#!/bin/bash
# Select a model from Cursor's model picker dropdown.
# Usage: select_model.sh <search_term> [position] [window_hint]
#   search_term:  text to type in the picker to filter results (e.g. "opus", "sonnet")
#   position:     1-based index in filtered results (default: 1 = first match)
#   window_hint:  substring to match in window title for multi-window setups (optional)
#
# The model picker is a dropdown opened by Ctrl+Shift+M. It only works when
# the chat panel has focus, not the editor. This script:
#   1. Raises the correct Cursor window (if window_hint given)
#   2. Focuses the chat panel via Cmd+L
#   3. Opens the model picker with Ctrl+Shift+M
#   4. Types the search term to filter
#   5. Arrow-downs to the target position
#   6. Presses Enter to confirm
#
# Examples:
#   select_model.sh "opus" 1                          # first "opus" result
#   select_model.sh "opus" 2                          # second "opus" result
#   select_model.sh "gemini" 1 "Experiment-Tracker"   # target specific window

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: select_model.sh <search_term> [position] [window_hint]" >&2
    exit 1
fi

SEARCH="$1"
POS="${2:-1}"
WINDOW_HINT="${3:-}"

ARROW_SCRIPT=""
for ((i = 0; i < POS; i++)); do
    ARROW_SCRIPT+='
    key code 125
    delay 0.3'
done

RAISE_SCRIPT=""
if [ -n "$WINDOW_HINT" ]; then
    RAISE_SCRIPT="
    tell process \"Cursor\"
        try
            set targetWindow to (first window whose name contains \"${WINDOW_HINT}\")
            perform action \"AXRaise\" of targetWindow
        end try
    end tell
    delay 0.3"
fi

osascript <<EOF
tell application "System Events"
    ${RAISE_SCRIPT}
end tell

tell application "Cursor" to activate
delay 0.5

tell application "System Events"
    -- Escape any open menus/dialogs
    key code 53
    delay 0.3

    -- Focus the chat panel input (Cmd+L)
    keystroke "l" using {command down}
    delay 0.8

    -- Open model picker: Ctrl+Shift+M
    keystroke "m" using {control down, shift down}
    delay 2

    -- Type search term to filter
    keystroke "${SEARCH}"
    delay 1.2

    -- Arrow down to the target position${ARROW_SCRIPT}

    -- Confirm selection
    delay 0.3
    key code 36
end tell
EOF

echo "Selected model: ${SEARCH} (position ${POS})"

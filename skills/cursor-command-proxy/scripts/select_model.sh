#!/bin/bash
# Select a model from Cursor's model picker dropdown.
# Usage: select_model.sh <search_term> [position]
#   search_term: text to type in the picker to filter results (e.g. "opus", "sonnet")
#   position:    1-based index in filtered results (default: 1 = first match)
#
# Examples:
#   select_model.sh "opus" 1        # first "opus" result (opus-max)
#   select_model.sh "opus" 2        # second "opus" result (opus)
#   select_model.sh "sonnet" 1      # first "sonnet" result

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: select_model.sh <search_term> [position]" >&2
    exit 1
fi

SEARCH="$1"
POS="${2:-1}"

ARROW_SCRIPT=""
for ((i = 0; i < POS; i++)); do
    ARROW_SCRIPT+='
    key code 125
    delay 0.3'
done

osascript <<EOF
tell application "Cursor" to activate
delay 0.3
tell application "System Events"
    -- Open model picker: Ctrl+Shift+M
    keystroke "m" using {control down, shift down}
    delay 1.2

    -- Type search term
    keystroke "${SEARCH}"
    delay 0.8

    -- Arrow down to the target position${ARROW_SCRIPT}

    -- Confirm selection
    delay 0.2
    key code 36
end tell
EOF

echo "Selected model: ${SEARCH} (position ${POS})"

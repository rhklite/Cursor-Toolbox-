#!/bin/bash
# Execute a command via Cursor's Command Palette (Cmd+Shift+P).
# Usage: cmd_palette.sh "Command Name" ["Secondary Selection"]
# Examples:
#   cmd_palette.sh "Markdown Preview Enhanced: Open Preview to the Side"
#   cmd_palette.sh "Remote-SSH: Connect to Host..." "myhost"

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: cmd_palette.sh \"Command Name\" [\"Secondary Selection\"]" >&2
    exit 1
fi

COMMAND_TEXT="$1"
SECONDARY="${2:-}"

osascript <<EOF
tell application "Cursor" to activate
delay 0.2
tell application "System Events"
    -- Open Command Palette: Cmd+Shift+P
    keystroke "p" using {command down, shift down}
    delay 0.5

    -- Type the command name
    keystroke "${COMMAND_TEXT}"
    delay 0.4

    -- Press Enter to execute
    key code 36
end tell
EOF

if [ -n "$SECONDARY" ]; then
    sleep 0.6
    osascript <<EOF
tell application "System Events"
    keystroke "${SECONDARY}"
    delay 0.3
    key code 36
end tell
EOF
    echo "Executed: ${COMMAND_TEXT} -> ${SECONDARY}"
else
    echo "Executed: ${COMMAND_TEXT}"
fi

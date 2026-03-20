#!/bin/bash
# Send a keyboard shortcut to Cursor via osascript.
# Usage: send_shortcut.sh <key> [modifier1] [modifier2] ...
#   Modifiers: "command down", "shift down", "control down", "option down"
# Examples:
#   send_shortcut.sh "b" "command down"               # Cmd+B
#   send_shortcut.sh "=" "command down"               # Cmd+=
#   send_shortcut.sh "a" "control down" "shift down"  # Ctrl+Shift+A
#   send_shortcut.sh "i" "command down"               # Cmd+I

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: send_shortcut.sh <key> [modifier1] [modifier2] ..." >&2
    exit 1
fi

KEY="$1"
shift

MODIFIERS=""
if [ $# -gt 0 ]; then
    MODIFIERS=$(printf ", %s" "$@")
    MODIFIERS=" using {${MODIFIERS:2}}"
fi

osascript <<EOF
tell application "Cursor" to activate
delay 0.2
tell application "System Events"
    keystroke "${KEY}"${MODIFIERS}
end tell
EOF

echo "Sent keystroke: ${KEY}${MODIFIERS:+ (${*})}"

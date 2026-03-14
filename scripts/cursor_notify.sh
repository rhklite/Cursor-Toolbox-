#!/usr/bin/env bash
# General-purpose desktop notification for Cursor rules/commands.
# Usage: cursor_notify.sh "Title" "Body"
# macOS: osascript notification. Linux: notify-send. Headless/SSH: silent no-op.
set -euo pipefail

title="${1:-Cursor}"
body="${2:-}"

[[ -z "${body}" ]] && exit 0

if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${body}\" with title \"${title}\"" 2>/dev/null || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "${title}" "${body}" 2>/dev/null || true
fi

#!/usr/bin/env bash
set -euo pipefail

TOOLBOX_DIR="${HOME}/.cursor"
DEBOUNCE_SECS="${TOOLBOX_SYNC_DEBOUNCE:-30}"
LOG="${TOOLBOX_DIR}/logs/toolbox_sync_watcher.log"
LOCK="/tmp/toolbox_sync_watcher.lock"

WATCHED_DIRS=(skills commands rules scripts agents)

mkdir -p "$(dirname "$LOG")"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

if [ -f "$LOCK" ]; then
  lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
  if [ "$lock_age" -lt "$DEBOUNCE_SECS" ]; then
    log "debounce: skipped (lock age ${lock_age}s < ${DEBOUNCE_SECS}s)"
    exit 0
  fi
  rm -f "$LOCK"
fi
touch "$LOCK"

log "watcher triggered, debouncing ${DEBOUNCE_SECS}s"
sleep "$DEBOUNCE_SECS"

dirty_files=()
for dir in "${WATCHED_DIRS[@]}"; do
  target="${TOOLBOX_DIR}/${dir}"
  [ -d "$target" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] && dirty_files+=("$line")
  done < <(git -C "$TOOLBOX_DIR" status --short -- "$dir" 2>/dev/null)
done

rm -f "$LOCK"

if [ ${#dirty_files[@]} -eq 0 ]; then
  log "clean: no uncommitted toolbox changes"
  exit 0
fi

log "DIRTY: ${#dirty_files[@]} uncommitted toolbox file(s)"
for f in "${dirty_files[@]}"; do
  log "  $f"
done

osascript -e "display notification \"${#dirty_files[@]} toolbox file(s) not synced\" with title \"Cursor Toolbox\" subtitle \"Run Sync Toolbox\"" 2>/dev/null || true

exit 0

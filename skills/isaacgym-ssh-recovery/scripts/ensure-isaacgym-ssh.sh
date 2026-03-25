#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${1:-isaacgym}"

if ! docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
  echo "Container $CONTAINER_NAME is not running." >&2
  exit 1
fi

SSHD_RUNNING=$(docker exec "$CONTAINER_NAME" pgrep -x sshd 2>/dev/null || true)

if [ -z "$SSHD_RUNNING" ]; then
  docker exec --user root "$CONTAINER_NAME" /usr/sbin/sshd
fi

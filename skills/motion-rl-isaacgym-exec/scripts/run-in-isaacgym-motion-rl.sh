#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <command> [args...]"
  exit 2
fi

SSH_ALIAS="isaacgym"
WORKDIR="/home/huh/software/motion_rl"
# Build a safely escaped command string for remote bash.
escaped_cmd=""
for arg in "$@"; do
  escaped_arg=$(printf "%q" "$arg")
  if [ -z "$escaped_cmd" ]; then
    escaped_cmd="$escaped_arg"
  else
    escaped_cmd="$escaped_cmd $escaped_arg"
  fi
done

ssh "${SSH_ALIAS}" "cd ${WORKDIR} && ${escaped_cmd}"

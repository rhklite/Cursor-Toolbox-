#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_ALIAS="${SSH_ALIAS:-isaacgym}"
JUMP_HOST="${ISAACGYM_JUMP_HOST:-huh.desktop.us}"
HEALTHCHECK_SCRIPT="${ISAACGYM_HEALTHCHECK_SCRIPT:-$HOME/.cursor/scripts/restart_isaacgym_healthcheck.sh}"

echo "[1/4] Local precheck: verify jump host reachable"
ssh -o BatchMode=yes -o ConnectTimeout=12 "${JUMP_HOST}" "echo jump_host_ok" >/dev/null

echo "[2/4] Ensure in-container SSH service bootstrap"
bash "${SCRIPT_DIR}/ensure-isaacgym-ssh.sh"

echo "[3/4] Restart container + run quick GPU/display checks on ${JUMP_HOST}"
ssh -o BatchMode=yes -o ConnectTimeout=20 "${JUMP_HOST}" \
  "bash \"${HEALTHCHECK_SCRIPT}\""

echo "[4/4] Verify local SSH alias ${SSH_ALIAS}"
ssh -o ConnectTimeout=12 "${SSH_ALIAS}" "hostname && whoami"

echo "Recovery complete: ssh ${SSH_ALIAS} and quick health checks passed."

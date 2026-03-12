#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${ISAACGYM_CONTAINER_NAME:-isaacgym}"
CONTAINER_USER="${ISAACGYM_CONTAINER_USER:-huh}"
CONTAINER_PORT="${ISAACGYM_SSH_PORT:-22022}"
DISPLAY_FALLBACK="${ISAACGYM_DISPLAY_FALLBACK:-:1}"

pass() {
  printf '[PASS] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1" >&2
}

restart_ok=0
ssh_ok=0
gpu_ok=0
display_ok=0

if docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true; then
  :
fi
if docker start "${CONTAINER_NAME}" >/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' | awk -v n="${CONTAINER_NAME}" '$1==n{ok=1} END{exit ok?0:1}'; then
    restart_ok=1
    pass "container restart: ${CONTAINER_NAME}"
  else
    fail "container restart: ${CONTAINER_NAME} not running"
  fi
else
  fail "container restart failed"
fi

if [[ "${restart_ok}" -eq 1 ]]; then
  if docker exec -u 0 "${CONTAINER_NAME}" sh -lc '
set -e
if [ ! -x /usr/sbin/sshd ]; then
  echo "Missing /usr/sbin/sshd" >&2
  exit 11
fi
if [ ! -e /usr/bin/zsh ]; then
  ln -s /bin/bash /usr/bin/zsh
fi
mkdir -p /run/sshd /home/'"${CONTAINER_USER}"'/.ssh
if [ ! -f /home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -t ed25519 -N "" -f /home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key >/dev/null
  chown '"${CONTAINER_USER}"':'"${CONTAINER_USER}"' /home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key /home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key.pub
  chmod 600 /home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key
  chmod 644 /home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key.pub
fi
/usr/bin/pkill -x sshd >/dev/null 2>&1 || true
/usr/sbin/sshd -f /dev/null \
  -o Port='"${CONTAINER_PORT}"' \
  -o ListenAddress=0.0.0.0 \
  -o PidFile=/tmp/sshd_cursor_'"${CONTAINER_PORT}"'.pid \
  -o HostKey=/home/'"${CONTAINER_USER}"'/.ssh/ssh_host_ed25519_key \
  -o AuthorizedKeysFile=.ssh/authorized_keys \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o ChallengeResponseAuthentication=no \
  -o UsePAM=no \
  -o PermitRootLogin=no \
  -o PubkeyAuthentication=yes \
  -o AllowUsers='"${CONTAINER_USER}"' \
  -o StrictModes=no \
  -o Subsystem="sftp internal-sftp"
' && nc -z 127.0.0.1 "${CONTAINER_PORT}"; then
    ssh_ok=1
    pass "ssh service on container port ${CONTAINER_PORT}"
  else
    fail "ssh service check failed"
  fi
fi

if [[ "${restart_ok}" -eq 1 ]]; then
  if docker exec "${CONTAINER_NAME}" sh -lc 'nvidia-smi >/dev/null 2>&1'; then
    gpu_ok=1
    pass "gpu check (nvidia-smi)"
  else
    fail "gpu check failed (nvidia-smi)"
  fi
fi

if [[ "${restart_ok}" -eq 1 ]]; then
  if docker exec "${CONTAINER_NAME}" sh -lc '
display="${DISPLAY:-'"${DISPLAY_FALLBACK}"'}"
[ -n "${display}" ]
[ -d /tmp/.X11-unix ]
ls /tmp/.X11-unix/X* >/dev/null 2>&1
'; then
    display_ok=1
    pass "display readiness (/tmp/.X11-unix + DISPLAY)"
  else
    fail "display readiness check failed"
  fi
fi

echo "restart_isaacgym_summary:"
echo "- container_restart: $([[ "${restart_ok}" -eq 1 ]] && echo pass || echo fail)"
echo "- ssh_service: $([[ "${ssh_ok}" -eq 1 ]] && echo pass || echo fail)"
echo "- gpu: $([[ "${gpu_ok}" -eq 1 ]] && echo pass || echo fail)"
echo "- display: $([[ "${display_ok}" -eq 1 ]] && echo pass || echo fail)"

if [[ "${restart_ok}" -eq 1 && "${ssh_ok}" -eq 1 && "${gpu_ok}" -eq 1 && "${display_ok}" -eq 1 ]]; then
  exit 0
fi

exit 2

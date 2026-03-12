#!/usr/bin/env bash
set -euo pipefail

JUMP_HOST="${ISAACGYM_JUMP_HOST:-huh.desktop.us}"
CONTAINER_NAME="${ISAACGYM_CONTAINER_NAME:-isaacgym}"
CONTAINER_USER="${ISAACGYM_CONTAINER_USER:-huh}"
CONTAINER_PORT="${ISAACGYM_SSH_PORT:-22022}"

ssh "${JUMP_HOST}" "CONTAINER_NAME='${CONTAINER_NAME}' CONTAINER_USER='${CONTAINER_USER}' CONTAINER_PORT='${CONTAINER_PORT}' bash -s" <<'REMOTE'
set -euo pipefail

docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true

if ! docker ps --format '{{.Names}}' | awk -v target="${CONTAINER_NAME}" '$1==target{found=1} END{exit found?0:1}'; then
  echo "Container '${CONTAINER_NAME}' is not running on jump host." >&2
  exit 10
fi

docker exec -u 0 "${CONTAINER_NAME}" sh -lc '
set -e

if [ ! -x /usr/sbin/sshd ]; then
  echo "Missing /usr/sbin/sshd in container. Install openssh-server in the container first." >&2
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
'

nc -z 127.0.0.1 "${CONTAINER_PORT}"
REMOTE

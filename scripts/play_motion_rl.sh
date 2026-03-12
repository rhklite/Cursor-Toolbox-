#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "Usage: $0 <command> [args...]"
  exit 2
fi

WORKDIR="/home/huh/software/motion_rl"
SSH_ALIAS="${MOTION_RL_SSH_ALIAS:-isaacgym}"
CONTAINER_NAME="${MOTION_RL_CONTAINER_NAME:-isaacgym}"
CONTAINER_USER="${MOTION_RL_CONTAINER_USER:-huh}"
REMOTE_RUNNER="${HOME}/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh"

is_inside_container() {
  [[ -f "/.dockerenv" && -d "${WORKDIR}" ]]
}

has_arg() {
  local needle="$1"
  shift
  for token in "$@"; do
    if [[ "${token}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

has_prefix_arg() {
  local prefix="$1"
  shift
  for token in "$@"; do
    if [[ "${token}" == "${prefix}"* ]]; then
      return 0
    fi
  done
  return 1
}

is_play_py_command() {
  local token
  for token in "$@"; do
    if [[ "${token}" == *"humanoid-gym/humanoid/scripts/play.py" || "${token}" == "play.py" ]]; then
      return 0
    fi
  done
  return 1
}

build_escaped_cmd() {
  local escaped=""
  local arg
  for arg in "$@"; do
    local q
    q=$(printf "%q" "${arg}")
    if [[ -z "${escaped}" ]]; then
      escaped="${q}"
    else
      escaped="${escaped} ${q}"
    fi
  done
  printf "%s" "${escaped}"
}

args=("$@")

if is_play_py_command "${args[@]}"; then
  if ! has_prefix_arg "DISPLAY=" "${args[@]}"; then
    args=("DISPLAY=:1" "${args[@]}")
  fi
  if ! has_arg "--resume" "${args[@]}"; then
    args+=("--resume")
  fi
  if ! has_arg "--total_steps" "${args[@]}"; then
    args+=("--total_steps" "100000000")
  fi
  if ! has_arg "--task" "${args[@]}"; then
    echo "Missing required argument for play.py: --task <value>" >&2
    exit 2
  fi
  if ! has_arg "--load_run" "${args[@]}"; then
    echo "Missing required argument for play.py: --load_run <value>" >&2
    exit 2
  fi
fi

escaped_cmd="$(build_escaped_cmd "${args[@]}")"

if is_inside_container; then
  echo "route: direct-container"
  bash -lc "cd ${WORKDIR} && ${escaped_cmd}"
  exit $?
fi

if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | awk -v target="${CONTAINER_NAME}" '$1==target{found=1} END{exit found?0:1}'; then
  echo "route: host-docker-exec"
  docker exec "${CONTAINER_NAME}" /bin/bash -lc "cd ${WORKDIR} && ${escaped_cmd}"
  exit $?
fi

if [[ ! -x "${REMOTE_RUNNER}" ]]; then
  echo "Missing motion rl remote runner: ${REMOTE_RUNNER}" >&2
  exit 3
fi

echo "route: ssh-routed (${SSH_ALIAS})"
bash "${REMOTE_RUNNER}" "${args[@]}"

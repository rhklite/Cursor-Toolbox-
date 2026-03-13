#!/usr/bin/env bash
set -euo pipefail

JUMP_HOST="huh.desktop.us"
ISAACGYM_RUNNER="${HOME}/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh"
HEALTHCHECK_SCRIPT="${HOME}/.cursor/scripts/restart_isaacgym_healthcheck.sh"
REMOTE_WORKDIR="/home/huh/software/motion_rl"
REMOTE_CKPT_DIR="${REMOTE_WORKDIR}"
REMOTE_LAYOUT_DIR="${REMOTE_WORKDIR}"
DEFAULT_LAYOUT="${REMOTE_WORKDIR}/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml"
DEFAULT_TOTAL_STEPS="100000000"
DISPLAY_VAR=":1"
PJ_LOG="/tmp/plotjuggler.log"

usage() {
  cat <<'EOF'
Usage: play_motion_rl.sh --task <name> --checkpoint <path> [OPTIONS]

Required:
  --task          Task name from the registry
  --checkpoint    Path to .pt checkpoint (local or remote path)

Options:
  --layout        PlotJuggler layout XML (local or remote path; default: r01_plus_amp_plotjuggler_limit_inspect.xml)
  --total_steps   Total play steps (default: 100000000)
  --skip-health   Skip container healthcheck
  --pull          Pull latest changes on remote repo (skip prompt)
  --no-pull       Do not pull (skip prompt)
  --interactive   Use play_interactive.py (keyboard velocity/push/reset + HUD)
  --push_vel_xy   Max push velocity for interactive keyboard push (default: 1.0)
  --help          Show this help
EOF
  exit "${1:-0}"
}

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
err()   { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*" >&2; }

TASK=""
CHECKPOINT=""
LAYOUT="${DEFAULT_LAYOUT}"
LAYOUT_USER_SET=0
TOTAL_STEPS="${DEFAULT_TOTAL_STEPS}"
SKIP_HEALTH=0
PULL_REPO=""
INTERACTIVE=0
PUSH_VEL_XY="1.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)          TASK="$2";          shift 2 ;;
    --checkpoint)    CHECKPOINT="$2";    shift 2 ;;
    --layout)        LAYOUT="$2"; LAYOUT_USER_SET=1; shift 2 ;;
    --total_steps)   TOTAL_STEPS="$2";   shift 2 ;;
    --skip-health)   SKIP_HEALTH=1;      shift   ;;
    --pull)          PULL_REPO=1;        shift   ;;
    --no-pull)       PULL_REPO=0;        shift   ;;
    --interactive)   INTERACTIVE=1;      shift   ;;
    --push_vel_xy)   PUSH_VEL_XY="$2";  shift 2 ;;
    --help|-h)       usage 0                     ;;
    *)               err "Unknown arg: $1"; usage 2 ;;
  esac
done

[[ -z "${TASK}" ]]       && { err "Missing --task";       usage 2; }
[[ -z "${CHECKPOINT}" ]] && { err "Missing --checkpoint"; usage 2; }

# ---------- 1. Container healthcheck ----------
if [[ "${SKIP_HEALTH}" -eq 0 ]]; then
  info "Running container healthcheck on ${JUMP_HOST}..."
  if ssh "${JUMP_HOST}" "bash ${HEALTHCHECK_SCRIPT}"; then
    ok "Container healthy"
  else
    err "Container healthcheck failed"
    exit 1
  fi
else
  info "Skipping container healthcheck (--skip-health)"
fi

# ---------- 2. Pull latest changes ----------
if [[ -z "${PULL_REPO}" ]]; then
  if [[ -t 0 ]]; then
    read -rp $'\033[1;34m[INFO]\033[0m  Pull latest changes for motion_rl on remote? [y/N] ' pull_answer
    [[ "${pull_answer}" =~ ^[Yy]$ ]] && PULL_REPO=1 || PULL_REPO=0
  else
    PULL_REPO=0
  fi
fi
if [[ "${PULL_REPO}" -eq 1 ]]; then
  info "Pulling latest changes on ${JUMP_HOST}:${REMOTE_WORKDIR}..."
  if ssh "${JUMP_HOST}" "git -C '${REMOTE_WORKDIR}' pull --ff-only"; then
    ok "Repo updated"
  else
    err "git pull --ff-only failed (divergent or uncommitted changes?). Continuing with current state."
  fi
else
  info "Skipping repo pull"
fi

# ---------- 3. Resolve checkpoint ----------
REMOTE_CKPT=""
if [[ -f "${CHECKPOINT}" ]]; then
  BASENAME="$(basename "${CHECKPOINT}")"
  info "Local checkpoint detected, copying to ${JUMP_HOST}..."
  scp "${CHECKPOINT}" "${JUMP_HOST}:${REMOTE_CKPT_DIR}/"
  REMOTE_CKPT="${REMOTE_CKPT_DIR}/${BASENAME}"
  ok "Checkpoint uploaded: ${REMOTE_CKPT}"
else
  info "Treating checkpoint as remote path: ${CHECKPOINT}"
  if ssh "${JUMP_HOST}" "test -f '${CHECKPOINT}'"; then
    REMOTE_CKPT="${CHECKPOINT}"
    ok "Remote checkpoint verified: ${REMOTE_CKPT}"
  else
    err "Checkpoint not found locally or on ${JUMP_HOST}: ${CHECKPOINT}"
    exit 1
  fi
fi

# ---------- 4. Resolve layout ----------
REMOTE_LAYOUT="${LAYOUT}"
if [[ "${LAYOUT_USER_SET}" -eq 1 && -f "${LAYOUT}" ]]; then
  BASENAME="$(basename "${LAYOUT}")"
  info "Local layout XML detected, copying to ${JUMP_HOST}..."
  scp "${LAYOUT}" "${JUMP_HOST}:${REMOTE_LAYOUT_DIR}/"
  REMOTE_LAYOUT="${REMOTE_LAYOUT_DIR}/${BASENAME}"
  ok "Layout uploaded: ${REMOTE_LAYOUT}"
elif [[ "${LAYOUT_USER_SET}" -eq 1 ]]; then
  info "Treating layout as remote path: ${LAYOUT}"
  if ssh "${JUMP_HOST}" "test -f '${LAYOUT}'"; then
    REMOTE_LAYOUT="${LAYOUT}"
    ok "Remote layout verified: ${REMOTE_LAYOUT}"
  else
    err "Layout not found locally or on ${JUMP_HOST}: ${LAYOUT}"
    exit 1
  fi
fi

# ---------- 5. Kill existing PlotJuggler ----------
info "Stopping any existing PlotJuggler on ${JUMP_HOST}..."
ssh "${JUMP_HOST}" "pkill -f plotjuggler 2>/dev/null || true"
sleep 1

# ---------- 6. Launch PlotJuggler ----------
info "Launching PlotJuggler on ${JUMP_HOST} (layout: $(basename "${REMOTE_LAYOUT}"))..."
ssh "${JUMP_HOST}" "DISPLAY=${DISPLAY_VAR} nohup plotjuggler --nosplash --layout '${REMOTE_LAYOUT}' > ${PJ_LOG} 2>&1 &"

PJ_OK=0
for i in 1 2 3 4 5; do
  sleep 1
  if ssh "${JUMP_HOST}" "pgrep -f plotjuggler >/dev/null 2>&1"; then
    PJ_PID=$(ssh "${JUMP_HOST}" "pgrep -f 'plotjuggler.*--layout' | head -1")
    PJ_OK=1
    break
  fi
done

if [[ "${PJ_OK}" -eq 1 ]]; then
  ok "PlotJuggler running (PID ${PJ_PID})"
else
  CRASH_LOG=$(ssh "${JUMP_HOST}" "cat ${PJ_LOG} 2>/dev/null | tail -10")
  err "PlotJuggler failed to start. Log:"
  echo "${CRASH_LOG}" >&2
  exit 1
fi

# ---------- 7. Launch play script ----------
if [[ "${INTERACTIVE}" -eq 1 ]]; then
  PLAY_SCRIPT="humanoid-gym/humanoid/scripts/play_interactive.py"
  info "Launching play_interactive.py in isaacgym container..."
else
  PLAY_SCRIPT="humanoid-gym/humanoid/scripts/play.py"
  info "Launching play.py in isaacgym container..."
fi
info "  task:       ${TASK}"
info "  checkpoint: ${REMOTE_CKPT}"
info "  steps:      ${TOTAL_STEPS}"
if [[ "${INTERACTIVE}" -eq 1 ]]; then
  info "  mode:       interactive (keyboard control)"
  info "  push_vel:   ${PUSH_VEL_XY}"
fi

PLAY_EXTRA_ARGS=""
if [[ "${INTERACTIVE}" -eq 1 ]]; then
  PLAY_EXTRA_ARGS="--push_vel_xy ${PUSH_VEL_XY}"
fi

bash "${ISAACGYM_RUNNER}" \
  DISPLAY=${DISPLAY_VAR} \
  python "${PLAY_SCRIPT}" \
  --task "${TASK}" \
  --checkpoint_path "${REMOTE_CKPT}" \
  --resume \
  --total_steps "${TOTAL_STEPS}" \
  ${PLAY_EXTRA_ARGS} &

PLAY_BG_PID=$!

PLAY_SCRIPT_BASE="$(basename "${PLAY_SCRIPT}")"
PLAY_OK=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 3
  if ssh "${JUMP_HOST}" "pgrep -af '${PLAY_SCRIPT_BASE}.*--task' >/dev/null 2>&1"; then
    PLAY_PID=$(ssh "${JUMP_HOST}" "pgrep -f '${PLAY_SCRIPT_BASE}.*--task' | head -1")
    PLAY_OK=1
    break
  fi
  if ! kill -0 "${PLAY_BG_PID}" 2>/dev/null; then
    err "play.py process exited early"
    wait "${PLAY_BG_PID}" || true
    exit 1
  fi
done

if [[ "${PLAY_OK}" -eq 1 ]]; then
  ok "${PLAY_SCRIPT_BASE} running (PID ${PLAY_PID})"
else
  err "${PLAY_SCRIPT_BASE} did not start within 30s"
  exit 1
fi

# ---------- 8. Summary ----------
echo ""
echo "=========================================="
echo "  Play Motion RL - SUCCESS"
echo "=========================================="
echo "  PlotJuggler PID:  ${PJ_PID}"
echo "  ${PLAY_SCRIPT_BASE} PID: ${PLAY_PID}"
echo "  Task:             ${TASK}"
echo "  Checkpoint:       ${REMOTE_CKPT}"
echo "  Layout:           $(basename "${REMOTE_LAYOUT}")"
echo ""
echo "  Next step:"
echo "    In PlotJuggler: Streaming -> Start: UDP Server"
echo "    Port: 9870, Protocol: JSON"
if [[ "${INTERACTIVE}" -eq 1 ]]; then
  echo ""
  echo "  Keyboard (Isaac Gym viewer):"
  echo "    W/S = fwd/back  A/D = left/right  Q/E = yaw"
  echo "    0 = stop  R = reset  P = push  ESC = quit"
fi
echo "=========================================="

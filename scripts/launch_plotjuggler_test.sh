#!/usr/bin/env bash
set -euo pipefail

JUMP_HOST="huh.desktop.us"
ISAACGYM_RUNNER="${HOME}/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh"
HEALTHCHECK_SCRIPT="${HOME}/.cursor/scripts/restart_isaacgym_healthcheck.sh"
REMOTE_WORKDIR="/home/huh/software/motion_rl"
REMOTE_CKPT_DIR="${REMOTE_WORKDIR}"
DEFAULT_LAYOUT="${REMOTE_WORKDIR}/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml"
DEFAULT_TOTAL_STEPS="100000000"
DISPLAY_VAR=":1"
PJ_LOG="/tmp/plotjuggler.log"

usage() {
  cat <<'EOF'
Usage: launch_plotjuggler_test.sh --task <name> --checkpoint <path> [OPTIONS]

Required:
  --task          Task name from the registry
  --checkpoint    Path to .pt checkpoint (local Mac path or remote path)

Options:
  --layout        PlotJuggler layout XML path on remote (default: r01_plus_amp_plotjuggler_limit_inspect.xml)
  --total_steps   Total play steps (default: 100000000)
  --skip-health   Skip container healthcheck
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
TOTAL_STEPS="${DEFAULT_TOTAL_STEPS}"
SKIP_HEALTH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)          TASK="$2";          shift 2 ;;
    --checkpoint)    CHECKPOINT="$2";    shift 2 ;;
    --layout)        LAYOUT="$2";        shift 2 ;;
    --total_steps)   TOTAL_STEPS="$2";   shift 2 ;;
    --skip-health)   SKIP_HEALTH=1;      shift   ;;
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

# ---------- 2. Resolve checkpoint ----------
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

# ---------- 3. Kill existing PlotJuggler ----------
info "Stopping any existing PlotJuggler on ${JUMP_HOST}..."
ssh "${JUMP_HOST}" "pkill -f plotjuggler 2>/dev/null || true"
sleep 1

# ---------- 4. Launch PlotJuggler ----------
info "Launching PlotJuggler on ${JUMP_HOST} (layout: $(basename "${LAYOUT}"))..."
ssh "${JUMP_HOST}" "DISPLAY=${DISPLAY_VAR} nohup plotjuggler --nosplash --layout '${LAYOUT}' > ${PJ_LOG} 2>&1 &"

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

# ---------- 5. Launch play.py ----------
info "Launching play.py in isaacgym container..."
info "  task:       ${TASK}"
info "  checkpoint: ${REMOTE_CKPT}"
info "  steps:      ${TOTAL_STEPS}"

bash "${ISAACGYM_RUNNER}" \
  DISPLAY=${DISPLAY_VAR} \
  python humanoid-gym/humanoid/scripts/play.py \
  --task "${TASK}" \
  --checkpoint_path "${REMOTE_CKPT}" \
  --resume \
  --total_steps "${TOTAL_STEPS}" &

PLAY_BG_PID=$!

PLAY_OK=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 3
  if ssh "${JUMP_HOST}" "pgrep -af 'play.py.*--task' >/dev/null 2>&1"; then
    PLAY_PID=$(ssh "${JUMP_HOST}" "pgrep -f 'play.py.*--task' | head -1")
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
  ok "play.py running (PID ${PLAY_PID})"
else
  err "play.py did not start within 30s"
  exit 1
fi

# ---------- 6. Summary ----------
echo ""
echo "=========================================="
echo "  PlotJuggler Test Launch - SUCCESS"
echo "=========================================="
echo "  PlotJuggler PID:  ${PJ_PID}"
echo "  play.py PID:      ${PLAY_PID}"
echo "  Task:             ${TASK}"
echo "  Checkpoint:       ${REMOTE_CKPT}"
echo "  Layout:           $(basename "${LAYOUT}")"
echo ""
echo "  Next step:"
echo "    In PlotJuggler: Streaming -> Start: UDP Server"
echo "    Port: 9870, Protocol: JSON"
echo "=========================================="

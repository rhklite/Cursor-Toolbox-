#!/usr/bin/env bash
set -euo pipefail

JUMP_HOST="huh.desktop.us"
ISAACGYM_RUNNER="${HOME}/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh"
HEALTHCHECK_SCRIPT="${HOME}/.cursor/scripts/restart_isaacgym_healthcheck.sh"
REMOTE_WORKDIR="/home/huh/software/motion_rl"
REMOTE_CKPT_DIR="${REMOTE_WORKDIR}"
REMOTE_LAYOUT_DIR="${REMOTE_WORKDIR}"
DEFAULT_TASK="r01_v12_amp_with_4dof_arms_and_head_full_scenes"
DEFAULT_LAYOUT="${REMOTE_WORKDIR}/humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml"
DEFAULT_TOTAL_STEPS="100000000"
DISPLAY_VAR=":1"
PJ_LOG="/tmp/plotjuggler.log"

usage() {
  cat <<'EOF'
Usage: play_motion_rl.sh --checkpoint <path> [OPTIONS]

Required:
  --checkpoint    Path to .pt checkpoint (local or remote path)

Options:
  --task          Task name from the registry (default: r01_v12_amp_with_4dof_arms_and_head_full_scenes)
  --layout        PlotJuggler layout XML (local or remote path; default: r01_plotjuggler_full.xml)
  --total_steps   Total play steps (default: 100000000)
  --skip-health   Skip container healthcheck
  --pull          Pull latest changes on remote repo (skip prompt)
  --no-pull       Do not pull (skip prompt)
  --replace       Kill existing play.py and launch new one (skip prompt)
  --refresh       Keep existing play.py, just refresh PlotJuggler (skip prompt)
  --interactive   Use play_interactive.py (modal disturbance controls + HUD; default: enabled)
  --help          Show this help
EOF
  exit "${1:-0}"
}

info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
err()   { printf '\033[1;31m[FAIL]\033[0m  %s\n' "$*" >&2; }

TASK="${DEFAULT_TASK}"
CHECKPOINT=""
LAYOUT="${DEFAULT_LAYOUT}"
LAYOUT_USER_SET=0
TOTAL_STEPS="${DEFAULT_TOTAL_STEPS}"
SKIP_HEALTH=0
PULL_REPO=""
PROCESS_ACTION=""
INTERACTIVE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)          TASK="$2";          shift 2 ;;
    --checkpoint)    CHECKPOINT="$2";    shift 2 ;;
    --layout)        LAYOUT="$2"; LAYOUT_USER_SET=1; shift 2 ;;
    --total_steps)   TOTAL_STEPS="$2";   shift 2 ;;
    --skip-health)   SKIP_HEALTH=1;      shift   ;;
    --pull)          PULL_REPO=1;        shift   ;;
    --no-pull)       PULL_REPO=0;        shift   ;;
    --replace)       PROCESS_ACTION="replace"; shift ;;
    --refresh)       PROCESS_ACTION="refresh"; shift ;;
    --interactive)   INTERACTIVE=1;      shift   ;;
    --help|-h)       usage 0                     ;;
    *)               err "Unknown arg: $1"; usage 2 ;;
  esac
done

# ---------- 1. Detect existing play.py processes ----------
EXISTING_PROCS=""
EXISTING_PROCS=$(ssh "${JUMP_HOST}" "pgrep -af 'play.*\.py.*--task' 2>/dev/null" || true)

REFRESH_ONLY=0

if [[ -n "${EXISTING_PROCS}" ]]; then
  if [[ "${PROCESS_ACTION}" == "refresh" ]]; then
    info "Existing process found — refresh mode (keeping existing):"
    echo "${EXISTING_PROCS}" | while IFS= read -r line; do info "  ${line}"; done
    REFRESH_ONLY=1
  elif [[ "${PROCESS_ACTION}" == "replace" ]]; then
    info "Existing process found — replacing:"
    echo "${EXISTING_PROCS}" | while IFS= read -r line; do info "  ${line}"; done
    ssh "${JUMP_HOST}" "pkill -f 'play.*\.py.*--task' 2>/dev/null || true"
    sleep 2
    ok "Existing process killed"
    SKIP_HEALTH=1
  else
    info "Existing process detected:"
    echo "${EXISTING_PROCS}" | while IFS= read -r line; do info "  ${line}"; done
    if [[ -t 0 ]]; then
      read -rp $'\033[1;34m[INFO]\033[0m  Replace with new process? [y/N] ' replace_answer
      if [[ "${replace_answer}" =~ ^[Yy]$ ]]; then
        ssh "${JUMP_HOST}" "pkill -f 'play.*\.py.*--task' 2>/dev/null || true"
        sleep 2
        ok "Existing process killed"
        SKIP_HEALTH=1
      else
        info "Keeping existing process — refreshing PlotJuggler only"
        REFRESH_ONLY=1
      fi
    else
      info "Non-interactive mode — proceeding with fresh launch"
    fi
  fi
elif [[ "${PROCESS_ACTION}" == "refresh" ]]; then
  err "No existing play.py process found — nothing to refresh against"
  exit 1
fi

if [[ "${REFRESH_ONLY}" -eq 0 ]]; then
  [[ -z "${CHECKPOINT}" ]] && { err "Missing --checkpoint"; usage 2; }
fi

# ---------- 2. Container healthcheck ----------
if [[ "${REFRESH_ONLY}" -eq 1 ]]; then
  info "Skipping container healthcheck (refresh mode)"
elif [[ "${SKIP_HEALTH}" -eq 0 ]]; then
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

# ---------- 3. Pull latest changes ----------
if [[ "${REFRESH_ONLY}" -eq 1 ]]; then
  info "Skipping repo pull (refresh mode)"
else
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
fi

# ---------- 4. Resolve checkpoint ----------
if [[ "${REFRESH_ONLY}" -eq 1 ]]; then
  REMOTE_CKPT="(existing)"
else
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
fi

# ---------- 5. Resolve layout ----------
REMOTE_LAYOUT="${LAYOUT}"
if [[ "${LAYOUT_USER_SET}" -eq 1 && -f "${LAYOUT}" ]]; then
  BASENAME="$(basename "${LAYOUT}")"
  info "Local layout XML detected, copying to ${JUMP_HOST}..."
  scp "${LAYOUT}" "${JUMP_HOST}:${REMOTE_LAYOUT_DIR}/"
  REMOTE_LAYOUT="${REMOTE_LAYOUT_DIR}/${BASENAME}"
  ok "Layout uploaded: ${REMOTE_LAYOUT}"
else
  info "Using layout path on ${JUMP_HOST}: ${LAYOUT}"
  if ssh "${JUMP_HOST}" "test -f '${LAYOUT}'"; then
    REMOTE_LAYOUT="${LAYOUT}"
    ok "Remote layout verified: ${REMOTE_LAYOUT}"
  else
    err "Layout path not found on local or ${JUMP_HOST}: ${LAYOUT}"
    exit 1
  fi
fi

# ---------- 6. Kill existing PlotJuggler ----------
info "Stopping any existing PlotJuggler on ${JUMP_HOST}..."
ssh "${JUMP_HOST}" "pkill -u \"\$(whoami)\" -f '[p]lotjuggler' 2>/dev/null || true"
sleep 1

if [[ -n "${PJ_LOG}" ]]; then
  info "PlotJuggler log: ${PJ_LOG}"
fi

# ---------- 7. Launch PlotJuggler ----------
info "Launching PlotJuggler on ${JUMP_HOST} with layout: ${REMOTE_LAYOUT}"

REMOTE_LAYOUT_ESCAPED="$(printf "%q" "${REMOTE_LAYOUT}")"
PJ_PID=$(ssh "${JUMP_HOST}" "DISPLAY=${DISPLAY_VAR} nohup plotjuggler --nosplash --layout ${REMOTE_LAYOUT_ESCAPED} > ${PJ_LOG} 2>&1 & echo \$!")
if [[ ! "${PJ_PID}" =~ ^[0-9]+$ ]]; then
  err "Failed to capture PlotJuggler PID"
  exit 1
fi
ok "PlotJuggler launch requested (PID ${PJ_PID})"

PJ_OK=0
for i in 1 2 3 4 5; do
  sleep 1
  if ssh "${JUMP_HOST}" "kill -0 ${PJ_PID} >/dev/null 2>&1"; then
    PJ_OK=1
    break
  fi
done

if [[ "${PJ_OK}" -eq 1 ]]; then
  ok "PlotJuggler running (PID ${PJ_PID})"
else
  CRASH_LOG=$(ssh "${JUMP_HOST}" "cat ${PJ_LOG} 2>/dev/null | tail -10")
  err "PlotJuggler PID ${PJ_PID} died before becoming ready. Log (last 10 lines):"
  echo "${CRASH_LOG}" >&2
  exit 1
fi

# ---------- 8. Launch play script ----------
if [[ "${REFRESH_ONLY}" -eq 1 ]]; then
  echo ""
  echo "=========================================="
  echo "  Play Motion RL - REFRESH SUCCESS"
  echo "=========================================="
  echo "  PlotJuggler PID:  ${PJ_PID}"
  echo "  play.py:          (kept existing)"
  echo "  Layout:           $(basename "${REMOTE_LAYOUT}")"
  echo ""
  echo "  Next step:"
  echo "    In PlotJuggler: Streaming -> Start: UDP Server"
  echo "    Port: 9870, Protocol: JSON"
  echo "=========================================="
  exit 0
fi

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
  info "  mode:       interactive (modal disturbance controls)"
fi

bash "${ISAACGYM_RUNNER}" \
  DISPLAY=${DISPLAY_VAR} \
  python "${PLAY_SCRIPT}" \
  --task "${TASK}" \
  --checkpoint_path "${REMOTE_CKPT}" \
  --resume \
  --total_steps "${TOTAL_STEPS}" &

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

# ---------- 9. Summary ----------
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
  echo "  Modes: 1=push  2=failure  3=velocity"
  echo "  P=apply disturbances  Tab=full reset  R=clear mode"
fi
echo "=========================================="

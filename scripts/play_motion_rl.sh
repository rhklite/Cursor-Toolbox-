#!/usr/bin/env bash
set -euo pipefail

REMOTE_WORKDIR="/home/huh/software/motion_rl"
HEALTHCHECK_SCRIPT="${HOME}/.cursor/scripts/restart_isaacgym_healthcheck.sh"
PJ_CLICKER="${HOME}/.cursor/scripts/pj_clicker.py"
DEFAULT_TASK="r01_v12_amp_with_4dof_arms_and_head_full_scenes"
DEFAULT_LAYOUT="${REMOTE_WORKDIR}/humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml"
DEFAULT_TOTAL_STEPS="100000000"
DISPLAY_VAR=":1"
PJ_LOG="/tmp/plotjuggler.log"
DOCKER_CONTAINER="isaacgym"

usage() {
  cat <<'EOF'
Usage: play_motion_rl.sh --checkpoint <path> [OPTIONS]

Required:
  --checkpoint    Path to .pt checkpoint (local path)

Options:
  --task          Task name from the registry (default: r01_v12_amp_with_4dof_arms_and_head_full_scenes)
  --layout        PlotJuggler layout XML (default: r01_plotjuggler_full.xml)
  --total_steps   Total play steps (default: 100000000)
  --skip-health   Skip container healthcheck
  --pull          Pull latest changes on repo (skip prompt)
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
TOTAL_STEPS="${DEFAULT_TOTAL_STEPS}"
SKIP_HEALTH=0
PULL_REPO=""
PROCESS_ACTION=""
INTERACTIVE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)          TASK="$2";          shift 2 ;;
    --checkpoint)    CHECKPOINT="$2";    shift 2 ;;
    --layout)        LAYOUT="$2";        shift 2 ;;
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
EXISTING_PROCS=$(docker exec "${DOCKER_CONTAINER}" bash -c "pgrep -af 'play[_].*\.py.*--task' 2>/dev/null" || true)

REFRESH_ONLY=0

if [[ -n "${EXISTING_PROCS}" ]]; then
  if [[ "${PROCESS_ACTION}" == "refresh" ]]; then
    info "Existing process found — refresh mode (keeping existing):"
    echo "${EXISTING_PROCS}" | while IFS= read -r line; do info "  ${line}"; done
    REFRESH_ONLY=1
  elif [[ "${PROCESS_ACTION}" == "replace" ]]; then
    info "Existing process found — replacing:"
    echo "${EXISTING_PROCS}" | while IFS= read -r line; do info "  ${line}"; done
    docker exec "${DOCKER_CONTAINER}" bash -c "pkill -f 'play[_].*\.py.*--task' 2>/dev/null || true"
    sleep 2
    ok "Existing process killed"
    SKIP_HEALTH=1
  else
    info "Existing process detected:"
    echo "${EXISTING_PROCS}" | while IFS= read -r line; do info "  ${line}"; done
    if [[ -t 0 ]]; then
      read -rp $'\033[1;34m[INFO]\033[0m  Replace with new process? [y/N] ' replace_answer
      if [[ "${replace_answer}" =~ ^[Yy]$ ]]; then
        docker exec "${DOCKER_CONTAINER}" bash -c "pkill -f 'play[_].*\.py.*--task' 2>/dev/null || true"
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
  info "Running container healthcheck..."
  if bash "${HEALTHCHECK_SCRIPT}"; then
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
      read -rp $'\033[1;34m[INFO]\033[0m  Pull latest changes for motion_rl? [y/N] ' pull_answer
      [[ "${pull_answer}" =~ ^[Yy]$ ]] && PULL_REPO=1 || PULL_REPO=0
    else
      PULL_REPO=0
    fi
  fi
  if [[ "${PULL_REPO}" -eq 1 ]]; then
    info "Pulling latest changes..."
    if git -C "${REMOTE_WORKDIR}" pull --ff-only; then
      ok "Repo updated"
    else
      err "git pull --ff-only failed. Continuing with current state."
    fi
  else
    info "Skipping repo pull"
  fi
fi

# ---------- 4. Resolve checkpoint ----------
if [[ "${REFRESH_ONLY}" -eq 1 ]]; then
  CKPT="(existing)"
else
  if [[ -f "${CHECKPOINT}" ]]; then
    CKPT="${CHECKPOINT}"
    ok "Checkpoint verified: ${CKPT}"
  else
    err "Checkpoint not found: ${CHECKPOINT}"
    exit 1
  fi
fi

# ---------- 5. Resolve layout ----------
if [[ -f "${LAYOUT}" ]]; then
  ok "Layout verified: ${LAYOUT}"
else
  err "Layout not found: ${LAYOUT}"
  exit 1
fi

# ---------- 6. Kill existing PlotJuggler ----------
info "Stopping any existing PlotJuggler..."
pkill -u "$(whoami)" -f '[p]lotjuggler' 2>/dev/null || true
sleep 1

# ---------- 7. Launch PlotJuggler (without layout — streaming first) ----------
info "Launching PlotJuggler (streaming-first mode)..."
DISPLAY="${DISPLAY_VAR}" nohup plotjuggler --nosplash > "${PJ_LOG}" 2>&1 &
PJ_PID=$!
ok "PlotJuggler launch requested (PID ${PJ_PID})"

PJ_OK=0
for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  if kill -0 "${PJ_PID}" >/dev/null 2>&1; then
    PJ_OK=1
    break
  fi
done

if [[ "${PJ_OK}" -eq 1 ]]; then
  ok "PlotJuggler running (PID ${PJ_PID})"
else
  err "PlotJuggler died. Log:"
  tail -10 "${PJ_LOG}" >&2
  exit 1
fi

# ---------- 7b. Start UDP streaming via pj_clicker ----------
info "Starting UDP streaming..."
sleep 5
if DISPLAY="${DISPLAY_VAR}" python3 "${PJ_CLICKER}" start-streaming; then
  ok "UDP streaming started (port 9870, JSON)"
else
  err "Failed to start streaming via pj_clicker"
  info "  Manual fallback: In PlotJuggler, Streaming -> Start: UDP Server, port 9870, JSON"
fi

# ---------- 7c. Ensure model files exist ----------
URDF_DIR="${REMOTE_WORKDIR}/resources/model_files/r01_v12_parallel_ankle/urdf"
if [[ ! -d "${URDF_DIR}" ]] || [[ -z "$(ls -A "${URDF_DIR}" 2>/dev/null)" ]]; then
  info "Model files missing — re-downloading..."
  if bash "${REMOTE_WORKDIR}/scripts/update_repo_deps.sh" --force; then
    ok "Model files restored"
  else
    err "Failed to download model files"
    exit 1
  fi
else
  ok "Model files present"
fi

# ---------- 8. Launch play script ----------
if [[ "${REFRESH_ONLY}" -eq 1 ]]; then
  info "Skipping play script launch (refresh mode — loading layout only)"
else
  if [[ "${INTERACTIVE}" -eq 1 ]]; then
    PLAY_SCRIPT="humanoid-gym/humanoid/scripts/play_interactive.py"
    info "Launching play_interactive.py in ${DOCKER_CONTAINER} container..."
  else
    PLAY_SCRIPT="humanoid-gym/humanoid/scripts/play.py"
    info "Launching play.py in ${DOCKER_CONTAINER} container..."
  fi
  info "  task:       ${TASK}"
  info "  checkpoint: ${CKPT}"
  info "  steps:      ${TOTAL_STEPS}"

  docker exec -d "${DOCKER_CONTAINER}" bash -c \
    "cd ${REMOTE_WORKDIR} && DISPLAY=${DISPLAY_VAR} python ${PLAY_SCRIPT} --task ${TASK} --checkpoint_path ${CKPT} --resume --total_steps ${TOTAL_STEPS} > /tmp/play_interactive.log 2>&1"

  PLAY_SCRIPT_BASE="$(basename "${PLAY_SCRIPT}")"
  PLAY_OK=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 3
    if docker exec "${DOCKER_CONTAINER}" bash -c "pgrep -f '${PLAY_SCRIPT_BASE}.*--task' >/dev/null 2>&1"; then
      PLAY_PID=$(docker exec "${DOCKER_CONTAINER}" bash -c "pgrep -f '${PLAY_SCRIPT_BASE}.*--task' | head -1")
      PLAY_OK=1
      break
    fi
  done

  if [[ "${PLAY_OK}" -eq 1 ]]; then
    ok "${PLAY_SCRIPT_BASE} running (PID ${PLAY_PID})"
  else
    err "${PLAY_SCRIPT_BASE} did not start within 30s"
    exit 1
  fi
fi

# ---------- 8b. Wait for UDP data, then load layout ----------
info "Waiting for UDP data to flow before loading layout (model loading takes ~30s)..."
sleep 40

info "Loading layout: $(basename "${LAYOUT}")"
if DISPLAY="${DISPLAY_VAR}" python3 "${PJ_CLICKER}" load-layout "${LAYOUT}"; then
  ok "Layout loaded — curves should auto-populate"
else
  err "Failed to load layout via pj_clicker"
  info "  Manual fallback: In PlotJuggler, Layout -> Load -> ${LAYOUT}"
fi

# ---------- 9. Summary ----------
echo ""
echo "=========================================="
echo "  Play Motion RL - SUCCESS"
echo "=========================================="
echo "  PlotJuggler PID:  ${PJ_PID}"
if [[ "${REFRESH_ONLY}" -eq 0 ]]; then
  echo "  ${PLAY_SCRIPT_BASE} PID: ${PLAY_PID}"
  echo "  Task:             ${TASK}"
  echo "  Checkpoint:       ${CKPT}"
else
  echo "  play.py:          (kept existing)"
fi
echo "  Layout:           $(basename "${LAYOUT}")"
echo "  Streaming:        UDP 9870, JSON (auto-started)"
if [[ "${INTERACTIVE}" -eq 1 && "${REFRESH_ONLY}" -eq 0 ]]; then
  echo ""
  echo "  Modes: 1=push  2=failure  3=velocity"
  echo "  P=apply disturbances  Tab=full reset  R=clear mode"
fi
echo "=========================================="

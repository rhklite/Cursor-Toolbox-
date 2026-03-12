#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy_fuyao.sh"

DEFAULT_LOCAL_ROOT="/home/huh/software/motion_rl"
DEFAULT_ENVS_INIT_REL="humanoid-gym/humanoid/envs/__init__.py"
DEFAULT_PATCH_FILE_REL="humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py"
DEFAULT_SSH_ALIAS="Huh8.remote_kernel.fuyao"
DEFAULT_REMOTE_ROOT="/root/motion_rl"
DEFAULT_REMOTE_SWEEP_ROOT="/tmp/fuyao_sweeps"
DEFAULT_RUN_ROOT_BASE="${HOME}/.cursor/tmp/orchestrator_runs"
DEFAULT_LABEL_PREFIX="sweep"
DEFAULT_MAX_LIVE_JOBS_PER_CYCLE="2"
DEFAULT_START_VALIDATE_TIMEOUT_S="300"
DEFAULT_START_VALIDATE_INTERVAL_S="15"
DEFAULT_CANCEL_VERIFY_TIMEOUT_S="180"
DEFAULT_CANCEL_VERIFY_INTERVAL_S="10"
DEFAULT_REMOTE_KERNEL="false"
DEFAULT_LOG_MARKERS="humanoid/scripts/train.py||Setting seed:||Logging training parameters on Fuyao"
DEFAULT_LOG_FAILURE_MARKERS="Traceback (most recent call last):||ModuleNotFoundError:||ImportError:||E: Failed to fetch https://mirrors.tuna.tsinghua.edu.cn/ubuntu||The repository 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu||No compatible fuyao log command variant succeeded.||*** Failed to load '/code/humanoid-gym/../resources/model_files||PxgCudaDeviceMemoryAllocator fail to allocate memory||Gym cuda error: an illegal memory access was encountered||RuntimeError: CUDA driver error: an illegal memory access was encountered||Invalid height samples shape||internal error : GPU"

declare -a COMBO_NAMES=()
declare -a COMBO_SPECS=()
declare -A COMBO_LABEL_MAP=()
declare -A COMBO_DIR_MAP=()

usage() {
    cat <<'EOF'
Usage:
  orchestrator.sh --payload /abs/path/to/sweep_payload.json
  orchestrator.sh --interactive

Payload minimum:
{
  "task": "r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes",
  "branch": "huh/dev_xxx",
  "patch_file_rel": "humanoid-gym/humanoid/envs/...py",
  "hp_specs": ["cgail_reg_coef=0.8,0.9"]
}

Important live-run confirmations (required when dry_run=false):
  "confirm_live_submit": true,
  "confirm_live_cancel": true

Parallel behavior:
  - Deploy/validate/cancel run in parallel per cycle.
  - Maximum live jobs per cycle is hard-capped at 2.
EOF
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf "%s" "$s"
}

read_with_default() {
    local prompt="$1"
    local default_value="$2"
    local val=""
    read -r -p "${prompt} [${default_value}]: " val
    val="$(trim "$val")"
    if [ -z "$val" ]; then
        printf "%s" "$default_value"
    else
        printf "%s" "$val"
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: missing command '$cmd'" >&2
        exit 1
    fi
}

json_file_field() {
    local path="$1"
    local field="$2"
    local default_value="${3:-}"
    python3 - "$path" "$field" "$default_value" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
field = sys.argv[2]
default = sys.argv[3]

if not path.exists():
    print(default)
    raise SystemExit(0)

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print(default)
    raise SystemExit(0)

value = data
for part in field.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        print(default)
        raise SystemExit(0)

if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
elif isinstance(value, (list, dict)):
    print(json.dumps(value, ensure_ascii=True))
else:
    print(value)
PY
}

validate_task_registered() {
    local envs_file="$1"
    local task_name="$2"
    python3 - "$envs_file" "$task_name" <<'PY'
import re
import sys

path = sys.argv[1]
task = sys.argv[2]
text = open(path, "r", encoding="utf-8").read()
pattern = re.compile(r'task_registry\.register\(\s*"([^"]+)"')
registered = set(pattern.findall(text))
if task not in registered:
    print(f"Task '{task}' is not registered in {path}", file=sys.stderr)
    if registered:
        sample = sorted(registered)[:15]
        print("Registered examples:", ", ".join(sample), file=sys.stderr)
    raise SystemExit(1)
PY
}

parse_hp_spec() {
    local line="$1"
    local key="${line%%=*}"
    local values="${line#*=}"
    key="$(trim "$key")"
    values="$(trim "$values")"
    if [ -z "$key" ] || [ -z "$values" ] || [ "$key" = "$line" ]; then
        return 1
    fi
    printf "%s=%s" "$key" "$values"
}

default_asset_preflight_relpaths_for_task() {
    local task_name="$1"
    case "$task_name" in
    r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes)
        printf "%s" "resources/model_files/r01_v12_serial_ankle/urdf/r01_v12_rl_simplified_plus_simple_foot_change_torque_with_head.urdf"
        ;;
    *)
        printf ""
        ;;
    esac
}

build_combos() {
    local -n out_ref=$1
    shift
    local specs=("$@")
    local current_combos=("")
    local key values raw_val val combo
    local -a next vals

    for spec in "${specs[@]}"; do
        key="${spec%%=*}"
        values="${spec#*=}"
        next=()
        IFS=',' read -r -a vals <<<"$values"
        for raw_val in "${vals[@]}"; do
            val="$(trim "$raw_val")"
            if [ -z "$val" ]; then
                continue
            fi
            for combo in "${current_combos[@]}"; do
                if [ -z "$combo" ]; then
                    next+=("${key}=${val}")
                else
                    next+=("${combo};${key}=${val}")
                fi
            done
        done
        current_combos=("${next[@]}")
    done
    out_ref=("${current_combos[@]}")
}

escape_label_piece() {
    local s="$1"
    s="${s// /_}"
    s="${s//\//_}"
    s="${s//:/_}"
    s="${s//,/__}"
    s="${s//;/-}"
    s="${s//=/_}"
    printf "%s" "$s"
}

combo_to_label_suffix() {
    local combo="$1"
    local pretty
    pretty="$(escape_label_piece "$combo")"
    printf "%s" "$pretty"
}

prepare_remote_combo_repo() {
    local ssh_alias="$1"
    local remote_root="$2"
    local branch="$3"
    local combo_dir="$4"
    local patch_file_rel="$5"
    local combo_assignments="$6"

    ssh "$ssh_alias" "bash -s" -- "$remote_root" "$branch" "$combo_dir" "$patch_file_rel" "$combo_assignments" <<'REMOTE_PREP'
set -euo pipefail

REMOTE_ROOT="$1"
BRANCH="$2"
COMBO_DIR="$3"
PATCH_FILE_REL="$4"
COMBO_ASSIGNMENTS="$5"

cd "$REMOTE_ROOT"
if [ -f ".git/index.lock" ]; then
    lock_age=$(( $(date +%s) - $(stat -c %Y ".git/index.lock" 2>/dev/null || echo 0) ))
    if [ "$lock_age" -gt 120 ]; then
        rm -f ".git/index.lock"
    fi
fi
git fetch origin "$BRANCH"

if [ -d "$COMBO_DIR" ]; then
    git worktree remove --force "$COMBO_DIR" >/dev/null 2>&1 || true
    rm -rf "$COMBO_DIR"
fi

git worktree add --force "$COMBO_DIR" "origin/${BRANCH}" >/dev/null

PATCH_TARGET="${COMBO_DIR}/${PATCH_FILE_REL}"
if [ ! -f "$PATCH_TARGET" ]; then
    echo "Error: patch target not found: ${PATCH_TARGET}" >&2
    exit 1
fi

python3 - "$PATCH_TARGET" "$COMBO_ASSIGNMENTS" <<'PY'
import re
import sys

path = sys.argv[1]
assignments = sys.argv[2]
pairs = []
for part in assignments.split(";"):
    if not part:
        continue
    if "=" not in part:
        raise SystemExit(f"Invalid assignment (missing '='): {part}")
    k, v = part.split("=", 1)
    k = k.strip()
    v = v.strip()
    if not k or not v:
        raise SystemExit(f"Invalid assignment: {part}")
    pairs.append((k, v))

text = open(path, "r", encoding="utf-8").read()

for key, value in pairs:
    pattern = re.compile(rf"(^[ \t]*{re.escape(key)}[ \t]*=[ \t]*).*$", re.MULTILINE)
    new_text, n = pattern.subn(lambda m: m.group(1) + value, text, count=1)
    if n == 0:
        raise SystemExit(f"Failed to patch key '{key}' in {path}. Ensure it appears as '<key> = <value>'")
    text = new_text

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
REMOTE_PREP
}

cleanup_remote_combo_repo() {
    local ssh_alias="$1"
    local remote_root="$2"
    local combo_dir="$3"
    ssh "$ssh_alias" "bash -s" -- "$remote_root" "$combo_dir" <<'REMOTE_CLEAN'
set -euo pipefail
REMOTE_ROOT="$1"
COMBO_DIR="$2"
cd "$REMOTE_ROOT"
git worktree remove --force "$COMBO_DIR" >/dev/null 2>&1 || true
rm -rf "$COMBO_DIR" || true
REMOTE_CLEAN
}

load_payload() {
    local payload_path="$1"
    if [ ! -f "$payload_path" ]; then
        echo "Error: payload file not found: $payload_path" >&2
        exit 1
    fi

    eval "$(python3 - "$payload_path" <<'PY'
import base64
import json
import os
import shlex
import sys

path = sys.argv[1]
data = json.load(open(path, "r", encoding="utf-8"))

def s(name, default):
    v = data.get(name, default)
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)

def emit(k, v):
    print(f"{k}={shlex.quote(v)}")

emit("LOCAL_ROOT", s("local_root", "/home/huh/software/motion_rl"))
emit("ENVS_INIT_REL", s("envs_init_rel", "humanoid-gym/humanoid/envs/__init__.py"))
emit("PATCH_FILE_REL", s("patch_file_rel", "humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py"))
task_name = s("task", "")
emit("TASK", task_name)
emit("BRANCH", s("branch", ""))
emit("SSH_ALIAS", s("ssh_alias", "Huh8.remote_kernel.fuyao"))
emit("REMOTE_ROOT", s("remote_root", "/root/motion_rl"))
emit("REMOTE_SWEEP_ROOT", s("remote_sweep_root", "/tmp/fuyao_sweeps"))
emit("RUN_ROOT_BASE", s("run_root_base", f"{os.path.expanduser('~')}/.cursor/tmp/orchestrator_runs"))
emit("LABEL_PREFIX", s("label_prefix", "sweep"))
emit("EXPERIMENT", s("experiment", "huh8/r01"))
emit("QUEUE", s("queue", "rc-wbc-4090-share"))
emit("PROJECT", s("project", "rc-wbc"))
emit("SITE", s("site", "fuyao_sh_n2"))
emit("NODES", s("nodes", "1"))
emit("GPUS_PER_NODE", s("gpus_per_node", "1"))
emit("GPU_TYPE", s("gpu_type", "shared"))
emit("GPU_SLICE", s("gpu_slice", ""))
emit("PRIORITY", s("priority", "normal"))
emit("DOCKER_IMAGE", s("docker_image", "infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347"))
emit("RL_DEVICE", s("rl_device", "cuda:0"))
emit("REMOTE_KERNEL", s("remote_kernel", "false"))
emit("DRY_RUN", s("dry_run", "false"))
emit("CONTINUE_ON_ERROR", s("continue_on_error", "true"))
emit("CONFIRM_LIVE_SUBMIT", s("confirm_live_submit", "false"))
emit("CONFIRM_LIVE_CANCEL", s("confirm_live_cancel", "false"))
emit("MAX_LIVE_JOBS_PER_CYCLE", s("max_live_jobs_per_cycle", data.get("max_parallel", 2)))
emit("START_VALIDATE_TIMEOUT_S", s("start_validation_timeout_s", "300"))
emit("START_VALIDATE_INTERVAL_S", s("start_validation_interval_s", "15"))
emit("CANCEL_VERIFY_TIMEOUT_S", s("cancel_verify_timeout_s", "180"))
emit("CANCEL_VERIFY_INTERVAL_S", s("cancel_verify_interval_s", "10"))
emit("KEEP_FAILED_WORKTREES", s("keep_failed_worktrees", "false"))
emit("LOG_MARKERS_JOINED", s("training_log_markers", "humanoid/scripts/train.py||Setting seed:||Logging training parameters on Fuyao"))
emit("LOG_FAILURE_MARKERS_JOINED", s("failure_log_markers", "Traceback (most recent call last):||ModuleNotFoundError:||ImportError:||E: Failed to fetch https://mirrors.tuna.tsinghua.edu.cn/ubuntu||The repository 'https://mirrors.tuna.tsinghua.edu.cn/ubuntu||No compatible fuyao log command variant succeeded.||*** Failed to load '/code/humanoid-gym/../resources/model_files||PxgCudaDeviceMemoryAllocator fail to allocate memory||Gym cuda error: an illegal memory access was encountered||RuntimeError: CUDA driver error: an illegal memory access was encountered||Invalid height samples shape||internal error : GPU"))

asset_preflight = data.get("asset_preflight_relpaths")
if not asset_preflight:
    default_asset_map = {
        "r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes": [
            "resources/model_files/r01_v12_serial_ankle/urdf/r01_v12_rl_simplified_plus_simple_foot_change_torque_with_head.urdf"
        ]
    }
    asset_preflight = default_asset_map.get(task_name, [])
if isinstance(asset_preflight, str):
    asset_joined = asset_preflight.strip()
elif isinstance(asset_preflight, list):
    asset_joined = ",".join(str(x).strip() for x in asset_preflight if str(x).strip())
else:
    asset_joined = ""
emit("ASSET_PREFLIGHT_RELPATHS_JOINED", asset_joined)

hp_specs = []
if "hp_specs" in data and isinstance(data["hp_specs"], list):
    hp_specs = [str(x).strip() for x in data["hp_specs"] if str(x).strip()]
elif "hyperparameters" in data and isinstance(data["hyperparameters"], list):
    for item in data["hyperparameters"]:
        key = str(item.get("key", "")).strip()
        vals = item.get("values", [])
        if key and isinstance(vals, list):
            joined = ",".join(str(v).strip() for v in vals if str(v).strip())
            if joined:
                hp_specs.append(f"{key}={joined}")

payload = "\n".join(hp_specs)
emit("HP_SPECS_B64", base64.b64encode(payload.encode("utf-8")).decode("ascii"))
PY
)"
}

interactive_collect() {
    LOCAL_ROOT="$(read_with_default "Local repo root" "$DEFAULT_LOCAL_ROOT")"
    ENVS_INIT_REL="$(read_with_default "Task registry file (relative to repo)" "$DEFAULT_ENVS_INIT_REL")"
    read -r -p "Task name (must be registered): " TASK
    TASK="$(trim "$TASK")"
    ASSET_PREFLIGHT_RELPATHS_JOINED="$(default_asset_preflight_relpaths_for_task "$TASK")"
    PATCH_FILE_REL="$(read_with_default "Task config file to patch (relative to repo)" "$DEFAULT_PATCH_FILE_REL")"
    BRANCH="$(read_with_default "Target branch to use as baseline" "$(git -C "$LOCAL_ROOT" rev-parse --abbrev-ref HEAD)")"
    SSH_ALIAS="$(read_with_default "SSH alias" "$DEFAULT_SSH_ALIAS")"
    REMOTE_ROOT="$(read_with_default "Remote repo root" "$DEFAULT_REMOTE_ROOT")"
    REMOTE_SWEEP_ROOT="$(read_with_default "Remote sweep root directory" "$DEFAULT_REMOTE_SWEEP_ROOT")"
    RUN_ROOT_BASE="$(read_with_default "Run root base directory" "$DEFAULT_RUN_ROOT_BASE")"
    LABEL_PREFIX="$(read_with_default "Sweep label prefix" "$DEFAULT_LABEL_PREFIX")"
    EXPERIMENT="$(read_with_default "Fuyao experiment" "huh8/r01")"
    QUEUE="$(read_with_default "Fuyao queue" "rc-wbc-4090-share")"
    PROJECT="$(read_with_default "Fuyao project" "rc-wbc")"
    SITE="$(read_with_default "Fuyao site" "fuyao_sh_n2")"
    NODES="$(read_with_default "Nodes" "1")"
    GPUS_PER_NODE="$(read_with_default "GPUs per node" "1")"
    GPU_TYPE="$(read_with_default "GPU type" "shared")"
    GPU_SLICE="$(read_with_default "GPU slice (empty means auto)" "")"
    PRIORITY="$(read_with_default "Priority" "normal")"
    DOCKER_IMAGE="$(read_with_default "Docker image" "infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347")"
    RL_DEVICE="$(read_with_default "RL device" "cuda:0")"
    REMOTE_KERNEL="$(read_with_default "Fuyao --remote-kernel mode? (true/false)" "$DEFAULT_REMOTE_KERNEL")"
    DRY_RUN="$(read_with_default "Dry run? (true/false)" "true")"
    CONTINUE_ON_ERROR="$(read_with_default "Continue on cycle failures? (true/false)" "true")"
    CONFIRM_LIVE_SUBMIT="$(read_with_default "Confirm live submit? (true/false)" "false")"
    CONFIRM_LIVE_CANCEL="$(read_with_default "Confirm live cancel? (true/false)" "false")"
    MAX_LIVE_JOBS_PER_CYCLE="$(read_with_default "Max live jobs per cycle (hard capped at 2)" "$DEFAULT_MAX_LIVE_JOBS_PER_CYCLE")"
    START_VALIDATE_TIMEOUT_S="$(read_with_default "Start validation timeout seconds" "$DEFAULT_START_VALIDATE_TIMEOUT_S")"
    START_VALIDATE_INTERVAL_S="$(read_with_default "Start validation poll interval seconds" "$DEFAULT_START_VALIDATE_INTERVAL_S")"
    CANCEL_VERIFY_TIMEOUT_S="$(read_with_default "Cancel verification timeout seconds" "$DEFAULT_CANCEL_VERIFY_TIMEOUT_S")"
    CANCEL_VERIFY_INTERVAL_S="$(read_with_default "Cancel verification poll interval seconds" "$DEFAULT_CANCEL_VERIFY_INTERVAL_S")"
    KEEP_FAILED_WORKTREES="$(read_with_default "Keep failed remote worktrees? (true/false)" "false")"
    LOG_MARKERS_JOINED="$DEFAULT_LOG_MARKERS"
    LOG_FAILURE_MARKERS_JOINED="$DEFAULT_LOG_FAILURE_MARKERS"

    echo
    echo "Enter hyperparameter lines as: key=v1,v2,v3"
    echo "Finish with an empty line."
    local -a hp_specs=()
    local line parsed
    while true; do
        read -r -p "hp> " line
        line="$(trim "$line")"
        [ -z "$line" ] && break
        parsed="$(parse_hp_spec "$line" || true)"
        if [ -z "$parsed" ]; then
            echo "Invalid spec: '$line'. Expected format key=v1,v2,v3" >&2
            exit 1
        fi
        hp_specs+=("$parsed")
    done
    if [ "${#hp_specs[@]}" -eq 0 ]; then
        echo "Error: at least one hyperparameter spec is required." >&2
        exit 1
    fi
    HP_SPECS_B64="$(printf '%s\n' "${hp_specs[@]}" | base64 -w0)"
}

write_manifest() {
    local manifest_path="$1"
    local sweep_id="$2"
    local combo_count="$3"
    local mode="$4"
    python3 - "$manifest_path" "$sweep_id" "$combo_count" "$mode" \
        "$TASK" "$BRANCH" "$PATCH_FILE_REL" "$SSH_ALIAS" "$REMOTE_ROOT" "$REMOTE_SWEEP_ROOT" \
        "$LABEL_PREFIX" "$DRY_RUN" "$CONTINUE_ON_ERROR" "$MAX_LIVE_JOBS_PER_CYCLE" \
        "$CONFIRM_LIVE_SUBMIT" "$CONFIRM_LIVE_CANCEL" "$START_VALIDATE_TIMEOUT_S" "$START_VALIDATE_INTERVAL_S" \
        "$CANCEL_VERIFY_TIMEOUT_S" "$CANCEL_VERIFY_INTERVAL_S" "$LOG_MARKERS_JOINED" "$LOG_FAILURE_MARKERS_JOINED" "$REMOTE_KERNEL" \
        "$ASSET_PREFLIGHT_RELPATHS_JOINED" <<'PY'
import json
import sys
from datetime import datetime, timezone

(
    path, sweep_id, combo_count, mode,
    task, branch, patch_file_rel, ssh_alias, remote_root, remote_sweep_root,
    label_prefix, dry_run, continue_on_error, max_live_jobs_per_cycle,
    confirm_live_submit, confirm_live_cancel, start_timeout, start_interval,
    cancel_timeout, cancel_interval, log_markers_joined, failure_log_markers_joined, remote_kernel,
    asset_preflight_relpaths_joined
) = sys.argv[1:]

manifest = {
    "sweep_id": sweep_id,
    "created_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "mode": mode,
    "task": task,
    "branch": branch,
    "patch_file_rel": patch_file_rel,
    "ssh_alias": ssh_alias,
    "remote_root": remote_root,
    "remote_sweep_root": remote_sweep_root,
    "label_prefix": label_prefix,
    "dry_run": dry_run == "true",
    "continue_on_error": continue_on_error == "true",
    "combo_count": int(combo_count),
    "max_live_jobs_per_cycle": int(max_live_jobs_per_cycle),
    "confirm_live_submit": confirm_live_submit == "true",
    "confirm_live_cancel": confirm_live_cancel == "true",
    "start_validation_timeout_s": int(start_timeout),
    "start_validation_interval_s": int(start_interval),
    "cancel_verify_timeout_s": int(cancel_timeout),
    "cancel_verify_interval_s": int(cancel_interval),
    "training_log_markers": [m for m in log_markers_joined.split("||") if m],
    "failure_log_markers": [m for m in failure_log_markers_joined.split("||") if m],
    "remote_kernel": remote_kernel == "true",
    "asset_preflight_relpaths": [m for m in asset_preflight_relpaths_joined.split(",") if m],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
PY
}

write_combo_payload() {
    local out_path="$1"
    local combo_name="$2"
    local combo_spec="$3"
    local combo_label="$4"
    local combo_dir="$5"
    python3 - "$out_path" "$combo_name" "$combo_spec" "$combo_label" "$combo_dir" \
        "$TASK" "$PATCH_FILE_REL" "$BRANCH" "$SSH_ALIAS" "$REMOTE_ROOT" \
        "$EXPERIMENT" "$QUEUE" "$PROJECT" "$SITE" "$NODES" "$GPUS_PER_NODE" "$GPU_TYPE" "$GPU_SLICE" \
        "$PRIORITY" "$DOCKER_IMAGE" "$RL_DEVICE" "$REMOTE_KERNEL" "$DRY_RUN" <<'PY'
import json
import sys

(
    out_path, combo_name, combo_spec, combo_label, combo_dir, task, patch_file_rel, branch,
    ssh_alias, remote_root, experiment, queue, project, site, nodes, gpus_per_node,
    gpu_type, gpu_slice, priority, docker_image, rl_device, remote_kernel, dry_run
) = sys.argv[1:]

payload = {
    "combo_name": combo_name,
    "combo_spec": combo_spec,
    "combo_label": combo_label,
    "combo_dir": combo_dir,
    "task": task,
    "patch_file_rel": patch_file_rel,
    "branch": branch,
    "ssh_alias": ssh_alias,
    "remote_root": remote_root,
    "deploy_args": {
        "experiment": experiment,
        "queue": queue,
        "project": project,
        "site": site,
        "nodes": nodes,
        "gpus_per_node": gpus_per_node,
        "gpu_type": gpu_type,
        "gpu_slice": gpu_slice,
        "priority": priority,
        "docker_image": docker_image,
        "rl_device": rl_device,
        "remote_kernel": remote_kernel == "true",
        "dry_run": dry_run == "true",
    },
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY
}

write_submit_result() {
    local out_path="$1"
    local combo_name="$2"
    local combo_spec="$3"
    local combo_label="$4"
    local combo_dir="$5"
    local submit_rc="$6"
    local success="$7"
    local submitted="$8"
    local prepared="$9"
    local job_name="${10}"
    local job_id="${11}"
    local reason="${12}"
    python3 - "$out_path" "$combo_name" "$combo_spec" "$combo_label" "$combo_dir" "$submit_rc" "$success" "$submitted" "$prepared" "$job_name" "$job_id" "$reason" <<'PY'
import json
import sys
from datetime import datetime, timezone

(
    path, combo_name, combo_spec, combo_label, combo_dir, submit_rc, success,
    submitted, prepared, job_name, job_id, reason
) = sys.argv[1:]

data = {
    "combo_name": combo_name,
    "combo_spec": combo_spec,
    "combo_label": combo_label,
    "combo_dir": combo_dir,
    "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "submit_rc": int(submit_rc),
    "success": success == "true",
    "submitted": submitted == "true",
    "prepared_remote_worktree": prepared == "true",
    "job_name": job_name or None,
    "job_id": job_id or None,
    "reason": reason or None,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
}

write_start_validation_result() {
    local out_path="$1"
    local combo_name="$2"
    local job_name="$3"
    local job_id="$4"
    local attempts="$5"
    local running_seen="$6"
    local marker_seen="$7"
    local start_confirmed="$8"
    local terminal_before_start="$9"
    local last_status="${10}"
    local last_markers_json="${11}"
    local failure_seen="${12}"
    local last_failure_markers_json="${13}"
    local reason="${14}"
    python3 - "$out_path" "$combo_name" "$job_name" "$job_id" "$attempts" "$running_seen" "$marker_seen" "$start_confirmed" "$terminal_before_start" "$last_status" "$last_markers_json" "$failure_seen" "$last_failure_markers_json" "$reason" <<'PY'
import json
import sys
from datetime import datetime, timezone

(
    path, combo_name, job_name, job_id, attempts, running_seen, marker_seen,
    start_confirmed, terminal_before_start, last_status, last_markers_json,
    failure_seen, last_failure_markers_json, reason
) = sys.argv[1:]

try:
    last_markers = json.loads(last_markers_json) if last_markers_json else []
except Exception:
    last_markers = []
try:
    last_failure_markers = json.loads(last_failure_markers_json) if last_failure_markers_json else []
except Exception:
    last_failure_markers = []

def classify_failure_mode(start_confirmed, reason, matched_failure_markers):
    if start_confirmed:
        return "NONE"
    marker_blob = " ".join(str(m) for m in matched_failure_markers).lower()
    if (
        "resources/model_files" in marker_blob
        or "failed to load" in marker_blob
        or ".urdf" in marker_blob
        or "asset_preflight" in marker_blob
    ):
        return "ASSET_MISSING_URDF"
    if (
        "pxgcudadevicememoryallocator fail to allocate memory" in marker_blob
        or "illegal memory access" in marker_blob
        or "invalid height samples shape" in marker_blob
        or "internal error : gpu" in marker_blob
        or "fail to launch kernel" in marker_blob
    ):
        return "PHYSX_GPU_MEMORY"
    if reason == "log_failure_marker_detected":
        return "UNKNOWN_FAILURE_MARKER"
    return "UNKNOWN"

failure_mode = classify_failure_mode(
    start_confirmed == "true",
    reason or "",
    last_failure_markers,
)

data = {
    "combo_name": combo_name,
    "job_name": job_name or None,
    "job_id": job_id or None,
    "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "attempts": int(attempts),
    "status_running_seen": running_seen == "true",
    "training_marker_seen": marker_seen == "true",
    "start_confirmed": start_confirmed == "true",
    "terminal_before_start": terminal_before_start == "true",
    "failure_marker_seen_before_start": failure_seen == "true",
    "failure_mode": failure_mode,
    "last_status": last_status or "UNKNOWN",
    "last_matched_markers": last_markers,
    "last_matched_failure_markers": last_failure_markers,
    "reason": reason or None,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
}

write_cancel_validation_result() {
    local out_path="$1"
    local combo_name="$2"
    local job_name="$3"
    local job_id="$4"
    local cancel_rc="$5"
    local cancel_confirmed="$6"
    local reason="$7"
    python3 - "$out_path" "$combo_name" "$job_name" "$job_id" "$cancel_rc" "$cancel_confirmed" "$reason" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, combo_name, job_name, job_id, cancel_rc, cancel_confirmed, reason = sys.argv[1:]

data = {
    "combo_name": combo_name,
    "job_name": job_name or None,
    "job_id": job_id or None,
    "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "cancel_rc": int(cancel_rc),
    "cancel_confirmed": cancel_confirmed == "true",
    "reason": reason or None,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, sort_keys=True)
PY
}

submit_combo_worker() {
    local combo_name="$1"
    local combo_spec="$2"
    local combo_label="$3"
    local combo_dir="$4"

    local combo_art_dir="${ARTIFACTS_DIR}/${combo_name}"
    local receipt_path="${combo_art_dir}/submission_receipt.json"
    local submit_result_path="${combo_art_dir}/submit_result.json"
    local submit_log="${LOGS_DIR}/${combo_name}.submit.log"

    mkdir -p "$combo_art_dir"

    local prep_rc=0
    local submit_rc=0
    local prepared="false"
    local success="false"
    local submitted="false"
    local job_name=""
    local job_id=""
    local reason=""

    {
        echo "combo_name=${combo_name}"
        echo "combo_label=${combo_label}"
        echo "combo_spec=${combo_spec}"
        echo "combo_dir=${combo_dir}"

        if [ "$DRY_RUN" != "true" ]; then
            set +e
            prepare_remote_combo_repo "$SSH_ALIAS" "$REMOTE_ROOT" "$BRANCH" "$combo_dir" "$PATCH_FILE_REL" "$combo_spec"
            prep_rc=$?
            set -e
            if [ "$prep_rc" -ne 0 ]; then
                reason="remote_prep_failed"
                submit_rc="$prep_rc"
            else
                prepared="true"
            fi
        else
            echo "DRY_RUN: skipping remote prep"
        fi

        if [ "$submit_rc" -eq 0 ]; then
            cmd=(
                "$DEPLOY_SCRIPT"
                --helper-mode deploy
                --skip-git-sync true
                --ssh-alias "$SSH_ALIAS"
                --remote-root "$combo_dir"
                --task "$TASK"
                --label "$combo_label"
                --remote-kernel "$REMOTE_KERNEL"
                --docker-image "$DOCKER_IMAGE"
                --nodes "$NODES"
                --gpus-per-node "$GPUS_PER_NODE"
                --gpu-type "$GPU_TYPE"
                --site "$SITE"
                --queue "$QUEUE"
                --project "$PROJECT"
                --experiment "$EXPERIMENT"
                --priority "$PRIORITY"
                --rl-device "$RL_DEVICE"
                --auto-yes true
                --receipt-out "$receipt_path"
            )
            if [ -n "${ASSET_PREFLIGHT_RELPATHS_JOINED:-}" ]; then
                cmd+=(--asset-preflight-relpaths "$ASSET_PREFLIGHT_RELPATHS_JOINED")
            fi
            if [ -n "$GPU_SLICE" ]; then
                cmd+=(--gpu-slice "$GPU_SLICE")
            fi
            if [ "$DRY_RUN" = "true" ]; then
                cmd+=(--dry-run)
            fi

            printf 'Running: %q ' "${cmd[@]}"
            echo
            set +e
            "${cmd[@]}"
            submit_rc=$?
            set -e
        fi
    } >"$submit_log" 2>&1 || true

    if [ -f "$receipt_path" ]; then
        submitted="$(json_file_field "$receipt_path" "submitted" "false")"
        job_name="$(json_file_field "$receipt_path" "job_name" "")"
        job_id="$(json_file_field "$receipt_path" "job_id" "")"
    fi

    if [ "$submit_rc" -eq 0 ] && { [ "$DRY_RUN" = "true" ] || [ "$submitted" = "true" ]; }; then
        success="true"
    else
        if [ -z "$reason" ]; then
            if [ "$submit_rc" -ne 0 ]; then
                reason="deploy_failed"
            else
                reason="missing_submission_receipt"
            fi
        fi
    fi

    if [ "$prepared" = "true" ] && [ "$KEEP_FAILED_WORKTREES" != "true" ]; then
        cleanup_remote_combo_repo "$SSH_ALIAS" "$REMOTE_ROOT" "$combo_dir" >>"$submit_log" 2>&1 || true
    fi

    write_submit_result \
        "$submit_result_path" "$combo_name" "$combo_spec" "$combo_label" "$combo_dir" \
        "$submit_rc" "$success" "$submitted" "$prepared" "$job_name" "$job_id" "$reason"
}

validate_start_worker() {
    local combo_name="$1"

    local combo_art_dir="${ARTIFACTS_DIR}/${combo_name}"
    local submit_result_path="${combo_art_dir}/submit_result.json"
    local start_result_path="${combo_art_dir}/start_validation.json"
    local start_log="${LOGS_DIR}/${combo_name}.start_validation.log"
    local status_json_tmp="${combo_art_dir}/status_probe.json"
    local log_json_tmp="${combo_art_dir}/log_probe.json"

    local submit_success
    submit_success="$(json_file_field "$submit_result_path" "success" "false")"
    local job_name
    job_name="$(json_file_field "$submit_result_path" "job_name" "")"
    local job_id
    job_id="$(json_file_field "$submit_result_path" "job_id" "")"

    local attempts=0
    local running_seen="false"
    local marker_seen="false"
    local start_confirmed="false"
    local terminal_before_start="false"
    local failure_seen="false"
    local last_status="UNKNOWN"
    local last_markers="[]"
    local last_failure_markers="[]"
    local reason=""

    {
        echo "combo_name=${combo_name}"
        echo "job_name=${job_name}"
        echo "job_id=${job_id}"

        if [ "$submit_success" != "true" ]; then
            reason="skipped_submit_failed"
        elif [ "$DRY_RUN" = "true" ]; then
            reason="skipped_dry_run"
        elif [ -z "$job_name" ] && [ -z "$job_id" ]; then
            reason="missing_job_identifier"
        else
            local deadline=$((SECONDS + START_VALIDATE_TIMEOUT_S))
            while [ "$SECONDS" -le "$deadline" ]; do
                attempts=$((attempts + 1))
                echo "attempt=${attempts}"

                status_cmd=("$DEPLOY_SCRIPT" --helper-mode status --ssh-alias "$SSH_ALIAS" --status-out "$status_json_tmp" --site "$SITE")
                log_cmd=("$DEPLOY_SCRIPT" --helper-mode log --ssh-alias "$SSH_ALIAS" --log-out "$log_json_tmp" --log-markers "$LOG_MARKERS_JOINED" --log-failure-markers "$LOG_FAILURE_MARKERS_JOINED" --site "$SITE")
                if [ -n "$job_name" ]; then
                    status_cmd+=(--job-name "$job_name")
                    log_cmd+=(--job-name "$job_name")
                fi
                if [ -n "$job_id" ]; then
                    status_cmd+=(--job-id "$job_id")
                    log_cmd+=(--job-id "$job_id")
                fi

                set +e
                "${status_cmd[@]}" >>"$start_log" 2>&1
                status_rc=$?
                "${log_cmd[@]}" >>"$start_log" 2>&1
                log_rc=$?
                set -e

                status_terminal="false"
                if [ -f "$status_json_tmp" ]; then
                    status_running="$(json_file_field "$status_json_tmp" "is_running" "false")"
                    status_terminal="$(json_file_field "$status_json_tmp" "is_terminal" "false")"
                    last_status="$(json_file_field "$status_json_tmp" "status" "UNKNOWN")"
                    if [ "$status_running" = "true" ]; then
                        running_seen="true"
                    fi
                fi

                failure_now="false"
                if [ -f "$log_json_tmp" ]; then
                    marker_now="$(json_file_field "$log_json_tmp" "has_training_marker" "false")"
                    last_markers="$(json_file_field "$log_json_tmp" "matched_markers" "[]")"
                    failure_now="$(json_file_field "$log_json_tmp" "has_failure_marker" "false")"
                    last_failure_markers="$(json_file_field "$log_json_tmp" "matched_failure_markers" "[]")"
                    if [ "$marker_now" = "true" ]; then
                        marker_seen="true"
                    fi
                    if [ "$failure_now" = "true" ] && [ "$marker_seen" != "true" ]; then
                        failure_seen="true"
                        reason="log_failure_marker_detected"
                        break
                    fi
                fi

                if [ "$running_seen" = "true" ] && [ "$marker_seen" = "true" ]; then
                    start_confirmed="true"
                    reason="start_confirmed"
                    break
                fi

                if [ "$status_terminal" = "true" ] && [ "$marker_seen" != "true" ]; then
                    terminal_before_start="true"
                    reason="terminal_before_start"
                    break
                fi

                if [ "$status_rc" -ne 0 ] && [ "$log_rc" -ne 0 ]; then
                    reason="status_and_log_probe_failed"
                fi

                sleep "$START_VALIDATE_INTERVAL_S"
            done

            if [ "$start_confirmed" != "true" ] && [ -z "$reason" ]; then
                reason="start_timeout"
            fi
        fi
    } >"$start_log" 2>&1 || true

    write_start_validation_result \
        "$start_result_path" "$combo_name" "$job_name" "$job_id" "$attempts" \
        "$running_seen" "$marker_seen" "$start_confirmed" "$terminal_before_start" \
        "$last_status" "$last_markers" "$failure_seen" "$last_failure_markers" "$reason"
}

cancel_combo_worker() {
    local combo_name="$1"

    local combo_art_dir="${ARTIFACTS_DIR}/${combo_name}"
    local submit_result_path="${combo_art_dir}/submit_result.json"
    local start_result_path="${combo_art_dir}/start_validation.json"
    local cancel_result_path="${combo_art_dir}/cancel_validation.json"
    local cancel_log="${LOGS_DIR}/${combo_name}.cancel.log"
    local cancel_helper_json="${combo_art_dir}/cancel_helper.json"

    local submit_success
    submit_success="$(json_file_field "$submit_result_path" "success" "false")"
    local start_confirmed
    start_confirmed="$(json_file_field "$start_result_path" "start_confirmed" "false")"
    local job_name
    job_name="$(json_file_field "$submit_result_path" "job_name" "")"
    local job_id
    job_id="$(json_file_field "$submit_result_path" "job_id" "")"

    local cancel_rc=0
    local cancel_confirmed="false"
    local reason=""

    {
        echo "combo_name=${combo_name}"
        echo "job_name=${job_name}"
        echo "job_id=${job_id}"

        if [ "$DRY_RUN" = "true" ]; then
            reason="skipped_dry_run"
            cancel_confirmed="true"
        elif [ "$submit_success" != "true" ]; then
            reason="skipped_submit_failed"
        elif [ -z "$job_name" ] && [ -z "$job_id" ]; then
            reason="missing_job_identifier"
        elif [ "$CONFIRM_LIVE_CANCEL" != "true" ]; then
            reason="blocked_cancel_confirmation_missing"
        else
            local cancel_scope="submitted_job_cleanup"
            if [ "$start_confirmed" = "true" ]; then
                cancel_scope="start_confirmed_cleanup"
            fi
            cmd=(
                "$DEPLOY_SCRIPT"
                --helper-mode cancel
                --ssh-alias "$SSH_ALIAS"
                --cancel-out "$cancel_helper_json"
                --cancel-verify true
                --cancel-verify-timeout "$CANCEL_VERIFY_TIMEOUT_S"
                --cancel-verify-interval "$CANCEL_VERIFY_INTERVAL_S"
            )
            if [ -n "$job_name" ]; then
                cmd+=(--job-name "$job_name")
            fi
            if [ -n "$job_id" ]; then
                cmd+=(--job-id "$job_id")
            fi
            if [ -n "$SITE" ]; then
                cmd+=(--site "$SITE")
            fi

            echo "cancel_scope=${cancel_scope}"
            printf 'Running: %q ' "${cmd[@]}"
            echo
            set +e
            "${cmd[@]}"
            cancel_rc=$?
            set -e

            if [ -f "$cancel_helper_json" ]; then
                cancel_confirmed="$(json_file_field "$cancel_helper_json" "terminal_state_confirmed" "false")"
            fi

            if [ "$cancel_rc" -eq 0 ] && [ "$cancel_confirmed" = "true" ]; then
                reason="cancel_confirmed"
            else
                reason="cancel_not_confirmed"
            fi
        fi
    } >"$cancel_log" 2>&1 || true

    write_cancel_validation_result \
        "$cancel_result_path" "$combo_name" "$job_name" "$job_id" "$cancel_rc" "$cancel_confirmed" "$reason"
}

run_parallel_workers() {
    local worker_fn="$1"
    shift
    local names=("$@")
    local pids=()
    local name
    for name in "${names[@]}"; do
        "$worker_fn" "$name" &
        pids+=("$!")
    done
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
}

write_cycle_critique() {
    local critique_path="$1"
    local cycle_idx="$2"
    local -a chunk_names=("${@:3}")
    {
        echo "# Cycle ${cycle_idx} Critique"
        echo
        local combo_name final_status
        for combo_name in "${chunk_names[@]}"; do
            final_status="$(cat "${STATUS_DIR}/${combo_name}.status" 2>/dev/null || echo "unknown")"
            echo "- ${combo_name}: ${final_status}"
        done
        echo
        echo "## Notes"
        echo "- Validation requires both running status and training-entry log markers."
        echo "- Validation fails early on configured fatal log markers before training markers appear."
        echo "- Cancellation is attempted in parallel for every successfully submitted live job."
    } >"$critique_path"
}

main() {
    local mode="payload"
    local payload_path=""
    local arg

    if [ $# -eq 0 ]; then
        usage
        exit 2
    fi

    while [ $# -gt 0 ]; do
        arg="$1"
        case "$arg" in
        --payload)
            payload_path="$2"
            mode="payload"
            shift 2
            ;;
        --interactive)
            mode="interactive"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            usage
            exit 2
            ;;
        esac
    done

    require_cmd python3
    require_cmd git
    require_cmd base64
    require_cmd ssh
    if [ ! -x "$DEPLOY_SCRIPT" ]; then
        echo "Error: local deploy script not executable: $DEPLOY_SCRIPT" >&2
        exit 1
    fi

    echo "=== Parallel Training Deployment Orchestrator ==="

    if [ "$mode" = "payload" ]; then
        if [ -z "$payload_path" ]; then
            echo "Error: --payload is required in payload mode." >&2
            exit 2
        fi
        load_payload "$payload_path"
    else
        interactive_collect
    fi

    if [ -z "${TASK:-}" ]; then
        echo "Error: task is required." >&2
        exit 1
    fi
    if [ -z "${BRANCH:-}" ]; then
        echo "Error: branch is required." >&2
        exit 1
    fi

    if [ ! -d "$LOCAL_ROOT/.git" ]; then
        echo "Error: local root is not a git repo: $LOCAL_ROOT" >&2
        exit 1
    fi

    if ! [[ "$MAX_LIVE_JOBS_PER_CYCLE" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: max_live_jobs_per_cycle must be a positive integer." >&2
        exit 1
    fi
    if [ "$MAX_LIVE_JOBS_PER_CYCLE" -gt 2 ]; then
        echo "Capping max_live_jobs_per_cycle to 2."
        MAX_LIVE_JOBS_PER_CYCLE="2"
    fi

    if ! [[ "$START_VALIDATE_TIMEOUT_S" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: start_validation_timeout_s must be a positive integer." >&2
        exit 1
    fi
    if ! [[ "$START_VALIDATE_INTERVAL_S" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: start_validation_interval_s must be a positive integer." >&2
        exit 1
    fi
    if ! [[ "$CANCEL_VERIFY_TIMEOUT_S" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: cancel_verify_timeout_s must be a positive integer." >&2
        exit 1
    fi
    if ! [[ "$CANCEL_VERIFY_INTERVAL_S" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: cancel_verify_interval_s must be a positive integer." >&2
        exit 1
    fi

    local envs_init_abs="${LOCAL_ROOT}/${ENVS_INIT_REL}"
    local patch_file_abs="${LOCAL_ROOT}/${PATCH_FILE_REL}"
    if [ ! -f "$envs_init_abs" ]; then
        echo "Error: task registry file not found: $envs_init_abs" >&2
        exit 1
    fi
    if [ ! -f "$patch_file_abs" ]; then
        echo "Error: patch file not found: $patch_file_abs" >&2
        exit 1
    fi
    validate_task_registered "$envs_init_abs" "$TASK"

    local -a hp_specs=()
    if [ -n "${HP_SPECS_B64:-}" ]; then
        mapfile -t hp_specs < <(printf '%s' "$HP_SPECS_B64" | base64 -d | sed '/^[[:space:]]*$/d')
    fi
    if [ "${#hp_specs[@]}" -eq 0 ]; then
        echo "Error: no hyperparameter specs provided." >&2
        exit 1
    fi

    local -a combos=()
    build_combos combos "${hp_specs[@]}"
    if [ "${#combos[@]}" -eq 0 ]; then
        echo "Error: no combinations generated." >&2
        exit 1
    fi

    local sweep_id
    sweep_id="${LABEL_PREFIX}-$(date +%Y%m%d-%H%M%S)"
    RUN_ROOT="${RUN_ROOT_BASE}/${sweep_id}"
    PAYLOADS_DIR="${RUN_ROOT}/payloads"
    LOGS_DIR="${RUN_ROOT}/logs"
    STATUS_DIR="${RUN_ROOT}/status"
    ARTIFACTS_DIR="${RUN_ROOT}/artifacts"
    CRITIQUE_DIR="${RUN_ROOT}/critique"
    mkdir -p "$PAYLOADS_DIR" "$LOGS_DIR" "$STATUS_DIR" "$ARTIFACTS_DIR" "$CRITIQUE_DIR"

    write_manifest "${RUN_ROOT}/run_manifest.json" "$sweep_id" "${#combos[@]}" "$mode"

    if [ "$DRY_RUN" != "true" ]; then
        if [ "$CONFIRM_LIVE_SUBMIT" != "true" ]; then
            echo "Error: live run blocked. Set confirm_live_submit=true in payload." >&2
            exit 1
        fi
        if [ "$CONFIRM_LIVE_CANCEL" != "true" ]; then
            echo "Error: live run blocked. Set confirm_live_cancel=true in payload." >&2
            exit 1
        fi
        if [ -n "$(git -C "$LOCAL_ROOT" status --porcelain)" ]; then
            echo "Error: local repo is dirty. Clean it before baseline push." >&2
            exit 1
        fi
        echo "Pushing baseline branch once: ${BRANCH}"
        git -C "$LOCAL_ROOT" push -u origin "$BRANCH"
    else
        echo "Dry run mode: baseline push and live confirmations skipped."
    fi

    local idx combo combo_name combo_label combo_suffix combo_dir combo_payload
    for idx in "${!combos[@]}"; do
        combo="${combos[$idx]}"
        combo_name="$(printf "combo_%04d" "$((idx + 1))")"
        combo_suffix="$(combo_to_label_suffix "$combo")"
        combo_label="${LABEL_PREFIX}-${combo_suffix}"
        combo_dir="${REMOTE_SWEEP_ROOT}/${sweep_id}/${combo_name}"
        combo_payload="${PAYLOADS_DIR}/${combo_name}.json"

        COMBO_NAMES+=("$combo_name")
        COMBO_SPECS+=("$combo")
        COMBO_LABEL_MAP["$combo_name"]="$combo_label"
        COMBO_DIR_MAP["$combo_name"]="$combo_dir"

        write_combo_payload "$combo_payload" "$combo_name" "$combo" "$combo_label" "$combo_dir"
        echo "pending" >"${STATUS_DIR}/${combo_name}.status"
    done

    local total="${#COMBO_NAMES[@]}"
    local failed_total=0
    local success_total=0
    local cycle_idx=0
    local stop_early="false"

    local offset end i
    for ((offset = 0; offset < total; offset += MAX_LIVE_JOBS_PER_CYCLE)); do
        cycle_idx=$((cycle_idx + 1))
        local -a chunk_names=()
        end=$((offset + MAX_LIVE_JOBS_PER_CYCLE))
        if [ "$end" -gt "$total" ]; then
            end="$total"
        fi
        for ((i = offset; i < end; i++)); do
            chunk_names+=("${COMBO_NAMES[$i]}")
        done

        echo
        echo "=== Cycle ${cycle_idx} / submit chunk size ${#chunk_names[@]} ==="

        local combo_name cycle_index submit_idx
        local -a submit_pids=()
        for combo_name in "${chunk_names[@]}"; do
            submit_idx=$((10#${combo_name#combo_} - 1))
            submit_combo_worker "$combo_name" "${COMBO_SPECS[$submit_idx]}" "${COMBO_LABEL_MAP[$combo_name]}" "${COMBO_DIR_MAP[$combo_name]}" &
            submit_pids+=("$!")
        done
        local pid
        for pid in "${submit_pids[@]}"; do
            wait "$pid" || true
        done

        run_parallel_workers validate_start_worker "${chunk_names[@]}"
        run_parallel_workers cancel_combo_worker "${chunk_names[@]}"

        local combo_failed_in_cycle=0
        for combo_name in "${chunk_names[@]}"; do
            local submit_result_path="${ARTIFACTS_DIR}/${combo_name}/submit_result.json"
            local start_result_path="${ARTIFACTS_DIR}/${combo_name}/start_validation.json"
            local cancel_result_path="${ARTIFACTS_DIR}/${combo_name}/cancel_validation.json"

            local submit_success
            submit_success="$(json_file_field "$submit_result_path" "success" "false")"
            local start_confirmed
            start_confirmed="$(json_file_field "$start_result_path" "start_confirmed" "false")"
            local failure_mode
            failure_mode="$(json_file_field "$start_result_path" "failure_mode" "UNKNOWN")"
            local cancel_confirmed
            cancel_confirmed="$(json_file_field "$cancel_result_path" "cancel_confirmed" "false")"

            local final_status=""
            if [ "$submit_success" != "true" ]; then
                final_status="submit_failed"
            elif [ "$DRY_RUN" = "true" ]; then
                final_status="dry_run_submitted"
            elif [ "$start_confirmed" != "true" ]; then
                if [ "$failure_mode" = "ASSET_MISSING_URDF" ]; then
                    final_status="asset_missing_urdf"
                elif [ "$failure_mode" = "PHYSX_GPU_MEMORY" ]; then
                    final_status="physx_gpu_memory_failure"
                else
                    final_status="start_not_confirmed"
                fi
            elif [ "$cancel_confirmed" != "true" ]; then
                final_status="cancel_failed"
            else
                final_status="success"
            fi

            echo "$final_status" >"${STATUS_DIR}/${combo_name}.status"
            if [ "$final_status" = "success" ] || [ "$final_status" = "dry_run_submitted" ]; then
                success_total=$((success_total + 1))
            else
                failed_total=$((failed_total + 1))
                combo_failed_in_cycle=$((combo_failed_in_cycle + 1))
            fi
        done

        write_cycle_critique "${CRITIQUE_DIR}/cycle_$(printf "%04d" "$cycle_idx").md" "$cycle_idx" "${chunk_names[@]}"

        if [ "$combo_failed_in_cycle" -gt 0 ] && [ "$CONTINUE_ON_ERROR" != "true" ]; then
            stop_early="true"
            echo "Stopping early because continue_on_error=false and cycle ${cycle_idx} had failures."
            break
        fi
    done

    echo
    echo "=== Parallel Sweep Summary ==="
    echo "Sweep ID: ${sweep_id}"
    echo "Run root: ${RUN_ROOT}"
    echo "Total combos: ${total}"
    echo "Succeeded: ${success_total}"
    echo "Failed: ${failed_total}"
    echo "Max live jobs per cycle: ${MAX_LIVE_JOBS_PER_CYCLE} (hard cap 2)"
    echo "Artifacts dir: ${ARTIFACTS_DIR}"
    echo "Critique dir: ${CRITIQUE_DIR}"
    echo "Run manifest: ${RUN_ROOT}/run_manifest.json"

    if [ "$failed_total" -gt 0 ] && [ "$DRY_RUN" != "true" ]; then
        echo
        echo "Failed combos:"
        local combo_name
        for combo_name in "${COMBO_NAMES[@]}"; do
            local st
            st="$(cat "${STATUS_DIR}/${combo_name}.status" 2>/dev/null || true)"
            if [ "$st" != "success" ]; then
                echo "  - ${combo_name}: ${st}"
                echo "    submit: ${ARTIFACTS_DIR}/${combo_name}/submit_result.json"
                echo "    start:  ${ARTIFACTS_DIR}/${combo_name}/start_validation.json"
                echo "    cancel: ${ARTIFACTS_DIR}/${combo_name}/cancel_validation.json"
            fi
        done
        exit 1
    fi

    if [ "$stop_early" = "true" ]; then
        exit 1
    fi
}

main "$@"

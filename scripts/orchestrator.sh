#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy_fuyao.sh"
PARALLEL_ENGINE_SCRIPT="${SCRIPT_DIR}/orchestrator_parallel.sh"

if [ -x "$PARALLEL_ENGINE_SCRIPT" ]; then
    exec "$PARALLEL_ENGINE_SCRIPT" "$@"
fi
DEFAULT_LOCAL_ROOT="/home/huh/software/motion_rl"
DEFAULT_ENVS_INIT_REL="humanoid-gym/humanoid/envs/__init__.py"
DEFAULT_PATCH_FILE_REL="humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py"
DEFAULT_REMOTE_DEPLOY_SCRIPT="/root/.cursor/scripts/deploy_fuyao.sh"
DEFAULT_SSH_ALIAS="Huh8.remote_kernel.fuyao"
DEFAULT_REMOTE_ROOT="/root/motion_rl"
DEFAULT_REMOTE_SWEEP_ROOT="/tmp/fuyao_sweeps"
DEFAULT_RUN_ROOT_BASE="${HOME}/.cursor/tmp/orchestrator_runs"
DEFAULT_MAX_PARALLEL="4"
DEFAULT_LABEL_PREFIX="sweep"
DEFAULT_SUBAGENT_RUNNER_TEMPLATE='cursor task --description "{description}" --prompt-file "{prompt_file}"'

usage() {
    cat <<'EOF'
Usage:
  orchestrator.sh --payload /abs/path/to/sweep_payload.json
  orchestrator.sh --interactive

Primary mode:
  --payload      Deterministic backend mode intended for Orchestrator Agent frontend.

Interactive mode:
  --interactive  Manual fallback intake in shell.

Payload schema (minimum):
{
  "task": "r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes",
  "branch": "your_branch",
  "patch_file_rel": "humanoid-gym/humanoid/envs/...py",
  "hp_specs": ["learning_rate=3e-4,1e-4", "entropy_coef=0.01,0.02"]
}

Optional fields (defaults from deploy_fuyao.sh where applicable):
  local_root, envs_init_rel, ssh_alias, remote_root, remote_sweep_root,
  run_root_base,
  dispatch_mode,
  max_parallel, label_prefix, experiment, queue, project, site, nodes,
  gpus_per_node, gpu_type, gpu_slice, priority, docker_image, rl_device,
  dry_run, continue_on_error, remote_deploy_script, subagent_runner_template.

Notes:
  - dispatch_mode controls execution backend:
      auto (default), subagent_cli, builtin_parallel
  - auto uses subagent CLI if available, otherwise builtin parallel executor.
  - Each execution sub-agent is instructed to call remote deploy script:
    /root/.cursor/scripts/deploy_fuyao.sh
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

render_runner_command() {
    local template="$1"
    local description="$2"
    local prompt_file="$3"
    local payload_file="$4"
    local combo_name="$5"
    python3 - "$template" "$description" "$prompt_file" "$payload_file" "$combo_name" <<'PY'
import sys
t, d, p, j, c = sys.argv[1:]
print(
    t.replace("{description}", d)
    .replace("{prompt_file}", p)
    .replace("{payload_file}", j)
    .replace("{combo_name}", c)
)
PY
}

validate_dispatch_log_has_submission_evidence() {
    local log_path="$1"
    local evidence_out="$2"
    python3 - "$log_path" "$evidence_out" <<'PY'
import pathlib
import sys

log_path = pathlib.Path(sys.argv[1])
evidence_out = pathlib.Path(sys.argv[2])
text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""

bad_markers = [
    "Ignoring option",
    "Runner command unavailable",
    "Unknown argument",
]

evidence_markers = [
    "Deploy command submitted.",
    "Final deploy command (runs on remote kernel via SSH):",
    "fuyao deploy",
]

for marker in bad_markers:
    if marker in text:
        evidence_out.write_text(f"blocked_by_marker: {marker}\n", encoding="utf-8")
        raise SystemExit(2)

for marker in evidence_markers:
    if marker in text:
        evidence_out.write_text(f"submission_evidence: {marker}\n", encoding="utf-8")
        raise SystemExit(0)

evidence_out.write_text("missing_submission_evidence\n", encoding="utf-8")
raise SystemExit(1)
PY
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
emit("TASK", s("task", ""))
emit("BRANCH", s("branch", ""))
emit("SSH_ALIAS", s("ssh_alias", "Huh8.remote_kernel.fuyao"))
emit("REMOTE_ROOT", s("remote_root", "/root/motion_rl"))
emit("REMOTE_SWEEP_ROOT", s("remote_sweep_root", "/tmp/fuyao_sweeps"))
emit("RUN_ROOT_BASE", s("run_root_base", f"{__import__('os').path.expanduser('~')}/.cursor/tmp/orchestrator_runs"))
emit("MAX_PARALLEL", s("max_parallel", "4"))
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
emit("DRY_RUN", s("dry_run", "false"))
emit("CONTINUE_ON_ERROR", s("continue_on_error", "true"))
emit("REMOTE_DEPLOY_SCRIPT", s("remote_deploy_script", "/root/.cursor/scripts/deploy_fuyao.sh"))
emit("SUBAGENT_RUNNER_TEMPLATE", s("subagent_runner_template", 'cursor task --description "{description}" --prompt-file "{prompt_file}"'))
emit("DISPATCH_MODE", s("dispatch_mode", "auto"))

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
    PATCH_FILE_REL="$(read_with_default "Task config file to patch (relative to repo)" "$DEFAULT_PATCH_FILE_REL")"
    BRANCH="$(read_with_default "Target branch to use as baseline" "$(git -C "$LOCAL_ROOT" rev-parse --abbrev-ref HEAD)")"
    SSH_ALIAS="$(read_with_default "SSH alias" "$DEFAULT_SSH_ALIAS")"
    REMOTE_ROOT="$(read_with_default "Remote repo root" "$DEFAULT_REMOTE_ROOT")"
    REMOTE_SWEEP_ROOT="$(read_with_default "Remote sweep root directory" "$DEFAULT_REMOTE_SWEEP_ROOT")"
    RUN_ROOT_BASE="$(read_with_default "Run root base directory" "$DEFAULT_RUN_ROOT_BASE")"
    MAX_PARALLEL="$(read_with_default "Max parallel sub-agents" "$DEFAULT_MAX_PARALLEL")"
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
    DRY_RUN="$(read_with_default "Dry run? (true/false)" "false")"
    CONTINUE_ON_ERROR="$(read_with_default "Continue on agent failures? (true/false)" "true")"
    REMOTE_DEPLOY_SCRIPT="$(read_with_default "Remote deploy script path" "$DEFAULT_REMOTE_DEPLOY_SCRIPT")"
    SUBAGENT_RUNNER_TEMPLATE="$(read_with_default "Sub-agent runner template" "$DEFAULT_SUBAGENT_RUNNER_TEMPLATE")"
    DISPATCH_MODE="$(read_with_default "Dispatch mode (auto/subagent_cli/builtin_parallel)" "auto")"

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

    echo "=== Training Deployment Orchestrator ==="

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
    local run_root
    run_root="${RUN_ROOT_BASE}/${sweep_id}"
    local payloads_dir prompts_dir logs_dir status_dir
    payloads_dir="${run_root}/payloads"
    prompts_dir="${run_root}/prompts"
    logs_dir="${run_root}/logs"
    status_dir="${run_root}/status"
    mkdir -p "$payloads_dir" "$prompts_dir" "$logs_dir" "$status_dir"

    if [ "$DRY_RUN" != "true" ]; then
        if [ -n "$(git -C "$LOCAL_ROOT" status --porcelain)" ]; then
            echo "Error: local repo is dirty. Clean it before baseline push." >&2
            exit 1
        fi
        echo "Pushing baseline branch once: ${BRANCH}"
        git -C "$LOCAL_ROOT" push -u origin "$BRANCH"
    else
        echo "Dry run mode: baseline push skipped."
    fi

    local -a dispatch_pids=()
    local -a combo_names=()
    local -a combo_specs=()
    local -a combo_log_paths=()
    local -a combo_runner_cmds=()
    local -a combo_evidence_paths=()
    local combo idx combo_name combo_label combo_suffix combo_dir combo_payload prompt_path dispatch_log runner_cmd
    local runner_bin="${SUBAGENT_RUNNER_TEMPLATE%% *}"
    local runner_available="true"
    local runner_block_reason=""
    if ! command -v "$runner_bin" >/dev/null 2>&1; then
        runner_available="false"
        runner_block_reason="runner_binary_not_found:${runner_bin}"
    fi
    if [ "$runner_available" = "true" ] && [ "$runner_bin" = "cursor" ]; then
        if [[ "$SUBAGENT_RUNNER_TEMPLATE" == *" task "* ]]; then
            if ! cursor --help 2>/dev/null | awk 'tolower($0) ~ /task|agent/ {found=1} END {exit found?0:1}'; then
                runner_available="false"
                runner_block_reason="cursor_cli_missing_task_or_agent_subcommand"
            fi
        fi
    fi
    local effective_dispatch_mode="$DISPATCH_MODE"
    if [ "$DISPATCH_MODE" = "auto" ]; then
        if [ "$runner_available" = "true" ]; then
            effective_dispatch_mode="subagent_cli"
        else
            effective_dispatch_mode="builtin_parallel"
        fi
    fi
    if [ "$effective_dispatch_mode" = "subagent_cli" ] && [ "$runner_available" != "true" ]; then
        echo "Error: dispatch_mode=subagent_cli but runner unavailable: ${runner_block_reason}" >&2
        exit 1
    fi
    if [ "$effective_dispatch_mode" != "subagent_cli" ] && [ "$effective_dispatch_mode" != "builtin_parallel" ]; then
        echo "Error: unsupported dispatch_mode '${DISPATCH_MODE}' (effective '${effective_dispatch_mode}')" >&2
        exit 1
    fi

    local manual_dispatch_script="${run_root}/manual_dispatch.sh"
    local retry_failed_script="${run_root}/retry_failed_dispatch.sh"
    : >"$manual_dispatch_script"
    : >"$retry_failed_script"
    chmod +x "$manual_dispatch_script"
    chmod +x "$retry_failed_script"

    python3 - "$run_root/run_manifest.json" "$sweep_id" "$TASK" "$BRANCH" "$PATCH_FILE_REL" "$SSH_ALIAS" \
        "$REMOTE_ROOT" "$REMOTE_DEPLOY_SCRIPT" "$LABEL_PREFIX" "$MAX_PARALLEL" "$DRY_RUN" "$CONTINUE_ON_ERROR" \
        "${#combos[@]}" "$mode" <<'PY'
import json
import sys

(
    out_path, sweep_id, task, branch, patch_file_rel, ssh_alias, remote_root,
    remote_deploy_script, label_prefix, max_parallel, dry_run, continue_on_error,
    combo_count, mode
) = sys.argv[1:]

manifest = {
    "sweep_id": sweep_id,
    "mode": mode,
    "task": task,
    "branch": branch,
    "patch_file_rel": patch_file_rel,
    "ssh_alias": ssh_alias,
    "remote_root": remote_root,
    "remote_deploy_script": remote_deploy_script,
    "label_prefix": label_prefix,
    "max_parallel": int(max_parallel),
    "dry_run": dry_run == "true",
    "continue_on_error": continue_on_error == "true",
    "combo_count": int(combo_count),
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
PY

    for idx in "${!combos[@]}"; do
        combo="${combos[$idx]}"
        combo_name="$(printf "combo_%04d" "$((idx + 1))")"
        combo_suffix="$(combo_to_label_suffix "$combo")"
        combo_label="${LABEL_PREFIX}-${combo_suffix}"
        combo_dir="${REMOTE_SWEEP_ROOT}/${sweep_id}/${combo_name}"
        combo_payload="${payloads_dir}/${combo_name}.json"
        prompt_path="${prompts_dir}/${combo_name}.md"
        dispatch_log="${logs_dir}/${combo_name}.dispatch.log"
        local evidence_file="${logs_dir}/${combo_name}.evidence.txt"

        python3 - "$combo_payload" "$combo_name" "$combo" "$combo_label" "$combo_dir" \
            "$TASK" "$PATCH_FILE_REL" "$BRANCH" "$SSH_ALIAS" "$REMOTE_ROOT" "$REMOTE_DEPLOY_SCRIPT" \
            "$EXPERIMENT" "$QUEUE" "$PROJECT" "$SITE" "$NODES" "$GPUS_PER_NODE" "$GPU_TYPE" "$GPU_SLICE" \
            "$PRIORITY" "$DOCKER_IMAGE" "$RL_DEVICE" "$DRY_RUN" <<'PY'
import json
import sys
(
    out_path, combo_name, combo_spec, label, combo_dir, task, patch_file_rel, branch,
    ssh_alias, remote_root, remote_deploy_script, experiment, queue, project, site,
    nodes, gpus_per_node, gpu_type, gpu_slice, priority, docker_image, rl_device, dry_run
) = sys.argv[1:]

payload = {
    "combo_name": combo_name,
    "combo_spec": combo_spec,
    "combo_label": label,
    "combo_dir": combo_dir,
    "task": task,
    "patch_file_rel": patch_file_rel,
    "branch": branch,
    "ssh_alias": ssh_alias,
    "remote_root": remote_root,
    "remote_deploy_script": remote_deploy_script,
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
        "dry_run": dry_run,
    },
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY

        cat >"$prompt_path" <<EOF
You are an execution sub-agent for one hyperparameter combo submission.

Read this payload JSON first:
\`${combo_payload}\`

Then execute exactly this workflow:
1) Parse payload fields and print them as a checklist.
2) On remote kernel (\${ssh_alias} from payload), create combo worktree:
   - cd "\${remote_root}"
   - git fetch origin "\${branch}"
   - git worktree remove --force "\${combo_dir}" || true
   - rm -rf "\${combo_dir}" || true
   - git worktree add --force "\${combo_dir}" "origin/\${branch}"
3) Patch hard-coded hyperparameters in:
   "\${combo_dir}/\${patch_file_rel}"
   using combo spec assignments \${combo_spec} where each entry is key=value and lines are expected in key = old_value form.
4) Submit deployment by invoking remote script:
   "\${remote_deploy_script}"
   with parameters from payload deploy_args and:
   --skip-git-sync true
   --task "\${task}"
   --label "\${combo_label}"
   --remote-root "\${combo_dir}"
5) If submission succeeds, print concise success line with combo_name and label.
6) If submission fails, print concise failure reason and keep worktree for debugging.
7) On success only, clean up combo worktree path.

Important:
- Do not ask user follow-up questions.
- Execute commands directly and report outputs succinctly.
EOF

        runner_cmd="$(render_runner_command "$SUBAGENT_RUNNER_TEMPLATE" "submit ${combo_name}" "$prompt_path" "$combo_payload" "$combo_name")"
        echo "$runner_cmd" >>"$manual_dispatch_script"
        echo "dispatched" >"${status_dir}/${combo_name}.status"

        while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MAX_PARALLEL" ]; do
            sleep 1
        done

        if [ "$effective_dispatch_mode" = "subagent_cli" ]; then
            (
                set -euo pipefail
                echo "dispatching ${combo_name} via subagent_cli"
                bash -lc "$runner_cmd"
            ) >"$dispatch_log" 2>&1 &
            dispatch_pids+=("$!")
        else
            (
                set -euo pipefail
                echo "dispatching ${combo_name} via builtin_parallel"
                if [ "$DRY_RUN" != "true" ]; then
                    prepare_remote_combo_repo "$SSH_ALIAS" "$REMOTE_ROOT" "$BRANCH" "$combo_dir" "$PATCH_FILE_REL" "$combo"
                else
                    echo "DRY-RUN: skipping remote patch preparation"
                fi
                cmd=(
                    "$DEPLOY_SCRIPT"
                    --skip-git-sync true
                    --ssh-alias "$SSH_ALIAS"
                    --remote-root "$combo_dir"
                    --task "$TASK"
                    --label "$combo_label"
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
                )
                if [ -n "$GPU_SLICE" ]; then
                    cmd+=(--gpu-slice "$GPU_SLICE")
                fi
                if [ "$DRY_RUN" = "true" ]; then
                    cmd+=(--dry-run)
                fi
                printf 'Running: %q ' "${cmd[@]}"
                echo
                "${cmd[@]}"
                if [ "$DRY_RUN" != "true" ]; then
                    cleanup_remote_combo_repo "$SSH_ALIAS" "$REMOTE_ROOT" "$combo_dir"
                fi
            ) >"$dispatch_log" 2>&1 &
            dispatch_pids+=("$!")
        fi

        combo_names+=("$combo_name")
        combo_specs+=("$combo")
        combo_log_paths+=("$dispatch_log")
        combo_runner_cmds+=("$runner_cmd")
        combo_evidence_paths+=("$evidence_file")
    done

    local failed=0 succeeded=0 i
    for i in "${!combo_names[@]}"; do
        if [ -n "${dispatch_pids[$i]}" ]; then
            if wait "${dispatch_pids[$i]}"; then
                if validate_dispatch_log_has_submission_evidence "${combo_log_paths[$i]}" "${combo_evidence_paths[$i]}"; then
                    echo "success" >"${status_dir}/${combo_names[$i]}.status"
                    succeeded=$((succeeded + 1))
                else
                    echo "failed_no_submission_evidence" >"${status_dir}/${combo_names[$i]}.status"
                    failed=$((failed + 1))
                    echo "${combo_runner_cmds[$i]}" >>"$retry_failed_script"
                    if [ "$CONTINUE_ON_ERROR" != "true" ]; then
                        echo "Stopping on missing submission evidence because continue_on_error=false"
                        break
                    fi
                fi
            else
                echo "failed" >"${status_dir}/${combo_names[$i]}.status"
                failed=$((failed + 1))
                echo "${combo_runner_cmds[$i]}" >>"$retry_failed_script"
                if [ "$CONTINUE_ON_ERROR" != "true" ]; then
                    echo "Stopping on first failure because continue_on_error=false"
                    break
                fi
            fi
        else
            failed=$((failed + 1))
            echo "${combo_runner_cmds[$i]}" >>"$retry_failed_script"
        fi
    done

    echo
    echo "=== Dispatch Summary ==="
    echo "Sweep ID: ${sweep_id}"
    echo "Run root: ${run_root}"
    echo "Total combos: ${#combos[@]}"
    echo "Succeeded dispatches: ${succeeded}"
    echo "Failed/undispatched: ${failed}"
    echo "Dispatch mode used: ${effective_dispatch_mode}"
    if [ "$effective_dispatch_mode" = "subagent_cli" ] && [ "$runner_available" != "true" ]; then
        echo "Runner unavailable: ${runner_block_reason}"
        echo "Manual dispatch script: ${manual_dispatch_script}"
    fi
    echo "Per-combo prompts: ${prompts_dir}"
    echo "Per-combo payloads: ${payloads_dir}"
    echo "Per-combo logs: ${logs_dir}"
    echo "Per-combo evidence: ${logs_dir}/*.evidence.txt"
    echo "Run manifest: ${run_root}/run_manifest.json"

    if [ "$failed" -gt 0 ]; then
        echo
        echo "Failed combo guidance:"
        for i in "${!combo_names[@]}"; do
            if [ "$(cat "${status_dir}/${combo_names[$i]}.status" 2>/dev/null || true)" != "success" ]; then
                echo "  - ${combo_names[$i]} : ${combo_specs[$i]}"
                echo "    log: ${combo_log_paths[$i]}"
                echo "    evidence: ${combo_evidence_paths[$i]}"
            fi
        done
        echo "Retry script: ${retry_failed_script}"
        exit 1
    fi
}

main "$@"

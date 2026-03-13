#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy_fuyao.sh"

DEFAULT_ENVS_INIT_REL="humanoid-gym/humanoid/envs/__init__.py"
DEFAULT_PATCH_FILE_REL="humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py"
DEFAULT_REMOTE_ROOT="/root/motion_rl"
DEFAULT_REMOTE_SWEEP_ROOT="/tmp/fuyao_sweeps"
DEFAULT_RUN_ROOT_BASE="${HOME}/.cursor/tmp/deploy_fuyao_sweep_runs"
DEFAULT_LABEL_PREFIX="auto"
DEFAULT_MAX_PARALLEL="4"
DEFAULT_QUEUE="rc-wbc-4090"
DEFAULT_PROJECT="rc-wbc"
DEFAULT_SITE="fuyao_sh_n2"
DEFAULT_EXPERIMENT="huh8/r01"
DEFAULT_GPUS_PER_NODE="1"
DEFAULT_NODES="1"
DEFAULT_GPU_TYPE="exclusive"
DEFAULT_PRIORITY="normal"
DEFAULT_DOCKER_IMAGE="infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347"
DEFAULT_RL_DEVICE="cuda:0"

# Deterministic hyperparameter alias config for readable sweep labels
HP_ALIAS_MAP_VERSION="1"
HP_ALIAS_FALLBACK_MAX_LEN=8
HP_ALIAS_KEYS=(
    learning_rate
    entropy_coef
    seed
    seeds
    gamma
    lam
    clip_param
    num_learning_epochs
    num_mini_batches
    desired_kl
    max_grad_norm
    value_loss_coef
    num_steps_per_env
    experiment_name
    init_noise_std
    num_envs
    frame_stack
    c_frame_stack
    max_push_vel_xy
    max_push_ang_vel
    tracking_avg_lin_vel
    tracking_sigma_lin_vel
    tracking_sigma_torso_ang_vel_xy
    batch_size
    epoch_num
    continue_value
)
HP_ALIAS_VALUES=(
    lr
    ec
    seed
    seed
    gamma
    lam
    cp
    nle
    nmb
    dkl
    mgn
    vlc
    nse
    exp
    instd
    nenv
    fs
    cfs
    mpvxy
    mpa
    tal
    tslv
    tsavxy
    bs
    en
    cval
)

hp_alias_lookup() {
    local key="$1"
    local idx
    for idx in "${!HP_ALIAS_KEYS[@]}"; do
        if [ "${HP_ALIAS_KEYS[$idx]}" = "$key" ]; then
            printf "%s" "${HP_ALIAS_VALUES[$idx]}"
            return 0
        fi
    done
    return 1
}

usage() {
    cat <<'EOF'
Usage:
  deploy_fuyao_sweep_dispatcher.sh --payload /abs/path/to/sweep_payload.json

Required:
  --payload    JSON payload path

Payload schema (minimum):
{
  "task": "r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes",
  "branch": "huh8/my-experiment",
  "hp_specs": ["learning_rate=1e-4,2e-4", "entropy_coef=0.01,0.005"],
  "confirm_dispatch": false
}

Optional:
  local_root, envs_init_rel, patch_file_rel, ssh_alias, remote_root, remote_sweep_root,
  run_root_base, max_parallel, label_prefix, queue, project, site, nodes,
  gpus_per_node, gpu_type, gpu_slice, priority, docker_image, rl_device,
  dry_run, continue_on_error, confirm_dispatch, experiment, hp_class_map
Special:
  --print-label-map        Print canonical hyperparameter alias map and exit
  --print-label-map-json   Print the alias map in JSON and exit
  --check-label-aliases    Run deterministic label regression check and exit
EOF
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf "%s" "$s"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: missing command '$cmd'" >&2
        exit 1
    fi
}

is_true() {
    local val
    val="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$val" in
        true|1|yes|on) return 0 ;;
        false|0|no|off|"") return 1 ;;
        *) return 2 ;;
    esac
}

read_payload() {
    local payload_path="$1"
    if [ -z "$payload_path" ]; then
        echo "Error: --payload is required." >&2
        exit 1
    fi
    if [ ! -f "$payload_path" ]; then
        echo "Error: payload file not found: $payload_path" >&2
        exit 1
    fi
    require_cmd python3

    eval "$(
        python3 - "$payload_path" <<'PY'
import base64
import json
import shlex
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as exc:
    print(f"Error: failed to read payload {path}: {exc}", file=sys.stderr)
    raise SystemExit(1)


def s(name, default):
    value = data.get(name, default)
    if isinstance(value, bool):
        return "true" if value else "false"
    return "" if value is None else str(value)


def emit(name, value):
    print(f'{name}={shlex.quote(value)}')


emit("TASK", s("task", ""))
emit("BRANCH", s("branch", ""))
emit("LOCAL_ROOT", s("local_root", ""))
emit("ENVS_INIT_REL", s("envs_init_rel", "humanoid-gym/humanoid/envs/__init__.py"))
emit("PATCH_FILE_REL", s("patch_file_rel", "humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py"))
emit("SSH_ALIAS", s("ssh_alias", "Huh8.remote_kernel.fuyao"))
emit("REMOTE_ROOT", s("remote_root", "/root/motion_rl"))
emit("REMOTE_SWEEP_ROOT", s("remote_sweep_root", "/tmp/fuyao_sweeps"))
emit("RUN_ROOT_BASE", s("run_root_base", f"{__import__('os').path.expanduser('~')}/.cursor/tmp/deploy_fuyao_sweep_runs"))
emit("LABEL_PREFIX", s("label_prefix", "sweep"))
emit("MAX_PARALLEL", s("max_parallel", "4"))
emit("EXPERIMENT", s("experiment", "huh8/r01"))
emit("QUEUE", s("queue", "rc-wbc-4090"))
emit("PROJECT", s("project", "rc-wbc"))
emit("SITE", s("site", "fuyao_sh_n2"))
emit("NODES", s("nodes", "1"))
emit("GPUS_PER_NODE", s("gpus_per_node", "1"))
emit("GPU_TYPE", s("gpu_type", "exclusive"))
emit("GPU_SLICE", s("gpu_slice", ""))
emit("PRIORITY", s("priority", "normal"))
emit("DOCKER_IMAGE", s("docker_image", "infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347"))
emit("RL_DEVICE", s("rl_device", "cuda:0"))
emit("DRY_RUN", s("dry_run", "false"))
emit("CONTINUE_ON_ERROR", s("continue_on_error", "true"))

hp_specs = []
if "hp_specs" in data and isinstance(data["hp_specs"], list):
    hp_specs = [str(x).strip() for x in data["hp_specs"] if str(x).strip()]
elif "hyperparameters" in data and isinstance(data["hyperparameters"], list):
    for item in data["hyperparameters"]:
        if isinstance(item, dict):
            key = str(item.get("key", "")).strip()
            values = item.get("values", [])
            if not key or not isinstance(values, list):
                continue
            parsed_values = [str(v).strip() for v in values if str(v).strip()]
            if parsed_values:
                hp_specs.append(f"{key}={','.join(parsed_values)}")
        else:
            text = str(item).strip()
            if text:
                hp_specs.append(text)

emit("HP_SPECS_B64", base64.b64encode("\n".join(hp_specs).encode("utf-8")).decode("ascii"))

class_map = data.get("hp_class_map", {})
if class_map is None:
    class_map = {}
emit("HP_CLASS_MAP_B64", base64.b64encode(json.dumps(class_map, sort_keys=True).encode("utf-8")).decode("ascii"))
emit("RESUME", s("resume", "false"))
emit("CHECKPOINT_PATH", s("checkpoint_path", ""))
emit("CONFIRM_DISPATCH", s("confirm_dispatch", "false"))
PY
    )"
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
registered = set(re.compile(r'task_registry\.register\(\s*"([^"]+)"').findall(text))
if task not in registered:
    print(f"Task '{task}' is not registered in {path}", file=sys.stderr)
    if registered:
        sample = sorted(registered)[:20]
        print("Registered examples: " + ", ".join(sample), file=sys.stderr)
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
    local specs=("$@")
    local current=("")
    local -a next=()
    local key values raw_val val combo
    local spec

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
            for combo in "${current[@]}"; do
                if [ -z "$combo" ]; then
                    next+=("${key}=${val}")
                else
                    next+=("${combo};${key}=${val}")
                fi
            done
        done
        current=("${next[@]}")
    done

    BUILD_COMBOS_RESULT=("${current[@]}")
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
    local pair key value short_key short_value suffix
    local IFS=';'
    local -a pairs=()
    local index=0
    local count=0

    if [ -z "$combo" ]; then
        printf "combo"
        return
    fi

    read -r -a pairs <<< "$combo"
    for index in "${!pairs[@]}"; do
        pair="${pairs[$index]}"
        if [[ "$pair" != *"="* ]]; then
            continue
        fi

        key="${pair%%=*}"
        value="${pair#*=}"
        key="$(trim "$key")"
        value="$(trim "$value")"

        if [ -z "$key" ] || [ -z "$value" ]; then
            continue
        fi

        short_key="$(hp_alias "$key")"
        short_value="$(escape_label_piece "$value")"

        if [ "$count" -gt 0 ]; then
            suffix+="-"
        fi
        suffix+="${short_key}_${short_value}"
        count=$((count + 1))
    done

    if [ -z "$suffix" ]; then
        suffix="$(escape_label_piece "$combo")"
    fi
    if [ -z "$suffix" ]; then
        suffix="combo"
    fi
    printf "%s" "$suffix"
}

sanitize_alias_key() {
    local token="$1"
    local sanitized
    sanitized="$(python3 - "$token" "$HP_ALIAS_FALLBACK_MAX_LEN" <<'PY'
import re
import sys

token = sys.argv[1].strip().lower()
max_len = int(sys.argv[2])

token = re.sub(r"[^a-z0-9_]+", "_", token)
token = re.sub(r"_+", "_", token).strip("_")
if not token:
    token = "k"
if len(token) > max_len:
    token = token[:max_len]
print(token)
PY
)"
    printf "%s" "$sanitized"
}

hp_alias() {
    local key="$1"
    local normalized
    local alias
    normalized="$(printf "%s" "$key" | tr "[:upper:]" "[:lower:]")"
    alias="$(hp_alias_lookup "$normalized" || true)"
    if [ -n "$alias" ]; then
        printf "%s" "$alias"
        return 0
    fi
    printf "%s" "$(sanitize_alias_key "$normalized")"
}

derive_sweep_label_prefix() {
    local task="$1"
    python3 - "$task" <<'PY'
import sys

task = sys.argv[1]
noise = {"with", "and", "full", "scenes", "the", "for", "plus", "a", "an"}
parts = [p for p in task.split("_") if p.lower() not in noise and p]
slug = "-".join(parts[:5])
if len(slug) > 24:
    slug = slug[:24].rstrip("-")
if not slug:
    slug = "sweep"
print(slug)
PY
}

print_label_map() {
    local print_json="$1"
    local -a sorted_keys=()
    local key val
    local index=0
    local total=0
    local tmp_keys

    sorted_keys=("${HP_ALIAS_KEYS[@]}")
    IFS=$'\n' sorted_keys=($(printf '%s\n' "${sorted_keys[@]}" | sort))
    total="${#sorted_keys[@]}"

    if [ "$print_json" = "true" ]; then
        echo "{"
        echo "  \"alias_map_version\": \"${HP_ALIAS_MAP_VERSION}\","
        echo "  \"fallback_policy\": \"lowercase, replace non [a-z0-9_] with '_', collapse repeats, trim, fallback to 'k', truncate to ${HP_ALIAS_FALLBACK_MAX_LEN}\","
        echo "  \"aliases\": {"
        for key in "${sorted_keys[@]}"; do
            index=$((index + 1))
            val="$(hp_alias_lookup "$key")"
            if [ "$index" -lt "$total" ]; then
                echo "    \"${key}\": \"${val}\","
            else
                echo "    \"${key}\": \"${val}\""
            fi
        done
        echo "  }"
        echo "}"
        return 0
    fi

    echo "Hyperparameter label alias map (version ${HP_ALIAS_MAP_VERSION})"
    echo "Long name -> short alias"
    for key in "${sorted_keys[@]}"; do
        val="$(hp_alias_lookup "$key")"
        printf "  %s -> %s\n" "$key" "$val"
    done
    echo
    echo "Fallback policy: lowercase, replace non [a-z0-9_] with '_', collapse repeats, trim edges, fallback to 'k', truncate to ${HP_ALIAS_FALLBACK_MAX_LEN}."
}

run_label_alias_regression() {
    local sample1="learning_rate=1e-4;seed=1"
    local sample2="learning_rate=1e-4;seed=1"
    local sample3="seed=1;learning_rate=1e-4"
    local out1 out2 out3
    local -a specs=(
        "learning_rate=1e-4,2e-4"
        "seed=1,2"
    )
    local -a combos=()
    local -a suffix_seen_keys=()
    local combo suffix
    local index_seen

    out1="$(combo_to_label_suffix "$sample1")"
    out2="$(combo_to_label_suffix "$sample2")"
    if [ "$out1" != "$out2" ]; then
        echo "Regression failure: repeated rendering mismatch." >&2
        echo "sample1=${sample1}" >&2
        echo "sample2=${sample2}" >&2
        echo "out1=${out1}" >&2
        echo "out2=${out2}" >&2
        return 1
    fi

    out3="$(combo_to_label_suffix "$sample3")"
    echo "Order-sensitive check:"
    echo "  ${sample1} -> ${out1}"
    echo "  ${sample3} -> ${out3}"

    build_combos combos "${specs[@]}"
    for combo in "${combos[@]}"; do
        suffix="$(combo_to_label_suffix "${combo}")"
        index_seen=-1
        for idx in "${!suffix_seen_keys[@]}"; do
            if [ "${suffix_seen_keys[$idx]}" = "$suffix" ]; then
                index_seen=$idx
                break
            fi
        done
        if [ "$index_seen" -ge 0 ]; then
            echo "Regression failure: duplicate suffix detected: ${suffix}" >&2
            echo "combo=${combo}" >&2
            echo "previous=${suffix_seen_keys[$index_seen]}" >&2
            return 1
        fi
        suffix_seen_keys+=("$suffix")
        echo "  ${combo} -> ${suffix}"
    done

    echo "Label alias regression passed."
    return 0
}

write_json_file() {
    local out_path="$1"
    local payload="$2"
    python3 - "$out_path" "$payload" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(sys.argv[2])
path.parent.mkdir(parents=True, exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY
}

extract_job_name_from_log() {
    local log_path="$1"
    if [ ! -f "$log_path" ]; then
        printf ""
        return 0
    fi
    python3 - "$log_path" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, "r", encoding="utf-8", errors="replace").read()
pattern = re.compile(r"bifrost-\d{16,}-\S+")
match = pattern.findall(text)
if match:
    print(match[-1])
PY
}

write_status() {
    local status_path="$1"
    local status="$2"
    local reason="$3"
    local combo_name="$4"
    local combo_label="$5"
    local job_name="$6"
    local combo_dir="$7"

    python3 - "$status_path" "$status" "$reason" "$combo_name" "$combo_label" "$job_name" "$combo_dir" <<'PY'
import json
import sys

path, status, reason, combo_name, combo_label, job_name, combo_dir = sys.argv[1:8]
payload = {
    "status": status,
    "reason": reason,
    "combo_name": combo_name,
    "combo_label": combo_label,
    "job_name": job_name,
    "combo_dir": combo_dir,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, sort_keys=True)
PY
}

prepare_remote_combo_repo() {
    local ssh_alias="$1"
    local remote_root="$2"
    local branch="$3"
    local combo_dir="$4"
    local patch_file_rel="$5"
    local assignments_b64="$6"
    local class_map_b64="$7"

    ssh "$ssh_alias" "bash -s" -- "$remote_root" "$branch" "$combo_dir" "$patch_file_rel" "$assignments_b64" "$class_map_b64" <<'REMOTE_PREP'
set -euo pipefail

REMOTE_ROOT="$1"
BRANCH="$2"
COMBO_DIR="$3"
PATCH_FILE_REL="$4"
ASSIGNMENTS_B64="$5"
CLASS_MAP_B64="$6"

cd "$REMOTE_ROOT"
mkdir -p "$COMBO_DIR"
git fetch origin "$BRANCH"

if [ -d "$COMBO_DIR" ]; then
    git worktree remove --force "$COMBO_DIR" >/dev/null 2>&1 || true
    rm -rf "$COMBO_DIR"
fi

git worktree add --force "$COMBO_DIR" "origin/${BRANCH}" >/dev/null

if [ -d /tmp/fuyao_deps ]; then
    cp -r /tmp/fuyao_deps/* "$COMBO_DIR/" 2>/dev/null || true
fi

PATCH_TARGET="${COMBO_DIR}/${PATCH_FILE_REL}"
if [ ! -f "$PATCH_TARGET" ]; then
    echo "Error: patch target not found: ${PATCH_TARGET}" >&2
    exit 1
fi

python3 - "$PATCH_TARGET" "$ASSIGNMENTS_B64" "$CLASS_MAP_B64" <<'PY'
import base64
import json
import re
import sys

path = sys.argv[1]
assignments = base64.b64decode(sys.argv[2]).decode("utf-8")
class_map_text = base64.b64decode(sys.argv[3]).decode("utf-8") if len(sys.argv) > 3 else "{}"

DEFAULT_CLASS_MAP = {
    "learning_rate": "algorithm",
    "entropy_coef": "algorithm",
    "gamma": "algorithm",
    "lam": "algorithm",
    "clip_param": "algorithm",
    "num_learning_epochs": "algorithm",
    "num_mini_batches": "algorithm",
    "desired_kl": "algorithm",
    "max_grad_norm": "algorithm",
    "value_loss_coef": "algorithm",
    "use_clipped_value_loss": "algorithm",
    "schedule": "algorithm",
    "mirror_loss_coeff": "algorithm.symmetry_cfg",
    "use_mirror_loss": "algorithm.symmetry_cfg",
    "use_data_augmentation": "algorithm.symmetry_cfg",
    "use_scaled_orthogonal_init": "algorithm.symmetry_cfg",
    "orthogonal_init_scale": "algorithm.symmetry_cfg",
    "amp_task_reward_lerp": "runner",
    "max_iterations": "runner",
    "num_steps_per_env": "runner",
    "experiment_name": "runner",
    "init_noise_std": "policy",
    "frame_stack": "env",
    "num_envs": "env",
    "num_single_obs": "env",
    "c_frame_stack": "env",
    "tracking_sigma_lin_vel": "rewards",
    "soft_dof_vel_limit": "rewards",
    "soft_dof_pos_limit": "rewards",
    "tracking_sigma_torso_ang_vel_xy": "rewards",
    "tracking_avg_ang_vel": "rewards.scales",
    "torque_limits": "rewards.scales",
    "stand_still": "rewards.scales",
    "foot_distance_limit": "rewards.scales",
    "hip_roll_and_ankle_pitch_torque_limits": "rewards.scales",
    "catwalk_thigh_roll": "rewards.scales",
    "push_robots": "domain_rand",
    "max_push_vel_xy": "domain_rand",
    "randomize_base_mass": "domain_rand",
    "randomize_com_displacement": "domain_rand",
    "randomize_motor_strength": "domain_rand",
    "com_displacement_range": "domain_rand",
    "motor_strength_range": "domain_rand",
    "straight_prob": "commands.new_sample_methods",
    "backward_prob": "commands.new_sample_methods",
    "stand_prob": "commands.new_sample_methods",
    "turn_prob": "commands.new_sample_methods",
    "amp_task_reward_lerp": "runner",
}

def parse_assignments(raw):
    pairs = []
    for part in raw.split(";"):
        part = part.strip()
        if not part:
            continue
        if "=" not in part:
            raise SystemExit(f"Invalid assignment (missing '='): {part}")
        k, v = part.split("=", 1)
        k = k.strip()
        v = v.strip()
        if not k or not v:
            raise SystemExit(f"Invalid assignment (empty key/value): {part}")
        pairs.append((k, v))
    return pairs

def try_regex_replace(text, key, value):
    pattern = re.compile(rf"(^[ \t]*{re.escape(key)}[ \t]*=[ \t]*).*$", re.MULTILINE)
    new_text, n = pattern.subn(lambda m: m.group(1) + value, text, count=1)
    return new_text, n > 0

def indent_of(line):
    return len(line) - len(line.lstrip())

def find_class_block(lines, class_name, start=0, min_indent=-1):
    pat = re.compile(rf"^(\s*)class\s+{re.escape(class_name)}\b")
    for i in range(start, len(lines)):
        m = pat.match(lines[i])
        if not m:
            continue
        class_indent = len(m.group(1))
        if class_indent <= min_indent:
            continue
        colon_line = i
        if ":" not in lines[i]:
            for j in range(i + 1, len(lines)):
                if ":" in lines[j]:
                    colon_line = j
                    break
        body_indent = None
        for j in range(colon_line + 1, len(lines)):
            stripped = lines[j].strip()
            if stripped and not stripped.startswith("#"):
                body_indent = indent_of(lines[j])
                break
        if body_indent is None:
            body_indent = class_indent + 4
        last_body = colon_line
        for j in range(colon_line + 1, len(lines)):
            stripped = lines[j].strip()
            if not stripped or stripped.startswith("#"):
                continue
            line_indent = indent_of(lines[j])
            if line_indent <= class_indent:
                break
            last_body = j
        return i, body_indent, last_body
    return None

def inject_into_class(lines, class_path, key, value):
    parts = class_path.split(".")
    search_start = 0
    min_indent = -1
    for part in parts:
        result = find_class_block(lines, part, search_start, min_indent)
        if result is None:
            raise SystemExit(f"Cannot locate class {part} for path {class_path}")
        class_line, body_indent, last_body = result
        search_start = class_line + 1
        min_indent = indent_of(lines[class_line])
    insert_idx = last_body + 1
    lines.insert(insert_idx, " " * body_indent + f"{key} = {value}\n")
    return lines

class_map = dict(DEFAULT_CLASS_MAP)
if class_map_text:
    class_map.update(json.loads(class_map_text))

text = open(path, "r", encoding="utf-8").read()
pairs = parse_assignments(assignments)
if not pairs:
    raise SystemExit("No assignments found")

for key, value in pairs:
    new_text, did_replace = try_regex_replace(text, key, value)
    if did_replace:
        text = new_text
        continue

    target_class = class_map.get(key)
    if target_class is None:
        available = ", ".join(sorted(class_map.keys()))
        raise SystemExit(
            f"Key '{key}' not present in config and no class mapping available. "
            f"Known keys: {available}"
        )
    lines = text.splitlines(keepends=True)
    lines = inject_into_class(lines, target_class, key, value)
    text = "".join(lines)

with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
REMOTE_PREP
}

run_combo() {
    local combo_name="$1"
    local combo_spec="$2"
    local combo_label="$3"
    local combo_dir="$4"
    local dispatch_log="$5"
    local status_path="$6"
    local payload_path="$7"
    local artifact_dir="$8"

    local rc=0
    local reason="pending"
    local job_name=""
    mkdir -p "$artifact_dir"

    {
        echo "combo_name=${combo_name}"
        echo "combo_label=${combo_label}"
        echo "combo_spec=${combo_spec}"
        echo "combo_dir=${combo_dir}"
    } >"$dispatch_log"

    {
        echo "{\"combo_name\": \"${combo_name}\", \"combo_spec\": \"${combo_spec}\", \"combo_label\": \"${combo_label}\"}" >"$payload_path"
    } >"$payload_path" 2>/dev/null || true

    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY_RUN: skipping remote repo prep and dispatch" >>"$dispatch_log"
        echo "Job name: dry-run-placeholder" >>"$dispatch_log"
        reason="dry_run"
        write_status "$status_path" "success" "$reason" "$combo_name" "$combo_label" "$job_name" "$combo_dir"
        write_json_file "${artifact_dir}/dispatch_receipt.json" "$(cat <<EOF
{"combo_name":"${combo_name}","combo_label":"${combo_label}","combo_spec":"${combo_spec}","combo_dir":"${combo_dir}","submitted":false,"dry_run":true}
EOF
)"
        return 0
    fi

    local combo_assignments_b64 class_map_b64
    combo_assignments_b64="$(printf '%s' "$combo_spec" | base64 | tr -d '\n')"
    class_map_b64="$(printf '%s' "$HP_CLASS_MAP_B64" | tr -d '\n')"
    if ! prepare_remote_combo_repo "$SSH_ALIAS" "$REMOTE_ROOT" "$BRANCH" "$combo_dir" "$PATCH_FILE_REL" "$combo_assignments_b64" "$class_map_b64" >>"$dispatch_log" 2>&1; then
        rc=$?
        reason="remote_combo_prepare_failed"
        write_status "$status_path" "failed" "$reason" "$combo_name" "$combo_label" "$job_name" "$combo_dir"
        return "$rc"
    fi

    if [ "$RESUME" = "true" ] && [ -n "$CHECKPOINT_REMOTE_FULL" ]; then
        if ! ssh "$SSH_ALIAS" "cp '${CHECKPOINT_REMOTE_FULL}' '${combo_dir}/humanoid-gym/' && test -f '${combo_dir}/humanoid-gym/${CHECKPOINT_BASENAME}'" >>"$dispatch_log" 2>&1; then
            rc=$?
            reason="checkpoint_copy_failed"
            echo "Error: checkpoint not found at ${combo_dir}/humanoid-gym/${CHECKPOINT_BASENAME} after copy" >>"$dispatch_log"
            write_status "$status_path" "failed" "$reason" "$combo_name" "$combo_label" "$job_name" "$combo_dir"
            return "$rc"
        fi
    fi

    local -a deploy_cmd=(
        "$DEPLOY_SCRIPT"
        --skip-git-sync true
        --ssh-alias "$SSH_ALIAS"
        --remote-root "$combo_dir"
        --remote-kernel false
        --task "$TASK"
        --label "$combo_label"
        --experiment "$EXPERIMENT"
        --site "$SITE"
        --queue "$QUEUE"
        --project "$PROJECT"
        --nodes "$NODES"
        --gpus-per-node "$GPUS_PER_NODE"
        --priority "$PRIORITY"
        --docker-image "$DOCKER_IMAGE"
        --rl-device "$RL_DEVICE"
        --auto-yes true
    )
    if [ "$RESUME" = "true" ]; then
        deploy_cmd+=(--resume true --checkpoint-path "$CHECKPOINT_BASENAME")
    fi
    if [ "$DRY_RUN" = "true" ]; then
        deploy_cmd+=(--dry-run)
    fi

    {
        echo "Dispatch command: ${deploy_cmd[*]}"
    } >>"$dispatch_log"

    set +e
    "${deploy_cmd[@]}" >>"$dispatch_log" 2>&1
    rc=$?
    set -e

    if [ "$rc" -eq 0 ]; then
        job_name="$(extract_job_name_from_log "$dispatch_log")"
        if [ -n "$job_name" ]; then
            reason="submitted"
            write_status "$status_path" "success" "$reason" "$combo_name" "$combo_label" "$job_name" "$combo_dir"
            write_json_file "${artifact_dir}/dispatch_receipt.json" "{\"combo_name\":\"${combo_name}\",\"combo_label\":\"${combo_label}\",\"combo_dir\":\"${combo_dir}\",\"job_name\":\"${job_name}\",\"submitted\":true}"
            echo "job_name=${job_name}" >>"$dispatch_log"
            return 0
        fi
        reason="submitted_no_job_name"
        write_status "$status_path" "success" "$reason" "$combo_name" "$combo_label" "$job_name" "$combo_dir"
        write_json_file "${artifact_dir}/dispatch_receipt.json" "{\"combo_name\":\"${combo_name}\",\"combo_label\":\"${combo_label}\",\"combo_dir\":\"${combo_dir}\",\"submitted\":true}"
        echo "job_name=unknown" >>"$dispatch_log"
        return 0
    fi

    write_status "$status_path" "failed" "deploy_failed" "$combo_name" "$combo_label" "$job_name" "$combo_dir"
    write_json_file "${artifact_dir}/dispatch_receipt.json" "{\"combo_name\":\"${combo_name}\",\"combo_label\":\"${combo_label}\",\"combo_dir\":\"${combo_dir}\",\"submitted\":false}"
    return "$rc"
}

cleanup_remote_combo_repo() {
    local combo_dir="$1"
    ssh "$SSH_ALIAS" "bash -s" -- "$REMOTE_ROOT" "$combo_dir" <<'REMOTE_CLEAN'
set -euo pipefail

REMOTE_ROOT="$1"
COMBO_DIR="$2"
cd "$REMOTE_ROOT"
git worktree remove --force "$COMBO_DIR" >/dev/null 2>&1 || true
rm -rf "$COMBO_DIR" || true
REMOTE_CLEAN
}

main() {
    local payload_path=""
    local arg mode="payload"

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
            --print-label-map)
                mode="print-label-map"
                shift
                ;;
            --print-label-map-json)
                mode="print-label-map-json"
                shift
                ;;
            --check-label-aliases)
                mode="check-label-aliases"
                shift
                ;;
            --cancel-sweep)
                echo "Current sweep dispatcher does not implement --cancel-sweep."
                echo "Manual cancellation is supported via job names in logs: fuyao cancel <job_name>"
                exit 1
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

    if [ "$mode" = "print-label-map" ]; then
        print_label_map false
        exit 0
    fi
    if [ "$mode" = "print-label-map-json" ]; then
        print_label_map true
        exit 0
    fi
    if [ "$mode" = "check-label-aliases" ]; then
        run_label_alias_regression
        return $?
    fi

    if [ "$mode" != "payload" ] || [ -z "$payload_path" ]; then
        echo "Error: missing --payload" >&2
        exit 1
    fi

    require_cmd git
    require_cmd base64
    require_cmd ssh
    if [ ! -x "$DEPLOY_SCRIPT" ]; then
        echo "Error: deploy script not executable: $DEPLOY_SCRIPT" >&2
        exit 1
    fi

    read_payload "$payload_path"

    if [ -z "$TASK" ]; then
        echo "Error: task is required." >&2
        exit 1
    fi
    if [ -z "$BRANCH" ]; then
        echo "Error: branch is required." >&2
        exit 1
    fi
case "$DRY_RUN" in
        true)
            DRY_RUN="true"
            ;;
        false)
            DRY_RUN="false"
            ;;
        *)
            echo "Error: dry_run must be a boolean true/false." >&2
            exit 1
            ;;
    esac

    case "$CONTINUE_ON_ERROR" in
        true)
            CONTINUE_ON_ERROR="true"
            ;;
        false)
            CONTINUE_ON_ERROR="false"
            ;;
        *)
            echo "Error: continue_on_error must be a boolean true/false." >&2
            exit 1
            ;;
    esac

    case "$RESUME" in
        true)
            RESUME="true"
            if [ -z "$CHECKPOINT_PATH" ]; then
                echo "Error: checkpoint_path is required when resume=true." >&2
                exit 1
            fi
            if [ "$DRY_RUN" != "true" ] && [ ! -f "$CHECKPOINT_PATH" ]; then
                echo "Error: checkpoint file not found: $CHECKPOINT_PATH" >&2
                exit 1
            fi
            ;;
        false|"")
            RESUME="false"
            ;;
        *)
            echo "Error: resume must be a boolean true/false." >&2
            exit 1
            ;;
    esac

    if ! [[ "$MAX_PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: max_parallel must be a positive integer." >&2
        exit 1
    fi

    if [ -z "$LOCAL_ROOT" ]; then
        if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            LOCAL_ROOT="$(git rev-parse --show-toplevel)"
        else
            echo "Error: local_root is required in payload when not running from a git repo." >&2
            exit 1
        fi
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

    if [ "$LABEL_PREFIX" = "auto" ]; then
        LABEL_PREFIX="$(derive_sweep_label_prefix "$TASK")"
        echo "Auto-derived label prefix: ${LABEL_PREFIX}"
    fi

    HP_SPECS=()
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$line" ]; then
            HP_SPECS+=("$line")
        fi
    done < <(printf '%s' "$HP_SPECS_B64" | base64 -d | sed '/^[[:space:]]*$/d')
    if [ "${#HP_SPECS[@]}" -eq 0 ]; then
        echo "Error: no hyperparameter specs provided." >&2
        exit 1
    fi

    local -a normalized_specs=()
    local spec parsed
    for spec in "${HP_SPECS[@]}"; do
        parsed="$(parse_hp_spec "$spec" || true)"
        if [ -z "$parsed" ]; then
            echo "Error: invalid hyperparameter spec: '$spec'" >&2
            exit 1
        fi
        normalized_specs+=("$parsed")
    done

    if ! is_true "$CONFIRM_DISPATCH" && [ "$DRY_RUN" != "true" ]; then
        echo "Error: live dispatch blocked. Set confirm_dispatch=true in payload after explicit user confirmation." >&2
        exit 1
    fi

    if [ "$DRY_RUN" != "true" ]; then
        if [ ! -d "$LOCAL_ROOT/.git" ]; then
            echo "Error: local root is not a git repo: $LOCAL_ROOT" >&2
            exit 1
        fi
        if [ -n "$(git -C "$LOCAL_ROOT" status --porcelain)" ]; then
            echo "Error: local repo is dirty. Clean it before dispatch." >&2
            exit 1
        fi
        if ! git -C "$LOCAL_ROOT" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
            echo "Error: local branch does not exist: $BRANCH" >&2
            exit 1
        fi
        echo "Pushing baseline branch: ${BRANCH}"
        git -C "$LOCAL_ROOT" push -u origin "$BRANCH"
    fi

    local -a combos=()
    local -a BUILD_COMBOS_RESULT
    build_combos "${normalized_specs[@]}"
    combos=("${BUILD_COMBOS_RESULT[@]}")
    if [ "${#combos[@]}" -eq 0 ]; then
        echo "Error: no combinations generated." >&2
        exit 1
    fi

    local sweep_id
    sweep_id="${LABEL_PREFIX}-$(date +%Y%m%d-%H%M%S)-$((RANDOM))"
    RUN_ROOT="${RUN_ROOT_BASE}/${sweep_id}"
    PAYLOADS_DIR="${RUN_ROOT}/payloads"
    LOGS_DIR="${RUN_ROOT}/logs"
    STATUS_DIR="${RUN_ROOT}/status"
    ARTIFACTS_DIR="${RUN_ROOT}/artifacts"
    mkdir -p "$PAYLOADS_DIR" "$LOGS_DIR" "$STATUS_DIR" "$ARTIFACTS_DIR"

    local manifest_resume_block=""
    if [ "$RESUME" = "true" ]; then
        manifest_resume_block="\"resume\": true, \"checkpoint_path\": \"${CHECKPOINT_PATH}\","
    else
        manifest_resume_block="\"resume\": false,"
    fi

    write_json_file "${RUN_ROOT}/run_manifest.json" "{
  \"sweep_id\": \"${sweep_id}\",
  \"task\": \"${TASK}\",
  \"branch\": \"${BRANCH}\",
  \"patch_file_rel\": \"${PATCH_FILE_REL}\",
  \"label_prefix\": \"${LABEL_PREFIX}\",
  \"label_alias_map_version\": \"${HP_ALIAS_MAP_VERSION}\",
  \"total_combos\": ${#combos[@]},
  \"max_parallel\": ${MAX_PARALLEL},
  ${manifest_resume_block}
  \"dry_run\": ${DRY_RUN},
  \"continue_on_error\": ${CONTINUE_ON_ERROR}
}"

    if [ "$DRY_RUN" != "true" ]; then
        echo "Fetching repo dependencies on remote kernel..."
        if ssh "$SSH_ALIAS" "bash -s" -- "$REMOTE_ROOT" <<'FETCH_DEPS'
set -euo pipefail
cd "$1"
rm -rf /tmp/fuyao_deps
mkdir -p /tmp/fuyao_deps
if [ -f scripts/update_repo_deps.sh ]; then
    bash scripts/update_repo_deps.sh --prefix /tmp/fuyao_deps
else
    echo "No update_repo_deps.sh found; skipping dependency fetch."
fi
FETCH_DEPS
        then
            echo "Dependencies fetched."
        else
            echo "Warning: dependency fetch failed (exit $?). Proceeding with existing repo resources."
        fi
    fi

    CHECKPOINT_BASENAME=""
    CHECKPOINT_REMOTE_FULL=""
    if [ "$RESUME" = "true" ]; then
        CHECKPOINT_BASENAME="$(basename "$CHECKPOINT_PATH")"
        local ckpt_size
        ckpt_size="$(stat -f%z "$CHECKPOINT_PATH" 2>/dev/null || stat -c%s "$CHECKPOINT_PATH" 2>/dev/null || echo 0)"
        if [ "$ckpt_size" -lt 1024 ]; then
            echo "Error: checkpoint file too small (${ckpt_size} bytes): $CHECKPOINT_PATH" >&2
            exit 1
        fi
        echo "Checkpoint: ${CHECKPOINT_BASENAME} ($(( ckpt_size / 1024 / 1024 )) MB)"
        echo "  Note: fuyao_train.sh runs from humanoid-gym/; checkpoint will be placed there."

        local ckpt_remote_dir="/tmp/fuyao_sweep_checkpoints/${sweep_id}"
        CHECKPOINT_REMOTE_FULL="${ckpt_remote_dir}/${CHECKPOINT_BASENAME}"
        if [ "$DRY_RUN" != "true" ]; then
            echo "Uploading checkpoint to remote: ${CHECKPOINT_REMOTE_FULL}"
            ssh "$SSH_ALIAS" "mkdir -p '${ckpt_remote_dir}'"
            scp "$CHECKPOINT_PATH" "${SSH_ALIAS}:${CHECKPOINT_REMOTE_FULL}"
            ssh "$SSH_ALIAS" "test -f '${CHECKPOINT_REMOTE_FULL}'" || {
                echo "Error: checkpoint upload verification failed." >&2
                exit 1
            }
            echo "Checkpoint uploaded and verified."
        else
            echo "DRY_RUN: would upload checkpoint to ${CHECKPOINT_REMOTE_FULL}"
        fi
    fi

    local -a combo_names=()
    local -a combo_labels=()
    local -a running_pids=()
    local -a used_label_suffixes_keys=()
    local -a used_label_suffixes_counts=()
    local idx combo_name combo_label combo_suffix combo_dir dispatch_log status_path combo_payload artifact_dir
    local start_idx=0
    local match_idx

    for idx in "${!combos[@]}"; do
        combo_name="$(printf "combo_%04d" "$((idx + 1))")"
        combo_suffix="$(combo_to_label_suffix "${combos[$idx]}")"
        match_idx=-1
        for i in "${!used_label_suffixes_keys[@]}"; do
            if [ "${used_label_suffixes_keys[$i]}" = "$combo_suffix" ]; then
                match_idx=$i
                break
            fi
        done
        if [ "$match_idx" -ge 0 ]; then
            used_label_suffixes_counts[$match_idx]=$((used_label_suffixes_counts[$match_idx] + 1))
            combo_suffix="${combo_suffix}-$(printf "%02d" "${used_label_suffixes_counts[$match_idx]}")"
        else
            used_label_suffixes_keys+=("$combo_suffix")
            used_label_suffixes_counts+=(1)
        fi
        combo_label="${LABEL_PREFIX}-$(printf "%04d" "$((idx + 1))")-${combo_suffix}"
        combo_dir="${REMOTE_SWEEP_ROOT}/${sweep_id}/${combo_name}"
        dispatch_log="${LOGS_DIR}/${combo_name}.dispatch.log"
        status_path="${STATUS_DIR}/${combo_name}.json"
        combo_payload="${PAYLOADS_DIR}/${combo_name}.json"
        artifact_dir="${ARTIFACTS_DIR}/${combo_name}"

        combo_suffix="${combos[$idx]}"
        combo_names+=("$combo_name")
        combo_labels+=("$combo_label")

        cat <<EOF > "$combo_payload"
{"combo_spec":"${combo_suffix}","combo_name":"${combo_name}","combo_label":"${combo_label}"}
EOF

        while [ "${#running_pids[@]}" -ge "$MAX_PARALLEL" ]; do
            local next_running=()
            for i in "${!running_pids[@]}"; do
                if kill -0 "${running_pids[$i]}" 2>/dev/null; then
                    next_running+=("${running_pids[$i]}")
                else
                    wait "${running_pids[$i]}" || true
                fi
            done
            running_pids=(${next_running[@]+"${next_running[@]}"})
            if [ "${#running_pids[@]}" -ge "$MAX_PARALLEL" ]; then
                sleep 1
            fi
        done

        run_combo "$combo_name" "$combo_suffix" "$combo_label" "$combo_dir" "$dispatch_log" "$status_path" "$combo_payload" "$artifact_dir" >> "$dispatch_log" 2>&1 &
        local combo_pid=$!
        running_pids+=("$combo_pid")
    done

    for pid in "${running_pids[@]}"; do
        wait "$pid" || true
    done

    local success_count=0
    local failed_count=0
    local final_status
    local combo_name status_json combo_status

    for combo_name in "${combo_names[@]}"; do
        status_json="${STATUS_DIR}/${combo_name}.json"
        if [ -f "$status_json" ]; then
            combo_status="$(python3 - "$status_json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path, "r", encoding="utf-8"))
    print(data.get("status", "unknown"))
except Exception:
    print("unknown")
PY
)"
        else
            combo_status="missing_status"
        fi
        if [ "$combo_status" = "success" ]; then
            success_count=$((success_count + 1))
        else
            failed_count=$((failed_count + 1))
        fi
    done

    echo
    echo "=== Sweep Summary ==="
    echo "Run root: ${RUN_ROOT}"
    echo "Sweep ID: ${sweep_id}"
    echo "Total combos: ${#combos[@]}"
    echo "Succeeded: ${success_count}"
    echo "Failed: ${failed_count}"
    echo "Dispatch logs: ${LOGS_DIR}/*.dispatch.log"
    echo "Artifacts: ${ARTIFACTS_DIR}"
    echo
    if [ "$failed_count" -gt 0 ]; then
        echo "Failed combos:"
        for combo_name in "${combo_names[@]}"; do
            status_json="${STATUS_DIR}/${combo_name}.json"
            combo_status="$(python3 - "$status_json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    print(json.load(open(path, "r", encoding="utf-8")).get("status", "unknown"))
except Exception:
    print("unknown")
PY
)"
            if [ "$combo_status" != "success" ]; then
                echo "  - ${combo_name}: ${combo_status} (log: ${LOGS_DIR}/${combo_name}.dispatch.log)"
            fi
        done
    fi

    if [ "$failed_count" -gt 0 ] && [ "$CONTINUE_ON_ERROR" != "true" ]; then
        echo
        echo "Some combos failed and continue_on_error=false. Exiting non-zero."
        return 1
    fi
}

main "$@"

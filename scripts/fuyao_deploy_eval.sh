#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  fuyao_deploy_eval.sh --task TASK [--checkpoint PATH | --checkpoint-remote PATH] [options] [-- eval_args]

Required:
  --task TASK                    Registered task name.
  --checkpoint PATH              Local checkpoint file to upload.
  --checkpoint-remote PATH       Existing checkpoint path on remote kernel.

Options:
  --eval-type TYPE               torque_survey | standard | custom (default: torque_survey)
  --walk-checkpoint PATH         Local walk model checkpoint to upload (enables model-switch mode).
  --walk-checkpoint-remote PATH  Existing walk model path on remote kernel.
  --gpus N                       GPUs per node (default: 1).
  --custom-cmd CMD               Required for --eval-type custom.
  --branch NAME                  Remote branch to sync before deploy.
  --label LABEL                  Fuyao label. Default: eval-<task>-<timestamp>.
  --project NAME                 Fuyao project (default: rc-wbc).
  --experiment NAME              Fuyao experiment (default: huh8/r01).
  --queue NAME                   Queue name or alias (default: rc-wbc-4090).
  --site SITE                    Optional site override.
  --ssh-alias HOST               SSH alias (default: remote.kernel.fuyao).
  --remote-workdir PATH          Remote repo root (default: /root/motion_rl).
  --yes                          Pass --yes to fuyao deploy.
  --dry-run                      Print remote deploy command only.
  --help                         Show this message.

Examples:
  fuyao_deploy_eval.sh \
    --task r01_v12_amp_with_4dof_arms_and_head_full_scenes_stability_priority \
    --checkpoint ~/checkpoints/recovery_model.pt \
    --walk-checkpoint ~/checkpoints/liudun_model_15000.pt \
    --eval-type standard \
    --gpus 4 \
    --label sweep-a-eval \
    --yes
EOF
}

quote_join() {
    local out=""
    local item
    for item in "$@"; do
        out+=$(printf "%q " "$item")
    done
    printf "%s" "${out% }"
}

normalize_queue() {
    local input="$1"
    case "$input" in
        4090|rc-wbc|rc-wbc-4090)
            echo "rc-wbc-4090"
            ;;
        l20|rc-wbc-l20)
            echo "rc-wbc-l20"
            ;;
        a100|rc-llmrl-a100-580)
            echo "rc-llmrl-a100-580"
            ;;
        rc-perception|rc-perception-4090)
            echo "rc-perception-4090"
            ;;
        rc-perception-l20)
            echo "rc-perception-l20"
            ;;
        *)
            echo "$input"
            ;;
    esac
}

default_site_for_queue() {
    local queue_name="$1"
    case "$queue_name" in
        rc-llmrl-a100-580|rc-perception-l20)
            echo "fuyao_c1"
            ;;
        *)
            echo "fuyao_sh_n2"
            ;;
    esac
}

ssh_alias="remote.kernel.fuyao"
remote_workdir="/root/motion_rl"
fuyao_image="infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347"
project="rc-wbc"
experiment="huh8/r01"
queue_input="rc-wbc-4090"
site=""
label=""
branch=""
task_name=""
checkpoint_local=""
checkpoint_remote=""
walk_checkpoint_local=""
walk_checkpoint_remote=""
gpus=1
eval_type="torque_survey"
custom_cmd=""
yes_flag=false
dry_run=false
declare -a eval_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)
            task_name="$2"
            shift 2
            ;;
        --checkpoint)
            checkpoint_local="$2"
            shift 2
            ;;
        --checkpoint-remote)
            checkpoint_remote="$2"
            shift 2
            ;;
        --walk-checkpoint)
            walk_checkpoint_local="$2"
            shift 2
            ;;
        --walk-checkpoint-remote)
            walk_checkpoint_remote="$2"
            shift 2
            ;;
        --gpus)
            gpus="$2"
            shift 2
            ;;
        --eval-type)
            eval_type="$2"
            shift 2
            ;;
        --custom-cmd)
            custom_cmd="$2"
            shift 2
            ;;
        --branch)
            branch="$2"
            shift 2
            ;;
        --label)
            label="$2"
            shift 2
            ;;
        --project)
            project="$2"
            shift 2
            ;;
        --experiment)
            experiment="$2"
            shift 2
            ;;
        --queue)
            queue_input="$2"
            shift 2
            ;;
        --site)
            site="$2"
            shift 2
            ;;
        --ssh-alias)
            ssh_alias="$2"
            shift 2
            ;;
        --remote-workdir)
            remote_workdir="$2"
            shift 2
            ;;
        --yes)
            yes_flag=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            eval_args=("$@")
            break
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$task_name" ]]; then
    echo "ERROR: --task is required." >&2
    exit 1
fi

if [[ -n "$checkpoint_local" && -n "$checkpoint_remote" ]]; then
    echo "ERROR: provide only one of --checkpoint or --checkpoint-remote." >&2
    exit 1
fi

if [[ -z "$checkpoint_local" && -z "$checkpoint_remote" ]]; then
    echo "ERROR: checkpoint is required via --checkpoint or --checkpoint-remote." >&2
    exit 1
fi

if [[ "$eval_type" == "custom" && -z "$custom_cmd" ]]; then
    echo "ERROR: --custom-cmd is required for --eval-type custom." >&2
    exit 1
fi

if [[ -n "$checkpoint_local" && ! -f "$checkpoint_local" ]]; then
    echo "ERROR: local checkpoint not found: $checkpoint_local" >&2
    exit 1
fi

if [[ -n "$walk_checkpoint_local" && -n "$walk_checkpoint_remote" ]]; then
    echo "ERROR: provide only one of --walk-checkpoint or --walk-checkpoint-remote." >&2
    exit 1
fi

if [[ -n "$walk_checkpoint_local" && ! -f "$walk_checkpoint_local" ]]; then
    echo "ERROR: local walk checkpoint not found: $walk_checkpoint_local" >&2
    exit 1
fi

has_walk_ckpt=false
if [[ -n "$walk_checkpoint_local" || -n "$walk_checkpoint_remote" ]]; then
    has_walk_ckpt=true
fi

queue_name=$(normalize_queue "$queue_input")
if [[ -z "$site" ]]; then
    site=$(default_site_for_queue "$queue_name")
fi

if [[ -z "$label" ]]; then
    ts=$(date +%Y%m%d%H%M%S)
    sanitized_task=$(echo "$task_name" | tr '/ ' '__')
    label="eval-${sanitized_task}-${ts}"
fi

local_eval_script="${HOME}/.cursor/scripts/fuyao_eval_only.sh"
if [[ ! -f "$local_eval_script" ]]; then
    echo "ERROR: missing eval entrypoint script: $local_eval_script" >&2
    exit 1
fi

ssh -G "$ssh_alias" >/dev/null 2>&1 || {
    echo "ERROR: SSH alias unavailable: $ssh_alias" >&2
    exit 1
}

stamp=$(date +%Y%m%d%H%M%S)
remote_tmp_dir="/tmp/fuyao_eval_deploy_${stamp}_$$"
remote_eval_template="${remote_tmp_dir}/fuyao_eval_only.sh"
remote_eval_script="${remote_tmp_dir}/humanoid-gym/scripts/fuyao_eval_only.sh"
remote_checkpoint="${remote_tmp_dir}/humanoid-gym/resume/model.pt"
remote_walk_checkpoint="${remote_tmp_dir}/humanoid-gym/resume/walk_model.pt"

cleanup_remote() {
    ssh "$ssh_alias" "rm -rf $(printf "%q" "$remote_tmp_dir")" >/dev/null 2>&1 || true
}
trap cleanup_remote EXIT

if [[ -n "$branch" ]]; then
    echo "Syncing remote branch: $branch"
    ssh "$ssh_alias" "set -euo pipefail; cd $(printf "%q" "$remote_workdir"); git fetch origin; if git show-ref --verify --quiet refs/heads/$(printf "%q" "$branch"); then git checkout $(printf "%q" "$branch"); else git checkout -b $(printf "%q" "$branch") origin/$(printf "%q" "$branch"); fi; git reset --hard origin/$(printf "%q" "$branch")"
fi

echo "Preparing remote staging directory."
ssh "$ssh_alias" "set -euo pipefail; rm -rf $(printf "%q" "$remote_tmp_dir"); mkdir -p $(printf "%q" "$remote_tmp_dir"); rsync -a --filter=':- .gitignore' $(printf "%q" "$remote_workdir")/ $(printf "%q" "$remote_tmp_dir")/; mkdir -p $(printf "%q" "$remote_tmp_dir")/humanoid-gym/resume $(printf "%q" "$remote_tmp_dir")/humanoid-gym/scripts"

echo "Hydrating staged package with cached repository dependencies."
ssh "$ssh_alias" "set -euo pipefail; cd $(printf "%q" "$remote_workdir"); mkdir -p /root/.cache/motion_rl_deps; bash ./scripts/update_repo_deps.sh --prefix /root/.cache/motion_rl_deps; cp -r /root/.cache/motion_rl_deps/* $(printf "%q" "$remote_tmp_dir")/"

echo "Verifying required URDF exists in staged package."
ssh "$ssh_alias" "set -euo pipefail; test -f $(printf "%q" "$remote_tmp_dir")/resources/model_files/r01_v12_serial_ankle/urdf/r01_v12_rl_simplified_plus_simple_foot_change_torque_with_head.urdf || { echo 'ERROR: required URDF not found in staged package.' >&2; exit 1; }"

echo "Injecting eval entrypoint."
scp "$local_eval_script" "${ssh_alias}:${remote_eval_template}" >/dev/null
ssh "$ssh_alias" "set -euo pipefail; cp $(printf "%q" "$remote_eval_template") $(printf "%q" "$remote_eval_script"); chmod +x $(printf "%q" "$remote_eval_script")"

local_fuyao_evaluate="$(dirname "$local_eval_script")/../../../software/motion_rl/humanoid-gym/scripts/fuyao_evaluate.sh"
if [[ ! -f "$local_fuyao_evaluate" ]]; then
    local_fuyao_evaluate="${HOME}/software/motion_rl/humanoid-gym/scripts/fuyao_evaluate.sh"
fi
if [[ -f "$local_fuyao_evaluate" ]]; then
    echo "Injecting fuyao_evaluate.sh."
    scp "$local_fuyao_evaluate" "${ssh_alias}:${remote_tmp_dir}/humanoid-gym/scripts/fuyao_evaluate.sh" >/dev/null
fi

if [[ -n "$checkpoint_local" ]]; then
    echo "Uploading local checkpoint."
    scp "$checkpoint_local" "${ssh_alias}:${remote_checkpoint}" >/dev/null
else
    echo "Staging remote checkpoint."
    ssh "$ssh_alias" "set -euo pipefail; cp $(printf "%q" "$checkpoint_remote") $(printf "%q" "$remote_checkpoint")"
fi

if [[ "$has_walk_ckpt" == true ]]; then
    if [[ -n "$walk_checkpoint_local" ]]; then
        echo "Uploading local walk checkpoint."
        scp "$walk_checkpoint_local" "${ssh_alias}:${remote_walk_checkpoint}" >/dev/null
    else
        echo "Staging remote walk checkpoint."
        ssh "$ssh_alias" "set -euo pipefail; cp $(printf "%q" "$walk_checkpoint_remote") $(printf "%q" "$remote_walk_checkpoint")"
    fi
fi

declare -a remote_cmd=(
    fuyao deploy
    "--docker-image=${fuyao_image}"
    "--nodes=1"
    "--gpus-per-node=${gpus}"
    "--site=${site}"
    "--label=${label}"
    "--experiment=${experiment}"
    "--project=${project}"
    "--queue=${queue_name}"
)

if [[ "$yes_flag" == true ]]; then
    remote_cmd+=("--yes")
fi

remote_cmd+=(
    /bin/bash humanoid-gym/scripts/fuyao_eval_only.sh
    --task "$task_name"
    --checkpoint_path /code/humanoid-gym/resume/model.pt
    --eval-type "$eval_type"
)

if [[ "$has_walk_ckpt" == true ]]; then
    remote_cmd+=(--walk_checkpoint_path /code/humanoid-gym/resume/walk_model.pt)
fi

if [[ "$eval_type" == "custom" ]]; then
    remote_cmd+=(--custom-cmd "$custom_cmd")
fi

if [[ ${#eval_args[@]} -gt 0 ]]; then
    remote_cmd+=(-- "${eval_args[@]}")
fi

quoted_remote_cmd=$(quote_join "${remote_cmd[@]}")

if [[ "$dry_run" == true ]]; then
    echo "DRY_RUN_REMOTE:"
    echo "  ssh ${ssh_alias} \"cd ${remote_tmp_dir} && ${quoted_remote_cmd}\""
    exit 0
fi

echo "Submitting Fuyao eval-only job."
tmp_log=$(mktemp /tmp/fuyao_eval_deploy_log_XXXXXX)
if printf 'n\n' | ssh "$ssh_alias" "set -euo pipefail; cd $(printf "%q" "$remote_tmp_dir"); ${quoted_remote_cmd}" | tee "$tmp_log"; then
    :
else
    echo "ERROR: fuyao deploy command failed." >&2
    rm -f "$tmp_log"
    exit 1
fi

job_name=$(awk '{
    if (match($0, /bifrost-[0-9]{16,}-[A-Za-z0-9_-]+/)) {
        print substr($0, RSTART, RLENGTH)
    }
}' "$tmp_log" | tail -n 1)
rm -f "$tmp_log"

if [[ -n "$job_name" ]]; then
    echo "Submitted job_name: $job_name"
else
    echo "WARNING: job_name not found in output." >&2
fi

echo "Done."

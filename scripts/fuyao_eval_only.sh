#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: fuyao_eval_only.sh --task TASK --checkpoint_path PATH [options] [-- extra_args]

Required:
  --task TASK                 Registered task name.
  --checkpoint_path PATH      Checkpoint path inside container.

Options:
  --eval-type TYPE            torque_survey | standard | custom (default: torque_survey)
  --walk_checkpoint_path PATH Walking model checkpoint (enables model-switch mode).
  --custom-cmd CMD            Required when --eval-type custom.
  --help                      Show this message.

Notes:
  - This script is intended to run inside Fuyao container.
  - For staged checkpoints, use /code/humanoid-gym/resume/model.pt.
EOF
}

task_name=""
checkpoint_path=""
walk_checkpoint_path=""
eval_type="torque_survey"
custom_cmd=""
declare -a passthrough_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task)
            task_name="$2"
            shift 2
            ;;
        --checkpoint_path)
            checkpoint_path="$2"
            shift 2
            ;;
        --walk_checkpoint_path)
            walk_checkpoint_path="$2"
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
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            passthrough_args=("$@")
            break
            ;;
        *)
            passthrough_args+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$task_name" || -z "$checkpoint_path" ]]; then
    echo "ERROR: --task and --checkpoint_path are required." >&2
    usage
    exit 1
fi

if [[ "$eval_type" == "custom" && -z "$custom_cmd" ]]; then
    echo "ERROR: --custom-cmd is required for --eval-type custom." >&2
    exit 1
fi

export TZ=Asia/Shanghai
export WANDB_API_KEY=
export WANDB_MODE=offline

pip install accelerate noise

cd /code/humanoid-gym
pip install -e .

python -c "from humanoid.envs import *; print('Pre-flight import check passed')" || {
    echo "FATAL: Python import check failed. Aborting eval-only job." >&2
    exit 1
}

is_main_process=true
if [[ "${RANK:-0}" != "0" ]]; then
    is_main_process=false
fi

post_xrobot() {
    local status="${1:-}"
    if [[ "$is_main_process" != "true" ]]; then
        return 0
    fi
    if [[ -f "scripts/xrobot_post_request.py" ]]; then
        if [[ -n "$status" ]]; then
            python scripts/xrobot_post_request.py --status "$status" || true
        else
            python scripts/xrobot_post_request.py || true
        fi
    fi
}

if [[ "$is_main_process" == "true" ]]; then
    (
        crontab -l 2>/dev/null
        echo "*/1 * * * * rsync -ar --inplace /code/humanoid-gym/logs/ /model/"
        echo "*/1 * * * * rsync -ar --inplace /code/humanoid-gym/checkpoints/ /model/checkpoints/"
    ) | crontab - || true
    service cron start || true
fi

post_xrobot

resolved_checkpoint="$checkpoint_path"
if [[ ! -f "$resolved_checkpoint" ]]; then
    if [[ -f "/code/$checkpoint_path" ]]; then
        resolved_checkpoint="/code/$checkpoint_path"
    elif [[ -f "/code/humanoid-gym/resume/model.pt" ]]; then
        resolved_checkpoint="/code/humanoid-gym/resume/model.pt"
    fi
fi

if [[ ! -f "$resolved_checkpoint" ]]; then
    echo "ERROR: checkpoint not found: $checkpoint_path" >&2
    exit 1
fi

resolved_walk_ckpt=""
if [[ -n "$walk_checkpoint_path" ]]; then
    resolved_walk_ckpt="$walk_checkpoint_path"
    if [[ ! -f "$resolved_walk_ckpt" ]]; then
        if [[ -f "/code/$walk_checkpoint_path" ]]; then
            resolved_walk_ckpt="/code/$walk_checkpoint_path"
        elif [[ -f "/code/humanoid-gym/resume/walk_model.pt" ]]; then
            resolved_walk_ckpt="/code/humanoid-gym/resume/walk_model.pt"
        fi
    fi
    if [[ ! -f "$resolved_walk_ckpt" ]]; then
        echo "ERROR: walk checkpoint not found: $walk_checkpoint_path" >&2
        exit 1
    fi
fi

echo "Eval-only job starting."
echo "task=$task_name"
echo "eval_type=$eval_type"
echo "checkpoint=$resolved_checkpoint"
if [[ -n "$resolved_walk_ckpt" ]]; then
    echo "walk_checkpoint=$resolved_walk_ckpt"
fi

case "$eval_type" in
    torque_survey)
        python humanoid/scripts/play_torque_survey.py \
            --task "$task_name" \
            --checkpoint_path "$resolved_checkpoint" \
            --headless \
            "${passthrough_args[@]}"
        ;;
    standard)
        if [[ "$task_name" == *"stability_priority"* ]]; then
            declare -a feval_args=(
                bash scripts/fuyao_evaluate.sh
                --task "$task_name"
                --checkpoint-path "$resolved_checkpoint"
            )
            if [[ -n "$resolved_walk_ckpt" ]]; then
                feval_args+=(--walk-checkpoint "$resolved_walk_ckpt")
            fi
            "${feval_args[@]}" "${passthrough_args[@]}" || echo "[fuyao_eval_only] WARNING: fuyao_evaluate.sh exited non-zero ($?), continuing to artifact sync"
        elif [[ "$task_name" != *"mimic"* && "$task_name" != *"fr"* ]]; then
            python humanoid/scripts/play_balancing.py \
                --task "$task_name" \
                --headless \
                --record_video \
                --sim_device cpu \
                --checkpoint_path "$resolved_checkpoint" \
                "${passthrough_args[@]}"
        fi

        python humanoid/scripts/play.py \
            --task "$task_name" \
            --headless \
            --export_policy \
            --log_data \
            --fixed_command \
            --record_video \
            --output_csv \
            --checkpoint_path "$resolved_checkpoint" \
            "${passthrough_args[@]}"

        if [[ "$task_name" == *"mimic"* || "$task_name" == *"fr"* ]]; then
            python humanoid/scripts/play_success.py \
                --task "$task_name" \
                --headless \
                --fixed_command \
                --record_video \
                --checkpoint_path "$resolved_checkpoint" \
                "${passthrough_args[@]}"
        fi
        ;;
    custom)
        bash -lc "$custom_cmd"
        ;;
    *)
        echo "ERROR: unsupported --eval-type: $eval_type" >&2
        exit 1
        ;;
esac

if [[ "$is_main_process" == "true" ]]; then
    rsync -ar --inplace /code/humanoid-gym/logs/ /model/ || true
    rsync -ar --inplace /code/humanoid-gym/checkpoints/ /model/checkpoints/ || true
fi

post_xrobot "finish"

echo "Eval-only job finished."

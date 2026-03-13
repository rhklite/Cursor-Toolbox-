#!/usr/bin/env bash
set -euo pipefail

# Verify that Fuyao training jobs from a sweep are actually running.
# Polls fuyao info/log via SSH to confirm training has started.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_SSH_ALIAS="Huh8.remote_kernel.fuyao"
DEFAULT_POLL_INTERVAL=30
DEFAULT_MAX_ATTEMPTS=20

usage() {
    cat <<'EOF'
Usage:
  verify_fuyao_jobs.sh --run-root <path> [options]
  verify_fuyao_jobs.sh --job-names <name1,name2,...> [options]

Modes:
  --run-root <path>          Read job info from sweep run directory
  --job-names <csv>          Directly specify comma-separated fuyao job names

Options:
  --ssh-alias <alias>        SSH alias for remote kernel (default: Huh8.remote_kernel.fuyao)
  --poll-interval <seconds>  Seconds between polls (default: 30)
  --max-attempts <n>         Max poll attempts per job (default: 20)
  --once                     Check once without polling (no retries)
  --check-artifacts          Also check OSS for model checkpoint artifacts
  -h, --help                 Show this help
EOF
}

# Extract fuyao job names from sweep dispatch logs.
# Looks for patterns like: bifrost-YYYYMMDDHHMMSSNN-username
extract_job_names_from_run_root() {
    local run_root="$1"
    local logs_dir="${run_root}/logs"

    if [ ! -d "$logs_dir" ]; then
        echo "Error: logs directory not found: $logs_dir" >&2
        exit 1
    fi

    python3 - "$logs_dir" <<'PY'
import pathlib
import re
import sys

logs_dir = pathlib.Path(sys.argv[1])
job_pattern = re.compile(r"(bifrost-\d{16,}-\S+)")
seen = set()
results = []

for log_file in sorted(logs_dir.glob("*.dispatch.log")):
    text = log_file.read_text(encoding="utf-8", errors="replace")
    combo_name = log_file.stem.replace(".dispatch", "")
    matches = job_pattern.findall(text)
    if matches:
        job_name = matches[-1]
        if job_name not in seen:
            seen.add(job_name)
            results.append(f"{combo_name}={job_name}")

if not results:
    print("NO_JOBS_FOUND", file=sys.stderr)
    raise SystemExit(1)

print("\n".join(results))
PY
}

# Check job status via fuyao info
check_job_status() {
    local ssh_alias="$1"
    local job_name="$2"

    local info_output
    info_output="$(ssh "$ssh_alias" "echo N | fuyao info -n '$job_name' 2>&1" 2>/dev/null || true)"

    python3 -c "
import re, sys
info_text = sys.argv[1]
status = 'unknown'
m = re.search(r'status\s*:\s*(\S+)', info_text)
if m:
    raw = m.group(1).upper()
    if 'RUNNING' in raw: status = 'running'
    elif 'PENDING' in raw or 'QUEUED' in raw or 'WAITING' in raw or 'RECEIVED' in raw or 'SCHEDULED' in raw or 'SUBMITTED' in raw: status = 'pending'
    elif 'SUCCEED' in raw or 'COMPLETED' in raw: status = 'succeeded'
    elif 'FAIL' in raw: status = 'failed'
    elif 'CANCEL' in raw: status = 'cancelled'
elif 'not found' in info_text.lower() or 'does not exist' in info_text.lower():
    status = 'not_found'
print(status)
" "$info_output"
}

# Check training logs for evidence that training has actually started
check_training_started() {
    local ssh_alias="$1"
    local job_name="$2"

    local log_output
    log_output="$(ssh "$ssh_alias" "echo N | fuyao log --job-name='$job_name' --rank=0 --show-stdout 2>&1" 2>/dev/null || true)"

    if [ -z "$log_output" ]; then
        echo "no_logs"
        return
    fi

    python3 -c "
import re, sys
log_text = sys.argv[1]

training_markers = [
    'num_learning_iterations', 'Mean reward', 'mean_reward',
    'AverageReturn', 'ep_rew_mean', 'reward_mean', 'Episode reward',
    'value_loss', 'policy_loss', 'surrogate_loss',
    'Uploaded file to RTD',
]
training_patterns = [
    r'model_\d+\.pt',
    r'Learning iteration \d+',
]
setup_markers = [
    'auto register tasks', 'tasks registered',
    'Loading extension module gymtorch', 'pip install',
    'Loading AMP', 'Loading motion',
    'ppo_runner.learn', 'Starting training',
]
failed_markers = [
    'Traceback', 'RuntimeError', 'CUDA out of memory', 'OOM',
    'Segmentation fault', 'core dumped', 'ModuleNotFoundError',
    'ImportError', 'FileNotFoundError',
]

has_training = any(m in log_text for m in training_markers) or any(re.search(p, log_text) for p in training_patterns)
has_setup = any(m in log_text for m in setup_markers)
has_failure = any(m in log_text for m in failed_markers)

if has_failure and not has_training:
    print('failed_with_error')
elif has_training:
    print('training_confirmed')
elif has_setup:
    print('setup_in_progress')
else:
    print('waiting_for_logs')
" "$log_output"
}

# Check OSS artifacts for model checkpoint files.
# Extracts username from job_name, constructs the OSS URL, and curls it
# from the remote kernel SSH machine. Falls back to log-based detection.
check_artifacts() {
    local ssh_alias="$1"
    local job_name="$2"

    python3 - "$job_name" "$ssh_alias" <<'PYART'
import re, subprocess, sys

job_name = sys.argv[1]
ssh_alias = sys.argv[2]

m = re.search(r'^[^-]+-[^-]+-(.+)$', job_name)
if not m:
    print('artifacts_check_failed')
    sys.exit(0)

user = m.group(1)
oss_url = f'https://xrobot.xiaopeng.link/resource/xrobot-log/user-upload/fuyao/{user}/{job_name}/'

try:
    result = subprocess.run(
        ['ssh', ssh_alias, f'curl -sf --max-time 10 "{oss_url}"'],
        capture_output=True, text=True, timeout=30,
    )
    if result.returncode != 0:
        print('artifacts_check_failed')
        sys.exit(0)
    response = result.stdout
    if re.search(r'model_\d+\.pt', response):
        print('artifacts_found')
    else:
        print('no_artifacts')
except Exception:
    print('artifacts_check_failed')
PYART
}

main() {
    local run_root=""
    local job_names_csv=""
    local ssh_alias="$DEFAULT_SSH_ALIAS"
    local poll_interval="$DEFAULT_POLL_INTERVAL"
    local max_attempts="$DEFAULT_MAX_ATTEMPTS"
    local once=false
    local check_artifacts_flag=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --run-root) run_root="$2"; shift 2 ;;
            --job-names) job_names_csv="$2"; shift 2 ;;
            --ssh-alias) ssh_alias="$2"; shift 2 ;;
            --poll-interval) poll_interval="$2"; shift 2 ;;
            --max-attempts) max_attempts="$2"; shift 2 ;;
            --once) once=true; shift ;;
            --check-artifacts) check_artifacts_flag=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
        esac
    done

    if [ -z "$run_root" ] && [ -z "$job_names_csv" ]; then
        echo "Error: specify --run-root or --job-names" >&2
        usage
        exit 2
    fi

    echo "=== Fuyao Job Verification ==="
    echo "SSH alias: ${ssh_alias}"
    echo "Poll interval: ${poll_interval}s"
    echo "Max attempts: ${max_attempts}"
    echo

    # Resolve job names
    local -a combo_labels=()
    local -a job_names=()

    if [ -n "$run_root" ]; then
        echo "Reading job names from: ${run_root}/logs/"
        local mapping_output
        mapping_output="$(extract_job_names_from_run_root "$run_root")"
        if [ -z "$mapping_output" ]; then
            echo "Error: no job names found in dispatch logs." >&2
            echo "Jobs may not have been submitted yet, or logs are missing." >&2
            exit 1
        fi
        while IFS= read -r line; do
            local combo_part="${line%%=*}"
            local job_part="${line#*=}"
            combo_labels+=("$combo_part")
            job_names+=("$job_part")
        done <<< "$mapping_output"
    else
        IFS=',' read -r -a job_names <<< "$job_names_csv"
        for jn in "${job_names[@]}"; do
            combo_labels+=("$jn")
        done
    fi

    echo "Found ${#job_names[@]} job(s) to verify:"
    for i in "${!job_names[@]}"; do
        echo "  ${combo_labels[$i]} -> ${job_names[$i]}"
    done
    echo

    # Verification output directory
    local verify_dir=""
    if [ -n "$run_root" ]; then
        verify_dir="${run_root}/verification"
        mkdir -p "$verify_dir"
    fi

    # Poll loop
    local -a final_status=()
    local -a final_training=()
    local -a final_artifacts=()
    for i in "${!job_names[@]}"; do
        final_status+=("unknown")
        final_training+=("unknown")
        final_artifacts+=("unchecked")
    done

    local all_resolved=false
    local attempt=0

    while [ "$all_resolved" = "false" ] && [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        echo "--- Poll ${attempt}/${max_attempts} ---"
        all_resolved=true

        for i in "${!job_names[@]}"; do
            if [ "${final_training[$i]}" = "training_confirmed" ] || \
               [ "${final_training[$i]}" = "failed_with_error" ] || \
               [ "${final_status[$i]}" = "failed" ] || \
               [ "${final_status[$i]}" = "succeeded" ] || \
               [ "${final_status[$i]}" = "cancelled" ] || \
               [ "${final_status[$i]}" = "not_found" ]; then
                continue
            fi

            all_resolved=false
            local job="${job_names[$i]}"
            local label="${combo_labels[$i]}"

            local status
            status="$(check_job_status "$ssh_alias" "$job")"
            final_status[$i]="$status"

            local training="n/a"
            local artifacts="n/a"
            if [ "$status" = "running" ] || [ "$status" = "succeeded" ]; then
                training="$(check_training_started "$ssh_alias" "$job")"
                final_training[$i]="$training"

                if [ "$check_artifacts_flag" = "true" ] && [ "$training" = "training_confirmed" ]; then
                    artifacts="$(check_artifacts "$ssh_alias" "$job")"
                    final_artifacts[$i]="$artifacts"
                fi
            fi

            if [ "$check_artifacts_flag" = "true" ]; then
                printf "  %-20s %-40s status=%-12s training=%-20s artifacts=%s\n" "$label" "$job" "$status" "$training" "$artifacts"
            else
                printf "  %-20s %-40s status=%-12s training=%s\n" "$label" "$job" "$status" "$training"
            fi

            if [ "$status" = "failed" ] || [ "$status" = "not_found" ] || [ "$status" = "cancelled" ]; then
                final_training[$i]="$status"
            fi
        done

        if [ "$once" = "true" ]; then
            break
        fi

        if [ "$all_resolved" = "false" ] && [ "$attempt" -lt "$max_attempts" ]; then
            echo "  Waiting ${poll_interval}s before next poll..."
            sleep "$poll_interval"
        fi
    done

    echo
    echo "=== Verification Summary ==="
    local confirmed=0 confirmed_with_artifacts=0 setup=0 pending=0 failed=0 other=0
    for i in "${!job_names[@]}"; do
        local label="${combo_labels[$i]}"
        local job="${job_names[$i]}"
        local st="${final_status[$i]}"
        local tr="${final_training[$i]}"
        local ar="${final_artifacts[$i]}"
        local verdict="UNKNOWN"

        if [ "$tr" = "training_confirmed" ] && [ "$ar" = "artifacts_found" ]; then
            verdict="TRAINING_WITH_ARTIFACTS"
            confirmed_with_artifacts=$((confirmed_with_artifacts + 1))
            confirmed=$((confirmed + 1))
        elif [ "$tr" = "training_confirmed" ]; then
            verdict="TRAINING"
            confirmed=$((confirmed + 1))
        elif [ "$tr" = "setup_in_progress" ]; then
            verdict="SETUP"
            setup=$((setup + 1))
        elif [ "$tr" = "failed_with_error" ] || [ "$st" = "failed" ]; then
            verdict="FAILED"
            failed=$((failed + 1))
        elif [ "$st" = "pending" ]; then
            verdict="PENDING"
            pending=$((pending + 1))
        elif [ "$st" = "cancelled" ] || [ "$st" = "not_found" ]; then
            verdict="GONE"
            failed=$((failed + 1))
        else
            verdict="UNKNOWN"
            other=$((other + 1))
        fi

        printf "  %-20s %-40s %s\n" "$label" "$job" "$verdict"

        if [ -n "$verify_dir" ]; then
            cat > "${verify_dir}/${label}.json" <<VJSON
{"combo": "${label}", "job_name": "${job}", "job_status": "${st}", "training_status": "${tr}", "artifact_status": "${ar}", "verdict": "${verdict}"}
VJSON
        fi
    done

    echo
    echo "Training confirmed: ${confirmed}"
    if [ "$check_artifacts_flag" = "true" ]; then
        echo "  with artifacts:   ${confirmed_with_artifacts}"
    fi
    echo "Setup in progress:  ${setup}"
    echo "Pending/queued:     ${pending}"
    echo "Failed/gone:        ${failed}"
    echo "Other/unknown:      ${other}"

    if [ -n "$verify_dir" ]; then
        echo "Verification results: ${verify_dir}/"
    fi

    if [ "$failed" -gt 0 ]; then
        echo
        echo "WARNING: ${failed} job(s) failed or not found."
        echo "Check logs with: ssh ${ssh_alias} 'fuyao log <job_name>'"
        exit 1
    fi

    if [ "$confirmed" -eq "${#job_names[@]}" ]; then
        echo
        echo "All ${confirmed} job(s) confirmed training."
        exit 0
    fi
}

main "$@"

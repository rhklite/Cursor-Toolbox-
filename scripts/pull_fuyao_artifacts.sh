#!/usr/bin/env bash
# pull_fuyao_artifacts.sh — download job artifacts from OSS via fuyao kernel,
# selectively filter, and transfer to the destination host.
#
# Usage:
#   pull_fuyao_artifacts.sh --job-names "name1,name2"
#   pull_fuyao_artifacts.sh --job-names "name1" --dest-host huh.desktop.us --selective
#   pull_fuyao_artifacts.sh --job-names "name1" --backfill

set -euo pipefail

# ── defaults ────────────────────────────────────────────────────────────
SSH_FUYAO="${SSH_FUYAO:-remote.kernel.fuyao}"
DEST_HOST="${DEST_HOST:-huh.desktop.us}"
DEST_DIR="${DEST_DIR:-~/fuyao_artifacts}"
SELECTIVE=true
CLEANUP=true
BACKFILL=false
JOB_NAMES=""
XROBOT_API="https://xrobot.xiaopeng.link/fuyao/api/v1"

# ── usage ───────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
Usage: pull_fuyao_artifacts.sh [OPTIONS]

Required:
  --job-names "n1,n2,..."   Comma-separated fuyao job names

Options:
  --dest-host HOST          Destination SSH host (default: huh.desktop.us)
  --dest-dir  DIR           Remote destination directory (default: ~/fuyao_artifacts)
  --ssh-fuyao ALIAS         Fuyao kernel SSH alias (default: remote.kernel.fuyo)
  --selective               Only pull eval artifacts + final/best checkpoints (default)
  --no-selective            Pull all artifacts
  --cleanup / --no-cleanup  Remove temp dir on fuyao kernel (default: cleanup)
  --backfill                Push jobs to daemon inbox if not already registered
  -h, --help                Show this help
EOF
    exit 1
}

# ── parse args ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --job-names)     JOB_NAMES="$2"; shift 2 ;;
        --dest-host)     DEST_HOST="$2"; shift 2 ;;
        --dest-dir)      DEST_DIR="$2"; shift 2 ;;
        --ssh-fuyao)     SSH_FUYAO="$2"; shift 2 ;;
        --selective)     SELECTIVE=true; shift ;;
        --no-selective)  SELECTIVE=false; shift ;;
        --cleanup)       CLEANUP=true; shift ;;
        --no-cleanup)    CLEANUP=false; shift ;;
        --backfill)      BACKFILL=true; shift ;;
        -h|--help)       usage ;;
        *)               echo "Unknown option: $1" >&2; usage ;;
    esac
done

if [[ -z "$JOB_NAMES" ]]; then
    echo "Error: --job-names is required" >&2
    usage
fi

IFS=',' read -ra JOBS <<< "$JOB_NAMES"
echo "Jobs: ${#JOBS[@]}"
for j in "${JOBS[@]}"; do echo "  $j"; done
echo "Dest: ${DEST_HOST}:${DEST_DIR}"
echo "Selective: ${SELECTIVE}"
echo ""

# ── step 1: discover artifacts via xrobot API ───────────────────────────
discover_artifacts() {
    local job_name="$1"
    local job_id

    job_id=$(ssh -o ConnectTimeout=10 "$SSH_FUYAO" \
        "fuyao info --job-name '$job_name'" 2>/dev/null \
        | grep -E 'job_id\s*:' | head -1 | sed 's/.*:\s*//')

    if [[ -z "$job_id" ]]; then
        echo "Warning: cannot resolve job_id for $job_name" >&2
        return 1
    fi

    echo "  job_id=$job_id"
    local api_resp
    api_resp=$(curl -sf "${XROBOT_API}/jobs/${job_id}" 2>/dev/null || true)
    if [[ -n "$api_resp" ]]; then
        local count
        count=$(echo "$api_resp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
arts=d.get('data',{}).get('artifacts',[])
print(len(arts))
" 2>/dev/null || echo 0)
        echo "  Registered artifacts: $count"
    fi
}

# ── step 2: download from OSS to fuyao kernel ──────────────────────────
REMOTE_TMP="/tmp/fuyao_pull_$$"
NAMES_JSON=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1].split(',')))" "$JOB_NAMES")

echo "==> Downloading from OSS to ${SSH_FUYAO}:${REMOTE_TMP} ..."

# Build the Python download script for the remote kernel.
# Uses %-formatting to avoid f-string compatibility issues with older Python.
REMOTE_PY=$(cat <<PYEOF
import os, sys
try:
    from xrobot_dataset import download_artifacts
except ImportError:
    print("ERROR: xrobot_dataset not available on this kernel", file=sys.stderr)
    sys.exit(1)

local_dir = "${REMOTE_TMP}"
os.makedirs(local_dir, exist_ok=True)

job_names = ${NAMES_JSON}
print("Downloading %d job(s) to %s" % (len(job_names), local_dir))

download_artifacts(
    fuyao_job_names=job_names,
    local_dir=local_dir,
    internal=True,
    parallelism=4,
    ignore_download_error=True,
)
print("DOWNLOAD_COMPLETE")
PYEOF
)

ssh -o ConnectTimeout=10 "$SSH_FUYAO" "python3 -c $(printf '%q' "$REMOTE_PY")" 2>&1 | \
    while IFS= read -r line; do echo "  [remote] $line"; done

echo ""

# ── step 3: selective rsync from fuyao kernel to local temp ─────────────
LOCAL_TMP=$(mktemp -d /tmp/fuyao_artifacts_XXXXXX)
trap 'rm -rf "$LOCAL_TMP"' EXIT

TOTAL_FILES=0
TOTAL_SIZE=0

for JOB in "${JOBS[@]}"; do
    echo "==> Syncing $JOB ..."
    REMOTE_JOB="${REMOTE_TMP}/${JOB}/"
    LOCAL_JOB="${LOCAL_TMP}/${JOB}/"
    mkdir -p "$LOCAL_JOB"

    if [[ "$SELECTIVE" == "true" ]]; then
        rsync -az --compress \
            --include='*/' \
            --include='metadata.json' \
            --include='xbrain_summary.html' \
            --include='model_*/default_*/**' \
            --include='*_balancing/**' \
            --include='model_20000.pt' \
            --exclude='*.pt' \
            "${SSH_FUYAO}:${REMOTE_JOB}" "$LOCAL_JOB" 2>/dev/null || {
                echo "  Warning: rsync failed for $JOB" >&2
            }

        # Find and pull the highest-numbered best_k_value=*.pt
        BEST_FILE=$(ssh "$SSH_FUYAO" \
            "find '${REMOTE_JOB}' -maxdepth 1 -name '*best_k_value=*.pt' 2>/dev/null | sort -t= -k2 -rn | head -1" \
            2>/dev/null || true)

        if [[ -n "$BEST_FILE" ]]; then
            BEST_BASENAME=$(basename "$BEST_FILE")
            scp -q "${SSH_FUYAO}:${BEST_FILE}" "${LOCAL_JOB}${BEST_BASENAME}" 2>/dev/null || true
            echo "  + best checkpoint: $BEST_BASENAME"
        fi
    else
        rsync -az --compress \
            "${SSH_FUYAO}:${REMOTE_JOB}" "$LOCAL_JOB" 2>/dev/null || {
                echo "  Warning: rsync failed for $JOB" >&2
            }
    fi

    FILE_COUNT=$(find "$LOCAL_JOB" -type f | wc -l | tr -d ' ')
    DIR_SIZE=$(du -sh "$LOCAL_JOB" 2>/dev/null | cut -f1)
    echo "  $JOB: $FILE_COUNT file(s), $DIR_SIZE"
    TOTAL_FILES=$((TOTAL_FILES + FILE_COUNT))
done

echo ""

# ── step 4: transfer from local to dest-host ────────────────────────────
echo "==> Transferring to ${DEST_HOST}:${DEST_DIR} ..."

ssh -o ConnectTimeout=10 "$DEST_HOST" "mkdir -p ${DEST_DIR}" 2>/dev/null

for JOB in "${JOBS[@]}"; do
    LOCAL_JOB="${LOCAL_TMP}/${JOB}/"
    if [[ -d "$LOCAL_JOB" ]]; then
        rsync -az --compress \
            "$LOCAL_JOB" "${DEST_HOST}:${DEST_DIR}/${JOB}/" 2>/dev/null || {
                echo "  Warning: transfer failed for $JOB" >&2
            }
        echo "  $JOB -> ${DEST_HOST}:${DEST_DIR}/${JOB}/"
    fi
done

echo ""

# ── step 5: cleanup fuyao kernel ────────────────────────────────────────
if [[ "$CLEANUP" == "true" ]]; then
    echo "==> Cleaning up ${SSH_FUYAO}:${REMOTE_TMP} ..."
    ssh -o ConnectTimeout=10 "$SSH_FUYAO" "rm -rf '${REMOTE_TMP}'" 2>/dev/null || true
    echo "  Done."
fi

echo ""

# ── step 6: backfill daemon registry ────────────────────────────────────
if [[ "$BACKFILL" == "true" ]]; then
    echo "==> Backfilling daemon registry ..."
    BACKFILL_JSON="["
    FIRST=true
    for JOB in "${JOBS[@]}"; do
        if [[ "$FIRST" == "true" ]]; then
            FIRST=false
        else
            BACKFILL_JSON+=","
        fi
        BACKFILL_JSON+="{\"job_name\":\"${JOB}\",\"status\":\"completed\",\"protected\":false}"
    done
    BACKFILL_JSON+="]"

    bash ~/.cursor/scripts/fuyao_push_inbox.sh --jobs "$BACKFILL_JSON" --server "$DEST_HOST" || {
        echo "  Warning: backfill push failed" >&2
    }
fi

# ── summary ─────────────────────────────────────────────────────────────
echo "=== Summary ==="
echo "Jobs processed: ${#JOBS[@]}"
echo "Total files transferred: $TOTAL_FILES"
echo "Destination: ${DEST_HOST}:${DEST_DIR}"
echo "Selective: $SELECTIVE"
echo "Cleanup: $CLEANUP"
echo "Backfill: $BACKFILL"

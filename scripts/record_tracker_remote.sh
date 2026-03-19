#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="huh.desktop.us"
REMOTE_TRACKER_CLI="python3 ~/software/Experiment-Tracker-/tracker_cli.py"
REMOTE_STORE_ROOT="~/.exp-tracker"
REMOTE_TMP_DIR="/tmp"

usage() {
    cat <<EOF
Usage: $(basename "$0") --command <record-sweep|record-deploy> --json-file <path>

Records tracker data directly on ${REMOTE_HOST} via SSH.

Required:
  --command     Tracker subcommand (record-sweep or record-deploy)
  --json-file   Local path to the JSON payload file

Optional:
  --host        Override remote host (default: ${REMOTE_HOST})
EOF
    exit 1
}

COMMAND=""
JSON_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --command)   COMMAND="$2";   shift 2 ;;
        --json-file) JSON_FILE="$2"; shift 2 ;;
        --host)      REMOTE_HOST="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *)           echo "Unknown arg: $1" >&2; usage ;;
    esac
done

if [[ -z "$COMMAND" || -z "$JSON_FILE" ]]; then
    echo "Error: --command and --json-file are required." >&2
    usage
fi

if [[ ! -f "$JSON_FILE" ]]; then
    echo "Error: file not found: $JSON_FILE" >&2
    exit 1
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)_$$"
REMOTE_PAYLOAD="${REMOTE_TMP_DIR}/tracker_payload_${TIMESTAMP}.json"

cleanup() {
    ssh "$REMOTE_HOST" "rm -f '$REMOTE_PAYLOAD'" 2>/dev/null || true
}
trap cleanup EXIT

scp -q "$JSON_FILE" "${REMOTE_HOST}:${REMOTE_PAYLOAD}"

ssh "$REMOTE_HOST" "${REMOTE_TRACKER_CLI} --store-root ${REMOTE_STORE_ROOT} ${COMMAND} --json-file ${REMOTE_PAYLOAD}"

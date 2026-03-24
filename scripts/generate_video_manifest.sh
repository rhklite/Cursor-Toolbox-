#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [-o output_json] REPORT_ROOT" >&2
  echo "Scans REPORT_ROOT/success and REPORT_ROOT/failure for curated mp4 files." >&2
}

output_path=""
while getopts ":o:h" opt; do
  case "$opt" in
    o) output_path="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Missing argument for -$OPTARG" >&2
      usage
      exit 1
      ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for JSON output generation." >&2
  exit 1
fi

report_root="$(python3 - <<'PY' "$1"
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).expanduser().resolve())
PY
)"

if [[ ! -d "$report_root" ]]; then
  echo "Report root not found: $report_root" >&2
  exit 1
fi

if [[ -z "$output_path" ]]; then
  output_path="$report_root/video_manifest.json"
else
  output_path="$(python3 - <<'PY' "$output_path"
import pathlib
import sys
print(pathlib.Path(sys.argv[1]).expanduser().resolve())
PY
)"
fi

mkdir -p "$(dirname "$output_path")"

tmp_records="$(mktemp)"
trap 'rm -f "$tmp_records"' EXIT

collect_from_dir() {
  local source_dir="$1"
  [[ -d "$source_dir" ]] || return 0
  shopt -s nullglob
  local file
  for file in "$source_dir"/*.mp4; do
    local base
    base="$(basename "$file")"
    if [[ "$base" =~ ^([0-9]+)_([a-z0-9_]+)_(linear|angular)_mag([0-9p]+)_(success|failure)(_original)?\.mp4$ ]]; then
      local idx="${BASH_REMATCH[1]}"
      local condition="${BASH_REMATCH[2]}"
      local sweep="${BASH_REMATCH[3]}"
      local mag_token="${BASH_REMATCH[4]}"
      local outcome="${BASH_REMATCH[5]}"
      local suffix="${BASH_REMATCH[6]:-}"
      local variant="overlay"
      if [[ -n "$suffix" ]]; then
        variant="original"
      fi

      local magnitude
      magnitude="$(awk -v raw="${mag_token//p/.}" 'BEGIN{printf "%.2f", raw+0}')"
      local run_label="${condition}_${sweep}"
      local data_dir="$report_root/stability-eval/data/$condition/$sweep"
      if [[ ! -d "$data_dir" ]]; then
        data_dir=""
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$run_label" "$idx" "$file" "$outcome" "$magnitude" "$variant" "$data_dir" "$base" >>"$tmp_records"
    else
      echo "Skipping unmatched filename: $base" >&2
    fi
  done
  shopt -u nullglob
}

collect_from_dir "$report_root/success"
collect_from_dir "$report_root/failure"

if [[ ! -s "$tmp_records" ]]; then
  printf '{}\n' >"$output_path"
  echo "Wrote empty manifest: $output_path"
  exit 0
fi

python3 - <<'PY' "$tmp_records" "$output_path"
import json
import pathlib
import sys
from collections import defaultdict

records_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])

groups = defaultdict(list)
data_dirs = {}
with records_path.open("r", encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        run_label, idx, path, outcome, magnitude, variant, data_dir, base = line.split("\t")
        groups[run_label].append(
            {
                "idx": int(idx),
                "path": path,
                "outcome": outcome,
                "magnitude": magnitude,
                "variant": variant,
                "base": base,
            }
        )
        if data_dir:
            data_dirs[run_label] = data_dir
        elif run_label not in data_dirs:
            data_dirs[run_label] = None

manifest = {}
for run_label in sorted(groups.keys()):
    videos = sorted(groups[run_label], key=lambda r: (r["idx"], r["base"]))
    manifest[run_label] = {
        "data_dir": data_dirs.get(run_label),
        "videos": [
            {
                "path": v["path"],
                "outcome": v["outcome"],
                "magnitude": v["magnitude"],
                "variant": v["variant"],
            }
            for v in videos
        ],
    }

output_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

echo "Wrote manifest: $output_path"

#!/usr/bin/env bash
set -euo pipefail

STATE_DIR_DEFAULT="${HOME}/.cursor/tmp/sync_toolbox_state"
CONFLICTS_DEFAULT="${STATE_DIR_DEFAULT}/latest_conflicts.json"
RESOLUTIONS_DEFAULT="${STATE_DIR_DEFAULT}/latest_resolutions.json"
DIFF_HELPER="${HOME}/.cursor/scripts/sync_toolbox_diff_summary.py"
BACKUP_ROOT_LOCAL="${HOME}/.cursor/tmp/sync_toolbox_backups"

TARGET_ALIASES=("huh.desktop.us" "isaacgym")
CATEGORIES=("rules" "commands" "skills" "agents" "scripts")
TOOLBOX_REPO_DIR="${HOME}/.cursor"
TOOLBOX_GIT_REMOTE="origin"

log() {
  printf '[sync-toolbox] %s\n' "$*"
}

err() {
  printf '[sync-toolbox] ERROR: %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  sync_toolbox.sh discover [--json-out PATH] [--state-dir PATH]
  sync_toolbox.sh apply [--resolution-file PATH] [--destinations CSV|all] [--async] [--dry-run] [--interactive] [--state-dir PATH]
  sync_toolbox.sh verify [--json-out PATH] [--state-dir PATH]

Notes:
  - Discovery reads host aliases from ~/.ssh/config.
  - apply runs discovery first and then applies sync operations.
  - --destinations limits apply destinations (example: local,isaacgym).
  - --async applies copy operations in parallel.
  - Conflicts require a resolution source or interactive choice.
EOF
}

safe_name() {
  echo "$1" | tr -c 'A-Za-z0-9._-' '_'
}

single_quote_escape() {
  printf "%s" "$1" | sed "s/'/'\"'\"'/g"
}

sync_toolbox_repo_by_git() {
  local repo_dir="$1"
  local remote_name="$2"
  local branch=""

  if [[ ! -d "${repo_dir}/.git" ]]; then
    err "Repository directory not found: ${repo_dir}"
    return 1
  fi

  if ! git -C "${repo_dir}" remote get-url "${remote_name}" >/dev/null 2>&1; then
    err "Git remote '${remote_name}' is missing in ${repo_dir}"
    return 1
  fi

  if ! branch="$(git -C "${repo_dir}" rev-parse --abbrev-ref HEAD)"; then
    err "Unable to determine current branch in ${repo_dir}"
    return 1
  fi

  if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
    err "Refusing to sync detached HEAD in ${repo_dir}"
    return 1
  fi

  if [[ -n "$(git -C "${repo_dir}" status --short)" ]]; then
    err "Uncommitted changes detected in ${repo_dir}; aborting git sync."
    return 1
  fi

  if ! git -C "${repo_dir}" fetch --prune "${remote_name}"; then
    err "Failed to fetch from ${remote_name} for ${repo_dir}"
    return 1
  fi

  if git -C "${repo_dir}" pull --ff-only "${remote_name}" "${branch}"; then
    return 0
  fi

  log "Fast-forward pull failed for ${repo_dir}; attempting merge from ${remote_name}/${branch}"
  if ! git -C "${repo_dir}" merge --no-edit "${remote_name}/${branch}"; then
    err "Failed to merge ${remote_name}/${branch} in ${repo_dir}"
    return 1
  fi

  return 0
}

sync_toolbox_repo_local() {
  local repo_dir="$1"
  sync_toolbox_repo_by_git "${repo_dir}" "${TOOLBOX_GIT_REMOTE}"
}

sync_toolbox_repo_remote() {
  local destination="$1"

  if ! ssh -o BatchMode=yes "${destination}" 'bash -s' <<'REMOTE_SYNC'
set -euo pipefail
repo="${HOME}/.cursor"
remote_name="origin"

if [ ! -d "${repo}/.git" ]; then
  echo "[sync-toolbox] remote destination missing repository: ${repo}" >&2
  exit 1
fi

if ! git -C "${repo}" remote get-url "${remote_name}" >/dev/null 2>&1; then
  echo "[sync-toolbox] remote destination missing remote '${remote_name}' in ${repo}" >&2
  exit 2
fi

branch="$(git -C "${repo}" rev-parse --abbrev-ref HEAD)"
if [ -z "${branch}" ] || [ "${branch}" = "HEAD" ]; then
  echo "[sync-toolbox] remote destination has detached HEAD in ${repo}" >&2
  exit 3
fi

if [ -n "$(git -C "${repo}" status --short)" ]; then
  echo "[sync-toolbox] remote destination has uncommitted changes in ${repo}" >&2
  exit 4
fi

if ! git -C "${repo}" fetch --prune "${remote_name}"; then
  echo "[sync-toolbox] failed to fetch from ${remote_name} in ${repo}" >&2
  exit 5
fi

if ! git -C "${repo}" pull --ff-only "${remote_name}" "${branch}"; then
  if ! git -C "${repo}" merge --no-edit "${remote_name}/${branch}"; then
    echo "[sync-toolbox] failed to merge ${remote_name}/${branch} in ${repo}" >&2
    exit 6
  fi
fi
REMOTE_SYNC
  then
    return 1
  fi
}

sync_toolbox_destination() {
  local destination="$1"
  local dry_run="$2"

  if [[ "${dry_run}" == "true" ]]; then
    log "DRY-RUN: ${destination} toolbox git pull/merge"
    return 0
  fi

  if [[ "${destination}" == "local" ]]; then
    sync_toolbox_repo_local "${TOOLBOX_REPO_DIR}"
  elif is_self "${destination}"; then
    log "Skipping self-sync: ${destination} resolves to this host ($(hostname))"
    return 0
  else
    sync_toolbox_repo_remote "${destination}"
  fi
}

ensure_prereqs() {
  command -v python3 >/dev/null 2>&1 || {
    err "python3 is required."
    exit 1
  }
  command -v git >/dev/null 2>&1 || {
    err "git is required."
    exit 1
  }
  command -v ssh >/dev/null 2>&1 || {
    err "ssh is required."
    exit 1
  }
}

validate_alias_exists() {
  local alias_name="$1"
  if ! ssh -G "${alias_name}" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

is_self() {
  local alias_name="$1"
  local resolved_host
  resolved_host="$(ssh -G "${alias_name}" 2>/dev/null | awk '/^hostname / {print $2}')"
  local self_host
  self_host="$(hostname)"
  [[ "${resolved_host}" == "${self_host}" ]] && return 0
  return 1
}

collect_manifest_local() {
  local out_file="$1"
  python3 - "${out_file}" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

out_file = pathlib.Path(sys.argv[1]).expanduser()
home = pathlib.Path.home()
root = home / ".cursor"
categories = ["rules", "commands", "skills", "agents", "scripts"]
script_suffixes = (".sh", ".bash")

def include_entry(category: str, relpath: str) -> bool:
    if category != "scripts":
        return True
    return relpath.endswith(script_suffixes)

entries = []
for category in categories:
    base = root / category
    if not base.exists():
        continue
    for path in sorted(base.rglob("*")):
        if not path.is_file():
            continue
        relpath = path.relative_to(base).as_posix()
        if not include_entry(category, relpath):
            continue
        stat = path.stat()
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        entries.append(
            {
                "category": category,
                "relpath": relpath,
                "sha256": sha,
                "mtime": int(stat.st_mtime),
                "size": int(stat.st_size),
                "path": str(path),
            }
        )

payload = {"source": "local", "reachable": True, "entries": entries}
out_file.parent.mkdir(parents=True, exist_ok=True)
out_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
PY
}

collect_manifest_remote() {
  local alias_name="$1"
  local out_file="$2"

  if ! validate_alias_exists "${alias_name}"; then
    python3 - "${out_file}" "${alias_name}" <<'PY'
import json
import pathlib
import sys
out = pathlib.Path(sys.argv[1]).expanduser()
alias_name = sys.argv[2]
out.parent.mkdir(parents=True, exist_ok=True)
payload = {"source": alias_name, "reachable": False, "error": "SSH alias missing in ~/.ssh/config", "entries": []}
out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
PY
    return 0
  fi

  if ssh -o BatchMode=yes "${alias_name}" "python3 - <<'PY'
import hashlib
import json
import pathlib

home = pathlib.Path.home()
root = home / '.cursor'
categories = ['rules', 'commands', 'skills', 'agents', 'scripts']
script_suffixes = ('.sh', '.bash')

def include_entry(category: str, relpath: str) -> bool:
    if category != 'scripts':
        return True
    return relpath.endswith(script_suffixes)
entries = []
for category in categories:
    base = root / category
    if not base.exists():
        continue
    for path in sorted(base.rglob('*')):
        if not path.is_file():
            continue
        relpath = path.relative_to(base).as_posix()
        if not include_entry(category, relpath):
            continue
        stat = path.stat()
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        entries.append(
            {
                'category': category,
                'relpath': relpath,
                'sha256': sha,
                'mtime': int(stat.st_mtime),
                'size': int(stat.st_size),
                'path': str(path),
            }
        )
print(json.dumps({'source': '${alias_name}', 'reachable': True, 'entries': entries}, indent=2))
PY" > "${out_file}.tmp"; then
    mv "${out_file}.tmp" "${out_file}"
  else
    rm -f "${out_file}.tmp"
    python3 - "${out_file}" "${alias_name}" <<'PY'
import json
import pathlib
import sys
out = pathlib.Path(sys.argv[1]).expanduser()
alias_name = sys.argv[2]
out.parent.mkdir(parents=True, exist_ok=True)
payload = {"source": alias_name, "reachable": False, "error": "SSH connection failed", "entries": []}
out.write_text(json.dumps(payload, indent=2), encoding="utf-8")
PY
  fi
}

build_conflict_report() {
  local manifests_dir="$1"
  local out_file="$2"

  python3 - "${manifests_dir}" "${out_file}" <<'PY'
import collections
import datetime as dt
import json
import pathlib
import sys

manifests_dir = pathlib.Path(sys.argv[1]).expanduser()
out_file = pathlib.Path(sys.argv[2]).expanduser()
ordered_sources = ["local", "huh.desktop.us", "isaacgym"]

source_payloads = {}
for mf in sorted(manifests_dir.glob("manifest_*.json")):
    data = json.loads(mf.read_text(encoding="utf-8"))
    source_payloads[data["source"]] = data

all_sources = [s for s in ordered_sources if s in source_payloads]
reachable = [s for s in all_sources if source_payloads[s].get("reachable")]
unreachable = [s for s in all_sources if not source_payloads[s].get("reachable")]

by_file = collections.defaultdict(dict)
for source in all_sources:
    payload = source_payloads[source]
    if not payload.get("reachable"):
        continue
    for entry in payload.get("entries", []):
        key = f"{entry['category']}/{entry['relpath']}"
        by_file[key][source] = entry

files = []
conflicts = []
auto_sync = []
identical_count = 0
partial_count = 0

for key in sorted(by_file):
    present = by_file[key]
    present_sources = sorted(present.keys(), key=lambda s: all_sources.index(s))
    missing_sources = [s for s in reachable if s not in present]

    hash_groups = collections.defaultdict(list)
    for src in present_sources:
        hash_groups[present[src]["sha256"]].append(src)

    if len(hash_groups) == 1 and not missing_sources:
        status = "identical"
        identical_count += 1
    elif len(hash_groups) == 1 and missing_sources:
        status = "partial"
        partial_count += 1
        winner = present_sources[0]
        for dst in missing_sources:
            auto_sync.append({"id": key, "source": winner, "destination": dst})
    else:
        status = "conflict"
        conflict = {
            "id": key,
            "category": key.split("/", 1)[0],
            "relpath": key.split("/", 1)[1],
            "present_sources": present_sources,
            "missing_sources": missing_sources,
            "hash_groups": {h: v for h, v in hash_groups.items()},
        }
        conflicts.append(conflict)

    files.append(
        {
            "id": key,
            "status": status,
            "present_sources": present_sources,
            "missing_sources": missing_sources,
            "entries": present,
        }
    )

report = {
    "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    "all_sources": all_sources,
    "reachable_sources": reachable,
    "unreachable_sources": unreachable,
    "unreachable_details": {s: source_payloads[s].get("error", "unknown") for s in unreachable},
    "files": files,
    "conflicts": conflicts,
    "auto_sync": auto_sync,
    "counts": {
        "files_seen": len(files),
        "identical": identical_count,
        "partial": partial_count,
        "conflicts": len(conflicts),
        "auto_sync_ops": len(auto_sync),
    },
}

out_file.parent.mkdir(parents=True, exist_ok=True)
out_file.write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report["counts"], indent=2))
PY
}

run_discover() {
  local state_dir="$1"
  local json_out="$2"
  local manifests_dir="${state_dir}/manifests"
  mkdir -p "${manifests_dir}"

  log "Collecting local manifest"
  collect_manifest_local "${manifests_dir}/manifest_local.json"

  for alias_name in "${TARGET_ALIASES[@]}"; do
    log "Collecting remote manifest: ${alias_name}"
    collect_manifest_remote "${alias_name}" "${manifests_dir}/manifest_$(safe_name "${alias_name}").json"
  done

  log "Building conflict report"
  build_conflict_report "${manifests_dir}" "${json_out}"
  log "Discovery report written: ${json_out}"
}

load_resolution_map() {
  local resolution_file="$1"
  local out_tsv="$2"
  python3 - "${resolution_file}" "${out_tsv}" <<'PY'
import json
import pathlib
import sys

res_file = pathlib.Path(sys.argv[1]).expanduser()
out_tsv = pathlib.Path(sys.argv[2]).expanduser()
out_tsv.parent.mkdir(parents=True, exist_ok=True)

if not res_file.exists():
    out_tsv.write_text("", encoding="utf-8")
    raise SystemExit(0)

data = json.loads(res_file.read_text(encoding="utf-8"))
rows = []
for item in data.get("decisions", []):
    rows.append(f"{item['id']}\t{item['choice']}\n")
out_tsv.write_text("".join(rows), encoding="utf-8")
PY
}

materialize_file_from_source() {
  local source_name="$1"
  local category="$2"
  local relpath="$3"
  local out_path="$4"

  mkdir -p "$(dirname "${out_path}")"
  if [[ "${source_name}" == "local" ]]; then
    local local_path="${HOME}/.cursor/${category}/${relpath}"
    if [[ ! -f "${local_path}" ]]; then
      return 1
    fi
    cp "${local_path}" "${out_path}"
    return 0
  fi

  if ssh -n -o BatchMode=yes "${source_name}" "cat \"\$HOME/.cursor/${category}/${relpath}\"" > "${out_path}" 2>/dev/null; then
    return 0
  fi
  return 1
}

backup_destination_if_exists() {
  local destination="$1"
  local category="$2"
  local relpath="$3"
  local stamp="$4"

  if [[ "${destination}" == "local" ]]; then
    local dst="${HOME}/.cursor/${category}/${relpath}"
    if [[ -f "${dst}" ]]; then
      local backup="${BACKUP_ROOT_LOCAL}/${stamp}/local/${category}/${relpath}"
      mkdir -p "$(dirname "${backup}")"
      cp "${dst}" "${backup}"
    fi
    return 0
  fi

  ssh -n -o BatchMode=yes "${destination}" \
    "dst=\"\$HOME/.cursor/${category}/${relpath}\"; bak=\"\$HOME/.cursor/tmp/sync_toolbox_backups/${stamp}/${destination}/${category}/${relpath}\"; if [ -f \"\$dst\" ]; then mkdir -p \"\$(dirname \"\$bak\")\" && cp \"\$dst\" \"\$bak\"; fi; true" >/dev/null
}

copy_file_between_sources() {
  local source_name="$1"
  local destination="$2"
  local category="$3"
  local relpath="$4"
  local stamp="$5"
  local dry_run="$6"

  if [[ "${source_name}" == "${destination}" ]]; then
    return 0
  fi

  local src_desc="${source_name}:${category}/${relpath}"
  local dst_desc="${destination}:${category}/${relpath}"

  if [[ "${dry_run}" == "true" ]]; then
    log "DRY-RUN copy ${src_desc} -> ${dst_desc}"
    return 0
  fi

  backup_destination_if_exists "${destination}" "${category}" "${relpath}" "${stamp}"

  local tmp_file
  tmp_file="$(mktemp)"
  if ! materialize_file_from_source "${source_name}" "${category}" "${relpath}" "${tmp_file}"; then
    rm -f "${tmp_file}"
    err "Failed to fetch ${src_desc}"
    return 1
  fi

  if [[ "${destination}" == "local" ]]; then
    local dst="${HOME}/.cursor/${category}/${relpath}"
    mkdir -p "$(dirname "${dst}")"
    cp "${tmp_file}" "${dst}"
    rm -f "${tmp_file}"
    log "Copied ${src_desc} -> ${dst_desc}"
    return 0
  fi

  if ssh -o BatchMode=yes "${destination}" "dst=\"\$HOME/.cursor/${category}/${relpath}\"; mkdir -p \"\$(dirname \"\$dst\")\" && cat > \"\$dst\"" < "${tmp_file}"; then
    log "Copied ${src_desc} -> ${dst_desc}"
    rm -f "${tmp_file}"
    return 0
  fi

  rm -f "${tmp_file}"
  err "Failed to copy ${src_desc} -> ${dst_desc}"
  return 1
}

show_conflict_prompt() {
  local conflicts_json="$1"
  local decisions_out="$2"
  local temp_dir="$3"

  python3 - "${conflicts_json}" "${decisions_out}" <<'PY'
import json
import pathlib
import sys

conflicts_path = pathlib.Path(sys.argv[1]).expanduser()
decisions_out = pathlib.Path(sys.argv[2]).expanduser()
report = json.loads(conflicts_path.read_text(encoding="utf-8"))
decisions_out.parent.mkdir(parents=True, exist_ok=True)
seed = {"decisions": [], "note": "Decisions filled by interactive shell prompts."}
for c in report.get("conflicts", []):
    seed["decisions"].append({"id": c["id"], "choice": ""})
decisions_out.write_text(json.dumps(seed, indent=2), encoding="utf-8")
PY

  local conflict_count
  conflict_count="$(python3 - "${conflicts_json}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
print(len(data.get("conflicts", [])))
PY
)"
  if [[ "${conflict_count}" == "0" ]]; then
    return 0
  fi

  log "Interactive conflict prompts:"
  python3 - "${conflicts_json}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
for idx, c in enumerate(data.get("conflicts", []), start=1):
    print(f"\n[{idx}] {c['id']}")
    print("  Sources:", ", ".join(c.get("present_sources", [])))
PY

  local ids
  ids="$(python3 - "${conflicts_json}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
for c in data.get("conflicts", []):
    print(c["id"])
PY
)"

  while IFS= read -r conflict_id; do
    [[ -z "${conflict_id}" ]] && continue
    local category="${conflict_id%%/*}"
    local relpath="${conflict_id#*/}"

    local present_sources
    present_sources="$(python3 - "${conflicts_json}" "${conflict_id}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
cid = sys.argv[2]
for c in data.get("conflicts", []):
    if c["id"] == cid:
        for s in c.get("present_sources", []):
            print(s)
        break
PY
)"
    local recent_info
    recent_info="$(python3 - "${conflicts_json}" "${conflict_id}" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
cid = sys.argv[2]
selected = ""
selected_mtime = ""

for f in report.get("files", []):
    if f.get("id") != cid:
        continue
    entries = f.get("entries", {})
    best_mtime = -1
    for source, entry in entries.items():
        ts = int(entry.get("mtime", -1))
        if ts > best_mtime:
            best_mtime = ts
            selected = source
            selected_mtime = str(ts)
    break

if selected:
    print(f"{selected}\t{selected_mtime}")
PY
)"

    local recent_source=""
    local recent_mtime=""
    if [[ -n "${recent_info}" ]]; then
      recent_source="$(printf '%s' "${recent_info}" | cut -f1)"
      recent_mtime="$(printf '%s' "${recent_info}" | cut -f2-)"
    fi

    local base_source
    base_source="$(printf '%s\n' "${present_sources}" | awk 'NF{print; exit}')"
    if [[ -z "${base_source}" ]]; then
      continue
    fi

    local base_file="${temp_dir}/$(safe_name "${conflict_id}")_$(safe_name "${base_source}").txt"
    materialize_file_from_source "${base_source}" "${category}" "${relpath}" "${base_file}" || true

    log "Conflict: ${conflict_id}"
    log "Compare to baseline source: ${base_source}"
    while IFS= read -r src; do
      [[ -z "${src}" ]] && continue
      local current_file="${temp_dir}/$(safe_name "${conflict_id}")_$(safe_name "${src}").txt"
      materialize_file_from_source "${src}" "${category}" "${relpath}" "${current_file}" || true
      if [[ "${src}" == "${base_source}" ]]; then
        echo "${src}:"
        echo "- Baseline source."
        continue
      fi
      if [[ -f "${base_file}" && -f "${current_file}" ]]; then
        python3 "${DIFF_HELPER}" \
          --left-file "${base_file}" \
          --right-file "${current_file}" \
          --left-label "${base_source}" \
          --right-label "${src}"
      else
        echo "${src}:"
        echo "- Unable to materialize file for summary."
      fi
    done <<< "${present_sources}"

    echo "Choose source for ${conflict_id}:"
    local i=1
    while IFS= read -r src; do
      [[ -z "${src}" ]] && continue
      echo "  ${i}) ${src}"
      i=$((i + 1))
    done <<< "${present_sources}"
    if [[ -n "${recent_source}" ]]; then
      if [[ "${recent_mtime}" != "-1" ]]; then
        echo "  r) most recent edit (${recent_source}, mtime: ${recent_mtime})"
      else
        echo "  r) most recent edit (${recent_source})"
      fi
    fi
    echo "  s) skip"

    local selected=""
    while [[ -z "${selected}" ]]; do
      read -r -p "> " answer
      if [[ "${answer}" == "s" || "${answer}" == "S" ]]; then
        selected="skip"
        break
      fi
      if [[ "${answer}" == "r" || "${answer}" == "R" ]]; then
        if [[ -n "${recent_source}" ]]; then
          selected="${recent_source}"
          break
        fi
      fi
      if [[ "${answer}" =~ ^[0-9]+$ ]]; then
        local pick
        pick="$(printf '%s\n' "${present_sources}" | sed -n "${answer}p" || true)"
        if [[ -n "${pick}" ]]; then
          selected="${pick}"
          break
        fi
      fi
      echo "Invalid choice. Enter number, r, or s."
    done

    python3 - "${decisions_out}" "${conflict_id}" "${selected}" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1]).expanduser()
cid = sys.argv[2]
choice = sys.argv[3]
data = json.loads(path.read_text(encoding="utf-8"))
for item in data.get("decisions", []):
    if item.get("id") == cid:
        item["choice"] = choice
path.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY
  done <<< "${ids}"
}

build_operation_plan() {
  local report_json="$1"
  local resolution_tsv="$2"
  local out_ops_json="$3"
  local destinations_csv="${4:-all}"

  python3 - "${report_json}" "${resolution_tsv}" "${out_ops_json}" "${destinations_csv}" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
res_tsv = pathlib.Path(sys.argv[2]).expanduser()
out_path = pathlib.Path(sys.argv[3]).expanduser()
destinations_raw = sys.argv[4].strip()

decisions = {}
if res_tsv.exists():
    for line in res_tsv.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        fid, choice = line.split("\t", 1)
        decisions[fid] = choice

reachable = report.get("reachable_sources", [])
all_sources = set(report.get("all_sources", []))
files_by_id = {f["id"]: f for f in report.get("files", [])}
ops = []
skipped = []

approved_set = None
if destinations_raw and destinations_raw.lower() != "all":
    requested = [x.strip() for x in destinations_raw.split(",") if x.strip()]
    invalid = [d for d in requested if d not in all_sources]
    for d in invalid:
        skipped.append({"id": "*", "reason": f"unknown_destination:{d}"})
    approved_set = {d for d in requested if d in all_sources}

def is_allowed(destination: str) -> bool:
    if approved_set is None:
        return True
    return destination in approved_set

for auto in report.get("auto_sync", []):
    fid = auto["id"]
    info = files_by_id.get(fid)
    if not info:
        continue
    if not is_allowed(auto["destination"]):
        skipped.append({"id": fid, "reason": f"destination_not_approved:{auto['destination']}"})
        continue
    category, relpath = fid.split("/", 1)
    ops.append(
        {
            "id": fid,
            "category": category,
            "relpath": relpath,
            "source": auto["source"],
            "destination": auto["destination"],
            "reason": "fill_missing",
        }
    )

for conflict in report.get("conflicts", []):
    fid = conflict["id"]
    choice = decisions.get(fid, "").strip()
    if not choice or choice.lower() == "skip":
        skipped.append({"id": fid, "reason": "no_resolution"})
        continue
    if choice not in conflict.get("present_sources", []):
        skipped.append({"id": fid, "reason": f"invalid_source:{choice}"})
        continue
    category, relpath = fid.split("/", 1)
    for dst in reachable:
        if dst == choice:
            continue
        if not is_allowed(dst):
            continue
        ops.append(
            {
                "id": fid,
                "category": category,
                "relpath": relpath,
                "source": choice,
                "destination": dst,
                "reason": "conflict_resolution",
            }
        )

payload = {
    "operations": ops,
    "skipped_conflicts": skipped,
    "approved_destinations": sorted(approved_set) if approved_set is not None else "all",
}
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
print(json.dumps({"operations": len(ops), "skipped_conflicts": len(skipped)}, indent=2))
PY
}

apply_operations() {
  local ops_json="$1"
  local dry_run="$2"
  local async_mode="${3:-false}"

  local destination_lines
  destination_lines="$(python3 - "${ops_json}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
seen = []
for op in data.get("operations", []):
    destination = op.get("destination", "")
    if destination and destination not in seen:
        seen.append(destination)
        print(destination)
PY
)"

  if [[ -z "${destination_lines}" ]]; then
    log "No eligible operations to apply."
    return 0
  fi

  local failures=0
  if [[ "${async_mode}" == "true" && "${dry_run}" != "true" ]]; then
    local -a pids=()
    local -a destinations=()
    while IFS= read -r destination; do
      [[ -z "${destination}" ]] && continue
      log "Apply (git sync): ${destination}"
      destinations+=("${destination}")
      (
        sync_toolbox_destination "${destination}" "${dry_run}"
      ) &
      pids+=("$!")
    done <<< "${destination_lines}"
    for idx in "${!pids[@]}"; do
      pid="${pids[$idx]}"
      if ! wait "${pid}"; then
        failures=$((failures + 1))
        err "Failed to sync destination ${destinations[$idx]}"
      fi
    done
  else
    while IFS= read -r destination; do
      [[ -z "${destination}" ]] && continue
      log "Apply (git sync): ${destination}"
      if ! sync_toolbox_destination "${destination}" "${dry_run}"; then
        failures=$((failures + 1))
      fi
    done <<< "${destination_lines}"
  fi

  if [[ "${failures}" -gt 0 ]]; then
    err "Apply finished with ${failures} failed operations."
    return 1
  fi
  return 0
}

emit_apply_report() {
  local ops_json="$1"
  local verify_json="$2"
  python3 - "${ops_json}" "${verify_json}" <<'PY'
import json
import pathlib
import sys

ops_path = pathlib.Path(sys.argv[1]).expanduser()
verify_path = pathlib.Path(sys.argv[2]).expanduser()

ops = {"operations": [], "skipped_conflicts": []}
if ops_path.exists():
    ops = json.loads(ops_path.read_text(encoding="utf-8"))
verify = {}
if verify_path.exists():
    verify = json.loads(verify_path.read_text(encoding="utf-8"))

destinations = []
for op in ops.get("operations", []):
    dst = op.get("destination")
    if dst and dst not in destinations:
        destinations.append(dst)

counts = verify.get("counts", {})
unreachable_count = len(verify.get("unreachable_sources", []))
skipped_count = len(ops.get("skipped_conflicts", []))

print("successfully synced to")
if destinations:
    for dst in destinations:
        print(f"- {dst}")
else:
    print("- none")

print("verification counts:")
print(f"- identical: {counts.get('identical', 0)}")
print(f"- partial: {counts.get('partial', 0)}")
print(f"- conflicts: {counts.get('conflicts', 0)}")
print(f"- unreachable: {unreachable_count}")

if destinations:
    synced_text = ", ".join(destinations)
    print(f"Office Sync Action: Synced to {synced_text}. Skipped items: {skipped_count}; unreachable hosts: {unreachable_count}.")
else:
    print(f"Office Sync Action: No hosts were synced. Skipped items: {skipped_count}; unreachable hosts: {unreachable_count}.")
PY
}

run_verify() {
  local state_dir="$1"
  local json_out="$2"
  run_discover "${state_dir}" "${json_out}"
  local status
  status="$(python3 - "${json_out}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
conflicts = len(data.get("conflicts", []))
partial = data.get("counts", {}).get("partial", 0)
unreachable = len(data.get("unreachable_sources", []))
print(f"{conflicts}\t{partial}\t{unreachable}")
PY
)"
  local conflicts partial unreachable
  conflicts="$(echo "${status}" | awk -F'\t' '{print $1}')"
  partial="$(echo "${status}" | awk -F'\t' '{print $2}')"
  unreachable="$(echo "${status}" | awk -F'\t' '{print $3}')"
  log "Verification: conflicts=${conflicts}, partial=${partial}, unreachable=${unreachable}"
  if [[ "${conflicts}" -eq 0 && "${partial}" -eq 0 ]]; then
    if [[ "${unreachable}" -gt 0 ]]; then
      log "Converged among reachable sources; some sources unreachable."
    else
      log "All reachable sources are fully converged."
    fi
    return 0
  fi
  err "Not fully converged. Review ${json_out}"
  return 2
}

main() {
  ensure_prereqs

  local command="${1:-}"
  if [[ -z "${command}" ]]; then
    usage
    exit 1
  fi
  shift || true

  local state_dir="${STATE_DIR_DEFAULT}"
  local json_out="${CONFLICTS_DEFAULT}"
  local resolution_file=""
  local destinations="all"
  local async_mode="false"
  local dry_run="false"
  local interactive="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state-dir)
        state_dir="$2"
        shift 2
        ;;
      --json-out)
        json_out="$2"
        shift 2
        ;;
      --resolution-file)
        resolution_file="$2"
        shift 2
        ;;
      --destinations)
        destinations="$2"
        shift 2
        ;;
      --async)
        async_mode="true"
        shift
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --interactive)
        interactive="true"
        shift
        ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  mkdir -p "${state_dir}"

  case "${command}" in
    discover)
      run_discover "${state_dir}" "${json_out}"
      ;;
    verify)
      run_verify "${state_dir}" "${json_out}"
      ;;
    apply)
      run_discover "${state_dir}" "${json_out}"

      local conflict_count
      conflict_count="$(python3 - "${json_out}" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
print(len(data.get("conflicts", [])))
PY
)"

      if [[ -z "${resolution_file}" ]]; then
        resolution_file="${RESOLUTIONS_DEFAULT}"
      fi

      if [[ "${interactive}" == "true" ]]; then
        show_conflict_prompt "${json_out}" "${resolution_file}" "${state_dir}/materialized"
      elif [[ "${conflict_count}" -gt 0 && ! -f "${resolution_file}" ]]; then
        err "Conflicts found (${conflict_count}) but no resolution file."
        err "Run interactive mode, or provide --resolution-file."
        exit 2
      fi

      local resolution_tsv="${state_dir}/resolved.tsv"
      load_resolution_map "${resolution_file}" "${resolution_tsv}"

      local ops_json="${state_dir}/operations.json"
      build_operation_plan "${json_out}" "${resolution_tsv}" "${ops_json}" "${destinations}"
      apply_operations "${ops_json}" "${dry_run}" "${async_mode}"

      local verify_json="${state_dir}/post_apply_report.json"
      run_verify "${state_dir}" "${verify_json}" || true
      emit_apply_report "${ops_json}" "${verify_json}"
      log "Apply flow complete."
      ;;
    *)
      err "Unknown command: ${command}"
      usage
      exit 1
      ;;
  esac
}

main "$@"

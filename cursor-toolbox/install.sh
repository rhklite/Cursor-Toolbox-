#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

ask_with_default() {
  local prompt="$1"
  local default="$2"
  local value=""
  read -r -p "$prompt [$default]: " value
  if [[ -z "$value" ]]; then
    value="$default"
  fi
  printf '%s' "$value"
}

expand_home() {
  local path="$1"
  if [[ "$path" == ~* ]]; then
    eval "printf '%s' \"$path\""
  else
    printf '%s' "$path"
  fi
}

echo "Cursor Toolbox Installer"
echo "========================"

cursor_root_raw="$(ask_with_default "Cursor config root" "~/.cursor")"
draft_doc_output="$(ask_with_default "Draft technical document output directory" "docs/design/published")"
draft_doc_toc_script="$(ask_with_default "Draft technical document TOC script path" "docs/update-toc.sh")"
understand_doc_output_raw="$(ask_with_default "Understand-document output directory" "~/Downloads/understand-document")"
design_packet_base="$(ask_with_default "Design-packet base directory" "workspace_root")"
postmortem_report_root="$(ask_with_default "Postmortem report root" "docs/experiments/report-assets")"
postmortem_output_dir="$(ask_with_default "Postmortem output directory" "docs/postmortem")"
cluster_ssh_alias="$(ask_with_default "Cluster SSH alias" "cluster.remote")"
remote_alias="$(ask_with_default "Remote alias for pulling remote eval artifacts" "$cluster_ssh_alias")"

cursor_root="$(expand_home "$cursor_root_raw")"
understand_doc_output="$(expand_home "$understand_doc_output_raw")"

mkdir -p "$cursor_root"

installed_count=0
backup_count=0

declare -a BACKUPS
declare -a INSTALLED

while IFS= read -r -d '' src; do
  rel="${src#"$SCRIPT_DIR"/}"
  case "$rel" in
    install.sh|README.md)
      continue
      ;;
  esac

  dest="$cursor_root/$rel"
  mkdir -p "$(dirname "$dest")"

  if [[ -f "$dest" ]]; then
    backup_path="${dest}.bak.${TIMESTAMP}"
    cp "$dest" "$backup_path"
    BACKUPS+=("$backup_path")
    backup_count=$((backup_count + 1))
  fi

  cp "$src" "$dest"
  INSTALLED+=("$dest")
  installed_count=$((installed_count + 1))
done < <(find "$SCRIPT_DIR" \( -path "$SCRIPT_DIR/.git" -o -path "$SCRIPT_DIR/.git/*" \) -prune -o -type f -print0)

python3 - "$cursor_root" "$draft_doc_output" "$draft_doc_toc_script" "$understand_doc_output" "$postmortem_report_root" "$postmortem_output_dir" "$cluster_ssh_alias" "$remote_alias" <<'PY'
from pathlib import Path
import sys

(
    cursor_root,
    draft_doc_output,
    draft_doc_toc_script,
    understand_doc_output,
    postmortem_report_root,
    postmortem_output_dir,
    cluster_ssh_alias,
    remote_alias,
) = sys.argv[1:]

replacements = {
    "DRAFT_DOC_OUTPUT_DIR": draft_doc_output,
    "DRAFT_DOC_TOC_SCRIPT": draft_doc_toc_script,
    "UNDERSTAND_DOC_OUTPUT_DIR": understand_doc_output,
    "POSTMORTEM_REPORT_ROOT": postmortem_report_root,
    "POSTMORTEM_OUTPUT_DIR": postmortem_output_dir,
    "CLUSTER_SSH_ALIAS": cluster_ssh_alias,
    "REMOTE_ALIAS": remote_alias,
}

targets = [
    "skills/draft-technical-document/SKILL.md",
    "skills/understand-document/SKILL.md",
    "skills/rl-postmortem/SKILL.md",
    "skills/deploy-fuyao/SKILL.md",
    "skills/sweep-fuyao/SKILL.md",
    "commands/deploy-fuyao.md",
    "commands/sweep-fuyao.md",
    "commands/postmortem-gemini.md",
    "commands/postmortem-synthesis.md",
    "scripts/deploy_fuyao.sh",
    "scripts/deploy_fuyao_sweep_dispatcher.sh",
    "scripts/verify_fuyao_jobs.sh",
    "docs/cursor-deploy-command-flow.md",
]

root = Path(cursor_root)
for rel in targets:
    p = root / rel
    if not p.exists():
        continue
    text = p.read_text(encoding="utf-8")
    for old, new in replacements.items():
        text = text.replace(old, new)
    p.write_text(text, encoding="utf-8")
PY

echo
echo "Install complete."
echo "Installed files: $installed_count"
echo "Backup files: $backup_count"
echo "Cursor root: $cursor_root"
echo "Design-packet base (informational): $design_packet_base"

if [[ $backup_count -gt 0 ]]; then
  echo
  echo "Backups created:"
  for b in "${BACKUPS[@]}"; do
    echo "- $b"
  done
fi

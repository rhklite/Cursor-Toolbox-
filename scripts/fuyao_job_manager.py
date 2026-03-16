#!/usr/bin/env python3
"""Fuyao Job Manager — cancel, status, pull artifacts, FFF queries, and registry management."""

__version__ = "1.1.0"

import argparse
import fcntl
import json
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
import urllib.error
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

REGISTRY_PATH = Path.home() / ".cursor" / "tmp" / "fuyao_job_registry.json"
ARTIFACTS_BASE = Path.home() / ".cursor" / "tmp" / "fuyao_artifacts"
DEFAULT_SSH_ALIAS = "remote.kernel.fuyo"
OSS_BASE_URL = "https://xrobot.xiaopeng.link/resource/xrobot-log/user-upload/fuyao"
FFF_API_BASE = "https://xrobot.xiaopeng.link/fuyao/api/v1"
REGISTRY_VERSION = 1
SSH_MAX_RETRIES = 2
DOWNLOAD_TIMEOUT = 600

USER_RE = re.compile(r"^[^-]+-[^-]+-(.+)$")

TYPE_PATTERNS = {
    "checkpoints": [r"model_.*\.pt$"],
    "logs": [r"\.log$", r"\.txt$"],
    "videos": [r"\.mp4$", r"\.avi$", r"\.webm$"],
    "onnx": [r"\.onnx$"],
    "metrics": [r"metrics?\.json$", r"\.csv$"],
    "tensorboard": [r"events\.out\.tfevents"],
    "pdf": [r"\.pdf$"],
}

CANCEL_SIGNALS = {
    "1": "Model issue, config issue",
    "2": "Training process looks abnormal",
    "3": "Loss value is on the wrong track",
    "4": "Loss value is hard to converge",
    "5": "Dataset issue",
    "6": "Early stop",
    "7": "Others",
}


# ---------------------------------------------------------------------------
# Registry helpers
# ---------------------------------------------------------------------------

def _load_registry() -> Dict[str, Any]:
    if not REGISTRY_PATH.exists():
        return {"version": REGISTRY_VERSION, "jobs": []}
    try:
        with open(REGISTRY_PATH, "r", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            data = json.load(f)
            fcntl.flock(f, fcntl.LOCK_UN)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"Warning: corrupt registry ({exc}), returning empty.", file=sys.stderr)
        return {"version": REGISTRY_VERSION, "jobs": []}
    if data.get("version", 0) != REGISTRY_VERSION:
        print(f"Warning: registry version mismatch (expected {REGISTRY_VERSION}, got {data.get('version')})", file=sys.stderr)
    return data


def _save_registry(data: Dict[str, Any]) -> None:
    REGISTRY_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        dir=str(REGISTRY_PATH.parent), suffix=".tmp", prefix=".reg_"
    )
    try:
        with open(fd, "w", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            json.dump(data, f, indent=2, sort_keys=False)
            f.flush()
            fcntl.flock(f, fcntl.LOCK_UN)
        Path(tmp_path).replace(REGISTRY_PATH)
    except Exception:
        try:
            Path(tmp_path).unlink(missing_ok=True)
        except Exception:
            pass
        raise


def _find_jobs(
    registry: Dict[str, Any],
    sweep_id: Optional[str] = None,
    job_name: Optional[str] = None,
    label_pattern: Optional[str] = None,
    status_filter: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Filter jobs from registry by criteria."""
    results = registry.get("jobs", [])
    if sweep_id:
        results = [j for j in results if j.get("sweep_id") == sweep_id]
    if job_name:
        results = [j for j in results if j.get("job_name") == job_name]
    if label_pattern:
        try:
            pat = re.compile(label_pattern)
        except re.error as exc:
            print(f"Error: invalid regex '{label_pattern}': {exc}", file=sys.stderr)
            raise
        results = [j for j in results if pat.search(j.get("combo_label", "") or j.get("label", ""))]
    if status_filter:
        results = [j for j in results if j.get("status") == status_filter]
    return results


def _update_job_status(registry: Dict[str, Any], job_name: str, status: str) -> bool:
    for job in registry.get("jobs", []):
        if job.get("job_name") == job_name:
            job["status"] = status
            return True
    return False


def _extract_user(job_name: str) -> str:
    m = USER_RE.match(job_name)
    return m.group(1) if m else ""


def _oss_url(job_name: str) -> str:
    user = _extract_user(job_name)
    if not user:
        print(f"Warning: cannot extract user from job name '{job_name}'", file=sys.stderr)
    return f"{OSS_BASE_URL}/{user}/{job_name}/"


# ---------------------------------------------------------------------------
# SSH helper
# ---------------------------------------------------------------------------

def _ssh_cmd(ssh_alias: str, remote_cmd: str, timeout: int = 30) -> Tuple[int, str]:
    """Run a command on the remote via SSH with retry. Returns (exit_code, output)."""
    cmd = ["ssh", ssh_alias, remote_cmd]
    for attempt in range(SSH_MAX_RETRIES):
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            if attempt < SSH_MAX_RETRIES - 1:
                continue
            return 1, "SSH command timed out after retries"
    return 1, "SSH command failed"


def _ssh_fuyao_cmd(ssh_alias: str, fuyao_subcmd: str, job_name: str,
                   extra_args: str = "", timeout: int = 30) -> Tuple[int, str]:
    """Build a shell-safe fuyao command and execute via SSH."""
    quoted_name = shlex.quote(job_name)
    remote = f"{fuyao_subcmd} --job-name {quoted_name}"
    if extra_args:
        remote = f"{remote} {extra_args}"
    return _ssh_cmd(ssh_alias, remote, timeout=timeout)


# ---------------------------------------------------------------------------
# History parser (shared)
# ---------------------------------------------------------------------------

def _parse_running_jobs(ssh_alias: str, limit: int = 50) -> List[Dict[str, str]]:
    """Fetch fuyao history and return list of running jobs with job_name and status."""
    rc, output = _ssh_cmd(ssh_alias, f"fuyao history --limit {limit}", timeout=30)
    running = []
    current: Dict[str, str] = {}
    for line in output.splitlines():
        if "job_name" in line and ":" in line:
            current["job_name"] = line.split(":", 1)[1].strip()
        elif "status" in line and ":" in line:
            st = line.split(":", 1)[1].strip()
            current["fuyao_status"] = st
            if st == "JOB_RUNNING" and current.get("job_name"):
                running.append(dict(current))
            current = {}
    return running


# ---------------------------------------------------------------------------
# OSS directory listing parser
# ---------------------------------------------------------------------------

class _DirListingParser(HTMLParser):
    """Parse an HTML directory listing for href links."""
    def __init__(self):
        super().__init__()
        self.files: List[str] = []

    def handle_starttag(self, tag: str, attrs: list) -> None:
        if tag == "a":
            for name, value in attrs:
                if name == "href" and value and not value.startswith(".."):
                    self.files.append(value)


def _list_oss_files(job_name: str) -> List[str]:
    """List files in a job's OSS directory."""
    url = _oss_url(job_name)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "fuyao-job-manager/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"Warning: cannot list OSS for {job_name}: {exc}", file=sys.stderr)
        return []
    parser = _DirListingParser()
    parser.feed(html)
    return parser.files


def _filter_files(files: List[str], file_type: str, pattern: Optional[str] = None) -> List[str]:
    """Filter files by type and optional regex pattern."""
    if file_type == "all":
        all_patterns: List[str] = []
        for pats in TYPE_PATTERNS.values():
            all_patterns.extend(pats)
        result = [f for f in files if any(re.search(p, f) for p in all_patterns)]
    elif file_type in TYPE_PATTERNS:
        pats = TYPE_PATTERNS[file_type]
        result = [f for f in files if any(re.search(p, f) for p in pats)]
    else:
        result = files

    if pattern:
        pat = re.compile(pattern)  # let re.error propagate to caller
        result = [f for f in result if pat.search(f)]
    return result


def _download_file(url: str, dest: Path) -> bool:
    """Download a single file from URL to dest."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "fuyao-job-manager/1.0"})
        with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as resp:
            with open(dest, "wb") as f:
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)
        return True
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"  Failed to download {url}: {exc}", file=sys.stderr)
        return False


# ---------------------------------------------------------------------------
# Subcommand: status
# ---------------------------------------------------------------------------

def cmd_status(args) -> None:
    registry = _load_registry()
    ssh_alias = args.ssh_alias

    if args.all_running:
        jobs_to_check = _parse_running_jobs(ssh_alias)
    elif args.sweep_id:
        jobs_to_check = [{"job_name": j["job_name"]} for j in _find_jobs(registry, sweep_id=args.sweep_id)]
    elif args.job_name:
        jobs_to_check = [{"job_name": args.job_name}]
    else:
        jobs_to_check = [{"job_name": j["job_name"]} for j in registry.get("jobs", [])]

    if not jobs_to_check:
        print("No jobs found.")
        return

    rows = []
    for entry in jobs_to_check:
        jn = entry["job_name"]
        fuyao_status = entry.get("fuyao_status")
        if not fuyao_status:
            rc, out = _ssh_fuyao_cmd(ssh_alias, "fuyao info", jn, timeout=15)
            fuyao_status = "unknown"
            for line in out.splitlines():
                if "status" in line and ":" in line:
                    fuyao_status = line.split(":", 1)[1].strip()
                    break

        reg_jobs = _find_jobs(registry, job_name=jn)
        reg_status = reg_jobs[0].get("status", "-") if reg_jobs else "-"
        label = (reg_jobs[0].get("combo_label", "") or reg_jobs[0].get("label", "")) if reg_jobs else "-"
        protected = reg_jobs[0].get("protected", False) if reg_jobs else False
        rows.append((jn, label, fuyao_status, reg_status, protected))

    if getattr(args, "json", False):
        print(json.dumps([{"job_name": r[0], "label": r[1], "fuyao_status": r[2],
                           "registry_status": r[3], "protected": r[4]} for r in rows], indent=2))
        return

    print(f"{'JOB NAME':<45} {'LABEL':<45} {'FUYAO STATUS':<18} {'REGISTRY':<12} {'PROTECTED'}")
    print("-" * 135)
    counts = {}
    for jn, label, fuyao_status, reg_status, protected in rows:
        print(f"{jn:<45} {label:<45} {fuyao_status:<18} {reg_status:<12} {'yes' if protected else 'no'}")
        counts[fuyao_status] = counts.get(fuyao_status, 0) + 1
    print(f"\nTotal: {len(rows)} job(s). " + ", ".join(f"{k}: {v}" for k, v in sorted(counts.items())))


# ---------------------------------------------------------------------------
# Subcommand: cancel
# ---------------------------------------------------------------------------

def cmd_cancel(args) -> None:
    registry = _load_registry()
    ssh_alias = args.ssh_alias

    if args.stale:
        protected_names = {j["job_name"] for j in registry.get("jobs", []) if j.get("protected")}
        all_running = _parse_running_jobs(ssh_alias)
        targets = [j["job_name"] for j in all_running if j["job_name"] not in protected_names]
        if protected_names:
            print(f"Protected jobs (will NOT be cancelled): {len(protected_names)}")
            for pn in sorted(protected_names):
                print(f"  [protected] {pn}")
            print()
    elif args.label_pattern:
        try:
            matched = _find_jobs(registry, label_pattern=args.label_pattern)
        except re.error:
            sys.exit(1)
        targets = [j["job_name"] for j in matched]
    elif args.sweep_id:
        matched = _find_jobs(registry, sweep_id=args.sweep_id)
        targets = [j["job_name"] for j in matched]
    elif args.job_name:
        targets = [args.job_name]
    else:
        print("Error: specify --sweep-id, --job-name, --label-pattern, or --stale", file=sys.stderr)
        sys.exit(1)

    if not targets:
        print("No jobs matched the cancel criteria.")
        return

    blocked = []
    if not args.force:
        for jn in targets:
            reg = _find_jobs(registry, job_name=jn)
            if reg and reg[0].get("protected"):
                blocked.append(jn)

    if blocked:
        print("BLOCKED: the following jobs are protected:")
        for jn in blocked:
            reg = _find_jobs(registry, job_name=jn)
            label = reg[0].get("combo_label", "") if reg else ""
            print(f"  [protected] {jn}  {label}")
        print("\nUse --force to override. Aborting.")
        sys.exit(1)

    print(f"Jobs to cancel: {len(targets)}")
    for jn in targets:
        reg = _find_jobs(registry, job_name=jn)
        label = (reg[0].get("combo_label", "") or reg[0].get("label", "")) if reg else "-"
        print(f"  {jn}  {label}")

    if args.dry_run:
        print("\n[dry-run] No jobs were cancelled.")
        return

    if not getattr(args, "yes", False):
        try:
            answer = input("\nProceed with cancellation? [y/N] ").strip().lower()
        except EOFError:
            answer = "n"
        if answer not in ("y", "yes"):
            print("Cancelled by user.")
            return

    print(f"\nCancelling {len(targets)} job(s)...")
    for jn in targets:
        quoted = shlex.quote(jn)
        rc, out = _ssh_cmd(
            ssh_alias,
            f"TERM=dumb fuyao cancel --job-name {quoted} --signal {shlex.quote(args.signal)}",
            timeout=30,
        )
        response = "unknown"
        for line in out.splitlines():
            if "Response" in line:
                m = re.search(r"Response \[(\d+)\]", line)
                if m:
                    response = m.group(1)
                break
        print(f"  {jn} -> {response}")
        _update_job_status(registry, jn, "cancelled")

    _save_registry(registry)
    print(f"\nDone. {len(targets)} job(s) cancel requests sent.")


# ---------------------------------------------------------------------------
# Subcommand: pull
# ---------------------------------------------------------------------------

def cmd_pull(args) -> None:
    registry = _load_registry()

    if args.sweep_id:
        jobs = _find_jobs(registry, sweep_id=args.sweep_id)
        job_names = [j["job_name"] for j in jobs]
    elif args.job_name:
        job_names = [args.job_name]
    else:
        print("Error: specify --job-name or --sweep-id", file=sys.stderr)
        sys.exit(1)

    if not job_names:
        print("No jobs found.")
        return

    file_type = args.type or "all"
    total_downloaded = 0

    for jn in job_names:
        print(f"\n--- {jn} ---")
        files = _list_oss_files(jn)
        if not files:
            print("  No files found on OSS.")
            continue

        try:
            matched = _filter_files(files, file_type, args.pattern)
        except re.error as exc:
            print(f"  Error: invalid pattern: {exc}", file=sys.stderr)
            continue

        if not matched:
            print(f"  No files matching type={file_type}" + (f" pattern={args.pattern}" if args.pattern else ""))
            continue

        print(f"  Found {len(matched)} file(s):")
        for fname in matched:
            print(f"    {fname}")

        out_dir = Path(args.output_dir) if args.output_dir else ARTIFACTS_BASE / jn
        base_url = _oss_url(jn)

        for fname in matched:
            url = base_url + fname
            dest = out_dir / fname
            print(f"  Downloading {fname}...", end=" ", flush=True)
            if _download_file(url, dest):
                print("ok")
                total_downloaded += 1
            else:
                print("FAILED")

    print(f"\nTotal: {total_downloaded} file(s) downloaded.")


# ---------------------------------------------------------------------------
# Subcommand: pull-logs
# ---------------------------------------------------------------------------

def cmd_pull_logs(args) -> None:
    registry = _load_registry()
    ssh_alias = args.ssh_alias

    if args.sweep_id:
        jobs = _find_jobs(registry, sweep_id=args.sweep_id)
        job_names = [j["job_name"] for j in jobs]
    elif args.job_name:
        job_names = [args.job_name]
    else:
        print("Error: specify --job-name or --sweep-id", file=sys.stderr)
        sys.exit(1)

    for jn in job_names:
        print(f"\n--- {jn} ---")
        rc, output = _ssh_fuyao_cmd(
            ssh_alias, "fuyao log", jn,
            extra_args="--rank 0 --show-stdout", timeout=60,
        )

        lines = output.splitlines()
        if args.tail and len(lines) > args.tail:
            lines = lines[-args.tail:]

        text = "\n".join(lines)

        if args.save:
            save_dir = Path(args.save)
            save_dir.mkdir(parents=True, exist_ok=True)
            dest = save_dir / f"{jn}.log"
            dest.write_text(text, encoding="utf-8")
            print(f"  Saved to {dest}")
        else:
            print(text)


# ---------------------------------------------------------------------------
# Subcommand: tensorboard (stub)
# ---------------------------------------------------------------------------

def cmd_tensorboard(args) -> None:
    registry = _load_registry()

    if args.sweep_id:
        jobs = _find_jobs(registry, sweep_id=args.sweep_id)
        job_names = [j["job_name"] for j in jobs]
    elif args.job_name:
        job_names = [args.job_name]
    else:
        print("Error: specify --job-name or --sweep-id", file=sys.stderr)
        sys.exit(1)

    print("TensorBoard download not yet implemented.\n")
    print("TensorBoard event files are typically at:")
    for jn in job_names:
        url = _oss_url(jn)
        print(f"  {url}")
    print("\nTo implement: download events.out.tfevents.* files from these paths,")
    print("then run: tensorboard --logdir <output_dir>")


# ---------------------------------------------------------------------------
# Subcommand: fff
# ---------------------------------------------------------------------------

def cmd_fff(args) -> None:
    if args.list:
        _fff_list(args)
    elif args.compare:
        _fff_compare(args)
    elif args.download:
        _fff_download(args)
    else:
        print("Error: specify --list, --compare, or --download", file=sys.stderr)
        sys.exit(1)


def _fff_api_request(endpoint: str, method: str = "GET", data: Optional[dict] = None) -> dict:
    url = f"{FFF_API_BASE}/{endpoint}"
    headers = {"User-Agent": "fuyao-job-manager/1.0"}
    body = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"FFF API error: {exc}", file=sys.stderr)
        return {}


def _fff_list(args) -> None:
    params = {}
    if args.job_name:
        params["job_name"] = args.job_name
    if args.label:
        params["label"] = args.label
    if args.user:
        params["user"] = args.user

    query = urllib.parse.urlencode(params) if params else ""
    endpoint = f"jobs?{query}" if query else "jobs"
    result = _fff_api_request(endpoint)

    if not result:
        print("No results from FFF API.")
        return

    jobs_data = result.get("data", result)
    if isinstance(jobs_data, list):
        print(f"Found {len(jobs_data)} job(s):")
        for job in jobs_data:
            jn = job.get("job_name", "")
            label = job.get("label", "")
            status = job.get("status", "")
            print(f"  {jn:<50} {label:<40} {status}")
    else:
        print(json.dumps(jobs_data, indent=2))


def _fff_compare(args) -> None:
    registry = _load_registry()
    if args.sweep_id:
        jobs = _find_jobs(registry, sweep_id=args.sweep_id)
    elif args.job_name:
        jobs = [{"job_name": args.job_name}]
    else:
        print("Error: specify --job-name or --sweep-id for comparison", file=sys.stderr)
        return

    metrics: Dict[str, dict] = {}
    for j in jobs:
        jn = j.get("job_name", "")
        if not jn:
            continue
        url = _oss_url(jn) + "metrics.json"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "fuyao-job-manager/1.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                metrics[jn] = data
        except (urllib.error.URLError, urllib.error.HTTPError):
            metrics[jn] = {"error": "not found"}

    if not metrics:
        print("No metrics data found.")
        return

    all_keys: set = set()
    for data in metrics.values():
        if isinstance(data, dict):
            all_keys.update(data.keys())
    all_keys.discard("error")

    print(f"\n{'METRIC':<30}", end="")
    for jn in metrics:
        label_short = jn.split("-")[-1] if "-" in jn else jn
        print(f" {label_short:<20}", end="")
    print()
    print("-" * (30 + 20 * len(metrics)))

    for key in sorted(all_keys):
        print(f"{key:<30}", end="")
        for jn in metrics:
            val = metrics[jn].get(key, "-")
            if isinstance(val, float):
                print(f" {val:<20.4f}", end="")
            else:
                print(f" {str(val):<20}", end="")
        print()


def _fff_download(args) -> None:
    if not args.job_name:
        print("Error: --job-name required for --download", file=sys.stderr)
        sys.exit(1)

    files = _list_oss_files(args.job_name)
    if not files:
        print("No files found.")
        return

    if args.pattern:
        try:
            pat = re.compile(args.pattern)
        except re.error as exc:
            print(f"Error: invalid pattern: {exc}", file=sys.stderr)
            sys.exit(1)
        files = [f for f in files if pat.search(f)]

    if not files:
        print("No files matching pattern.")
        return

    out_dir = Path(args.output_dir) if args.output_dir else ARTIFACTS_BASE / args.job_name
    base_url = _oss_url(args.job_name)

    for fname in files:
        url = base_url + fname
        dest = out_dir / fname
        print(f"  Downloading {fname}...", end=" ", flush=True)
        if _download_file(url, dest):
            print("ok")
        else:
            print("FAILED")


# ---------------------------------------------------------------------------
# Subcommand: registry
# ---------------------------------------------------------------------------

def cmd_registry(args) -> None:
    registry = _load_registry()

    if args.list:
        _registry_list(registry, as_json=getattr(args, "json", False))

    elif args.protect:
        _registry_set_protected(registry, args.protect, True)

    elif args.unprotect:
        _registry_set_protected(registry, args.unprotect, False)

    elif args.add:
        _registry_add(registry, args)

    elif getattr(args, "remove", None):
        _registry_remove(registry, args.remove)

    elif getattr(args, "clear", False):
        _registry_clear()

    elif getattr(args, "add_batch", None):
        _registry_add_batch(args.add_batch)

    elif args.sync:
        _registry_sync(registry, args.ssh_alias)

    else:
        print("Error: specify --list, --protect, --unprotect, --add, --remove, --clear, --add-batch, or --sync",
              file=sys.stderr)
        sys.exit(1)


def _registry_list(registry: Dict[str, Any], as_json: bool = False) -> None:
    jobs = registry.get("jobs", [])
    if not jobs:
        print("Registry is empty.")
        return
    if as_json:
        print(json.dumps(jobs, indent=2))
        return
    print(f"{'JOB NAME':<45} {'SWEEP ID':<40} {'LABEL':<45} {'STATUS':<12} {'PROTECTED':<10} {'GPUS'}")
    print("-" * 160)
    for j in jobs:
        jn = j.get("job_name", "")
        sid = j.get("sweep_id", "-")
        label = j.get("combo_label", "") or j.get("label", "")
        status = j.get("status", "-")
        protected = "yes" if j.get("protected") else "no"
        gpus = str(j.get("gpus", "-"))
        print(f"{jn:<45} {sid:<40} {label:<45} {status:<12} {protected:<10} {gpus}")


def _registry_set_protected(registry: Dict[str, Any], job_name: str, value: bool) -> None:
    found = False
    for j in registry.get("jobs", []):
        if j.get("job_name") == job_name:
            j["protected"] = value
            found = True
            break
    if found:
        _save_registry(registry)
        print(f"{'Protected' if value else 'Unprotected'}: {job_name}")
    else:
        print(f"Job not found in registry: {job_name}", file=sys.stderr)


def _registry_add(registry: Dict[str, Any], args) -> None:
    try:
        gpus = int(args.gpus) if args.gpus else 0
    except ValueError:
        print(f"Error: --gpus must be numeric, got '{args.gpus}'", file=sys.stderr)
        sys.exit(1)

    new_job = {
        "job_name": args.add,
        "sweep_id": args.sweep_id or "",
        "combo_label": args.label or "",
        "task": args.task or "",
        "queue": args.queue or "",
        "gpus": gpus,
        "dispatched_at": datetime.now(timezone.utc).isoformat(),
        "status": "running",
        "protected": True,
    }
    existing = [j for j in registry.get("jobs", []) if j.get("job_name") == args.add]
    if existing:
        existing[0].update(new_job)
    else:
        registry.setdefault("jobs", []).append(new_job)
    _save_registry(registry)
    print(f"Registered: {args.add}")


def _registry_remove(registry: Dict[str, Any], job_name: str) -> None:
    before = len(registry.get("jobs", []))
    registry["jobs"] = [j for j in registry.get("jobs", []) if j.get("job_name") != job_name]
    after = len(registry["jobs"])
    if after < before:
        _save_registry(registry)
        print(f"Removed: {job_name}")
    else:
        print(f"Job not found in registry: {job_name}", file=sys.stderr)


def _registry_clear() -> None:
    _save_registry({"version": REGISTRY_VERSION, "jobs": []})
    print("Registry cleared.")


def _registry_add_batch(json_file: str) -> None:
    path = Path(json_file)
    if not path.exists():
        print(f"Error: file not found: {json_file}", file=sys.stderr)
        sys.exit(1)
    with open(path, "r", encoding="utf-8") as f:
        batch = json.load(f)
    if not isinstance(batch, list):
        print("Error: JSON file must contain a list of job objects", file=sys.stderr)
        sys.exit(1)

    registry = _load_registry()
    existing_names = {j["job_name"] for j in registry.get("jobs", [])}
    added = 0
    for entry in batch:
        jn = entry.get("job_name", "")
        if not jn:
            continue
        job = {
            "job_name": jn,
            "sweep_id": entry.get("sweep_id", ""),
            "combo_label": entry.get("combo_label", "") or entry.get("label", ""),
            "task": entry.get("task", ""),
            "queue": entry.get("queue", ""),
            "gpus": entry.get("gpus", 0),
            "dispatched_at": entry.get("dispatched_at", datetime.now(timezone.utc).isoformat()),
            "status": entry.get("status", "running"),
            "protected": entry.get("protected", True),
        }
        if jn in existing_names:
            for j in registry["jobs"]:
                if j["job_name"] == jn:
                    j.update(job)
                    break
        else:
            registry["jobs"].append(job)
            existing_names.add(jn)
        added += 1
    _save_registry(registry)
    print(f"Batch registered: {added} job(s)")


def _registry_sync(registry: Dict[str, Any], ssh_alias: str) -> None:
    """Reconcile registry status with live fuyao status."""
    jobs = registry.get("jobs", [])
    if not jobs:
        print("Registry is empty.")
        return

    print(f"Syncing {len(jobs)} registered job(s) with fuyao...")
    updated = 0
    for j in jobs:
        jn = j.get("job_name", "")
        if not jn:
            continue
        rc, out = _ssh_fuyao_cmd(ssh_alias, "fuyao info", jn, timeout=15)
        fuyao_status = "unknown"
        for line in out.splitlines():
            if "status" in line and ":" in line:
                fuyao_status = line.split(":", 1)[1].strip()
                break

        status_map = {
            "JOB_RUNNING": "running",
            "JOB_CANCELLED": "cancelled",
            "JOB_COMPLETED": "completed",
            "JOB_FAILED": "failed",
        }
        new_status = status_map.get(fuyao_status, j.get("status", "unknown"))
        if new_status != j.get("status"):
            old = j.get("status")
            j["status"] = new_status
            if new_status in ("cancelled", "completed", "failed"):
                j["protected"] = False
            print(f"  {jn}: {old} -> {new_status}")
            updated += 1

    _save_registry(registry)
    print(f"Sync complete. {updated} job(s) updated.")


# ---------------------------------------------------------------------------
# Argument parser
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="fuyao_job_manager", description="Fuyao Job Manager")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    # --- status ---
    p_status = sub.add_parser("status", help="Check job status")
    g_status = p_status.add_mutually_exclusive_group()
    g_status.add_argument("--sweep-id", help="Filter by sweep ID")
    g_status.add_argument("--job-name", help="Check a specific job")
    g_status.add_argument("--all-running", action="store_true", help="Show all running jobs from fuyao history")
    p_status.add_argument("--ssh-alias", default=DEFAULT_SSH_ALIAS)
    p_status.add_argument("--json", action="store_true", help="Output as JSON")

    # --- cancel ---
    p_cancel = sub.add_parser("cancel", help="Cancel jobs with safety guard")
    g_cancel = p_cancel.add_mutually_exclusive_group()
    g_cancel.add_argument("--sweep-id", help="Cancel all jobs in a sweep")
    g_cancel.add_argument("--job-name", help="Cancel a specific job")
    g_cancel.add_argument("--stale", action="store_true", help="Cancel all running jobs NOT in the protected set")
    g_cancel.add_argument("--label-pattern", help="Cancel jobs matching label regex")
    p_cancel.add_argument("--force", action="store_true", help="Skip protected-set guard")
    p_cancel.add_argument("--dry-run", action="store_true", help="Preview only")
    p_cancel.add_argument("--yes", action="store_true", help="Skip confirmation prompt")
    p_cancel.add_argument("--signal", default="7",
                          help="Cancel reason: " + ", ".join(f"{k}={v}" for k, v in CANCEL_SIGNALS.items()))
    p_cancel.add_argument("--ssh-alias", default=DEFAULT_SSH_ALIAS)

    # --- pull ---
    p_pull = sub.add_parser("pull", help="Download artifacts from OSS")
    g_pull = p_pull.add_mutually_exclusive_group(required=True)
    g_pull.add_argument("--sweep-id", help="Pull artifacts for all jobs in a sweep")
    g_pull.add_argument("--job-name", help="Pull artifacts for a specific job")
    p_pull.add_argument("--type", choices=["checkpoints", "logs", "videos", "onnx", "metrics", "all"], default="all")
    p_pull.add_argument("--output-dir", help="Download destination directory")
    p_pull.add_argument("--pattern", help="Regex filter on file names")
    p_pull.add_argument("--ssh-alias", default=DEFAULT_SSH_ALIAS)

    # --- pull-logs ---
    p_plogs = sub.add_parser("pull-logs", help="Fetch training stdout from fuyao")
    g_plogs = p_plogs.add_mutually_exclusive_group(required=True)
    g_plogs.add_argument("--sweep-id", help="Fetch logs for all jobs in a sweep")
    g_plogs.add_argument("--job-name", help="Fetch log for a specific job")
    p_plogs.add_argument("--tail", type=int, default=100, help="Last N lines (default: 100)")
    p_plogs.add_argument("--save", help="Directory to save log files")
    p_plogs.add_argument("--ssh-alias", default=DEFAULT_SSH_ALIAS)

    # --- tensorboard ---
    p_tb = sub.add_parser("tensorboard", help="TensorBoard download (stub)")
    g_tb = p_tb.add_mutually_exclusive_group(required=True)
    g_tb.add_argument("--sweep-id", help="TensorBoard for all jobs in a sweep")
    g_tb.add_argument("--job-name", help="TensorBoard for a specific job")
    p_tb.add_argument("--output-dir", help="Download destination directory")

    # --- fff ---
    p_fff = sub.add_parser("fff", help="Query Fuyao File Finder")
    p_fff.add_argument("--list", action="store_true", help="List registered artifacts")
    p_fff.add_argument("--compare", action="store_true", help="Compare metrics across jobs")
    p_fff.add_argument("--download", action="store_true", help="Download artifact by path")
    p_fff.add_argument("--job-name", help="Job name")
    p_fff.add_argument("--label", help="Job label")
    p_fff.add_argument("--user", help="Job user")
    p_fff.add_argument("--sweep-id", help="Sweep ID (for compare)")
    p_fff.add_argument("--pattern", help="File name filter regex")
    p_fff.add_argument("--output-dir", help="Download destination")

    # --- registry ---
    p_reg = sub.add_parser("registry", help="Manage job registry")
    p_reg.add_argument("--list", action="store_true", help="List all registered jobs")
    p_reg.add_argument("--protect", metavar="JOB", help="Set job as protected")
    p_reg.add_argument("--unprotect", metavar="JOB", help="Remove job protection")
    p_reg.add_argument("--add", metavar="JOB", help="Register a job")
    p_reg.add_argument("--remove", metavar="JOB", help="Remove a job from registry")
    p_reg.add_argument("--clear", action="store_true", help="Clear the entire registry")
    p_reg.add_argument("--add-batch", metavar="FILE", help="Register jobs from a JSON file")
    p_reg.add_argument("--sync", action="store_true", help="Sync registry with live fuyao status")
    p_reg.add_argument("--json", action="store_true", help="Output as JSON (for --list)")
    p_reg.add_argument("--sweep-id", help="Sweep ID (for --add)")
    p_reg.add_argument("--label", help="Label (for --add)")
    p_reg.add_argument("--task", help="Task name (for --add)")
    p_reg.add_argument("--queue", help="Queue (for --add)")
    p_reg.add_argument("--gpus", help="GPUs per node (for --add)")
    p_reg.add_argument("--ssh-alias", default=DEFAULT_SSH_ALIAS)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    dispatch = {
        "status": cmd_status,
        "cancel": cmd_cancel,
        "pull": cmd_pull,
        "pull-logs": cmd_pull_logs,
        "tensorboard": cmd_tensorboard,
        "fff": cmd_fff,
        "registry": cmd_registry,
    }
    handler = dispatch.get(args.command)
    if handler:
        handler(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()

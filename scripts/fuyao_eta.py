#!/usr/bin/env python3
"""fuyao_eta.py — Query training ETA for running Fuyao jobs.

Usage:
  python3 ~/.cursor/scripts/fuyao_eta.py --job-name JOB1 JOB2 ...
  python3 ~/.cursor/scripts/fuyao_eta.py --all-running
  python3 ~/.cursor/scripts/fuyao_eta.py --sweep-id SWEEP_ID

Output is a human-readable table printed to stdout.
Agent MUST print this verbatim without interpretation or reformatting.
"""

import argparse
import fcntl
import json
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_SSH_ALIAS = "remote.kernel.fuyao"
REGISTRY_PATH = Path.home() / ".cursor" / "tmp" / "fuyao_job_registry.json"

# Pacific Time offset: PDT = UTC-7, PST = UTC-8
# Use fixed offset; stdlib zoneinfo not available on all Python 3.8 envs.
def _pacific_now() -> datetime:
    """Return current datetime in Pacific Time (auto-selects PDT/PST)."""
    try:
        from zoneinfo import ZoneInfo  # Python 3.9+
        return datetime.now(ZoneInfo("America/Los_Angeles"))
    except ImportError:
        # Fallback: determine PDT/PST by checking DST manually
        utc_now = datetime.now(timezone.utc)
        # DST: second Sunday in March through first Sunday in November
        year = utc_now.year
        # Second Sunday in March
        dst_start = _nth_weekday(year, 3, 6, 2)  # month=3, weekday=6(Sun), n=2
        # First Sunday in November
        dst_end = _nth_weekday(year, 11, 6, 1)   # month=11, weekday=6(Sun), n=1
        utc_naive = utc_now.replace(tzinfo=None)
        if dst_start <= utc_naive < dst_end:
            offset = timedelta(hours=-7)  # PDT
        else:
            offset = timedelta(hours=-8)  # PST
        pt_tz = timezone(offset)
        return utc_now.astimezone(pt_tz)


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> datetime:
    """Return datetime of the nth occurrence of weekday in given month/year."""
    first = datetime(year, month, 1)
    days_ahead = weekday - first.weekday()
    if days_ahead < 0:
        days_ahead += 7
    first_occurrence = first + timedelta(days=days_ahead)
    return first_occurrence + timedelta(weeks=n - 1)


# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------

def _ssh_run(ssh_alias: str, remote_cmd: str, timeout: int = 30) -> Tuple[int, str]:
    """Run remote_cmd via SSH, piping 'n' to handle fuyao upgrade prompts."""
    cmd = ["ssh", ssh_alias, remote_cmd]
    try:
        result = subprocess.run(
            cmd,
            input="n\n",
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return 1, "SSH_TIMEOUT"


# ---------------------------------------------------------------------------
# Job discovery
# ---------------------------------------------------------------------------

def _jobs_from_registry(sweep_id: str) -> List[str]:
    """Return job names for a sweep from the local registry."""
    if not REGISTRY_PATH.exists():
        return []
    try:
        with open(REGISTRY_PATH, "r", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            data = json.load(f)
            fcntl.flock(f, fcntl.LOCK_UN)
    except (json.JSONDecodeError, ValueError):
        return []
    jobs = data.get("jobs", []) if isinstance(data, dict) else data
    return [j["job_name"] for j in jobs if j.get("sweep_id") == sweep_id and j.get("job_name")]


def _jobs_all_running(ssh_alias: str) -> List[str]:
    """Return all currently running job names via fuyao history."""
    rc, output = _ssh_run(ssh_alias, "fuyao history --limit 50", timeout=30)
    running = []
    current: Dict[str, str] = {}
    for line in output.splitlines():
        if "job_name" in line and ":" in line:
            current["job_name"] = line.split(":", 1)[1].strip()
        elif "status" in line and ":" in line:
            st = line.split(":", 1)[1].strip()
            if st == "JOB_RUNNING" and current.get("job_name"):
                running.append(current["job_name"])
            current = {}
    return running


# ---------------------------------------------------------------------------
# Per-job data fetching (run in thread pool)
# ---------------------------------------------------------------------------

def _fetch_job_data(job_name: str, ssh_alias: str, tail: int) -> Dict[str, Any]:
    """Fetch label + ETA for one job via two parallel SSH calls."""
    result: Dict[str, Any] = {"job_name": job_name, "label": None, "error": None}

    # Fetch info and logs concurrently within this thread using two sub-threads
    with ThreadPoolExecutor(max_workers=2) as sub:
        info_future = sub.submit(
            _ssh_run, ssh_alias,
            f"printf 'n\\n' | fuyao info --job-name {shlex.quote(job_name)}",
            20,
        )
        log_future = sub.submit(
            _ssh_run, ssh_alias,
            f"printf 'n\\n' | fuyao log --job-name {shlex.quote(job_name)}"
            f" --rank 0 --show-stdout --tail {tail}",
            30,
        )
        info_rc, info_out = info_future.result()
        log_rc, log_out = log_future.result()

    # Parse label
    for line in info_out.splitlines():
        m = re.match(r"\s*label\s*:\s*(.+)", line)
        if m:
            result["label"] = m.group(1).strip()
            break

    if not result["label"]:
        result["label"] = job_name  # fallback to job name if not resolvable

    # Handle SSH timeout on log
    if log_out == "SSH_TIMEOUT" or log_rc != 0 and not log_out.strip():
        result["error"] = "SSH_TIMEOUT"
        return result

    # Parse last Learning iteration and ETA from log
    iter_matches = re.findall(r"Learning iteration\s+(\d+)/(\d+)", log_out)
    eta_matches = re.findall(r"ETA:\s*([\d.]+)s", log_out)

    if not iter_matches or not eta_matches:
        result["error"] = "INITIALIZING"
        return result

    cur_iter, total_iter = iter_matches[-1]
    eta_seconds = float(eta_matches[-1])

    result["cur_iter"] = int(cur_iter)
    result["total_iter"] = int(total_iter)
    result["eta_seconds"] = eta_seconds

    return result


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def _fmt_duration(seconds: float) -> str:
    """Format seconds as XhYYm or YYm."""
    total = int(seconds)
    h = total // 3600
    m = (total % 3600) // 60
    if h > 0:
        return f"{h}h{m:02d}m"
    return f"{m}m"


def _fmt_completion(eta_seconds: float) -> str:
    """Return estimated completion time in Pacific Time."""
    pt_now = _pacific_now()
    completion = pt_now + timedelta(seconds=eta_seconds)
    # Detect PDT vs PST from the offset
    offset_hours = int(completion.utcoffset().total_seconds() / 3600) if completion.utcoffset() else -8
    tz_label = "PDT" if offset_hours == -7 else "PST"
    return completion.strftime(f"%a %I:%M %p {tz_label}")


# ---------------------------------------------------------------------------
# Table printer
# ---------------------------------------------------------------------------

def _print_table(results: List[Dict[str, Any]], queried_at: datetime) -> None:
    COL_LABEL = 55
    COL_PROGRESS = 10
    COL_REMAINING = 11
    COL_COMPLETION = 20

    header = (
        f"{'LABEL':<{COL_LABEL}}"
        f"{'PROGRESS':>{COL_PROGRESS}}"
        f"{'REMAINING':>{COL_REMAINING}}"
        f"  {'EST COMPLETION (PT)':<{COL_COMPLETION}}"
    )
    sep = "-" * len(header)

    print(header)
    print(sep)

    for r in results:
        label = r.get("label") or r["job_name"]
        label_trunc = label[:COL_LABEL - 1] if len(label) >= COL_LABEL else label

        if r.get("error") == "SSH_TIMEOUT":
            progress_str = "TIMEOUT"
            remaining_str = "—"
            completion_str = "—"
        elif r.get("error") == "INITIALIZING":
            progress_str = "initializing"
            remaining_str = "—"
            completion_str = "—"
        elif r.get("error"):
            progress_str = f"ERROR: {r['error']}"
            remaining_str = "—"
            completion_str = "—"
        else:
            pct = 100.0 * r["cur_iter"] / r["total_iter"] if r["total_iter"] else 0.0
            progress_str = f"{pct:.1f}% ({r['cur_iter']}/{r['total_iter']})"
            remaining_str = _fmt_duration(r["eta_seconds"])
            completion_str = _fmt_completion(r["eta_seconds"])

        print(
            f"{label_trunc:<{COL_LABEL}}"
            f"{progress_str:>{COL_PROGRESS}}"
            f"{remaining_str:>{COL_REMAINING}}"
            f"  {completion_str:<{COL_COMPLETION}}"
        )

    print(sep)
    tz_label = "PDT" if (queried_at.utcoffset() and int(queried_at.utcoffset().total_seconds() / 3600) == -7) else "PST"
    print(f"Queried {len(results)} job(s) at {queried_at.strftime('%Y-%m-%d %I:%M %p')} {tz_label}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        prog="fuyao_eta",
        description=(
            "Query training ETA for running Fuyao jobs. "
            "Output is a human-readable table. Print verbatim."
        ),
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--job-name", nargs="+", metavar="NAME",
        help="One or more bifrost job names (extract from screenshot or user input)",
    )
    group.add_argument(
        "--all-running", action="store_true",
        help="Auto-discover all running jobs via fuyao history",
    )
    group.add_argument(
        "--sweep-id", metavar="ID",
        help="Resolve job names from local registry by sweep ID",
    )
    parser.add_argument("--ssh-alias", default=DEFAULT_SSH_ALIAS, metavar="ALIAS")
    parser.add_argument("--parallel", type=int, default=4, metavar="N",
                        help="Concurrent SSH workers (default: 4)")
    parser.add_argument("--tail", type=int, default=150, metavar="N",
                        help="Log lines to fetch per job (default: 150)")

    args = parser.parse_args()

    # Resolve job list
    if args.job_name:
        job_names = args.job_name
    elif args.all_running:
        print("Discovering running jobs...", file=sys.stderr)
        job_names = _jobs_all_running(args.ssh_alias)
        if not job_names:
            print("No running jobs found.")
            sys.exit(0)
        print(f"Found {len(job_names)} running job(s).", file=sys.stderr)
    elif args.sweep_id:
        job_names = _jobs_from_registry(args.sweep_id)
        if not job_names:
            print(f"No jobs found in registry for sweep: {args.sweep_id}")
            sys.exit(0)
    else:
        parser.print_help()
        print(
            "\nError: provide --job-name, --all-running, or --sweep-id.",
            file=sys.stderr,
        )
        sys.exit(1)

    queried_at = _pacific_now()

    # Fetch all jobs in parallel
    results: List[Dict[str, Any]] = [None] * len(job_names)
    workers = min(args.parallel, len(job_names))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        future_to_idx = {
            pool.submit(_fetch_job_data, jn, args.ssh_alias, args.tail): i
            for i, jn in enumerate(job_names)
        }
        for future in as_completed(future_to_idx):
            idx = future_to_idx[future]
            try:
                results[idx] = future.result()
            except Exception as exc:
                results[idx] = {
                    "job_name": job_names[idx],
                    "label": job_names[idx],
                    "error": str(exc),
                }

    _print_table(results, queried_at)


if __name__ == "__main__":
    main()

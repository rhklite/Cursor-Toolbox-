#!/usr/bin/env python3
"""pull_training_artifacts.py — Pull evaluation artifacts from completed Fuyao training jobs.

Thin orchestrator that resolves job names from the server registry, delegates
the actual download to pull_fuyao_artifacts.sh, and optionally links artifacts
in the experiment tracker.

Usage:
  python3 ~/.cursor/scripts/pull_training_artifacts.py --job-names NAME1 NAME2 ...
  python3 ~/.cursor/scripts/pull_training_artifacts.py --sweep-id SWEEP_ID
  python3 ~/.cursor/scripts/pull_training_artifacts.py --all-completed
  python3 ~/.cursor/scripts/pull_training_artifacts.py --all-completed --link

Agent MUST print stdout verbatim without interpretation or reformatting.
"""

import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

__version__ = "1.0.0"

SCRIPT_DIR = Path(__file__).resolve().parent
PULL_SCRIPT = SCRIPT_DIR / "pull_fuyao_artifacts.sh"
SERVER_HOST = "huh.desktop.us"
SERVER_REGISTRY = "~/software/Experiment-Tracker-/fuyao_job_registry.json"
TRACKER_CLI = "~/software/Experiment-Tracker-/tracker_cli.py"

TERMINAL_STATUSES = {"completed", "failed", "cancelled"}


def _ssh_read_registry(host: str) -> Dict[str, Any]:
    """Read the authoritative job registry from the server."""
    cmd = ["ssh", "-o", "ConnectTimeout=10", host, f"cat {SERVER_REGISTRY}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        if result.returncode != 0:
            print(f"Error reading server registry: {result.stderr.strip()}", file=sys.stderr)
            return {"jobs": []}
        return json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"Error reading server registry: {exc}", file=sys.stderr)
        return {"jobs": []}


def _resolve_jobs(
    registry: Dict[str, Any],
    sweep_id: Optional[str] = None,
    all_completed: bool = False,
    status_filter: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Filter registry jobs by sweep or completion status."""
    jobs = registry.get("jobs", [])
    if sweep_id:
        jobs = [j for j in jobs if j.get("sweep_id") == sweep_id]
    if all_completed:
        jobs = [j for j in jobs if j.get("status") == "completed"]
    elif status_filter:
        jobs = [j for j in jobs if j.get("status") == status_filter]
    return jobs


def _run_pull_script(
    job_names: List[str],
    selective: bool = True,
    dest_host: str = SERVER_HOST,
    dest_dir: str = "~/fuyao_artifacts",
    backfill: bool = False,
) -> int:
    """Invoke pull_fuyao_artifacts.sh and stream output."""
    if not PULL_SCRIPT.exists():
        print(f"Error: pull script not found at {PULL_SCRIPT}", file=sys.stderr)
        return 1

    names_csv = ",".join(job_names)
    cmd = [
        "bash",
        str(PULL_SCRIPT),
        "--job-names", names_csv,
        "--dest-host", dest_host,
        "--dest-dir", dest_dir,
    ]
    if selective:
        cmd.append("--selective")
    else:
        cmd.append("--no-selective")
    if backfill:
        cmd.append("--backfill")

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in iter(proc.stdout.readline, ""):
        print(line, end="", flush=True)
    proc.wait()
    return proc.returncode


def _link_artifacts(job_names: List[str], host: str = SERVER_HOST) -> None:
    """Run tracker_cli.py link-job-artifacts on the server for each job."""
    for jn in job_names:
        quoted = shlex.quote(jn)
        cmd = [
            "ssh", "-o", "ConnectTimeout=10", host,
            f"cd ~/software/Experiment-Tracker- && python3 {TRACKER_CLI} link-job-artifacts --job-name {quoted}",
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            output = (result.stdout + result.stderr).strip()
            if result.returncode == 0:
                print(f"  Linked: {jn}")
            else:
                print(f"  Link failed for {jn}: {output}", file=sys.stderr)
        except subprocess.TimeoutExpired:
            print(f"  Link timed out for {jn}", file=sys.stderr)


def _print_job_table(jobs: List[Dict[str, Any]]) -> None:
    """Print a summary table of resolved jobs."""
    if not jobs:
        print("No matching jobs found.")
        return

    col_label = 50
    col_status = 12
    col_sweep = 40

    def sep():
        return "+" + "-" * (col_label + 2) + "+" + "-" * (col_status + 2) + "+" + "-" * (col_sweep + 2) + "+"

    def row(label, status, sweep):
        return f"| {label:<{col_label}} | {status:<{col_status}} | {sweep:<{col_sweep}} |"

    print(sep())
    print(row("LABEL", "STATUS", "SWEEP_ID"))
    print(sep())
    for j in jobs:
        label = j.get("combo_label", j.get("job_name", "?"))
        if len(label) > col_label:
            label = label[: col_label - 1] + "…"
        status = j.get("status", "?")
        sweep = j.get("sweep_id", "?")
        if len(sweep) > col_sweep:
            sweep = sweep[: col_sweep - 1] + "…"
        print(row(label, status, sweep))
    print(sep())
    print(f"Total: {len(jobs)} job(s)")


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="pull_training_artifacts",
        description="Pull evaluation artifacts from completed Fuyao training jobs.",
    )

    target = parser.add_mutually_exclusive_group()
    target.add_argument(
        "--job-names", nargs="+", metavar="NAME",
        help="Explicit bifrost job names",
    )
    target.add_argument(
        "--sweep-id", metavar="ID",
        help="Pull all completed jobs in a sweep (from server registry)",
    )
    target.add_argument(
        "--all-completed", action="store_true",
        help="Pull all completed jobs from the server registry",
    )

    parser.add_argument("--dest-host", default=SERVER_HOST, help="Destination SSH host")
    parser.add_argument("--dest-dir", default="~/fuyao_artifacts", help="Remote destination dir")
    parser.add_argument("--no-selective", action="store_true", help="Download all artifacts (not just eval + best checkpoint)")
    parser.add_argument("--link", action="store_true", help="Link artifacts in experiment tracker after download")
    parser.add_argument("--dry-run", action="store_true", help="Show resolved jobs without downloading")
    parser.add_argument("--server-host", default=SERVER_HOST, help="Server hosting the registry")

    args = parser.parse_args()

    if args.job_names:
        job_names = args.job_names
        print(f"Target: {len(job_names)} explicit job(s)")
        jobs_meta = [{"job_name": n, "combo_label": n, "status": "?", "sweep_id": "?"} for n in job_names]
    elif args.sweep_id or args.all_completed:
        print("Reading server registry...", file=sys.stderr)
        registry = _ssh_read_registry(args.server_host)
        if args.sweep_id:
            jobs_meta = _resolve_jobs(registry, sweep_id=args.sweep_id)
        else:
            jobs_meta = _resolve_jobs(registry, all_completed=True)
        job_names = [j["job_name"] for j in jobs_meta if j.get("job_name")]
        if not job_names:
            print("No matching jobs found in server registry.")
            sys.exit(0)
    else:
        parser.print_help()
        print("\nError: provide --job-names, --sweep-id, or --all-completed.", file=sys.stderr)
        sys.exit(1)

    print()
    _print_job_table(jobs_meta)
    print()

    if args.dry_run:
        print("Dry run — no artifacts downloaded.")
        sys.exit(0)

    selective = not args.no_selective
    rc = _run_pull_script(
        job_names,
        selective=selective,
        dest_host=args.dest_host,
        dest_dir=args.dest_dir,
    )

    if rc != 0:
        print(f"\nPull script exited with code {rc}", file=sys.stderr)

    if args.link and job_names:
        print("\n==> Linking artifacts in tracker ...")
        _link_artifacts(job_names, host=args.server_host)

    print(f"\nDone. {len(job_names)} job(s) processed.")


if __name__ == "__main__":
    main()

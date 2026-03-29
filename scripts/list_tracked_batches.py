#!/usr/bin/env python3
"""List tracked registry jobs grouped by deployment batch.

This script is the source of truth for batch-grouped registry views.
It performs filtering and formatting so agents can pass output through verbatim.
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from zoneinfo import ZoneInfo


DEFAULT_SERVER = "huh.desktop.us"
DEFAULT_REGISTRY_PATH = "/home/huh/software/Experiment-Tracker-/fuyao_job_registry.json"
DEFAULT_TIMEZONE = "America/Los_Angeles"


@dataclass
class JobRow:
    job_name: str
    sweep_id: str
    status: str
    combo_label: str
    dispatched_raw: str
    dispatched_utc: Optional[datetime]
    dispatched_local: Optional[datetime]


def _run_ssh(server: str, remote_cmd: str, timeout: int = 30) -> str:
    cmd = ["ssh", server, remote_cmd]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if result.returncode != 0:
        msg = (result.stdout + result.stderr).strip()
        raise RuntimeError(f"SSH command failed ({result.returncode}): {msg}")
    return result.stdout


def _load_server_registry(server: str, registry_path: str, timeout: int) -> List[Dict[str, Any]]:
    remote_cmd = f"cat {shlex.quote(registry_path)}"
    raw = _run_ssh(server, remote_cmd, timeout=timeout)
    data = json.loads(raw)
    if isinstance(data, dict):
        jobs = data.get("jobs", [])
    else:
        jobs = data
    if not isinstance(jobs, list):
        raise ValueError("Registry payload does not contain a jobs list")
    return jobs


def _parse_dispatch_time(raw: str, local_tz: ZoneInfo) -> tuple[Optional[datetime], Optional[datetime]]:
    if not raw:
        return None, None
    value = raw.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(value)
    except ValueError:
        return None, None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    dt_utc = dt.astimezone(timezone.utc)
    return dt_utc, dt_utc.astimezone(local_tz)


def _parse_user_time(raw: str, local_tz: ZoneInfo) -> datetime:
    candidate = raw.strip()
    if not candidate:
        raise ValueError("empty time string")

    to_try = [candidate, candidate.replace(" ", "T")]
    for item in to_try:
        fixed = item[:-1] + "+00:00" if item.endswith("Z") else item
        try:
            parsed = datetime.fromisoformat(fixed)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=local_tz)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            pass

    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            parsed = datetime.strptime(candidate, fmt).replace(tzinfo=local_tz)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            pass

    raise ValueError(
        f"Invalid time format: {raw}. Use ISO time or 'YYYY-MM-DD HH:MM[:SS]'."
    )


def _to_rows(jobs: List[Dict[str, Any]], local_tz: ZoneInfo) -> List[JobRow]:
    rows: List[JobRow] = []
    for job in jobs:
        job_name = str(job.get("job_name", "")).strip()
        if not job_name:
            continue
        sweep_id = str(job.get("sweep_id", "")).strip() or "uncategorized"
        status = str(job.get("status", "unknown")).strip() or "unknown"
        combo_label = str(job.get("combo_label") or job.get("label") or "").strip()
        dispatched_raw = str(job.get("dispatched_at", "")).strip()
        dispatched_utc, dispatched_local = _parse_dispatch_time(dispatched_raw, local_tz)
        rows.append(
            JobRow(
                job_name=job_name,
                sweep_id=sweep_id,
                status=status,
                combo_label=combo_label,
                dispatched_raw=dispatched_raw,
                dispatched_utc=dispatched_utc,
                dispatched_local=dispatched_local,
            )
        )
    return rows


def _apply_time_filters(
    rows: List[JobRow],
    start_time_utc: Optional[datetime],
    end_time_utc: Optional[datetime],
) -> List[JobRow]:
    if start_time_utc is None and end_time_utc is None:
        return rows

    filtered: List[JobRow] = []
    for row in rows:
        if row.dispatched_utc is None:
            continue
        if start_time_utc is not None and row.dispatched_utc < start_time_utc:
            continue
        if end_time_utc is not None and row.dispatched_utc > end_time_utc:
            continue
        filtered.append(row)
    return filtered


def _sort_rows(rows: List[JobRow]) -> List[JobRow]:
    def sort_key(row: JobRow) -> tuple[int, float]:
        if row.dispatched_utc is None:
            return (0, float("-inf"))
        return (1, row.dispatched_utc.timestamp())

    return sorted(rows, key=sort_key, reverse=True)


def _group_rows(rows: List[JobRow]) -> List[Dict[str, Any]]:
    grouped: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        batch = grouped.setdefault(
            row.sweep_id,
            {
                "batch_id": row.sweep_id,
                "latest_utc": None,
                "jobs": [],
            },
        )
        batch["jobs"].append(row)
        if row.dispatched_utc is not None:
            current = batch["latest_utc"]
            if current is None or row.dispatched_utc > current:
                batch["latest_utc"] = row.dispatched_utc

    batches = list(grouped.values())
    for batch in batches:
        batch["jobs"] = _sort_rows(batch["jobs"])

    def batch_key(batch: Dict[str, Any]) -> tuple[int, float]:
        latest = batch.get("latest_utc")
        if latest is None:
            return (0, float("-inf"))
        return (1, latest.timestamp())

    batches.sort(key=batch_key, reverse=True)
    return batches


def _fmt_time(dt: Optional[datetime], local_tz: ZoneInfo) -> str:
    if dt is None:
        return "-"
    return dt.astimezone(local_tz).strftime("%Y-%m-%d %H:%M:%S %Z")


def _clip(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[: max(1, limit - 1)] + "…"


def _print_table(batches: List[Dict[str, Any]], local_tz: ZoneInfo) -> None:
    if not batches:
        print("No jobs match the requested filters.")
        return

    col_status = 10
    col_time = 23
    col_job = 35
    col_label = 52

    for batch in batches:
        batch_id = batch["batch_id"]
        jobs: List[JobRow] = batch["jobs"]
        latest = batch.get("latest_utc")
        print(
            f"=== batch: {batch_id} | jobs={len(jobs)} | latest={_fmt_time(latest, local_tz)} ==="
        )
        print(
            f"{'STATUS':<{col_status}} {'DISPATCHED_AT':<{col_time}} "
            f"{'JOB_NAME':<{col_job}} {'COMBO_LABEL':<{col_label}}"
        )
        print("-" * (col_status + col_time + col_job + col_label + 3))
        for row in jobs:
            print(
                f"{_clip(row.status, col_status):<{col_status}} "
                f"{_clip(_fmt_time(row.dispatched_local, local_tz), col_time):<{col_time}} "
                f"{_clip(row.job_name, col_job):<{col_job}} "
                f"{_clip(row.combo_label, col_label):<{col_label}}"
            )
        print("")


def _as_json_payload(batches: List[Dict[str, Any]], local_tz: ZoneInfo) -> List[Dict[str, Any]]:
    payload: List[Dict[str, Any]] = []
    for batch in batches:
        jobs_payload = []
        for row in batch["jobs"]:
            jobs_payload.append(
                {
                    "job_name": row.job_name,
                    "status": row.status,
                    "combo_label": row.combo_label,
                    "dispatched_at": row.dispatched_raw,
                    "dispatched_at_local": _fmt_time(row.dispatched_local, local_tz),
                }
            )
        payload.append(
            {
                "batch_id": batch["batch_id"],
                "latest_dispatched_at": (
                    batch["latest_utc"].astimezone(timezone.utc).isoformat()
                    if batch["latest_utc"] is not None
                    else None
                ),
                "latest_dispatched_at_local": _fmt_time(batch["latest_utc"], local_tz),
                "job_count": len(jobs_payload),
                "jobs": jobs_payload,
            }
        )
    return payload


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="list_tracked_batches",
        description="List tracked registry jobs grouped by sweep_id with optional time filtering.",
    )
    parser.add_argument("--server", default=DEFAULT_SERVER, help="SSH host for registry source")
    parser.add_argument(
        "--registry-path",
        default=DEFAULT_REGISTRY_PATH,
        help="Registry JSON path on server",
    )
    parser.add_argument(
        "--start-time",
        default=None,
        help="Inclusive lower bound for dispatched_at",
    )
    parser.add_argument(
        "--end-time",
        default=None,
        help="Inclusive upper bound for dispatched_at",
    )
    parser.add_argument(
        "--timezone",
        default=DEFAULT_TIMEZONE,
        help="Timezone used for parsing naive inputs and rendering output",
    )
    parser.add_argument(
        "--output",
        choices=("table", "json"),
        default="table",
        help="Output format",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="SSH timeout in seconds",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()

    try:
        local_tz = ZoneInfo(args.timezone)
    except Exception as exc:
        print(f"Error: invalid timezone '{args.timezone}': {exc}", file=sys.stderr)
        raise SystemExit(2)

    try:
        start_utc = _parse_user_time(args.start_time, local_tz) if args.start_time else None
        end_utc = _parse_user_time(args.end_time, local_tz) if args.end_time else None
        if start_utc is not None and end_utc is not None and start_utc > end_utc:
            raise ValueError("start-time must be earlier than or equal to end-time")
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(2)

    try:
        jobs = _load_server_registry(args.server, args.registry_path, timeout=args.timeout)
    except (RuntimeError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
        print(f"Error: failed to load registry: {exc}", file=sys.stderr)
        raise SystemExit(1)

    rows = _to_rows(jobs, local_tz)
    filtered_rows = _apply_time_filters(rows, start_utc, end_utc)
    batches = _group_rows(filtered_rows)

    if args.output == "json":
        print(json.dumps(_as_json_payload(batches, local_tz), indent=2))
    else:
        _print_table(batches, local_tz)


if __name__ == "__main__":
    main()

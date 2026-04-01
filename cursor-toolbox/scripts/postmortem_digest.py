#!/usr/bin/env python3
"""Batch postmortem digest generator for stability eval runs.

Reads stability_eval_results.csv, torque_limits.csv, metric.json, and
optional .mp4 videos from one or more run directories. Produces compact
DIGEST.md files and keyframe grids suitable for LLM consumption.

Usage:
    python postmortem_digest.py /path/to/run_dir
    python postmortem_digest.py dir1 dir2 --compare
    python postmortem_digest.py dir1 --baseline-config /path/to/baseline.yaml --top-n 5
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import pandas as pd
except ImportError:
    sys.exit("pandas is required: pip install pandas")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

OUTPUT_ROOT = Path.home() / "Downloads" / "postmortem_digests"
KEYFRAME_COUNT = 10
DEFAULT_TOP_N = 5

LINEAR_SWEEP_COLS = ("speed", "push_magnitude", "push_direction")
ANGULAR_SWEEP_COLS = ("speed", "push_ang_magnitude", "push_ang_axis")

TIER4_COLS = [
    "peak_excursion_pitch",
    "peak_excursion_roll",
    "peak_angular_velocity",
    "corrective_step_count",
    "action_smoothness_rms",
    "final_posture_offset",
]

# Initial thresholds for quick triage. Tune per project as needed.
TIER4_THRESHOLDS = {
    "peak_excursion_pitch": {"warn": 0.15, "unit": "rad"},
    "peak_excursion_roll": {"warn": 0.10, "unit": "rad"},
    "peak_angular_velocity": {"warn": 2.0, "unit": "rad/s"},
    "corrective_step_count": {"warn": 6.0, "unit": "steps"},
    "action_smoothness_rms": {"warn": 0.5, "unit": ""},
    "final_posture_offset": {"warn": 0.2, "unit": "rad"},
}

CORE_REQUIRED_COLS = [
    "triggered",
    "survived",
    "time_to_stabilize",
    "peak_joint_torque",
]

TIER1_COMPARISON_COLS = [
    "run_name",
    "survival_rate",
    "mean_time_to_stabilize",
    "max_peak_joint_torque",
    "triggered_count",
    "survival_count",
]


# ---------------------------------------------------------------------------
# CSV / metric.json readers
# ---------------------------------------------------------------------------


def read_results_csv(run_dir: Path) -> pd.DataFrame:
    csv_path = run_dir / "stability_eval_results.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"No stability_eval_results.csv in {run_dir}")
    return pd.read_csv(csv_path)


def read_torque_limits(run_dir: Path) -> pd.DataFrame:
    csv_path = run_dir / "torque_limits.csv"
    if not csv_path.exists():
        return pd.DataFrame(columns=["joint_name", "torque_limit"])
    return pd.read_csv(csv_path)


def read_metric_json(run_dir: Path) -> Dict[str, Any]:
    json_path = run_dir / "metric.json"
    if not json_path.exists():
        return {}
    with open(json_path) as f:
        data = json.load(f)
    if isinstance(data, list):
        return {item["key"]: item["value"] for item in data if "key" in item}
    return data


def parse_remote_spec(spec: str) -> Tuple[str, str]:
    if ":" not in spec:
        raise ValueError(
            f"Invalid --remote '{spec}'. Expected format ssh_alias:/absolute/path"
        )
    alias, remote_path = spec.split(":", 1)
    alias = alias.strip()
    remote_path = remote_path.strip()
    if not alias or not remote_path:
        raise ValueError(
            f"Invalid --remote '{spec}'. Expected format ssh_alias:/absolute/path"
        )
    if not remote_path.startswith("/"):
        raise ValueError(f"Remote path must be absolute in --remote '{spec}'")
    return alias, remote_path


def pull_remote_run_dirs(
    remote_specs: List[str], keep_local: bool
) -> Tuple[List[Path], Optional[Path]]:
    if not remote_specs:
        return [], None

    staging_root = Path(tempfile.mkdtemp(prefix="postmortem_pull_"))
    pulled_dirs: List[Path] = []

    include_args = [
        "--include=stability_eval_results.csv",
        "--include=torque_limits.csv",
        "--include=metric.json",
        "--include=config.yaml",
        "--include=*config*.yaml",
        "--include=*config*.json",
        "--include=*.mp4",
        "--exclude=*",
    ]

    for idx, spec in enumerate(remote_specs, start=1):
        alias, remote_path = parse_remote_spec(spec)
        local_dir = staging_root / f"{idx:02d}_{Path(remote_path).name}"
        local_dir.mkdir(parents=True, exist_ok=True)

        src = f"{alias}:{remote_path.rstrip('/')}/"
        dst = str(local_dir) + "/"
        cmd = ["rsync", "-az", "--prune-empty-dirs", *include_args, src, dst]
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=300)
        except subprocess.CalledProcessError as e:
            err = (e.stderr or e.stdout or "").strip()
            raise RuntimeError(f"rsync pull failed for {spec}: {err[:300]}")
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"rsync pull timed out for {spec}")

        if not (local_dir / "stability_eval_results.csv").exists():
            raise RuntimeError(
                f"Remote pull succeeded but missing stability_eval_results.csv for {spec}"
            )

        pulled_dirs.append(local_dir)
        print(f"[postmortem_digest] pulled {spec} -> {local_dir}")

    if keep_local:
        print(f"[postmortem_digest] keeping staging directory: {staging_root}")
        return pulled_dirs, staging_root

    return pulled_dirs, staging_root


# ---------------------------------------------------------------------------
# Detect sweep mode
# ---------------------------------------------------------------------------


def detect_sweep_cols(df: pd.DataFrame) -> Tuple[str, ...]:
    if "push_ang_magnitude" in df.columns:
        return ANGULAR_SWEEP_COLS
    return LINEAR_SWEEP_COLS


def detect_sweep_cols_from_header(columns: List[str]) -> Optional[Tuple[str, ...]]:
    colset = set(columns)
    if set(ANGULAR_SWEEP_COLS).issubset(colset):
        return ANGULAR_SWEEP_COLS
    if set(LINEAR_SWEEP_COLS).issubset(colset):
        return LINEAR_SWEEP_COLS
    return None


def validate_run_dir(run_dir: Path) -> Tuple[bool, List[str]]:
    issues: List[str] = []
    required_files = ["stability_eval_results.csv", "torque_limits.csv", "metric.json"]

    for fname in required_files:
        if not (run_dir / fname).exists():
            issues.append(f"missing file: {fname}")

    mp4s = list(run_dir.glob("*.mp4"))
    if not mp4s:
        issues.append("no .mp4 in run dir (allowed, but keyframe grid will be skipped)")

    csv_path = run_dir / "stability_eval_results.csv"
    if not csv_path.exists():
        return False, issues

    try:
        header_df = pd.read_csv(csv_path, nrows=0)
    except Exception as e:
        issues.append(f"cannot read CSV header: {e}")
        return False, issues

    columns = list(header_df.columns)
    sweep_cols = detect_sweep_cols_from_header(columns)
    if sweep_cols is None:
        issues.append(
            "cannot detect sweep mode; missing expected linear or angular sweep columns"
        )
        sweep_cols = ()

    missing = [c for c in [*CORE_REQUIRED_COLS, *sweep_cols, *TIER4_COLS] if c not in columns]
    if missing:
        issues.append(f"missing required columns: {', '.join(missing)}")

    pct_cols = [c for c in columns if c.startswith("peak_torque_pct_")]
    rate_cols = [c for c in columns if c.startswith("peak_torque_rate_")]
    if not pct_cols:
        issues.append("missing peak_torque_pct_* columns")
    if not rate_cols:
        issues.append("missing peak_torque_rate_* columns")

    tl_path = run_dir / "torque_limits.csv"
    if tl_path.exists():
        try:
            tl_header = list(pd.read_csv(tl_path, nrows=0).columns)
            for c in ("joint_name", "torque_limit"):
                if c not in tl_header:
                    issues.append(f"torque_limits.csv missing column: {c}")
        except Exception as e:
            issues.append(f"cannot read torque_limits.csv header: {e}")

    is_ok = not any(
        issue.startswith("missing file:")
        or issue.startswith("cannot read CSV header:")
        or issue.startswith("cannot detect sweep mode;")
        or issue.startswith("missing required columns:")
        or issue.startswith("missing peak_torque_pct_")
        or issue.startswith("missing peak_torque_rate_")
        or issue.startswith("torque_limits.csv missing column:")
        or issue.startswith("cannot read torque_limits.csv header:")
        for issue in issues
    )
    return is_ok, issues


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------


def aggregate_conditions(df: pd.DataFrame, sweep_cols: Tuple[str, ...]) -> pd.DataFrame:
    """Group by sweep axes, compute Tier 1 + Tier 4 aggregates."""
    triggered = df[df["triggered"] == True].copy()  # noqa: E712
    if triggered.empty:
        return pd.DataFrame()

    survived = triggered[triggered["survived"] == True]  # noqa: E712

    groups = triggered.groupby(list(sweep_cols), dropna=False)

    records = []
    for key, grp in groups:
        key_dict = dict(zip(sweep_cols, key if isinstance(key, tuple) else (key,)))
        n_triggered = len(grp)
        n_survived = grp["survived"].sum()
        rate = n_survived / max(n_triggered, 1)

        surv_grp = grp[grp["survived"] == True]  # noqa: E712
        tts_vals = surv_grp["time_to_stabilize"].dropna()
        pjt_vals = grp["peak_joint_torque"].dropna()

        rec = {
            **key_dict,
            "n_triggered": n_triggered,
            "n_survived": int(n_survived),
            "survival_rate": rate,
            "tts_mean": tts_vals.mean() if len(tts_vals) else float("nan"),
            "tts_std": tts_vals.std() if len(tts_vals) > 1 else float("nan"),
            "pjt_max": pjt_vals.max() if len(pjt_vals) else float("nan"),
        }

        for col in TIER4_COLS:
            vals = surv_grp[col].dropna() if col in surv_grp.columns else pd.Series()
            rec[f"{col}_mean"] = vals.mean() if len(vals) else float("nan")
            rec[f"{col}_std"] = vals.std() if len(vals) > 1 else float("nan")

        records.append(rec)

    return pd.DataFrame(records)


# ---------------------------------------------------------------------------
# Torque table
# ---------------------------------------------------------------------------


def build_torque_table(
    df: pd.DataFrame, torque_limits: pd.DataFrame
) -> List[Dict[str, Any]]:
    """Per-joint peak torque % and peak rate across all triggered trials."""
    triggered = df[df["triggered"] == True]  # noqa: E712
    if triggered.empty:
        return []

    limit_map = dict(zip(torque_limits["joint_name"], torque_limits["torque_limit"]))

    pct_cols = [c for c in triggered.columns if c.startswith("peak_torque_pct_")]
    rate_cols = [c for c in triggered.columns if c.startswith("peak_torque_rate_")]

    joint_names = [c.replace("peak_torque_pct_", "") for c in pct_cols]

    rows = []
    for name in joint_names:
        pct_col = f"peak_torque_pct_{name}"
        rate_col = f"peak_torque_rate_{name}"
        pct_vals = triggered[pct_col].dropna()
        rate_vals = (
            triggered[rate_col].dropna()
            if rate_col in triggered.columns
            else pd.Series()
        )
        rows.append(
            {
                "joint": name,
                "limit_Nm": limit_map.get(name, float("nan")),
                "max_pct": pct_vals.max() * 100 if len(pct_vals) else float("nan"),
                "mean_pct": pct_vals.mean() * 100 if len(pct_vals) else float("nan"),
                "max_rate_Nm_s": rate_vals.max() if len(rate_vals) else float("nan"),
                "mean_rate_Nm_s": rate_vals.mean() if len(rate_vals) else float("nan"),
            }
        )
    return rows


# ---------------------------------------------------------------------------
# Worst-N conditions
# ---------------------------------------------------------------------------


def rank_worst_conditions(
    agg: pd.DataFrame, top_n: int, sweep_cols: Tuple[str, ...]
) -> pd.DataFrame:
    """Rank conditions by lowest survival, then highest tts among survivors."""
    if agg.empty:
        return agg
    ranked = agg.sort_values(
        ["survival_rate", "tts_mean"], ascending=[True, False]
    ).head(top_n)
    return ranked


# ---------------------------------------------------------------------------
# Video keyframe grid
# ---------------------------------------------------------------------------


def find_video(run_dir: Path) -> Optional[Path]:
    mp4s = sorted(run_dir.glob("*.mp4"))
    return mp4s[0] if mp4s else None


def load_video_map(video_map_path: Path) -> Dict[str, List[Dict[str, str]]]:
    if not video_map_path.exists():
        raise FileNotFoundError(f"video map not found: {video_map_path}")

    with open(video_map_path) as f:
        raw = json.load(f)

    if not isinstance(raw, dict):
        raise ValueError("video map must be a JSON object keyed by run_label")

    parsed: Dict[str, List[Dict[str, str]]] = {}
    for run_name, entry in raw.items():
        if not isinstance(entry, dict):
            continue
        videos = entry.get("videos", [])
        if not isinstance(videos, list):
            continue

        normalized: List[Dict[str, str]] = []
        for v in videos:
            if not isinstance(v, dict):
                continue
            p = v.get("path")
            if not isinstance(p, str) or not p.strip():
                continue
            normalized.append(
                {
                    "path": p.strip(),
                    "variant": str(v.get("variant", "")).strip().lower(),
                    "outcome": str(v.get("outcome", "")).strip().lower(),
                }
            )
        parsed[str(run_name)] = normalized

    return parsed


def find_video_from_map(
    video_map: Dict[str, List[Dict[str, str]]], run_basename: str
) -> Optional[Path]:
    candidates = video_map.get(run_basename, [])
    if not candidates:
        return None

    ranked = sorted(
        candidates,
        key=lambda c: (
            c.get("variant") != "overlay",
            c.get("outcome") != "failure",
            c.get("path", ""),
        ),
    )

    for cand in ranked:
        p = Path(cand.get("path", "")).expanduser()
        if p.exists():
            return p
        print(f"[postmortem_digest] WARNING: mapped video does not exist: {p}")
    return None


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def choose_grid_layout(n_frames: int) -> Tuple[int, int]:
    n = max(1, n_frames)
    best: Optional[Tuple[int, int, int, int, int]] = None
    for rows in range(1, n + 1):
        cols = math.ceil(n / rows)
        if cols < rows:
            continue
        area = cols * rows
        wasted = area - n
        balance = abs(cols - rows)
        candidate = (wasted, area, balance, cols, rows)
        if best is None or candidate < best:
            best = candidate
    if best is None:
        return n, 1
    return best[3], best[4]


def generate_keyframe_grid(
    video_path: Path, output_path: Path, n_frames: int = KEYFRAME_COUNT
) -> bool:
    """Extract evenly-spaced keyframes and tile into a grid image."""
    if not ffmpeg_available():
        print("[postmortem_digest] ffmpeg not found, skipping video grid")
        return False

    # First, probe frame count to compute evenly-spaced indices
    probe_cmd = [
        "ffprobe",
        "-v",
        "error",
        "-count_frames",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=nb_read_frames",
        "-of",
        "csv=p=0",
        str(video_path),
    ]
    try:
        result = subprocess.run(probe_cmd, capture_output=True, text=True, timeout=60)
        total_frames = int(result.stdout.strip())
    except Exception:
        total_frames = 300  # fallback estimate

    if total_frames < n_frames:
        indices = list(range(total_frames))
    else:
        step = total_frames / n_frames
        indices = [int(step * i) for i in range(n_frames)]

    if not indices:
        print("[postmortem_digest] no frames detected, skipping video grid")
        return False

    tile_cols, tile_rows = choose_grid_layout(len(indices))
    select_expr = "+".join([f"eq(n\\,{idx})" for idx in indices])
    filter_with_ts = (
        f"select='{select_expr}',"
        "drawtext=text='%{pts\\:hms}':x=10:y=10:fontsize=22:"
        "fontcolor=white:borderw=2:bordercolor=black,"
        f"tile={tile_cols}x{tile_rows}"
    )
    filter_without_ts = f"select='{select_expr}',tile={tile_cols}x{tile_rows}"

    def _run_ffmpeg(vf: str) -> subprocess.CompletedProcess:
        cmd = [
            "ffmpeg",
            "-i",
            str(video_path),
            "-vf",
            vf,
            "-vsync",
            "vfr",
            "-frames:v",
            "1",
            "-y",
            str(output_path),
        ]
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=120, check=True
        )

    try:
        _run_ffmpeg(filter_with_ts)
        return True
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip().splitlines()[-1] if e.stderr else ""
        print(
            f"[postmortem_digest] drawtext unavailable or failed ({stderr}); retrying without timestamps"
        )
        try:
            _run_ffmpeg(filter_without_ts)
            return True
        except subprocess.CalledProcessError as inner:
            print(
                "[postmortem_digest] ffmpeg grid failed: "
                f"{((inner.stderr or '').strip().splitlines()[-1] if inner.stderr else '')}"
            )
            return False
        except Exception as inner:
            print(f"[postmortem_digest] ffmpeg error: {inner}")
            return False
    except Exception as e:
        print(f"[postmortem_digest] ffmpeg error: {e}")
        return False


# ---------------------------------------------------------------------------
# Config diff
# ---------------------------------------------------------------------------


def diff_configs(run_dir: Path, baseline_path: Optional[Path]) -> Optional[str]:
    """YAML-level diff of run config against baseline. Returns text diff or None."""
    if baseline_path is None:
        return None

    try:
        import yaml
    except ImportError:
        return "(pyyaml not installed, config diff skipped)"

    run_config_path = run_dir / "config.yaml"
    if not run_config_path.exists():
        candidates = list(run_dir.glob("*config*.yaml")) + list(
            run_dir.glob("*config*.json")
        )
        if candidates:
            run_config_path = candidates[0]
        else:
            return "(no config file found in run directory)"

    def load_yaml(p: Path) -> dict:
        with open(p) as f:
            return yaml.safe_load(f) or {}

    try:
        baseline = load_yaml(baseline_path)
        run_cfg = load_yaml(run_config_path)
    except Exception as e:
        return f"(config load error: {e})"

    def flat(d: dict, prefix: str = "") -> dict:
        out = {}
        for k, v in sorted(d.items()):
            key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                out.update(flat(v, key))
            else:
                out[key] = v
        return out

    fb = flat(baseline)
    fr = flat(run_cfg)
    all_keys = sorted(set(fb) | set(fr))

    lines = []
    for k in all_keys:
        bv = fb.get(k, "<absent>")
        rv = fr.get(k, "<absent>")
        if bv != rv:
            lines.append(f"  {k}: {bv} -> {rv}")

    if not lines:
        return "(no differences from baseline)"
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Markdown formatters
# ---------------------------------------------------------------------------


def _fmt(v: float, precision: int = 3) -> str:
    if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
        return "n/a"
    if isinstance(v, float):
        return f"{v:.{precision}f}"
    return str(v)


def sweep_mode_text(sweep_cols: Tuple[str, ...]) -> str:
    if tuple(sweep_cols) == ANGULAR_SWEEP_COLS:
        return "angular sweep (speed x push_ang_magnitude x push_ang_axis)"
    return "linear sweep (speed x push_magnitude x push_direction)"


def format_header(
    metric_json: Dict[str, Any], run_dir: Path, sweep_cols: Tuple[str, ...]
) -> str:
    lines = [
        f"# Postmortem Digest: {run_dir.name}",
        "",
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Mode: {sweep_mode_text(sweep_cols)}",
        "",
        "## Summary (metric.json)",
        "",
    ]
    for k, v in sorted(metric_json.items()):
        lines.append(f"- {k}: {_fmt(v) if isinstance(v, float) else v}")
    lines.append("")
    return "\n".join(lines)


def format_survival_table(agg: pd.DataFrame, sweep_cols: Tuple[str, ...]) -> str:
    if agg.empty:
        return "## Survival Table\n\n(no triggered trials)\n"

    headers = list(sweep_cols) + [
        "n_triggered",
        "n_survived",
        "survival_%",
        "tts_mean_s",
        "tts_std_s",
        "pjt_max_Nm",
    ]
    lines = ["## Survival by Condition", "", "| " + " | ".join(headers) + " |"]
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")

    for _, row in agg.iterrows():
        vals = [_fmt(row.get(c, ""), 2) for c in sweep_cols]
        vals += [
            str(int(row["n_triggered"])),
            str(int(row["n_survived"])),
            _fmt(row["survival_rate"] * 100, 1),
            _fmt(row["tts_mean"], 2),
            _fmt(row["tts_std"], 2),
            _fmt(row["pjt_max"], 1),
        ]
        lines.append("| " + " | ".join(vals) + " |")

    lines.append("")
    return "\n".join(lines)


def format_torque_table(torque_rows: List[Dict]) -> str:
    if not torque_rows:
        return "## Per-Joint Torque Summary\n\n(no data)\n"

    headers = [
        "joint",
        "limit_Nm",
        "max_%",
        "mean_%",
        "max_rate_Nm/s",
        "mean_rate_Nm/s",
    ]
    lines = ["## Per-Joint Torque Summary", "", "| " + " | ".join(headers) + " |"]
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")

    for r in torque_rows:
        lines.append(
            "| "
            + " | ".join(
                [
                    r["joint"],
                    _fmt(r["limit_Nm"], 1),
                    _fmt(r["max_pct"], 1),
                    _fmt(r["mean_pct"], 1),
                    _fmt(r["max_rate_Nm_s"], 1),
                    _fmt(r["mean_rate_Nm_s"], 1),
                ]
            )
            + " |"
        )

    lines.append("")
    return "\n".join(lines)


def format_tier4_table(agg: pd.DataFrame) -> str:
    if agg.empty:
        return "## Tier 4 Diagnostics\n\n(no data)\n"

    headers = ["metric", "mean", "std", "warn_threshold", "status"]
    lines = [
        "## Tier 4 Diagnostics (across all conditions)",
        "",
        "| " + " | ".join(headers) + " |",
    ]
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")

    for col in TIER4_COLS:
        mean_col = f"{col}_mean"
        std_col = f"{col}_std"
        if mean_col in agg.columns:
            m = agg[mean_col].mean()
            s = agg[std_col].mean()
            threshold = TIER4_THRESHOLDS.get(col, {}).get("warn", float("nan"))
            if isinstance(m, float) and math.isnan(m):
                status = "n/a"
            else:
                status = "OK" if m <= threshold else "WARN"
            lines.append(
                f"| {col} | {_fmt(m, 3)} | {_fmt(s, 3)} | {_fmt(threshold, 3)} | {status} |"
            )

    lines.append("")
    return "\n".join(lines)


def format_worst_conditions(worst: pd.DataFrame, sweep_cols: Tuple[str, ...]) -> str:
    if worst.empty:
        return "## Worst Conditions\n\n(none identified)\n"

    lines = ["## Worst Conditions (triage targets)", ""]
    for i, (_, row) in enumerate(worst.iterrows(), 1):
        cond_desc = ", ".join(f"{c}={_fmt(row[c], 2)}" for c in sweep_cols)
        lines.append(
            f"{i}. [{cond_desc}] survival={_fmt(row['survival_rate'] * 100, 1)}% "
            f"tts={_fmt(row['tts_mean'], 2)}s pjt_max={_fmt(row['pjt_max'], 1)}Nm"
        )

    lines.append("")
    return "\n".join(lines)


def format_config_diff(diff_text: Optional[str]) -> str:
    if diff_text is None:
        return ""
    return f"## Config Diff (vs baseline)\n\n```\n{diff_text}\n```\n"


def format_video_note(grid_path: Optional[Path]) -> str:
    if grid_path and grid_path.exists():
        return f"## Video Keyframes\n\nGrid image: {grid_path.name}\n"
    return "## Video Keyframes\n\n(no video available)\n"


def run_label(run_dir: Path) -> str:
    parent = run_dir.parent.name
    name = run_dir.name
    if parent and parent not in (".", "/"):
        return f"{parent}_{name}"
    return name


# ---------------------------------------------------------------------------
# Assembler
# ---------------------------------------------------------------------------


def assemble_digest(
    run_dir: Path,
    output_dir: Path,
    baseline_config: Optional[Path],
    top_n: int,
    video_map: Optional[Dict[str, List[Dict[str, str]]]] = None,
) -> Path:
    """Produce DIGEST_{run_basename}.md for a single run."""
    df = read_results_csv(run_dir)
    torque_limits = read_torque_limits(run_dir)
    metric_json = read_metric_json(run_dir)
    sweep_cols = detect_sweep_cols(df)

    agg = aggregate_conditions(df, sweep_cols)
    torque_rows = build_torque_table(df, torque_limits)
    worst = rank_worst_conditions(agg, top_n, sweep_cols)
    config_diff = diff_configs(run_dir, baseline_config)

    run_basename = run_label(run_dir)
    digest_name = f"DIGEST_{run_basename}.md"
    digest_path = output_dir / digest_name

    if video_map:
        video = find_video_from_map(video_map, run_basename)
    else:
        video = find_video(run_dir)
    grid_path = None
    if video:
        grid_path = output_dir / f"grid_{run_basename}.png"
        if not generate_keyframe_grid(video, grid_path):
            grid_path = None

    sections = [
        format_header(metric_json, run_dir, sweep_cols),
        format_survival_table(agg, sweep_cols),
        format_torque_table(torque_rows),
        format_tier4_table(agg),
        format_worst_conditions(worst, sweep_cols),
        format_config_diff(config_diff),
        format_video_note(grid_path),
    ]

    digest_path.write_text("\n".join(sections))
    print(f"[postmortem_digest] wrote {digest_path}")
    return digest_path


# ---------------------------------------------------------------------------
# Comparison mode
# ---------------------------------------------------------------------------


def assemble_comparison(run_dirs: List[Path], output_dir: Path) -> Path:
    """Produce COMPARISON.md with side-by-side Tier 1 metrics."""
    rows = []
    for rd in run_dirs:
        metric_json = read_metric_json(rd)
        df = read_results_csv(rd)
        triggered = df[df["triggered"] == True]  # noqa: E712
        survived = triggered[triggered["survived"] == True]  # noqa: E712

        tts_vals = survived["time_to_stabilize"].dropna()
        pjt_vals = triggered["peak_joint_torque"].dropna()

        rows.append(
            {
                "run_name": run_label(rd),
                "survival_rate": metric_json.get(
                    "survival_rate",
                    len(survived) / max(len(triggered), 1),
                ),
                "mean_time_to_stabilize": (
                    tts_vals.mean() if len(tts_vals) else float("nan")
                ),
                "max_peak_joint_torque": (
                    pjt_vals.max() if len(pjt_vals) else float("nan")
                ),
                "triggered_count": len(triggered),
                "survival_count": len(survived),
            }
        )

    comp = pd.DataFrame(rows, columns=TIER1_COMPARISON_COLS)

    lines = [
        "# Comparison Digest",
        "",
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"Runs: {len(run_dirs)}",
        "",
        "## Tier 1 Side-by-Side",
        "",
        "| " + " | ".join(TIER1_COMPARISON_COLS) + " |",
        "| " + " | ".join(["---"] * len(TIER1_COMPARISON_COLS)) + " |",
    ]
    for _, row in comp.iterrows():
        vals = [
            row["run_name"],
            _fmt(
                (
                    row["survival_rate"] * 100
                    if row["survival_rate"] <= 1
                    else row["survival_rate"]
                ),
                1,
            ),
            _fmt(row["mean_time_to_stabilize"], 2),
            _fmt(row["max_peak_joint_torque"], 1),
            str(int(row["triggered_count"])),
            str(int(row["survival_count"])),
        ]
        lines.append("| " + " | ".join(vals) + " |")

    lines.append("")
    comp_path = output_dir / "COMPARISON.md"
    comp_path.write_text("\n".join(lines))
    print(f"[postmortem_digest] wrote {comp_path}")
    return comp_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generate postmortem digest from stability eval artifacts."
    )
    parser.add_argument(
        "run_dirs",
        nargs="*",
        type=Path,
        help="One or more run output directories containing stability_eval_results.csv",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="Produce COMPARISON.md across multiple runs",
    )
    parser.add_argument(
        "--baseline-config",
        type=Path,
        default=None,
        help="Path to baseline YAML config for diff",
    )
    parser.add_argument(
        "--top-n",
        type=int,
        default=DEFAULT_TOP_N,
        help=f"Number of worst conditions to flag (default {DEFAULT_TOP_N})",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Override output directory (default: ~/Downloads/postmortem_digests/MMDD_HHMM/)",
    )
    parser.add_argument(
        "--remote",
        action="append",
        default=[],
        help="Pull run dir from remote before digest (format: ssh_alias:/absolute/path). "
        "Can be passed multiple times.",
    )
    parser.add_argument(
        "--keep-local",
        action="store_true",
        help="Keep local staging directory created by --remote pulls.",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Validate artifact presence and schema, then exit without generating digests.",
    )
    parser.add_argument(
        "--video-map",
        type=Path,
        default=None,
        help="Optional JSON manifest keyed by run_label to resolve video paths.",
    )

    args = parser.parse_args()
    if not args.run_dirs and not args.remote:
        parser.error("Provide at least one local run_dir or one --remote source.")

    staging_root: Optional[Path] = None
    try:
        all_run_dirs: List[Path] = list(args.run_dirs)
        if args.remote:
            try:
                pulled_dirs, staging_root = pull_remote_run_dirs(
                    args.remote, args.keep_local
                )
            except Exception as e:
                raise SystemExit(f"[postmortem_digest] ERROR pulling remote artifacts: {e}")
            all_run_dirs.extend(pulled_dirs)

        valid_dirs: List[Path] = []
        for rd in all_run_dirs:
            if not rd.is_dir():
                print(f"[postmortem_digest] WARNING: {rd} is not a directory, skipping")
                continue
            valid_dirs.append(rd)

        if not valid_dirs:
            raise SystemExit("No valid run directories found.")

        video_map: Optional[Dict[str, List[Dict[str, str]]]] = None
        if args.video_map:
            try:
                video_map = load_video_map(args.video_map)
                print(
                    f"[postmortem_digest] loaded video map: {args.video_map} "
                    f"({len(video_map)} run labels)"
                )
            except Exception as e:
                raise SystemExit(f"[postmortem_digest] ERROR loading --video-map: {e}")

        if args.validate:
            print(f"[postmortem_digest] validating {len(valid_dirs)} run directories")
            all_ok = True
            for rd in valid_dirs:
                ok, issues = validate_run_dir(rd)
                status = "OK" if ok else "FAIL"
                print(f"[postmortem_digest] [{status}] {rd}")
                for issue in issues:
                    print(f"  - {issue}")
                all_ok = all_ok and ok
            if all_ok:
                print("[postmortem_digest] validation passed")
                return
            raise SystemExit(1)

        if args.output_dir:
            output_dir = args.output_dir
        else:
            stamp = datetime.now().strftime("%m%d_%H%M")
            output_dir = OUTPUT_ROOT / stamp

        output_dir.mkdir(parents=True, exist_ok=True)

        processed_dirs: List[Path] = []
        for rd in valid_dirs:
            try:
                assemble_digest(
                    rd,
                    output_dir,
                    args.baseline_config,
                    args.top_n,
                    video_map=video_map,
                )
                processed_dirs.append(rd)
            except Exception as e:
                print(f"[postmortem_digest] ERROR processing {rd}: {e}")

        if args.compare and len(processed_dirs) >= 2:
            try:
                assemble_comparison(processed_dirs, output_dir)
            except Exception as e:
                print(f"[postmortem_digest] ERROR in comparison: {e}")

        print(f"[postmortem_digest] output directory: {output_dir}")
    finally:
        if staging_root and staging_root.exists() and not args.keep_local:
            shutil.rmtree(staging_root, ignore_errors=True)
            print(f"[postmortem_digest] cleaned staging directory: {staging_root}")


if __name__ == "__main__":
    main()

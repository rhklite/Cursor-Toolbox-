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
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import pandas as pd
    import numpy as np
except ImportError:
    sys.exit("pandas and numpy are required: pip install pandas numpy")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

OUTPUT_ROOT = Path.home() / "Downloads" / "postmortem_digests"
KEYFRAME_COUNT = 6
KEYFRAME_COLS = 3
KEYFRAME_ROWS = 2
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


# ---------------------------------------------------------------------------
# Detect sweep mode
# ---------------------------------------------------------------------------


def detect_sweep_cols(df: pd.DataFrame) -> Tuple[str, ...]:
    if "push_ang_magnitude" in df.columns:
        return ANGULAR_SWEEP_COLS
    return LINEAR_SWEEP_COLS


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


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def generate_keyframe_grid(
    video_path: Path, output_path: Path, n_frames: int = KEYFRAME_COUNT
) -> bool:
    """Extract evenly-spaced keyframes and tile into a grid image."""
    if not ffmpeg_available():
        print("[postmortem_digest] ffmpeg not found, skipping video grid")
        return False

    # select=expr filters n_frames evenly across the video using scene-agnostic
    # frame numbering; the tile filter assembles them into COLS x ROWS.
    select_expr = "+".join([f"eq(n\\,{i})" for i in range(n_frames)])

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

    select_expr = "+".join([f"eq(n\\,{idx})" for idx in indices])

    cmd = [
        "ffmpeg",
        "-i",
        str(video_path),
        "-vf",
        f"select='{select_expr}',tile={KEYFRAME_COLS}x{KEYFRAME_ROWS}",
        "-vsync",
        "vfr",
        "-frames:v",
        "1",
        "-y",
        str(output_path),
    ]
    try:
        subprocess.run(cmd, capture_output=True, timeout=120, check=True)
        return True
    except subprocess.CalledProcessError as e:
        print(
            f"[postmortem_digest] ffmpeg grid failed: {e.stderr[:200] if e.stderr else ''}"
        )
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


def format_header(metric_json: Dict[str, Any], run_dir: Path) -> str:
    lines = [
        f"# Postmortem Digest: {run_dir.name}",
        "",
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
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

    headers = ["metric", "mean", "std"]
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
            lines.append(f"| {col} | {_fmt(m, 3)} | {_fmt(s, 3)} |")

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


# ---------------------------------------------------------------------------
# Assembler
# ---------------------------------------------------------------------------


def assemble_digest(
    run_dir: Path,
    output_dir: Path,
    baseline_config: Optional[Path],
    top_n: int,
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

    run_basename = run_dir.name
    digest_name = f"DIGEST_{run_basename}.md"
    digest_path = output_dir / digest_name

    video = find_video(run_dir)
    grid_path = None
    if video:
        grid_path = output_dir / f"grid_{run_basename}.png"
        if not generate_keyframe_grid(video, grid_path):
            grid_path = None

    sections = [
        format_header(metric_json, run_dir),
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
                "run_name": rd.name,
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
        nargs="+",
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

    args = parser.parse_args()

    if args.output_dir:
        output_dir = args.output_dir
    else:
        stamp = datetime.now().strftime("%m%d_%H%M")
        output_dir = OUTPUT_ROOT / stamp

    output_dir.mkdir(parents=True, exist_ok=True)

    for rd in args.run_dirs:
        if not rd.is_dir():
            print(f"[postmortem_digest] WARNING: {rd} is not a directory, skipping")
            continue
        try:
            assemble_digest(rd, output_dir, args.baseline_config, args.top_n)
        except Exception as e:
            print(f"[postmortem_digest] ERROR processing {rd}: {e}")

    if args.compare and len(args.run_dirs) >= 2:
        valid_dirs = [rd for rd in args.run_dirs if rd.is_dir()]
        if len(valid_dirs) >= 2:
            try:
                assemble_comparison(valid_dirs, output_dir)
            except Exception as e:
                print(f"[postmortem_digest] ERROR in comparison: {e}")

    print(f"[postmortem_digest] output directory: {output_dir}")


if __name__ == "__main__":
    main()

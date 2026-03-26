#!/usr/bin/env python3
"""Assemble flat eval outputs into a standardized report tree.

Usage:
    python report_assembler.py \
        --hypothesis-slug stability-curriculum-push-ramp-v2 \
        --model-label model_7027 \
        --grid-dirs /path/to/linear_grid /path/to/angular_grid \
        --video-dirs /path/to/video_dir_1 /path/to/video_dir_2 \
        --output-root /Users/HanHu/software/motion_rl/docs/reports/
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple


ARTIFACT_NAMES = [
    "stability_eval_results.csv",
    "torque_limits.csv",
    "metric.json",
    "vel_traces.npz",
]


def derive_slug(hypothesis_source: str) -> str:
    """Derive a slug from a hypothesis filename or text."""
    name = (
        Path(hypothesis_source).stem
        if hypothesis_source.endswith(".md")
        else hypothesis_source
    )
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if len(slug) > 60:
        slug = slug[:60].rsplit("-", 1)[0]
    return slug


def detect_mode(grid_dir: Path) -> str:
    """Detect linear or angular mode from dir name or CSV schema."""
    dir_name = grid_dir.name.lower()
    if "angular" in dir_name:
        return "angular"
    if "linear" in dir_name:
        return "linear"

    csv_path = grid_dir / "stability_eval_results.csv"
    if csv_path.exists():
        import pandas as pd

        df = pd.read_csv(csv_path, nrows=0)
        if "push_ang_magnitude" in df.columns:
            return "angular"
    return "linear"


def _fmt_num(v: float) -> str:
    """0.5 -> 0p5, 0.25 -> 0p25, -0.5 -> n0p5."""
    return f"{v:.2g}".replace(".", "p").replace("-", "n")


def _make_linear_slug(magnitude: float, direction: float) -> str:
    return f"lin_m{_fmt_num(magnitude)}_d{int(direction)}"


def _make_angular_slug(magnitude: float, axis: str) -> str:
    safe_axis = axis.replace("+", "p").replace("-", "n").replace(" ", "")
    return f"ang_m{_fmt_num(magnitude)}_{safe_axis}"


def move_artifact_files(src_dir: Path, dest_dir: Path) -> None:
    """Move canonical artifact files to destination directory."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    for name in ARTIFACT_NAMES:
        src = src_dir / name
        if src.exists():
            shutil.move(str(src), str(dest_dir / name))
    _cleanup_source_dir(src_dir)


def classify_video_dir(video_dir: Path) -> Tuple[str, str, bool]:
    """Read one-row video CSV and return mode, condition slug, survived."""
    import pandas as pd

    csv_path = video_dir / "stability_eval_results.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"No CSV in video dir {video_dir}")

    df = pd.read_csv(csv_path)
    if df.empty:
        raise ValueError(f"CSV has no rows in video dir {video_dir}")
    row = df.iloc[0]

    if "push_ang_magnitude" in df.columns:
        mode = "angular"
        mag = float(row["push_ang_magnitude"])
        axis = str(row["push_ang_axis"])
        slug = _make_angular_slug(mag, axis)
    else:
        mode = "linear"
        mag = float(row["push_magnitude"])
        direction = float(row["push_direction"])
        slug = _make_linear_slug(mag, direction)

    survived = bool(row.get("survived", False))
    return mode, slug, survived


def move_video_file(video_dir: Path, dest_dir: Path, slug: str) -> None:
    """Move mp4 from video dir to destination using condition slug."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    mp4s = list(video_dir.glob("*.mp4"))
    if not mp4s:
        print(f"[report_assembler] WARNING: no .mp4 in {video_dir}")
        return

    shutil.move(str(mp4s[0]), str(dest_dir / f"{slug}.mp4"))
    _cleanup_source_dir(video_dir, remove_all_if_nonempty=True)


def _cleanup_source_dir(src_dir: Path, remove_all_if_nonempty: bool = False) -> None:
    """Remove source dir when safe, or aggressively when requested."""
    if not src_dir.exists():
        return

    remaining = list(src_dir.iterdir())
    if not remaining:
        src_dir.rmdir()
        print(f"[report_assembler] removed emptied source dir: {src_dir}")
        return

    if remove_all_if_nonempty:
        shutil.rmtree(src_dir)
        print(f"[report_assembler] removed source dir: {src_dir}")
        return

    allowed_suffixes = {".png"}
    allowed_names = {".DS_Store"}
    if all(p.suffix in allowed_suffixes or p.name in allowed_names for p in remaining):
        shutil.rmtree(src_dir)
        print(f"[report_assembler] removed source dir: {src_dir}")


def generate_charts(
    grid_dirs_by_mode: Dict[str, Path],
    model_label: str,
    graphics_dir: Path,
) -> int:
    """Call postmortem_charts.py on assembled artifact directories."""
    graphics_dir.mkdir(parents=True, exist_ok=True)
    chart_script = Path.home() / ".cursor" / "scripts" / "postmortem_charts.py"

    run_dirs: List[Path] = []
    labels: List[str] = []
    for mode in sorted(grid_dirs_by_mode.keys()):
        run_dirs.append(grid_dirs_by_mode[mode])
        labels.append(f"{model_label}_{mode}")

    if not run_dirs:
        print("[report_assembler] WARNING: no grid dirs available for chart generation")
        return 2

    cmd = [
        sys.executable,
        str(chart_script),
        *[str(rd) for rd in run_dirs],
        "--output-dir",
        str(graphics_dir),
        "--run-labels",
        ",".join(labels),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[report_assembler] WARNING: chart generation failed:")
        if result.stderr.strip():
            print(result.stderr.strip())
        return 2

    print(f"[report_assembler] charts generated in {graphics_dir}")
    return 0


def _validate_required_grid_inputs(grid_dir: Path) -> bool:
    """Return True when minimal required grid inputs exist."""
    required = grid_dir / "stability_eval_results.csv"
    return required.exists()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Assemble flat eval outputs into standardized report tree."
    )
    parser.add_argument(
        "--hypothesis-slug",
        type=str,
        required=True,
        help="Slug from hypothesis filename (e.g. stability-curriculum-push-ramp-v2)",
    )
    parser.add_argument(
        "--model-label",
        type=str,
        required=True,
        help="Human-readable model label for subfolder naming (e.g. model_7027)",
    )
    parser.add_argument(
        "--grid-dirs",
        nargs="+",
        type=Path,
        required=True,
        help="One or two grid eval output dirs (linear and/or angular)",
    )
    parser.add_argument(
        "--video-dirs",
        nargs="*",
        type=Path,
        default=[],
        help="Zero or more per-condition video eval output dirs",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        required=True,
        help="Parent dir for the report folder (e.g. docs/reports/)",
    )
    parser.add_argument(
        "--timestamp",
        type=str,
        default=None,
        help="Override timestamp YYYYMMDD_HHMM. Default: current time.",
    )
    parser.add_argument(
        "--skip-charts",
        action="store_true",
        help="Skip chart generation (useful if charts are generated separately)",
    )
    args = parser.parse_args()

    ts = args.timestamp or datetime.now().strftime("%Y%m%d_%H%M")
    report_dir = args.output_root / f"{args.hypothesis_slug}_{ts}"
    report_dir.mkdir(parents=True, exist_ok=True)

    for sub in ["artifacts", "videos", "graphics"]:
        (report_dir / sub / args.model_label).mkdir(parents=True, exist_ok=True)

    grid_dirs_by_mode: Dict[str, Path] = {}
    for gd in args.grid_dirs:
        if not gd.is_dir():
            print(f"[report_assembler] ERROR: grid dir does not exist: {gd}")
            return 1
        if not _validate_required_grid_inputs(gd):
            print(
                "[report_assembler] ERROR: missing stability_eval_results.csv in "
                f"{gd}"
            )
            return 1

        mode = detect_mode(gd)
        dest = report_dir / "artifacts" / args.model_label / mode
        move_artifact_files(gd, dest)
        grid_dirs_by_mode[mode] = dest

    for vd in args.video_dirs:
        if not vd.is_dir():
            print(
                f"[report_assembler] WARNING: video dir does not exist, skipping: {vd}"
            )
            continue
        try:
            mode, condition_slug, survived = classify_video_dir(vd)
        except Exception as exc:  # noqa: BLE001
            print(
                f"[report_assembler] WARNING: could not classify video dir {vd}: {exc}"
            )
            continue

        outcome = "success" if survived else "failure"
        dest = report_dir / "videos" / args.model_label / mode / outcome
        move_video_file(vd, dest, condition_slug)

    chart_rc = 0
    if not args.skip_charts:
        graphics_dir = report_dir / "graphics" / args.model_label
        chart_rc = generate_charts(grid_dirs_by_mode, args.model_label, graphics_dir)

    print(f"[report_assembler] report tree: {report_dir}")
    print(
        f"[report_assembler] artifacts: {len(args.grid_dirs)} grid dirs processed, "
        f"videos: {len(args.video_dirs)} video dirs processed"
    )

    if chart_rc == 2:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

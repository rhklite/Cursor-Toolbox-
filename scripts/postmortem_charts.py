#!/usr/bin/env python3
"""Deterministic postmortem chart generator for stability eval runs.

Reads stability_eval_results.csv, torque_limits.csv, metric.json, and
vel_traces.npz from one or more run directories. Produces all Tier 1 and
Tier 4 visual artifacts as PNGs with fixed filenames.

Usage:
    python postmortem_charts.py /path/to/run_dir --output-dir /path/to/out
    python postmortem_charts.py dir1 dir2 --run-labels center,tslv_080 --output-dir out
    python postmortem_charts.py dir1 --tier1          # Tier 1 charts only
    python postmortem_charts.py dir1 --tier4          # Tier 4 charts only
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

try:
    import pandas as pd
except ImportError:
    sys.exit("pandas is required: pip install pandas")

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

LINEAR_SWEEP_COLS = ("speed", "push_magnitude", "push_direction")
ANGULAR_SWEEP_COLS = ("speed", "push_ang_magnitude", "push_ang_axis")

TIER4_METRICS = [
    "peak_excursion_pitch",
    "peak_excursion_roll",
    "peak_angular_velocity",
    "corrective_step_count",
    "action_smoothness_rms",
    "final_posture_offset",
]

TIER4_THRESHOLDS = {
    "peak_excursion_pitch": {"warn": 0.15, "unit": "rad"},
    "peak_excursion_roll": {"warn": 0.10, "unit": "rad"},
    "peak_angular_velocity": {"warn": 2.0, "unit": "rad/s"},
    "corrective_step_count": {"warn": 6.0, "unit": "steps"},
    "action_smoothness_rms": {"warn": 0.5, "unit": ""},
    "final_posture_offset": {"warn": 0.2, "unit": "rad"},
}

DPI = 150


# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------


def load_results_csv(run_dir: Path) -> pd.DataFrame:
    csv_path = run_dir / "stability_eval_results.csv"
    if not csv_path.exists():
        raise FileNotFoundError(f"No stability_eval_results.csv in {run_dir}")
    return pd.read_csv(csv_path)


def load_torque_limits(run_dir: Path) -> pd.DataFrame:
    csv_path = run_dir / "torque_limits.csv"
    if not csv_path.exists():
        return pd.DataFrame(columns=["joint_name", "torque_limit"])
    return pd.read_csv(csv_path)


def load_metric_json(run_dir: Path) -> Dict[str, Any]:
    json_path = run_dir / "metric.json"
    if not json_path.exists():
        return {}
    with open(json_path) as f:
        data = json.load(f)
    if isinstance(data, list):
        return {item["key"]: item["value"] for item in data if "key" in item}
    return data


def load_vel_traces(run_dir: Path) -> Optional[Dict]:
    """Load vel_traces.npz and return parsed structure or None."""
    npz_path = run_dir / "vel_traces.npz"
    if not npz_path.exists():
        return None

    npz = np.load(npz_path, allow_pickle=True)
    meta_arr = npz.get("__meta__")
    if meta_arr is None:
        return None

    meta = json.loads(str(meta_arr[0]))
    dt = meta["dt"]
    angular_mode = meta["angular_mode"]
    conditions = meta["conditions"]
    manifest = meta["manifest"]

    vel_traces: Dict[int, List[np.ndarray]] = {}
    for ci_str, n_trials in manifest.items():
        ci = int(ci_str)
        traces = []
        for ti in range(n_trials):
            key = f"cond_{ci}_trial_{ti}"
            if key in npz:
                traces.append(npz[key])
        vel_traces[ci] = traces

    return {
        "dt": dt,
        "angular_mode": angular_mode,
        "conditions": conditions,
        "traces": vel_traces,
    }


def detect_sweep_mode(df: pd.DataFrame) -> Tuple[bool, str, str, str]:
    """Returns (angular_mode, mag_key, dir_key, dir_label)."""
    if "push_ang_magnitude" in df.columns:
        return True, "push_ang_magnitude", "push_ang_axis", "Axis"
    return False, "push_magnitude", "push_direction", "Direction"


def run_label_from_path(run_dir: Path) -> str:
    return run_dir.name


# ---------------------------------------------------------------------------
# Chart 1: Tier 1 Dashboard
# ---------------------------------------------------------------------------


def chart_tier1_dashboard(
    run_dirs: List[Path],
    labels: List[str],
    output_dir: Path,
) -> Path:
    """Grouped bar chart comparing survival rate, mean TTS, max peak torque."""
    n_runs = len(run_dirs)
    survival_rates = []
    mean_tts_vals = []
    max_pjt_vals = []

    for rd in run_dirs:
        metric = load_metric_json(rd)
        df = load_results_csv(rd)
        triggered = df[df["triggered"] == True]  # noqa: E712
        survived = triggered[triggered["survived"] == True]  # noqa: E712

        sr = metric.get("survival_rate", len(survived) / max(len(triggered), 1))
        if sr <= 1.0:
            sr *= 100.0
        survival_rates.append(sr)

        tts = survived["time_to_stabilize"].dropna()
        mean_tts_vals.append(tts.mean() if len(tts) else float("nan"))

        pjt = triggered["peak_joint_torque"].dropna()
        max_pjt_vals.append(pjt.max() if len(pjt) else float("nan"))

    fig, ax1 = plt.subplots(figsize=(max(6, 2.5 * n_runs), 5))

    x = np.arange(n_runs)
    bar_w = 0.25

    bars_sr = ax1.bar(
        x - bar_w, survival_rates, bar_w, label="Survival Rate (%)", color="#2196F3"
    )

    tts_display = [
        v if not (isinstance(v, float) and math.isnan(v)) else 0 for v in mean_tts_vals
    ]
    bars_tts = ax1.bar(x, tts_display, bar_w, label="Mean TTS (s)", color="#4CAF50")

    ax1.set_ylabel("Survival Rate (%) / TTS (s)", fontsize=11)
    ax1.set_xticks(x)
    ax1.set_xticklabels(labels, fontsize=9, rotation=30, ha="right")
    ax1.set_ylim(bottom=0)

    ax2 = ax1.twinx()
    pjt_display = [
        v if not (isinstance(v, float) and math.isnan(v)) else 0 for v in max_pjt_vals
    ]
    bars_pjt = ax2.bar(
        x + bar_w, pjt_display, bar_w, label="Max Peak Torque (Nm)", color="#FF9800"
    )
    ax2.set_ylabel("Max Peak Joint Torque (Nm)", fontsize=11)

    for bar_set, vals in [
        (bars_sr, survival_rates),
        (bars_tts, tts_display),
        (bars_pjt, pjt_display),
    ]:
        for bar, val in zip(bar_set, vals):
            if val and not (isinstance(val, float) and math.isnan(val)):
                ax1_or_2 = ax2 if bar_set is bars_pjt else ax1
                ax1_or_2.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_height(),
                    f"{val:.1f}",
                    ha="center",
                    va="bottom",
                    fontsize=7,
                )

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc="upper left", fontsize=8)

    fig.suptitle("Tier 1 Metrics Dashboard", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.94])

    out_path = output_dir / "tier1_dashboard.png"
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print(f"[postmortem_charts] saved {out_path.name}")
    return out_path


# ---------------------------------------------------------------------------
# Chart 2: Survival Heatmap
# ---------------------------------------------------------------------------


def chart_survival_heatmap(
    df: pd.DataFrame,
    run_label: str,
    output_dir: Path,
) -> List[Path]:
    """Per-run survival rate heatmap, one per detected sweep mode."""
    angular, mag_key, dir_key, dir_label = detect_sweep_mode(df)
    mode = "angular" if angular else "linear"

    triggered = df[df["triggered"] == True]  # noqa: E712
    if triggered.empty:
        return []

    magnitudes = sorted(triggered[mag_key].unique())
    directions = sorted(triggered[dir_key].unique(), key=str)

    grid = np.full((len(magnitudes), len(directions)), np.nan)
    annot = [[" "] * len(directions) for _ in range(len(magnitudes))]

    for ri, mv in enumerate(magnitudes):
        for ci, dv in enumerate(directions):
            mask = (triggered[mag_key] == mv) & (triggered[dir_key] == dv)
            cell = triggered[mask]
            if len(cell) == 0:
                continue
            n_surv = cell["survived"].sum()
            n_total = len(cell)
            rate = n_surv / n_total * 100.0
            grid[ri, ci] = rate
            annot[ri][ci] = f"{int(n_surv)}/{n_total}\n{rate:.0f}%"

    fig, ax = plt.subplots(
        figsize=(max(8, len(directions) * 1.5), max(5, len(magnitudes) * 0.8))
    )
    im = ax.imshow(
        grid,
        aspect="auto",
        origin="lower",
        cmap="RdYlGn",
        vmin=0,
        vmax=100,
        extent=[-0.5, len(directions) - 0.5, -0.5, len(magnitudes) - 0.5],
    )

    for ri in range(len(magnitudes)):
        for ci in range(len(directions)):
            txt = annot[ri][ci]
            if txt.strip():
                val = grid[ri, ci]
                color = "white" if (not np.isnan(val) and val < 40) else "black"
                ax.text(ci, ri, txt, ha="center", va="center", fontsize=7, color=color)

    ax.set_xticks(range(len(directions)))
    if not angular:
        dir_labels = [f"{int(float(d))}\u00b0" for d in directions]
    else:
        dir_labels = [str(d) for d in directions]
    ax.set_xticklabels(dir_labels, fontsize=9)
    ax.set_yticks(range(len(magnitudes)))
    mag_unit = "rad/s" if angular else "m/s"
    ax.set_yticklabels([f"{m:.2g}" for m in magnitudes], fontsize=9)
    ax.set_xlabel(dir_label, fontsize=12)
    ax.set_ylabel(f"Magnitude ({mag_unit})", fontsize=12)

    push_type = "Angular" if angular else "Linear"
    ax.set_title(
        f"{run_label} -- {push_type} Survival Rate (%)",
        fontsize=14,
        fontweight="bold",
    )
    fig.colorbar(im, ax=ax, label="Survival Rate (%)", shrink=0.8)
    fig.tight_layout()

    fname = f"survival_heatmap_{run_label}_{mode}.png"
    out_path = output_dir / fname
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print(f"[postmortem_charts] saved {fname}")
    return [out_path]


# ---------------------------------------------------------------------------
# Chart 3: Torque Heatmaps (from CSV)
# ---------------------------------------------------------------------------


def chart_torque_heatmaps(
    df: pd.DataFrame,
    run_label: str,
    output_dir: Path,
) -> List[Path]:
    """Peak torque and peak torque rate heatmaps from CSV columns."""
    angular, mag_key, dir_key, dir_label = detect_sweep_mode(df)
    mode = "angular" if angular else "linear"
    push_type = "Angular" if angular else "Linear"

    triggered = df[df["triggered"] == True].copy()  # noqa: E712
    if triggered.empty:
        return []

    pct_cols = [c for c in triggered.columns if c.startswith("peak_torque_pct_")]
    rate_cols = [c for c in triggered.columns if c.startswith("peak_torque_rate_")]
    dof_names = [c.replace("peak_torque_pct_", "") for c in pct_cols]

    magnitudes = sorted(triggered[mag_key].unique())
    directions = sorted(triggered[dir_key].unique(), key=str)

    def _build_grid(metric_fn):
        grid = np.full((len(magnitudes), len(directions)), np.nan)
        for ri, mv in enumerate(magnitudes):
            for ci, dv in enumerate(directions):
                mask = (triggered[mag_key] == mv) & (triggered[dir_key] == dv)
                cell = triggered[mask]
                if len(cell):
                    grid[ri, ci] = metric_fn(cell)
        return grid

    def _max_pct(cell: pd.DataFrame) -> float:
        vals = cell[pct_cols].values.flatten()
        vals = vals[~np.isnan(vals)]
        return float(np.max(vals) * 100.0) if len(vals) else 0.0

    def _max_rate(cell: pd.DataFrame) -> float:
        if not rate_cols:
            return 0.0
        vals = cell[rate_cols].values.flatten()
        vals = vals[~np.isnan(vals)]
        return float(np.max(vals)) if len(vals) else 0.0

    def _any_at_limit(cell: pd.DataFrame) -> bool:
        vals = cell[pct_cols].values.flatten()
        vals = vals[~np.isnan(vals)]
        return bool(np.any(vals >= 0.99))

    outputs = []
    for metric_name, metric_fn, vmax_val, unit in [
        ("Peak Torque", _max_pct, 100.0, "% of URDF limit"),
        ("Peak Torque Rate", _max_rate, None, "Nm/s"),
    ]:
        grid = _build_grid(metric_fn)
        fig, ax = plt.subplots(figsize=(10, 7))
        vmax = (
            vmax_val
            if vmax_val
            else float(np.nanmax(grid)) if not np.all(np.isnan(grid)) else 1.0
        )
        im = ax.imshow(
            grid,
            aspect="auto",
            origin="lower",
            cmap="YlOrRd",
            vmin=0,
            vmax=vmax,
            extent=[-0.5, len(directions) - 0.5, -0.5, len(magnitudes) - 0.5],
        )

        ax.set_xticks(range(len(directions)))
        if not angular:
            x_labels = [f"{int(float(d))}\u00b0" for d in directions]
        else:
            x_labels = [str(d) for d in directions]
        ax.set_xticklabels(x_labels, fontsize=9)
        ax.set_yticks(range(len(magnitudes)))
        mag_unit = "rad/s" if angular else "m/s"
        ax.set_yticklabels([f"{m:.2g}" for m in magnitudes], fontsize=9)
        ax.set_xlabel(dir_label, fontsize=12)
        ax.set_ylabel(f"Magnitude ({mag_unit})", fontsize=12)
        ax.set_title(
            f"{push_type} Push -- Max {metric_name} ({unit})",
            fontsize=14,
            fontweight="bold",
        )

        fig.colorbar(im, ax=ax, label=f"Max {metric_name.lower()} ({unit})", shrink=0.8)

        if metric_name == "Peak Torque":
            for ri, mv in enumerate(magnitudes):
                for ci, dv in enumerate(directions):
                    mask = (triggered[mag_key] == mv) & (triggered[dir_key] == dv)
                    cell = triggered[mask]
                    if len(cell) and _any_at_limit(cell):
                        ax.text(
                            ci,
                            ri,
                            "1",
                            ha="center",
                            va="center",
                            fontsize=9,
                            fontweight="bold",
                            color="white",
                            bbox=dict(boxstyle="square,pad=0.1", fc="red", ec="none"),
                        )

        fig.tight_layout()
        safe_name = metric_name.lower().replace(" ", "_")
        if run_label:
            fname = f"{run_label}_{mode}_{safe_name}.png"
        else:
            fname = f"heatmap_{mode}_{safe_name}.png"
        out_path = output_dir / fname
        fig.savefig(out_path, dpi=DPI)
        plt.close(fig)
        print(f"[postmortem_charts] saved {fname}")
        outputs.append(out_path)

    return outputs


# ---------------------------------------------------------------------------
# Chart 4: Deceleration Profiles (from NPZ)
# ---------------------------------------------------------------------------


def chart_deceleration_profiles(
    vel_data: Dict,
    run_label: str,
    output_dir: Path,
) -> Optional[Path]:
    """Mean +/- std velocity magnitude vs time post-failure."""
    dt = vel_data["dt"]
    angular_mode = vel_data["angular_mode"]
    conditions = vel_data["conditions"]
    traces = vel_data["traces"]
    mode = "angular" if angular_mode else "linear"
    mag_unit = "rad/s" if angular_mode else "m/s"

    cond_by_mag: Dict[float, List[int]] = defaultdict(list)
    for ci, cond in enumerate(conditions):
        cond_by_mag[float(cond[1])].append(ci)

    magnitudes = sorted(cond_by_mag.keys())
    if not magnitudes:
        return None

    fig, axes = plt.subplots(
        1, len(magnitudes), figsize=(5 * len(magnitudes), 4), squeeze=False
    )
    for idx, mag_val in enumerate(magnitudes):
        ax = axes[0, idx]
        all_traces = []
        for ci in cond_by_mag.get(mag_val, []):
            all_traces.extend(traces.get(ci, []))

        if not all_traces:
            ax.set_title(f"mag={mag_val:.2g} {mag_unit}\n(no data)")
            continue

        max_len = max(len(v) for v in all_traces)
        padded = np.full((len(all_traces), max_len), np.nan)
        for j, v in enumerate(all_traces):
            padded[j, : len(v)] = v
        mean_v = np.nanmean(padded, axis=0)
        std_v = np.nanstd(padded, axis=0)
        t = np.arange(max_len) * dt

        ax.plot(t, mean_v, color="#1565C0", linewidth=1.5)
        ax.fill_between(t, mean_v - std_v, mean_v + std_v, alpha=0.2, color="#1565C0")
        ax.set_xlabel("Time after T_fail (s)")
        ax.set_ylabel("Base velocity (m/s)")
        ax.set_title(f"mag={mag_val:.2g} {mag_unit}")
        ax.set_ylim(bottom=0)
        ax.grid(True, alpha=0.3)

    fig.suptitle("Deceleration Profile (post T_fail)", fontsize=14, fontweight="bold")
    fig.tight_layout(rect=[0, 0, 1, 0.94])

    fname = f"deceleration_profiles_{mode}.png"
    out_path = output_dir / fname
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print(f"[postmortem_charts] saved {fname}")
    return out_path


# ---------------------------------------------------------------------------
# Chart 5: Velocity Tracking Error (from NPZ)
# ---------------------------------------------------------------------------


def chart_velocity_tracking_error(
    vel_data: Dict,
    run_label: str,
    output_dir: Path,
) -> Optional[Path]:
    """Mean (actual - commanded) velocity vs time, colored by speed."""
    dt = vel_data["dt"]
    angular_mode = vel_data["angular_mode"]
    conditions = vel_data["conditions"]
    traces = vel_data["traces"]
    mode = "angular" if angular_mode else "linear"
    mag_unit = "rad/s" if angular_mode else "m/s"

    cond_by_mag: Dict[float, List[int]] = defaultdict(list)
    for ci, cond in enumerate(conditions):
        cond_by_mag[float(cond[1])].append(ci)

    magnitudes = sorted(cond_by_mag.keys())
    if not magnitudes:
        return None

    fig, axes = plt.subplots(
        1, len(magnitudes), figsize=(5 * len(magnitudes), 4), squeeze=False
    )
    for idx, mag_val in enumerate(magnitudes):
        ax = axes[0, idx]
        speeds_for_mag: set = set()
        traces_by_speed: Dict[float, List[np.ndarray]] = defaultdict(list)
        for ci in cond_by_mag.get(mag_val, []):
            cmd_speed = float(conditions[ci][0])
            speeds_for_mag.add(cmd_speed)
            for tr in traces.get(ci, []):
                traces_by_speed[cmd_speed].append(tr)

        if not traces_by_speed:
            ax.set_title(f"mag={mag_val:.2g} {mag_unit}\n(no data)")
            continue

        colors = plt.cm.viridis(np.linspace(0, 0.9, len(sorted(speeds_for_mag))))
        for si, (spd, col) in enumerate(zip(sorted(speeds_for_mag), colors)):
            tr_list = traces_by_speed[spd]
            if not tr_list:
                continue
            max_len = max(len(v) for v in tr_list)
            padded = np.full((len(tr_list), max_len), np.nan)
            for j, v in enumerate(tr_list):
                padded[j, : len(v)] = v
            mean_err = np.nanmean(padded, axis=0) - spd
            t = np.arange(max_len) * dt
            ax.plot(t, mean_err, linewidth=1.2, color=col, label=f"{spd:.1f} m/s")

        ax.axhline(0, color="gray", linestyle="--", alpha=0.5)
        ax.set_xlabel("Time after T_fail (s)")
        ax.set_ylabel("Velocity error (m/s)")
        ax.set_title(f"mag={mag_val:.2g} {mag_unit}")
        ax.legend(fontsize=7)
        ax.grid(True, alpha=0.3)

    fig.suptitle(
        "Velocity Tracking Error (actual - commanded)", fontsize=14, fontweight="bold"
    )
    fig.tight_layout(rect=[0, 0, 1, 0.94])

    fname = f"velocity_tracking_error_{mode}.png"
    out_path = output_dir / fname
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print(f"[postmortem_charts] saved {fname}")
    return out_path


# ---------------------------------------------------------------------------
# Chart 6: Tier 4 Flagged Metrics
# ---------------------------------------------------------------------------


def chart_tier4_flagged_metrics(
    run_dirs: List[Path],
    labels: List[str],
    output_dir: Path,
) -> Path:
    """Horizontal bar chart of Tier 4 metrics with OK/WARN threshold lines."""
    all_means: Dict[str, List[float]] = {m: [] for m in TIER4_METRICS}

    for rd in run_dirs:
        df = load_results_csv(rd)
        triggered = df[df["triggered"] == True]  # noqa: E712
        survived = triggered[triggered["survived"] == True]  # noqa: E712

        for metric in TIER4_METRICS:
            if metric in survived.columns:
                vals = survived[metric].dropna()
                all_means[metric].append(
                    float(vals.mean()) if len(vals) else float("nan")
                )
            else:
                all_means[metric].append(float("nan"))

    n_metrics = len(TIER4_METRICS)
    n_runs = len(run_dirs)
    fig_height = max(4, n_metrics * 0.6 * max(1, n_runs * 0.4))
    fig, ax = plt.subplots(figsize=(10, fig_height))

    y_positions = np.arange(n_metrics)
    bar_height = 0.8 / max(n_runs, 1)

    for ri, label in enumerate(labels):
        offsets = y_positions + (ri - n_runs / 2 + 0.5) * bar_height
        vals = [all_means[m][ri] for m in TIER4_METRICS]
        thresholds = [TIER4_THRESHOLDS[m]["warn"] for m in TIER4_METRICS]
        colors = []
        for v, t in zip(vals, thresholds):
            if isinstance(v, float) and math.isnan(v):
                colors.append("#BDBDBD")
            elif v <= t:
                colors.append("#4CAF50")
            else:
                colors.append("#F44336")
        display_vals = [
            v if not (isinstance(v, float) and math.isnan(v)) else 0 for v in vals
        ]
        ax.barh(
            offsets,
            display_vals,
            bar_height,
            label=label,
            color=colors,
            edgecolor="white",
            linewidth=0.5,
        )

    for i, metric in enumerate(TIER4_METRICS):
        threshold = TIER4_THRESHOLDS[metric]["warn"]
        ax.axvline(threshold, color="#FF9800", linestyle="--", linewidth=1, alpha=0.7)
        ax.text(
            threshold,
            i + (n_metrics * 0.02),
            f" {threshold}",
            va="bottom",
            fontsize=7,
            color="#FF9800",
        )

    metric_labels = []
    for m in TIER4_METRICS:
        unit = TIER4_THRESHOLDS[m]["unit"]
        metric_labels.append(f"{m} ({unit})" if unit else m)

    ax.set_yticks(y_positions)
    ax.set_yticklabels(metric_labels, fontsize=9)
    ax.set_xlabel("Aggregate Mean (survived trials)", fontsize=11)
    ax.set_title("Tier 4 Flagged Metrics", fontsize=14, fontweight="bold")
    ax.invert_yaxis()
    ax.grid(True, axis="x", alpha=0.3)

    if n_runs > 1:
        ax.legend(fontsize=8, loc="lower right")

    fig.tight_layout()
    out_path = output_dir / "tier4_flagged_metrics.png"
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print(f"[postmortem_charts] saved tier4_flagged_metrics.png")
    return out_path


# ---------------------------------------------------------------------------
# Chart 7: Root Height Recovery
# ---------------------------------------------------------------------------


def chart_root_height_recovery(
    run_dirs: List[Path],
    labels: List[str],
    output_dir: Path,
    target_height: float = 1.0,
) -> Path:
    """Grouped bar chart of mean final and min root height with target line."""
    final_means = []
    final_stds = []
    min_means = []

    for rd in run_dirs:
        df = load_results_csv(rd)
        triggered = df[df["triggered"] == True]  # noqa: E712
        survived = triggered[triggered["survived"] == True]  # noqa: E712

        if "final_root_height" in survived.columns and len(survived):
            vals = survived["final_root_height"].dropna()
            final_means.append(float(vals.mean()) if len(vals) else float("nan"))
            final_stds.append(float(vals.std()) if len(vals) > 1 else 0.0)
        else:
            final_means.append(float("nan"))
            final_stds.append(0.0)

        if "min_root_height" in survived.columns and len(survived):
            vals = survived["min_root_height"].dropna()
            min_means.append(float(vals.mean()) if len(vals) else float("nan"))
        else:
            min_means.append(float("nan"))

    n_runs = len(run_dirs)
    fig, ax = plt.subplots(figsize=(max(6, 2.5 * n_runs), 5))
    x = np.arange(n_runs)
    bar_w = 0.3

    colors_final = []
    for fm in final_means:
        if isinstance(fm, float) and math.isnan(fm):
            colors_final.append("#BDBDBD")
        elif fm >= 0.95:
            colors_final.append("#4CAF50")
        else:
            colors_final.append("#F44336")

    bars_final = ax.bar(
        x - bar_w / 2,
        [v if not (isinstance(v, float) and math.isnan(v)) else 0 for v in final_means],
        bar_w,
        yerr=[s for s in final_stds],
        capsize=3,
        label="Final Root Height (m)",
        color=colors_final,
        edgecolor="white",
        linewidth=0.5,
    )
    bars_min = ax.bar(
        x + bar_w / 2,
        [v if not (isinstance(v, float) and math.isnan(v)) else 0 for v in min_means],
        bar_w,
        label="Min Root Height (m)",
        color="#90CAF9",
        edgecolor="white",
        linewidth=0.5,
    )

    ax.axhline(
        target_height,
        color="#FF9800",
        linestyle="--",
        linewidth=1.5,
        label=f"Target ({target_height:.1f}m)",
    )
    ax.axhline(
        0.95,
        color="#FF9800",
        linestyle=":",
        linewidth=1,
        alpha=0.5,
        label="Warn (0.95m)",
    )

    for bar, val in zip(bars_final, final_means):
        if not (isinstance(val, float) and math.isnan(val)):
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height() + 0.005,
                f"{val:.3f}",
                ha="center",
                va="bottom",
                fontsize=7,
            )
    for bar, val in zip(bars_min, min_means):
        if not (isinstance(val, float) and math.isnan(val)):
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height() + 0.005,
                f"{val:.3f}",
                ha="center",
                va="bottom",
                fontsize=7,
            )

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9, rotation=30, ha="right")
    ax.set_ylabel("Root Height (m)", fontsize=11)
    ax.set_title("Root Height Recovery", fontsize=14, fontweight="bold")
    ax.set_ylim(
        bottom=(
            min(
                0.7,
                min(
                    v for v in min_means if not (isinstance(v, float) and math.isnan(v))
                )
                - 0.05,
            )
            if any(not (isinstance(v, float) and math.isnan(v)) for v in min_means)
            else 0.7
        ),
        top=1.1,
    )
    ax.legend(fontsize=8, loc="lower left")
    ax.grid(True, axis="y", alpha=0.3)

    fig.tight_layout()
    out_path = output_dir / "root_height_recovery.png"
    fig.savefig(out_path, dpi=DPI)
    plt.close(fig)
    print(f"[postmortem_charts] saved root_height_recovery.png")
    return out_path


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------


def generate_all(
    run_dirs: List[Path],
    labels: List[str],
    output_dir: Path,
    tier1: bool = True,
    tier4: bool = True,
) -> List[Path]:
    """Generate all requested chart types. Returns list of output paths."""
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs: List[Path] = []

    if tier1:
        outputs.append(chart_tier1_dashboard(run_dirs, labels, output_dir))

        for rd, label in zip(run_dirs, labels):
            df = load_results_csv(rd)
            outputs.extend(chart_survival_heatmap(df, label, output_dir))

    if tier4:
        for rd, label in zip(run_dirs, labels):
            df = load_results_csv(rd)
            outputs.extend(chart_torque_heatmaps(df, label, output_dir))

            vel_data = load_vel_traces(rd)
            if vel_data:
                p = chart_deceleration_profiles(vel_data, label, output_dir)
                if p:
                    outputs.append(p)
                p = chart_velocity_tracking_error(vel_data, label, output_dir)
                if p:
                    outputs.append(p)
            else:
                print(
                    f"[postmortem_charts] WARNING: no vel_traces.npz in {rd}, skipping velocity plots"
                )

        outputs.append(chart_tier4_flagged_metrics(run_dirs, labels, output_dir))

    has_height = False
    for rd in run_dirs:
        df = load_results_csv(rd)
        if "final_root_height" in df.columns:
            has_height = True
            break
    if has_height:
        outputs.append(chart_root_height_recovery(run_dirs, labels, output_dir))

    print(f"[postmortem_charts] generated {len(outputs)} charts in {output_dir}")
    return outputs


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Generate deterministic postmortem charts from stability eval artifacts."
    )
    parser.add_argument(
        "run_dirs",
        nargs="+",
        type=Path,
        help="One or more run output directories containing stability_eval_results.csv",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory to write chart PNGs into",
    )
    parser.add_argument(
        "--run-labels",
        type=str,
        default=None,
        help="Comma-separated labels for each run dir (default: directory names)",
    )
    parser.add_argument(
        "--tier1",
        action="store_true",
        help="Generate Tier 1 charts only",
    )
    parser.add_argument(
        "--tier4",
        action="store_true",
        help="Generate Tier 4 charts only",
    )

    args = parser.parse_args()

    if args.run_labels:
        labels = [s.strip() for s in args.run_labels.split(",")]
        if len(labels) != len(args.run_dirs):
            parser.error(
                f"--run-labels count ({len(labels)}) != run_dirs count ({len(args.run_dirs)})"
            )
    else:
        labels = [run_label_from_path(rd) for rd in args.run_dirs]

    do_tier1 = True
    do_tier4 = True
    if args.tier1 and not args.tier4:
        do_tier4 = False
    elif args.tier4 and not args.tier1:
        do_tier1 = False

    valid_dirs = []
    valid_labels = []
    for rd, lbl in zip(args.run_dirs, labels):
        if not rd.is_dir():
            print(f"[postmortem_charts] WARNING: {rd} is not a directory, skipping")
            continue
        if not (rd / "stability_eval_results.csv").exists():
            print(f"[postmortem_charts] WARNING: no CSV in {rd}, skipping")
            continue
        valid_dirs.append(rd)
        valid_labels.append(lbl)

    if not valid_dirs:
        sys.exit("[postmortem_charts] ERROR: no valid run directories found")

    generate_all(
        valid_dirs, valid_labels, args.output_dir, tier1=do_tier1, tier4=do_tier4
    )


if __name__ == "__main__":
    main()

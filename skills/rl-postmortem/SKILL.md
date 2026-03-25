---
name: rl-postmortem
description: Post-run analysis for RL experiments. Pre-digests stability eval artifacts via batch script, then interprets the compact digest to produce a structured diagnosis with next-step suggestions. Use when the user says postmortem, analyze run, what went wrong, diagnose training, or review run results.
---

# RL Postmortem

## Role

Structured post-run analysis that extracts maximum learning from each experiment run. Pre-processes raw artifacts into a compact digest (zero LLM tokens), then interprets the digest to produce a diagnosis and next steps.

## Steps

### 0. Gather run directories and hypothesis

Prompt the user for:

1. **Run directory (or directories)** — one or more output directories from `play_stability_eval.py`, each containing `stability_eval_results.csv`, `torque_limits.csv`, `metric.json`, and optionally `.mp4` video. This can be either:
   - local path(s), or
   - isaacgym remote path(s) like `/home/huh/software/motion_rl/...` (the script will pull these locally first via `--remote isaacgym:/...`)
2. **Hypothesis** (REQUIRED) — `hypothesis.md` or a text description of: (a) what change was made and why, (b) what outcome was expected, (c) what behavior was expected in the agent
3. **Baseline config** (optional) — path to a YAML config for diff; skip if not provided
4. **Comparison mode** — ask: "Do you want a multi-run comparison digest? (only if 2+ run dirs provided)"

Rules:
- If the user provides a single run directory, scan it for the required CSV/JSON files.
- If the path looks like an isaacgym path (`/home/huh/...`) or user says artifacts are in isaacgym, treat it as remote and invoke the script with `--remote isaacgym:<path>`.
- Remote pull prerequisite: SSH alias `isaacgym` and `rsync` must be available on the host running the skill.
- Hypothesis is mandatory. Resolve using this fallback order:
  1. A `hypothesis.md` file in the run directory or provided by the user.
  2. The user provides a text description during this step.
  3. If neither, prompt: "No hypothesis found. Please describe: (a) what change you made and why, (b) what outcome you expected, (c) what behavior you expected to see in the agent." Do not proceed until provided.

Present the resolved artifact list and wait for confirmation:

> Postmortem setup:
> - Run dir(s): [paths]
> - Hypothesis: [file or first ~30 words of text]
> - Baseline config: [path or "none"]
> - Comparison mode: [yes/no]
>
> Correct?

Do not proceed until the user confirms.

### 1. Run digest script

Run the batch digest script to pre-process all artifacts. This step uses zero LLM tokens — it is pure computation.

If curated videos are stored in report-level success and failure folders, generate a video map first:

```bash
bash ~/.cursor/scripts/generate_video_manifest.sh <report_root> \
    -o <report_root>/video_manifest.json
```

Then pass `--video-map <report_root>/video_manifest.json` to the digest script commands below.

First, run schema validation:

```bash
python ~/.cursor/scripts/postmortem_digest.py <run_dir_1> [<run_dir_2> ...] \
    [--remote isaacgym:/path/to/run_1] [--remote isaacgym:/path/to/run_2] \
    [--video-map <path/to/video_manifest.json>] \
    --validate
```

Then run digest generation:

```bash
python ~/.cursor/scripts/postmortem_digest.py <run_dir_1> [<run_dir_2> ...] \
    [--remote isaacgym:/path/to/run_1] [--remote isaacgym:/path/to/run_2] \
    [--video-map <path/to/video_manifest.json>] \
    [--compare] \
    [--baseline-config <path>] \
    [--top-n 5]
```

The script writes output to `~/Downloads/postmortem_digests/{MMDD_HHMM}/`:
- `DIGEST_{run_basename}.md` per run — compact text tables with survival, torque, Tier 4 diagnostics, worst conditions
- `grid_{run_basename}.png` per run (if video exists) — 10 keyframes in auto grid layout with frame timestamps overlayed; if drawtext is unavailable, script falls back to non-timestamp grid
- `COMPARISON.md` (if --compare was passed with 2+ dirs)

**If the script fails (non-zero exit):** warn the user, then fall back to the legacy workflow described in Appendix A below. Do not silently skip.

### 1.5. Generate postmortem charts

Run the deterministic chart generator to produce all Tier 1 and Tier 4 visual artifacts. This step uses zero LLM tokens — it is pure computation.

Use the same run directories from step 0. Output charts into a `charts/` subdirectory under the digest output directory:

```bash
python ~/.cursor/scripts/postmortem_charts.py <run_dir_1> [<run_dir_2> ...] \
    --output-dir ~/Downloads/postmortem_digests/{MMDD_HHMM}/charts/ \
    [--run-labels label1,label2,...]
```

If only Tier 1 or Tier 4 charts are needed, pass `--tier1` or `--tier4` respectively. Default generates all charts.

The script produces (when artifacts are available):

- `tier1_dashboard.png` — grouped bar chart: survival rate, mean TTS, max peak torque across runs
- `survival_heatmap_{label}_{mode}.png` — per-run magnitude x direction/axis survival rate grid
- `{label}_{mode}_peak_torque.png` and `{label}_{mode}_peak_torque_rate.png` — torque heatmaps from CSV
- `deceleration_profiles_{mode}.png` — velocity vs time post-failure (requires `vel_traces.npz` in run dir)
- `velocity_tracking_error_{mode}.png` — tracking error vs time (requires `vel_traces.npz` in run dir)
- `tier4_flagged_metrics.png` — horizontal bar chart of Tier 4 metrics with OK/WARN thresholds

Run labels default to directory names. Override with `--run-labels` for multi-variant runs (e.g., `--run-labels center,tslv_065,tslv_070,tslv_080`).

**If the script fails (non-zero exit):** warn the user that charts will be unavailable. Continue with digest-only analysis. Report missing chart classes in artifact gates and data gaps.

**Do NOT generate charts ad-hoc.** All visual artifacts must come from this script to ensure consistency across postmortem sessions.

### 2. Read digest and chart artifacts

Read the following files produced by steps 1 and 1.5:

- All `DIGEST_*.md` files in the output directory
- All `grid_*.png` keyframe images (if present)
- `COMPARISON.md` (if comparison mode was requested)
- All chart PNGs in the `charts/` subdirectory (tier1_dashboard, survival_heatmap, torque heatmaps, velocity plots, flagged metrics)
- The hypothesis (file or user-provided text from step 0)

Do NOT read raw CSV files, metric.json, TensorBoard events, or training logs. The digest contains all needed data in pre-aggregated form. Do NOT generate any charts or plots yourself — use only the outputs from step 1.5.

### 3. Behavior alignment

- Read the hypothesis (from step 0).
- Extract the top-level hypothesis and each sub-hypothesis if a hierarchical hypothesis is provided.
- Extract the specific expected behavior to compare against the keyframe grids in step 4.
- If the hypothesis does not contain an explicit expected-behavior statement, infer it from the hypothesis intent and state the inference for the user to verify.

### 4. Keyframe analysis

If keyframe grid images exist in the digest output:
- Examine each grid image. The grid shows 10 evenly-spaced frames from the evaluation video in an auto layout (top-left = start, bottom-right = end).
- Describe the agent's posture and behavior progression visible in the frames.
- Compare against expected behavior from step 3.
- Note specific discrepancies and hypothesize root causes.

If no keyframe grids were produced:
- State: "No video keyframes available."
- Ask the user if they have a video to review manually, or proceed without visual analysis.

### 5. Diagnosis report

Synthesize the digest data and keyframe analysis using this standalone template:

- `docs/templates/postmortem-report-template.md`

The human-facing report must follow the template's abstract-first structure, interleaved visual evidence sections, and graceful degradation rules for missing artifacts.

The LLM-facing report must follow the text-only sectioning in the template's LLM diagnosis output.

Diagnosis interpretation rule:
- The top-level verdict is independent of sub-hypothesis attribution.
- Sub-hypothesis failures are attribution findings, not blockers.
- If the top-level passes while a sub-hypothesis is unsupported, frame it as a learning about mechanism contribution rather than an overall failure.

If comparison mode was used, include a cross-run comparison section in both human and LLM reports.

### 6. File export

Export outputs into one timestamped postmortem folder with dual-consumer structure:

- Human report:
  - `docs/experiments/postmortems/YYYYMMDD_HH/postmortem.md`
- LLM artifacts folder:
  - `docs/experiments/postmortems/YYYYMMDD_HH/llm/`
  - Include `DIGEST_*.md` files
  - Include `COMPARISON.md` when comparison mode is enabled
  - Include text-only `diagnosis.md`
- Visual artifacts organized by tier:
  - `docs/experiments/postmortems/YYYYMMDD_HH/visuals/tier1/` — copy from charts/:
    - `tier1_dashboard.png`
    - `survival_heatmap_{label}_{mode}.png` (one per run per mode)
  - `docs/experiments/postmortems/YYYYMMDD_HH/visuals/tier4/` — copy from charts/:
    - `{label}_{mode}_peak_torque.png` and `{label}_{mode}_peak_torque_rate.png`
    - `deceleration_profiles_{mode}.png`
    - `velocity_tracking_error_{mode}.png`
    - `tier4_flagged_metrics.png`
  - `docs/experiments/postmortems/YYYYMMDD_HH/visuals/keyframes/` — copy from digest output:
    - `grid_*.png` keyframe grids
  - If a visual class is unavailable (script failed or vel_traces.npz missing), report it in artifact gates and data gaps instead of failing the run

Create destination directories if missing. Do NOT generate any visuals during the export step — only copy from step 1 and step 1.5 outputs.

### 7. Key findings summary

Print a concise summary in chat:

> **KEY FINDINGS**
>
> - [3-5 bullet points: most important findings from the diagnosis]
> - Each bullet: one sentence stating a finding and its implication
> - Prioritize: what worked, what failed, single most impactful next step

The postmortem is complete after this step.

---

## Appendix A: Legacy fallback workflow

Use this workflow ONLY if the digest script in step 1 fails. This consumes significantly more tokens.

### A1. Read raw artifacts

Read all available artifacts directly:
- `stability_eval_results.csv` — per-trial metrics
- `torque_limits.csv` — joint torque limits
- `metric.json` — summary metrics
- `.mp4` video (if available)

### A2. Training dynamics analysis (if training run, not eval-only)

Analyze metrics for: reward trajectory, loss components, entropy, clip fraction, SPS, episode length, death/termination breakdown.

### A3. Video analysis

Attempt video analysis using this fallback hierarchy:

1. **Task tool with video attachment** — spawn a generalPurpose subagent with the video file.
2. **Keyframe extraction** — run ffmpeg to extract 5 frames into a `.postmortem_frames/` temp directory inside the run dir. Analyze frames. Clean up after.
3. **Manual review** — ask the user to describe what they see.

### A4. Cleanup

Remove `.postmortem_frames/` directory if created. Remove any stray frame images from the repo root.

### A5. Produce diagnosis report

Follow step 5 format from the main workflow above.

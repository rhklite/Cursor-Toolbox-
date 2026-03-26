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

### 0.5. Assemble report tree

Run the report assembler to organize pulled eval artifacts into the standardized report tree. This step uses zero LLM tokens.

Derive the hypothesis slug from the hypothesis file:
- If hypothesis is a file: strip .md extension, lowercase, replace spaces/special chars with hyphens
- If hypothesis is user-provided text: ask the user for a short slug, or auto-generate from the first 4-5 words (lowercase, hyphen-separated)

For each model being analyzed, run:

```bash
python ~/.cursor/scripts/report_assembler.py \
    --hypothesis-slug <derived-slug> \
    --model-label <model_name> \
    --grid-dirs <linear_grid_dir> <angular_grid_dir> \
    --video-dirs <video_dir_1> <video_dir_2> ... \
    --output-root /Users/HanHu/software/motion_rl/docs/reports/ \
    --timestamp <YYYYMMDD_HHMM>
```

Use the same --timestamp value for all models in the same experiment so they land in the same report folder.

After assembly, the report tree is at: `docs/reports/{slug}_{timestamp}/`
- `artifacts/{model}/linear/` and `artifacts/{model}/angular/` contain CSV/JSON/NPZ for digest and chart generation
- `videos/{model}/linear/{success|failure}/` and `videos/{model}/angular/{success|failure}/` contain per-condition .mp4 files
- `graphics/{model}/` contains all chart PNGs

Record the resolved report root path (for example: `docs/reports/stability-curriculum-push-ramp-v2_20260325_1500`) for use in later steps.

**If the assembler fails (non-zero exit):** warn the user. Fall back to using the original flat directories for steps 1, 1.5, and 6, and note this in artifact gates/data gaps.

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
python ~/.cursor/scripts/postmortem_digest.py \
    <report_root>/artifacts/<model_label>/linear \
    <report_root>/artifacts/<model_label>/angular \
    [--remote isaacgym:/path/to/run_1] [--remote isaacgym:/path/to/run_2] \
    [--video-map <path/to/video_manifest.json>] \
    --validate
```

Then run digest generation:

```bash
python ~/.cursor/scripts/postmortem_digest.py \
    <report_root>/artifacts/<model_label>/linear \
    <report_root>/artifacts/<model_label>/angular \
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

### 1.5. Verify chart generation

The report assembler (step 0.5) already generated charts into `<report_root>/graphics/<model_label>/` via postmortem_charts.py. Verify these files exist:

- `tier1_dashboard.png`
- `survival_heatmap_<model_label>_linear_linear.png` and/or `survival_heatmap_<model_label>_angular_angular.png`
- `<model_label>_linear_linear_peak_torque.png` and `<model_label>_linear_linear_peak_torque_rate.png`
- `<model_label>_angular_angular_peak_torque.png` and `<model_label>_angular_angular_peak_torque_rate.png`
- `deceleration_profiles_linear.png` and/or `deceleration_profiles_angular.png` (requires `vel_traces.npz`)
- `velocity_tracking_error_linear.png` and/or `velocity_tracking_error_angular.png` (requires `vel_traces.npz`)
- `tier4_flagged_metrics.png`

If any charts are missing (for example, `vel_traces.npz` was absent or chart generation failed), note the gaps for Data Gaps and artifact gates. Do NOT generate charts ad-hoc.

### 2. Read digest and chart artifacts

Read the following files produced by steps 1 and 1.5:

- All `DIGEST_*.md` files in the output directory
- All `grid_*.png` keyframe images (if present)
- `COMPARISON.md` (if comparison mode was requested)
- All chart PNGs in `<report_root>/graphics/<model_label>/`
- The hypothesis (file or user-provided text from step 0)

Do NOT read raw CSV files, metric.json, TensorBoard events, or training logs. The digest contains all needed data in pre-aggregated form. Do NOT generate any charts or plots yourself — use only the chart PNGs already generated by the report assembler.

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

Export the postmortem markdown and create the report-tree symlink.

- Human report:
  - Write `docs/experiments/postmortems/YYYYMMDD_HH/postmortem.md`
  - All image references in this file MUST use repo-root-absolute paths (leading `/`)
  - Example: `![tier1_dashboard](/docs/reports/{slug}_{ts}/graphics/{model}/tier1_dashboard.png)`
- LLM artifacts folder:
  - Write `docs/experiments/postmortems/YYYYMMDD_HH/llm/`
  - Include `DIGEST_*.md` files
  - Include `COMPARISON.md` when comparison mode is enabled
  - Include text-only `diagnosis.md`
- Report symlink:
  - `ln -s ../../experiments/postmortems/YYYYMMDD_HH/postmortem.md docs/reports/{slug}_{ts}/postmortem.md`
- Keyframe grids:
  - Copy `grid_*.png` into a stable report-tree location (recommended: `docs/reports/{slug}_{ts}/graphics/{model}/grid_{run_basename}.png`)

Do NOT create a `visuals/` folder under `docs/experiments/postmortems/YYYYMMDD_HH/`. All visuals live under `docs/reports/{slug}_{ts}/graphics/{model}/`.

Create destination directories if missing. Do NOT generate visuals during export — only copy digest artifacts/keyframes and write markdown.

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

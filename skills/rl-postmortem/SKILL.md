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

1. **Run directory (or directories)** — one or more output directories from `play_stability_eval.py`, each containing `stability_eval_results.csv`, `torque_limits.csv`, `metric.json`, and optionally `.mp4` video
2. **Hypothesis** (REQUIRED) — `hypothesis.md` or a text description of: (a) what change was made and why, (b) what outcome was expected, (c) what behavior was expected in the agent
3. **Baseline config** (optional) — path to a YAML config for diff; skip if not provided
4. **Comparison mode** — ask: "Do you want a multi-run comparison digest? (only if 2+ run dirs provided)"

Rules:
- If the user provides a single run directory, scan it for the required CSV/JSON files.
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

**For each run directory**, invoke in parallel:

```bash
python ~/.cursor/scripts/postmortem_digest.py <run_dir_1> [<run_dir_2> ...] \
    [--compare] \
    [--baseline-config <path>] \
    [--top-n 5]
```

The script writes output to `~/Downloads/postmortem_digests/{MMDD_HHMM}/`:
- `DIGEST_{run_basename}.md` per run — compact text tables with survival, torque, Tier 4 diagnostics, worst conditions
- `grid_{run_basename}.png` per run (if video exists) — 3x2 keyframe grid
- `COMPARISON.md` (if --compare was passed with 2+ dirs)

**If the script fails (non-zero exit):** warn the user, then fall back to the legacy workflow described in Appendix A below. Do not silently skip.

### 2. Read digest artifacts

Read the following files produced by the script:

- All `DIGEST_*.md` files in the output directory
- All `grid_*.png` keyframe images (if present)
- `COMPARISON.md` (if comparison mode was requested)
- The hypothesis (file or user-provided text from step 0)

Do NOT read raw CSV files, metric.json, TensorBoard events, or training logs. The digest contains all needed data in pre-aggregated form.

### 3. Behavior alignment

- Read the hypothesis (from step 0).
- Extract the specific expected behavior to compare against the keyframe grids in step 4.
- If the hypothesis does not contain an explicit expected-behavior statement, infer it from the hypothesis intent and state the inference for the user to verify.

### 4. Keyframe analysis

If keyframe grid images exist in the digest output:
- Examine each grid image. The grid shows 6 evenly-spaced frames from the evaluation video in a 3x2 layout (top-left = start, bottom-right = end).
- Describe the agent's posture and behavior progression visible in the frames.
- Compare against expected behavior from step 3.
- Note specific discrepancies and hypothesize root causes.

If no keyframe grids were produced:
- State: "No video keyframes available."
- Ask the user if they have a video to review manually, or proceed without visual analysis.

### 5. Diagnosis report

Synthesize the digest data and keyframe analysis into a structured report:

```
POSTMORTEM DIAGNOSIS
====================

## Run summary
- Run: [directory name(s)]
- Survival rate: [from digest]
- Triggered / total: [from digest]
- Mode: [linear / angular sweep]

## What worked
- [1-2 bullet points on positive findings from the digest]

## What failed
- [Each failure with likely root cause, informed by worst-conditions list and torque table]

## Behavior vs expectation
- Expected: [from hypothesis]
- Observed: [from keyframe analysis or digest metrics]
- Gap: [specific discrepancy and hypothesized cause]

## Torque concerns
- [Flag any joints exceeding 80% of hardware limit]
- [Flag any joints with unusually high torque rates]

## Next experiments (max 3)
1. [Concrete suggestion: what to change, why, expected effect]
2. [...]
3. [...]

## Recommendation
[One sentence: adjust rewards / adjust architecture / adjust hyperparameters / adjust curriculum / redesign observation space]
```

If comparison mode was used, add a section:

```
## Cross-run comparison
- [Summary of how runs differ on Tier 1 metrics]
- [Which variant is strongest and why]
- [What the comparison suggests for next steps]
```

### 6. File export

Write the full diagnosis report to:

- Path: `docs/experiments/postmortems/MMDD_HHMM_OP.md`
- Create `docs/experiments/postmortems/` if it does not exist

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

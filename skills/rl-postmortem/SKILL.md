---
name: rl-postmortem
description: Post-run analysis for RL experiments. Reads training metrics, logs, config, and hypothesis, analyzes training dynamics, compares behavior video against expectations, and produces a structured diagnosis with next-step suggestions. Use when the user says postmortem, analyze run, what went wrong, diagnose training, or review run results.
---

# RL Postmortem

## Role

Structured post-run analysis that extracts maximum learning from each training run. Reads all available artifacts, diagnoses what happened, and proposes concrete next steps.

## Steps

### 0. Model confirmation

Before proceeding, prompt the user: "This skill runs best on **Opus (Agent mode)**. Are you currently on Opus in Agent mode? If not, please switch before we continue."

Do not proceed to step 1 until the user confirms.

### 1. Gather artifact locations

Prompt the user to provide paths for the artifacts they have available. Present this checklist and ask them to supply whichever paths they can:

1. **Run directory** — a single directory containing some or all artifacts below
2. **Metrics** — training metrics file (e.g., `metrics.jsonl`, TensorBoard `events.out.tfevents.*`, or wandb logs)
3. **Training log** — human-readable log (e.g., `train.log`)
4. **Config** — the config used for the run (e.g., `config.yaml`, or a Python config class path)
5. **Hypothesis** (REQUIRED) — `hypothesis.md` or equivalent describing the experiment hypothesis and expected behavior
6. **Video** — video of the trained agent (e.g., `best.mp4`, evaluation recording)

Rules:
- If the user provides a run directory, scan it for artifacts not explicitly provided.
- If the user provides individual file paths without a run directory, use those directly; do not attempt auto-detection for missing artifacts — ask the user for any additional files needed.
- If the user provides neither, attempt auto-detect: find the most recently modified directory under `runs/` or `logs/` (excluding `archive/`).

**Hypothesis is mandatory.** Resolve it using this fallback order:
1. A `hypothesis.md` file found in the run directory or provided by the user.
2. The user proactively provides a text description of the hypothesis during artifact gathering.
3. If neither (1) nor (2), prompt the user: "No hypothesis file found. Please describe: (a) what change you made and why, (b) what outcome you expected, and (c) what behavior you expected to see in the agent." Do not proceed until the user provides this.

Record whether the hypothesis came from a file or from user-provided text — this affects how it is passed in the Gemini handoff (step 8).

**Artifact confirmation (blocking).** After resolving all artifacts, present the full list to the user and wait for confirmation before proceeding:

> Analyzing with the following artifacts:
> - Run directory: [path]
> - Metrics: [path]
> - Training log: [path or "not available"]
> - Config: [path]
> - Hypothesis: [file path] or [user-provided text, first ~30 words...]
> - Video: [path or "not available"]
>
> Correct?

Do not proceed to step 2 until the user confirms.

### 2. Read artifacts

Read all artifacts resolved from step 1. Accept any of these formats:

- **Metrics** — `metrics.jsonl` (one JSON object per line), TensorBoard event files, wandb logs, or `metric.json` evaluation snapshots
- **Training log** — `train.log` or equivalent human-readable log with per-update progress
- **Config** — `config.yaml`, Python config class, or wandb config
- **Hypothesis** — `hypothesis.md` or equivalent with the hypothesis, expected outcome, and expected visual behavior
- **Video** — `.mp4`, `.webm`, or `.avi` file of the trained agent

When a user-provided path overrides an auto-detected file, use the user-provided path. If any optional artifact (training log, video) is unavailable after prompting, note it and proceed with what is available. Hypothesis is not optional — it must be resolved before proceeding (see step 1).

### 3. Training dynamics analysis

Analyze the metrics and log systematically. For each dimension, report a short finding:

- **Reward trajectory**: overall trend (improving, plateaued, collapsed, oscillating), final value, best value and when it occurred, variance
- **Loss components**: policy loss stability, value loss magnitude and trend, whether losses diverged
- **Entropy**: trajectory over training — healthy decay vs premature collapse vs stuck-high
- **Clip fraction**: average and trend — too high suggests learning rate is too large, too low suggests updates are too conservative
- **SPS**: stable vs degrading over time (memory leaks, env slowdown)
- **Episode length**: trend — increasing (agent surviving longer) or stuck (not learning to avoid death)
- **Death/termination breakdown**: if logged, report the ratio of termination types over training and how they shifted

### 4. Behavior alignment

- Read the "Expected visual behavior" or "Expected outcome" from the hypothesis (file or user-provided text resolved in step 1).
- Extract the specific expected behavior to compare against the video in step 5. If the hypothesis text does not contain an explicit expected-behavior statement, infer it from the hypothesis intent and state your inference for the user to verify.

### 5. Video analysis

Attempt video analysis using the following fallback hierarchy:

**Primary — Task tool with video attachment:**
Use the video path provided by the user in step 1. If no video was provided, prompt the user: "Do you have a video of the trained agent? If so, provide the path." If no video is available, skip directly to Fallback 2.

Use the Task tool with `subagent_type: "generalPurpose"` and the `attachments` parameter pointing to the video file. Include in the prompt:
- The expected behavior from step 4
- Ask: "Watch this video of a trained RL agent. Describe the agent's behavior in detail. Then compare it against this expected behavior: [expected]. List specific discrepancies and hypothesize root causes."

**Fallback 1 — Keyframe extraction:**
If the Task tool video analysis fails or returns an error:
- Create a temporary directory: `.postmortem_frames/` inside the run directory (e.g. `runs/0315_14/.postmortem_frames/`)
- Run `ffmpeg` to extract 5 evenly-spaced frames as PNG images **into that directory** (e.g. `ffmpeg -i <video> -vf "select=..." <run_dir>/.postmortem_frames/frame_%03d.png`)
- Do NOT write frames to the repo root or any directory outside `.postmortem_frames/`
- Analyze the extracted frames for visible behavior patterns

**Fallback 2 — Manual review prompt:**
If both above fail:
- State: "Video analysis unavailable. Please review the video manually."
- Provide the video file path
- Ask the user to describe what they see, then proceed with their description

Report:
- What behavior the video actually shows
- Discrepancies from the expected behavior
- Hypothesized causes for each discrepancy

### 5a. Cleanup temporary files

**This step is mandatory and must not be skipped.**

After step 5 completes (regardless of which fallback was used):
- Remove the `.postmortem_frames/` directory if it was created: `rm -rf <run_dir>/.postmortem_frames/`
- Remove any helper scripts created during frame extraction (e.g. `extract_frames.py`) from the repo root
- Remove any stray image files (`frame_*.jpg`, `frame_*.png`) from the repo root
- Verify no temporary artifacts remain: `ls frame_*.jpg frame_*.png 2>/dev/null` should return nothing

### 6. Diagnosis report

Synthesize all findings into a structured report:

```
POSTMORTEM DIAGNOSIS
====================

## Run summary
- Run: [directory name]
- Duration: [wall clock time or updates completed]
- Best reward: [value] at update [N]
- Final reward: [value]

## What worked
- [1-2 bullet points on positive findings]

## What failed
- [Each failure with likely root cause]

## Behavior vs expectation
- Expected: [from hypothesis]
- Observed: [from video analysis]
- Gap: [specific discrepancy and hypothesized cause]

## Next experiments (max 3)
1. [Concrete suggestion: what to change, why, expected effect]
2. [...]
3. [...]

## Recommendation
[One sentence: adjust rewards / adjust architecture / adjust hyperparameters / adjust curriculum / redesign observation space]
```

### 7. File export

Write the full diagnosis report from step 6 to a file. Use the current timestamp to name the file:

- Path: `docs/postmortem/MMDD_HHMM_OP.md` (e.g. `0315_1430_OP.md`)
- Create `docs/postmortem/` if it does not exist (`mkdir -p docs/postmortem`)
- The file should contain the complete diagnosis report as written in step 6

Record the timestamp prefix (e.g. `0315_1430`) for use in the Gemini handoff prompt.

### 8. Gemini handoff and workflow banner

Generate a self-contained prompt for the Gemini postmortem. This prompt must be fully copy-pasteable. Structure:

```
INDEPENDENT POSTMORTEM — GEMINI
================================

You are performing an independent postmortem analysis of an RL training run.
Analyze the artifacts below and produce your own diagnosis. Do NOT read any
existing postmortem reports — form your own conclusions independently.

## Hypothesis (REQUIRED — read this first)

[If hypothesis came from a file, include:]
- Hypothesis file: [path]

[If hypothesis was provided as inline text, embed it directly:]
> [full user-provided hypothesis text]

Read the hypothesis BEFORE analyzing any other artifacts. The hypothesis
defines what change was made, why, and what outcome was expected. All
analysis must be framed against these expectations.

## Artifacts to read
- Run directory: [path]
- Metrics: [path]
- Training log: [path, or "not available"]
- Config: [path]
- Video: [path, or "not available"]

## Analysis instructions
1. Read the hypothesis first — understand what was changed, the reasoning,
   and the expected outcome before looking at any data
2. Read all remaining artifacts listed above
3. Analyze training dynamics: reward trajectory, loss components, entropy,
   clip fraction, SPS, episode length, death/termination breakdown
4. If a video path is provided, analyze agent behavior
5. Evaluate all findings against the hypothesis: did the expected mechanism
   play out? Did the predicted outcome materialize? If not, why not?
6. Produce a structured diagnosis report with: run summary, what worked,
   what failed, behavior vs expectation (explicitly referencing the
   hypothesis), next experiments (max 3), recommendation

## File export
Write your full diagnosis report to: docs/postmortem/[TIMESTAMP]_GE.md
Create the directory if it does not exist (mkdir -p docs/postmortem).
```

Replace `[path]` placeholders with the actual artifact paths resolved in step 1. Replace `[TIMESTAMP]` with the same timestamp prefix used in step 7 (e.g. `0315_1430`). For inline-text hypotheses, embed the full text as a quoted block under the Hypothesis section.

Then display this banner prominently at the end of the response:

> **WORKFLOW TRANSITION: DUAL-MODEL POSTMORTEM**
>
> Opus postmortem complete. Report saved to `docs/postmortem/[TIMESTAMP]_OP.md`.
>
> Next steps:
> 1. Switch to **Gemini 2.5 Pro (Agent mode)** and paste the Gemini postmortem prompt above
> 2. After Gemini finishes, run `/postmortem-synthesis` to synthesize both reports and begin planning the next iteration

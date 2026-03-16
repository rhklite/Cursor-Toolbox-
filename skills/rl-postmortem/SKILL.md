---
name: rl-postmortem
description: Post-run analysis for RL experiments. Reads training metrics, logs, config, and hypothesis, analyzes training dynamics, compares behavior video against expectations, and produces a structured diagnosis with next-step suggestions. Use when the user says postmortem, analyze run, what went wrong, diagnose training, or review run results.
---

# RL Postmortem

## Role

Structured post-run analysis that extracts maximum learning from each training run. Reads all available artifacts, diagnoses what happened, and proposes concrete next steps.

## Model recommendation

> This skill runs best on **Opus (Agent mode)**.

## Steps

### 1. Gather artifact locations

Prompt the user to provide paths for the artifacts they have available. Present this checklist and ask them to supply whichever paths they can:

1. **Run directory** — a single directory containing some or all artifacts below
2. **Metrics** — training metrics file (e.g., `metrics.jsonl`, TensorBoard `events.out.tfevents.*`, or wandb logs)
3. **Training log** — human-readable log (e.g., `train.log`)
4. **Config** — the config used for the run (e.g., `config.yaml`, or a Python config class path)
5. **Hypothesis** — `hypothesis.md` or equivalent describing the experiment hypothesis and expected behavior
6. **Video** — video of the trained agent (e.g., `best.mp4`, evaluation recording)

Rules:
- If the user provides a run directory, scan it for artifacts not explicitly provided.
- If the user provides individual file paths without a run directory, use those directly; do not attempt auto-detection for missing artifacts — ask the user for any additional files needed.
- If the user provides neither, attempt auto-detect: find the most recently modified directory under `runs/` or `logs/` (excluding `archive/`).
- Always confirm with the user before proceeding: "Analyzing with the following artifacts: [list]. Correct?"

### 2. Read artifacts

Read all artifacts resolved from step 1. Accept any of these formats:

- **Metrics** — `metrics.jsonl` (one JSON object per line), TensorBoard event files, wandb logs, or `metric.json` evaluation snapshots
- **Training log** — `train.log` or equivalent human-readable log with per-update progress
- **Config** — `config.yaml`, Python config class, or wandb config
- **Hypothesis** — `hypothesis.md` or equivalent with the hypothesis, expected outcome, and expected visual behavior
- **Video** — `.mp4`, `.webm`, or `.avi` file of the trained agent

When a user-provided path overrides an auto-detected file, use the user-provided path. If any artifact is unavailable after prompting, note it and proceed with what is available.

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

- Read the "Expected visual behavior" or "Expected outcome" section from `hypothesis.md`.
- If `hypothesis.md` is missing or has no expected behavior section, prompt the user: "Describe what behavior you expected to see in the trained agent (1-2 sentences)."

### 5. Video analysis and cross-family critique

Attempt video analysis using the following fallback hierarchy. When video analysis routes to a Gemini model (via video attachment), the prompt piggybacks a broader cross-family critique of the entire training run alongside the video behavioral analysis. This provides an independent perspective from a different model family without requiring a manual model switch.

**Primary — Task tool with video attachment (Gemini piggyback):**
Use the video path provided by the user in step 1. If no video was provided, prompt the user: "Do you have a video of the trained agent? If so, provide the path." If no video is available, skip directly to Fallback 2.

Use the Task tool with `subagent_type: "generalPurpose"` and the `attachments` parameter pointing to the video file. Include in the prompt:
- The expected behavior from step 4
- A summary of the training dynamics findings from step 3 (reward trajectory, loss trends, entropy, clip fraction, episode length)
- The config and hypothesis summaries from steps 1-2
- Ask: "You are performing a cross-family postmortem review. Do two things:
  1. **Video analysis**: Watch this video of a trained RL agent. Describe the agent's behavior in detail. Compare it against this expected behavior: [expected]. List specific discrepancies and hypothesize root causes.
  2. **Training dynamics critique**: Given the metrics summary and config below, independently assess: Were the hyperparameters reasonable? Are there signs of reward hacking, entropy collapse, or value function issues that the primary analysis might have overlooked? What alternative explanations exist for the observed training trajectory?"

**Fallback 1 — Keyframe extraction:**
If the Task tool video analysis fails or returns an error:
- Run `ffmpeg` to extract 5 evenly-spaced frames from the video as PNG images
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
- Cross-family critique findings (if Gemini piggyback was used)

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

### 7. Model-switch banner

Display this banner prominently at the end of the response:

> **WORKFLOW TRANSITION: NEXT ITERATION**
>
> Postmortem complete. To plan the next iteration:
> 1. Switch to **Opus Max (Ask mode)** and use the **rl-thinking-partner** skill to explore the next design
> 2. After design is agreed, switch to **Gemini 2.5 Pro (Ask mode)** for cross-family critique of the design
> 3. Switch to **Opus (Agent mode)** to implement and run preflight verification
> 4. Launch the run

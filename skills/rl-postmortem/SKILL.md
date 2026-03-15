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

### 1. Locate run

- If the user provides a run directory path, use it.
- Otherwise, auto-detect: find the most recently modified directory under `runs/` (excluding `archive/`).
- Confirm with the user: "Analyzing run at [path]. Correct?"

### 2. Read artifacts

Read all available files from the run directory:

- **metrics.jsonl** — one JSON object per line with training metrics (reward, loss, entropy, clip fraction, SPS, etc.)
- **train.log** — human-readable log with per-update progress, best-checkpoint saves, early stopping events
- **config.yaml** — the exact config used for this run
- **hypothesis.md** — the hypothesis, expected outcome, and expected visual behavior (if present)

If any file is missing, note it and proceed with what is available.

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

### 5. Video analysis

Attempt video analysis using the following fallback hierarchy:

**Primary — Task tool with video attachment:**
Use the Task tool with `subagent_type: "generalPurpose"` and the `attachments` parameter pointing to the best video file (e.g., `best.mp4` or the most recent video in the run's `videos/` directory). Include in the prompt:
- The expected behavior from step 4
- Ask: "Watch this video of a trained RL agent. Describe the agent's behavior in detail. Then compare it against this expected behavior: [expected]. List specific discrepancies and hypothesize root causes."

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
> 1. Switch to **Opus Max (Ask mode)**
> 2. Use the **rl-thinking-partner** skill to explore the next design
> 3. When the design is ready, switch to **Opus (Agent mode)** and run `/preflight`

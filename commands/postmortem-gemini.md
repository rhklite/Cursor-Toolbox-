# Independent Gemini Postmortem

Perform a full independent postmortem analysis of a completed training run. This command is designed for Gemini in Agent mode.

## 0. Model confirmation (MANDATORY)

Before proceeding, prompt the user: "This command requires **Gemini 2.5 Pro in Agent mode**. Are you currently on Gemini 2.5 Pro in Agent mode? If not, please switch before we continue."

This is a hard gate. The agent MUST NOT proceed to step 1 until the user explicitly confirms they are on the correct model and mode.

## 1. Gather artifact locations

Prompt the user to provide paths for the artifacts they have available. Present this checklist and ask them to supply whichever paths they can:

1. **Run directory** — a single directory containing some or all artifacts below
2. **Metrics** — training metrics file (e.g., `metrics.jsonl`, TensorBoard event files, or wandb logs)
3. **Training log** — human-readable log (e.g., `train.log`)
4. **Config** — the config used for the run (e.g., `config.yaml`)
5. **Hypothesis** — `hypothesis.md` or equivalent describing the experiment hypothesis
6. **Video** — video of the trained agent (e.g., `best.mp4`)

Rules:
- If the user provides a run directory, scan it for artifacts not explicitly provided.
- If the user provides individual file paths without a run directory, use those directly.
- If the user provides neither, attempt auto-detect: find the most recently modified directory under `runs/` or `logs/` (excluding `archive/`).
- Always confirm with the user before proceeding: "Analyzing with the following artifacts: [list]. Correct?"

## 2. Read artifacts

Read all resolved artifacts. Accept these formats:
- **Metrics** — `metrics.jsonl` (one JSON object per line), TensorBoard event files, wandb logs, or `metric.json` evaluation snapshots
- **Training log** — `train.log` or equivalent
- **Config** — `config.yaml`, Python config class, or wandb config
- **Hypothesis** — `hypothesis.md` or equivalent
- **Video** — `.mp4`, `.webm`, or `.avi` file

## 3. Training dynamics analysis

Analyze the metrics systematically. For each dimension, report a short finding:
- **Reward trajectory**: overall trend, final value, best value and when, variance
- **Loss components**: policy loss stability, value loss magnitude and trend
- **Entropy**: healthy decay vs premature collapse vs stuck-high
- **Clip fraction**: average and trend
- **SPS**: stable vs degrading
- **Episode length**: trend
- **Death/termination breakdown**: if logged, report ratios and shifts

## 4. Behavior alignment

- Read the "Expected visual behavior" or "Expected outcome" from hypothesis.
- If unavailable, prompt the user for expected behavior description.

## 5. Video analysis

If a video is available, analyze agent behavior. Describe what the agent does, compare against expected behavior, list discrepancies and hypothesize root causes.

If no video is available, skip this step.

## 6. Diagnosis report

Produce a structured diagnosis:

```
POSTMORTEM DIAGNOSIS (GEMINI)
=============================

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
- Observed: [from video/metrics]
- Gap: [specific discrepancy and hypothesized cause]

## Next experiments (max 3)
1. [Concrete suggestion: what to change, why, expected effect]
2. [...]
3. [...]

## Recommendation
[One sentence: adjust rewards / adjust architecture / adjust hyperparameters / adjust curriculum / redesign observation space]
```

## 7. File export

Write the full diagnosis report to a file:
- Auto-detect the most recent `_OP.md` file in `docs/postmortem/` and use the same timestamp prefix for the GE filename (e.g. if `0315_1430_OP.md` exists, write to `0315_1430_GE.md`)
- If no `_OP.md` file exists, use the current timestamp: `MMDD_HHMM_GE.md`
- Create `docs/postmortem/` if it does not exist (`mkdir -p docs/postmortem`)

## 8. Key findings summary

After writing the report, print a concise key findings summary directly in the chat so the user sees it without opening the file. Format:

> **KEY FINDINGS (Gemini)**
>
> - [3-5 bullet points: the most important findings from the diagnosis]
> - Each bullet should be one sentence stating a finding and its implication
> - Prioritize: what worked, what failed, and the single most impactful next step

## 9. Completion banner

Display this banner at the end:

> **GEMINI POSTMORTEM COMPLETE**
>
> Report saved to `docs/postmortem/[TIMESTAMP]_GE.md`.
>
> Next step: run `/postmortem-synthesis` to synthesize both Opus and Gemini reports and begin planning the next iteration.

---
name: rl-preflight
description: Automated implementation verification and cross-family critique handoff for RL experiments. Reads the hypothesis, diffs the code, flags intent-vs-implementation mismatches, and generates a Gemini handoff prompt. Use when the user says preflight, pre-flight, before I run, sanity check my setup, or check before training.
---

# RL Preflight

## Role

Automated gate between design and execution. This skill does NOT repeat the design review (that already happened with the rl-thinking-partner). It verifies the code matches the stated design intent, then hands off to a cross-family model for independent critique.

## Model recommendation

> This skill runs best on **Opus (Agent mode)**. If you are on a different model, consider switching before proceeding.

## Steps

All steps are automated. Do not pause for user input until the final handoff banner.

### 1. Read intent

- Look for `hypothesis.md` in the workspace (search under `runs/`, the project root, or any experiment directory).
- If multiple exist, use the most recently modified one.
- If none exist, read the most recent chat history or ask the user: "No hypothesis.md found. What change are you testing and what do you expect to happen?"
- Extract: the hypothesis slug, what is being tested, expected outcome, and key config changes.

### 2. Read implementation

- Run `git diff` (staged and unstaged) to identify what files changed.
- If git diff is empty (changes already committed), use `git diff HEAD~1` or `git log --oneline -5` to find recent changes.
- Focus on files related to: reward functions, environment definitions, observation space, model architecture, training configs.
- Use semantic search or glob to locate these files if git diff is insufficient.

### 3. Automated verification

Compare intent (from hypothesis.md) against implementation (from code). For each stated change, report PASS or MISMATCH:

- **Value mismatches**: hypothesis says "set X to 2.0" but code shows X = 1.0
- **Missing config updates**: hypothesis mentions a parameter but the config file is unchanged
- **Sign errors**: reward term has wrong sign relative to stated intent
- **Commented-out code**: code that should be active is commented out, or vice versa
- **Wrong variable references**: reward computation references the wrong state variable
- **Stale values**: a value was changed in one location but not in another where it's duplicated

Output format:

```
PREFLIGHT VERIFICATION
======================
[PASS] Reward coefficient for contact term set to 0.5 (matches hypothesis)
[PASS] Observation space includes joint velocities (matches hypothesis)
[MISMATCH] Hypothesis states "disable distance shaping" but dist_shaping_alpha is still 0.1 in config
[MISMATCH] Reward function references old_pos instead of current_pos for velocity calculation
```

If all items pass, state: "All verified. Implementation matches stated intent."

If any mismatches exist, state: "N mismatches found. Review above before proceeding."

### 4. Gemini handoff prompt

Generate a self-contained prompt for the cross-family critique model. Gemini has full codebase access in Cursor, so embed file paths rather than code. Structure:

```
CROSS-FAMILY CRITIQUE REQUEST
==============================

## Hypothesis
[paste hypothesis from hypothesis.md]

## Files to review
- Reward function: [file path and line range]
- Environment config: [file path]
- Observation space: [file path and line range]
- Training config: [file path]
- Any other changed files: [file paths]

## Proposed changes and rationale
[summary of what changed and why]

## Preflight verification results
[paste the PASS/MISMATCH report from step 3]

## Your task
Read the files listed above. Given this hypothesis and the proposed changes:
1. What failure modes could emerge during training that this design does not account for?
2. Are there any reward hacking vectors the agent could exploit?
3. Could the observation space cause aliasing or information loss that undermines the hypothesis?
4. Is there anything in the implementation that contradicts the stated rationale?
```

### 5. Model-switch banner

Display this banner prominently at the end of the response:

> **WORKFLOW TRANSITION: CROSS-FAMILY CRITIQUE**
>
> Pre-flight complete. To get an independent critique:
> 1. Switch to **Gemini 3.1 Pro** in your model selector
> 2. Open a **new chat in Ask mode**
> 3. Paste the critique prompt above
>
> After Gemini review, switch back to **Opus (Agent mode)** to implement and launch the run.

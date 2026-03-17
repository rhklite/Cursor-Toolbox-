---
name: rl-preflight
description: Automated implementation verification for RL experiments. Reads the hypothesis, diffs the code, and flags intent-vs-implementation mismatches. Use when the user says preflight, pre-flight, before I run, sanity check my setup, or check before training.
---

# RL Preflight

## Role

Automated gate between design and execution. This skill does NOT repeat the design review (that already happened with the rl-thinking-partner). It verifies the code matches the stated design intent.

## Model recommendation

> This skill runs best on **Opus (Agent mode)**. If you are on a different model, consider switching before proceeding.

## Steps

All steps are automated. Do not pause for user input until the final verification summary.

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

#### 3a. Test-passage check

Before running intent-vs-implementation checks, verify that implementation tests exist and pass:

- Look for test files related to the current changes (search for recently created or modified test files via `git diff` or glob for `test_*.py` / `*_test.py` in relevant directories).
- If test files are found, run them. Report each as PASS or MISMATCH.
- If no test files are found, flag: `[MISMATCH] No implementation tests found. The implementation workflow should have created tests before reaching preflight.`
- If any tests fail, flag: `[MISMATCH] N implementation tests failing. These should have been resolved before reaching preflight.`

#### 3b. Intent-vs-implementation checks

Compare intent (from hypothesis.md) against implementation (from code). For each stated change, report PASS or MISMATCH:

- **Value mismatches**: hypothesis says "set X to 2.0" but code shows X = 1.0
- **Missing config updates**: hypothesis mentions a parameter but the config file is unchanged
- **Sign errors**: reward term has wrong sign relative to stated intent
- **Commented-out code**: code that should be active is commented out, or vice versa
- **Wrong variable references**: reward computation references the wrong state variable
- **Stale values**: a value was changed in one location but not in another where it's duplicated
- **Curriculum stage mismatches**: hypothesis specifies stage transitions, thresholds, or ordering that differ from what the code implements
- **Observation space ordering**: hypothesis describes a specific observation layout or ordering that does not match the actual tensor construction
- **Action space bounds**: hypothesis states an action range or clipping bound that differs from the configured values
- **Domain randomization parameters**: hypothesis specifies randomization ranges or distributions that are not reflected in the config or environment code
- **Episode length and termination conditions**: hypothesis defines episode duration, early termination triggers, or timeout values that do not match the implementation
- **Reward term omission or addition**: hypothesis lists specific reward terms to add, remove, or disable, but the code does not reflect all of them
- **Weight or coefficient drift**: hypothesis specifies reward weights or loss coefficients, but a subset are stale or were not updated across all config layers (base, task, override)

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

### 4. Verification complete

Display this banner prominently at the end of the response:

> **PREFLIGHT COMPLETE**
>
> Implementation verified against hypothesis. Ready to launch the run.
>
> Cross-family design critique was performed earlier (during the thinking partner phase via Gemini). If you skipped that step and want an independent review, switch to **Gemini 2.5 Pro (Ask mode)** now before launching.

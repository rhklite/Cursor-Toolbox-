---
name: merge-v12-feature-set
overview: Integrate only the V12 SA failure-balance feature set from `origin/jiaming/failure_balance_v12` into your current branch using a surgical, low-risk merge approach.
todos:
  - id: prep-branch
    content: Create temporary integration branch and confirm clean baseline on current branch.
    status: completed
  - id: port-feature-files
    content: Port only V12 failure-balance env/config/script and minimal __init__ task registration.
    status: completed
  - id: gate-runtime-data
    content: Validate RSI dataset availability and apply minimal dataset handling strategy.
    status: completed
  - id: run-smoke-checks
    content: Run task registration/script sanity checks and ensure interactive-play remains unaffected.
    status: completed
  - id: finalize-diff
    content: Audit final diff to ensure feature-only scope, then prepare final commit plan.
    status: completed
isProject: false
---

# V12 Failure-Balance Feature Merge Plan

## Scope (Feature-Only)

- Include only the functional feature files for V12 SA failure-balance:
  - [humanoid-gym/humanoid/envs/r01_amp/r01_v12_failure_balance_env.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_failure_balance_env.py)
  - [humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_failure_balance_config.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_failure_balance_config.py)
  - [humanoid-gym/humanoid/scripts/play_failure_balance.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/scripts/play_failure_balance.py)
  - minimal registration updates in [humanoid-gym/humanoid/envs/**init**.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py)
- Exclude non-feature payload (tooling/data-compare scripts, IDE config files, large model artifacts, unrelated deploy/evaluate script changes) unless required for runtime.

## Integration Steps

- Create a temporary integration branch from your current branch.
- Bring over only the 3 feature files and the required task registration lines from coworker branch.
- Resolve `__init__.py` overlap by preserving your existing V12 SA task registrations and appending only failure-balance imports/registration.
- Keep your interactive-play implementation untouched (`play_interactive.py` and its tests).
- Keep Fuyao script changes out of this merge (separate follow-up if needed).

## Runtime Dependency Gate

- Verify whether RSI dataset path `r01_v12_failure_balance` exists locally (used by `R01V12SAFailureBalanceCfg.motion.motion_dataset`).
- If absent, choose one minimal option:
  - copy only required dataset file(s), or
  - temporarily repoint config to an existing local dataset for smoke validation.

## Validation Checklist

- Task registration smoke-check: task key `r01_v12_sa_failure_balance` resolves and env builds.
- Script sanity-check: `play_failure_balance.py` argument parsing and model path behavior are valid.
- Regression check: existing interactive-play flow still runs and key bindings behave unchanged.
- Diff audit: confirm only feature-set files were modified.

## Delivery

- Produce one focused commit for feature merge (or two commits: env/config + script/registration) with concise rationale.
- Share quick run commands for:
  - failure-balance test entrypoint
  - existing interactive-play entrypoint
  to verify both paths coexist cleanly.

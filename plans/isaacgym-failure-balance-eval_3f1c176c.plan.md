---
name: isaacgym-failure-balance-eval
overview: Run a container-based functional verification of the merged V12 failure-balance feature set, with automatic asset provisioning when missing.
todos:
  - id: preflight-sync
    content: Verify container workspace and align it with merged host feature files before testing.
    status: completed
  - id: autofetch-assets
    content: Auto-provision missing RSI dataset/checkpoint assets in container workspace.
    status: completed
  - id: run-sanity-checks
    content: Run py_compile, task registration check, and script help check in container.
    status: completed
  - id: run-functional-single
    content: Execute one bounded play_failure_balance evaluation run and capture output.
    status: completed
  - id: report-results
    content: Summarize pass/fail evidence and remediation for any failure.
    status: completed
isProject: false
---

# Isaac Gym Evaluation Plan

## Objective

Validate the V12 failure-balance merge in Isaac Gym container using a functional single-run evaluation (per your selection), with auto-fetch/copy of missing dataset/checkpoint assets.

## Targets Under Test

- Task registration wiring in [humanoid-gym/humanoid/envs/**init**.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py)
- Failure env implementation in [humanoid-gym/humanoid/envs/r01_amp/r01_v12_failure_balance_env.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_failure_balance_env.py)
- Failure config in [humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_failure_balance_config.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_failure_balance_config.py)
- Runner script in [humanoid-gym/humanoid/scripts/play_failure_balance.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/scripts/play_failure_balance.py)

## Execution Plan

- **Container preflight and repo sync check**
  - Verify container wrapper works and points to `/home/huh/software/motion_rl`.
  - Confirm container branch/HEAD matches the merged host branch content; if not, sync container workspace to include the 4 merged files before testing.
- **Auto asset provisioning (as requested)**
  - Check presence of `humanoid-gym/datasets/r01_v12_failure_balance`.
  - Check presence of `humanoid-gym/logs/r01_v12_sa_failure_balance/walk_baseline/model_12141_best_k_value=53.696.pt`.
  - If missing, auto-copy/fetch required assets into container test workspace and record exactly what was provisioned.
- **Static/sanity checks in container**
  - `py_compile` on the 4 target files.
  - Task registration check: `r01_v12_sa_failure_balance` present in task registry.
  - Script interface check: `play_failure_balance.py --help` exits successfully.
- **Functional single-run evaluation**
  - Run one short evaluation of `play_failure_balance.py` with:
    - `--task r01_v12_sa_failure_balance`
    - `--num_runs 1`
    - bounded `--total_steps` (short runtime)
    - explicit `--checkpoint_path` (provisioned path) to avoid run-discovery ambiguity.
  - Capture pass/fail and the script’s final success-rate output.
- **Results audit and report**
  - Summarize each check status and command evidence.
  - If any failure occurs, provide verbatim error lines and remediation.

## Pass Criteria

- Container can import/compile target modules.
- Task key `r01_v12_sa_failure_balance` resolves.
- `play_failure_balance.py --help` works.
- One bounded evaluation run completes and prints final success ratio without crash.

## Notes

- Prior failure was caused by container branch mismatch (container lacked merged files); this plan explicitly resolves that before evaluation.
- No plan-file edits will be made.

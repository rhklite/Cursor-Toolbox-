---
name: Fix AMP D-reg center
overview: Correct the C-GAIL regularizer to AMP-consistent discriminator-only math (center at 0), keep policy objective untouched, and set `k=0.1` as default through existing config plumbing.
todos:
  - id: patch-disc-reg-formula
    content: Update discriminator regularizer in amp_ppo.py from center-0.5 to center-0 while preserving apply-to routing and scaling.
    status: completed
  - id: set-k-defaults
    content: Set cgail_reg_coef default to 0.1 in AMPPPO init and both AMP config classes used for this task.
    status: completed
  - id: confirm-no-policy-objective-change
    content: Verify policy objective terms and +1/-1 AMP discriminator targets are unchanged.
    status: completed
  - id: run-post-edit-checks
    content: Run syntax/lint checks on modified files and summarize evidence that only discriminator-side logic/defaults changed.
    status: completed
isProject: false
---

# Fix AMP Discriminator Regularizer

## Scope and constraints

- Only change discriminator-side regularization logic and its defaults.
- Do not change policy objective terms (`surrogate`, `value`, `entropy`, `adaptation`) or AMP discriminator targets (`expert -> +1`, `policy/fake -> -1`).

## Files to update

- Discriminator loss logic: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py)`
- Base AMP PPO defaults: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py)`
- SA full-scenes override defaults: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py)`

## Planned code changes

- In `_compute_cgail_reg_loss(policy_d, expert_d)` inside `amp_ppo.py`, replace center-0.5 terms with AMP-correct center-0 terms:
  - from `(D - target)^2` to `D^2`
  - keep existing `cgail_apply_to` routing (`policy_batch`, `expert_batch`, `both_policy_and_expert_batches`)
  - keep scaling as `0.5 * k * active_term`
- Keep discriminator LSGAN supervision unchanged in `update()`:
  - `MSE(expert_d, +1)` and `MSE(policy_d, -1)` remain exactly as-is.
- Set `k` default to `0.1` using existing config plumbing:
  - `AMPPPO.__init__(..., cgail_reg_coef=0.1, ...)`
  - `R01AMPCfgPPO.algorithm.cgail_reg_coef = 0.1`
  - `R01V12SAAMPWith4DoFArmsAndHeadFullScenesCfgPPO.algorithm.cgail_reg_coef = 0.1`
- Ensure no logic path in discriminator regularization still uses center `0.5`.

## Validation after edits

- Static checks:
  - verify `_compute_cgail_reg_loss` uses only `policy_d` / `expert_d` existing in discriminator step.
  - verify policy-objective terms are unchanged in `loss = (...)` composition.
  - verify defaults are `0.1` in the three locations above.
- Run lightweight syntax/lint checks on changed files and report exact diffs/paths.

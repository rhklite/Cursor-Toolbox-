---
name: torso-upright-reward-plan
overview: Add a torso-upright world-frame reward and enable torso angular damping in task configs, while keeping defaults safe and opt-in per task.
todos:
  - id: add-torso-orientation-reward
    content: Add _reward_torso_orientation in r01_v12_amp_env.py using torso_projected_gravity xy.
    status: completed
  - id: expose-config-knobs
    content: Expose torso_orientation and torso_ang_vel_xy_penalty scales with default 0.0 in SA base config.
    status: completed
  - id: set-leaf-task-values
    content: Apply chosen non-zero values in the specific task config(s) being trained.
    status: completed
  - id: validate-reward-wiring
    content: Run syntax/runtime smoke checks to confirm reward registration and task load.
    status: completed
isProject: false
---

# Torso Upright + Damping Rewards Plan

## Goal

Implement both stabilization signals you asked for:

- torso uprightness relative to gravity (world-frame objective), and
- torso angular-rate damping (body-frame objective).

## Code Changes

- Add a new reward term in [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_amp_env.py`] to measure torso tilt from gravity:
  - `def _reward_torso_orientation(self): return sum(torso_projected_gravity_xy^2)`
  - This uses existing `self.torso_projected_gravity`, so no new state plumbing is needed.
- Expose/standardize config knobs in [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py`]:
  - keep `rewards.tracking_sigma_torso_ang_vel_xy`
  - add `rewards.scales.torso_orientation = 0.0` (default off)
  - un-comment/add `rewards.scales.torso_ang_vel_xy_penalty = 0.0` (default off)
- Apply non-zero values in the target leaf task config(s):
  - [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority.py`]
  - and/or [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_ema.py`]
  - and/or [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority_ema.py`]
  depending on which task ID you run.

## Validation

- Syntax/lint check modified files.
- Runtime registry smoke-check: confirm selected task loads and reward names include `torso_orientation` / `torso_ang_vel_xy_penalty` when scales are non-zero.
- Short training sanity run: verify no instability from reward scale sign mistakes.

## Notes

- Keep defaults at `0.0` in base SA config so existing tasks are unaffected.
- Only leaf configs should carry your non-zero tuning choices.

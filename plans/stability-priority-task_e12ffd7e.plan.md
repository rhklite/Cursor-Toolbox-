---
name: stability-priority-task
overview: Add a new inherited SA AMP task config for stability-priority tuning knobs and register it as a new task ID, while keeping all values at current baseline defaults.
todos:
  - id: add-stability-priority-config
    content: Create inherited SA full-scenes stability-priority config module with all discussed tuning knobs explicitly defined at baseline values.
    status: completed
  - id: add-ppo-runner-overrides
    content: Add PPO runner subclass in the new module with unique experiment_name and explicit amp_task_reward_lerp.
    status: completed
  - id: register-new-task-id
    content: Import new config classes and register stability_priority task in humanoid env task registry.
    status: completed
  - id: sanity-check-task-wireup
    content: Verify naming consistency, uniqueness of task ID, and completeness of the explicit tuning-parameter list.
    status: completed
isProject: false
---

# Create Stability-Priority Task Variant

## Goal

Create a new task config variant that inherits from the current SA full-scenes task, explicitly exposes all tuning knobs we discussed, keeps **baseline/current values** by default, and registers a new task ID with suffix `stability_priority`.

## Files To Update

- New file: `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority.py)`
- Registry: `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py)`
- Reference base: `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py)`

## Implementation Plan

1. Add a new config module in `r01_amp` that inherits from the reference SA full-scenes config classes:
  - `R01V12SAAMPWith4DoFArmsAndHeadFullScenesStabilityPriorityCfg`
  - `R01V12SAAMPWith4DoFArmsAndHeadFullScenesStabilityPriorityCfgPPO`
2. In the new `Cfg`, explicitly define all tuning parameters (baseline values preserved) with short comments indicating suggested tuning ranges:
  - `rewards.scales`: `stand_still`, `orientation`, `ang_vel_xy`, `lin_vel_z`, `base_height`, `default_joint_pos`, `tracking_avg_lin_vel`
  - `rewards`: `tracking_sigma_lin_vel`
  - `commands.new_sample_methods`: `straight_prob`, `backward_prob`, `stand_prob`, `turn_prob`
  - `domain_rand`: `max_push_vel_xy`, `max_push_ang_vel`, `push_interval_t_range`
3. In the new `CfgPPO.runner`, explicitly expose `amp_task_reward_lerp = 0.3` and set a unique `experiment_name` ending with `_stability_priority`.
4. Register the new task in `envs/__init__.py`:
  - Add imports for the two new classes.
  - Add `task_registry.register(...)` with task ID:
    - `r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes_stability_priority`
  - Keep env class `R01V12AMPEnv` to match the reference SA task.
5. Validate consistency:
  - Confirm no duplicate task ID.
  - Confirm imports resolve and class names match registry entry.
  - Confirm all requested tuning knobs are explicitly present in the new file (even if values remain baseline).

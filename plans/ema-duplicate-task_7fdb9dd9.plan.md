---
name: ema-duplicate-task
overview: Create a duplicate of the current stability-priority task that reverts command/disturbance diffs to baseline values and switches average-velocity tracking to EMA with alpha 0.03, without changing behavior of existing tasks.
todos:
  - id: add-config-gated-ema-in-env
    content: Implement config-gated base velocity averaging mode in r01_amp_env.py with default sliding-window and optional EMA(alpha).
    status: completed
  - id: create-stability-ema-duplicate-config
    content: Add duplicate stability task config file with reverted command/disturbance values and EMA mode enabled.
    status: completed
  - id: register-ema-duplicate-task
    content: Import and register the new EMA duplicate task in envs/__init__.py with a unique task ID.
    status: completed
  - id: validate-scope-and-consistency
    content: Verify default behavior for existing tasks is unchanged and duplicate task uses EMA 0.03 with intended reverted values.
    status: completed
isProject: false
---

# Duplicate Task With EMA Tracking

## Goal

Add a new task variant duplicated from the current stability-priority task, but with:

- all command-sampling probability diffs reverted to baseline,
- all disturbance diffs (including rotational push) reverted to baseline,
- velocity tracking average changed from sliding-window mean to EMA (`alpha=0.03`) for this duplicate only.

## Chosen Settings From User

- EMA alpha: `0.03`
- Revert scope: all command sampling probability diffs and all disturbance diffs (including rotational disturbance).

## Files To Update

- EMA logic (backward-compatible): `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_env.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_env.py)`
- New duplicate task config: `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority_ema.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority_ema.py)`
- Task registry wiring: `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py)`

## Implementation Steps

1. **Add optional EMA averaging mode in env (default remains current behavior).**
  - In `R01AMPEnv`, keep existing sliding-window averaging as default.
  - Add config-driven mode selection via `getattr(self.cfg.commands, ...)`, e.g.:
    - `base_vel_avg_mode` in `{ "window", "ema" }` (default `"window"`)
    - `base_vel_ema_alpha` (default `0.03`)
  - In `_post_physics_step_callback()`, compute `base_avg_vel` with EMA when mode is `"ema"`; otherwise keep current rolling mean logic.
  - Ensure reset path clears EMA state consistently (reuse `reset_base_vel_history` compatibility).
2. **Create duplicate task config from current stability task.**
  - New classes:
    - `R01V12SAAMPWith4DoFArmsAndHeadFullScenesStabilityPriorityEMACfg`
    - `R01V12SAAMPWith4DoFArmsAndHeadFullScenesStabilityPriorityEMACfgPPO`
  - In duplicate config, revert to baseline values from parent SA config:
    - Disturbance: `max_push_vel_xy=0.5`, `max_push_ang_vel=0.0`, `push_interval_t_range=[5.0, 10.0]`
    - Command probs: `straight_prob=0.42`, `backward_prob=0.18`, `stand_prob=0.07`, `turn_prob=0.33`
  - Enable EMA only for this duplicate:
    - `commands.base_vel_avg_mode = "ema"`
    - `commands.base_vel_ema_alpha = 0.03`
  - Keep current stability-task intent knobs unchanged unless explicitly part of revert scope.
3. **Register duplicate task in registry.**
  - Import new config classes in `envs/__init__.py`.
  - Register a new unique task ID, e.g.:
    - `r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes_stability_priority_ema`
  - Keep env class `R01V12AMPEnv` for consistency with existing SA tasks.
4. **Verify no regressions and correct scoping.**
  - Confirm existing tasks still use window mean (default mode unchanged).
  - Confirm duplicate task receives EMA mode + alpha 0.03.
  - Sanity-check import/registration consistency and task ID uniqueness.

## Notes

- This plan intentionally avoids changing the existing stability-priority task semantics except through the new duplicate.
- EMA is introduced in a config-gated way to keep walking and other tasks backward-compatible by default.

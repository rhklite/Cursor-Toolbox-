---
name: leg-only-resume-eval-push
overview: Implement leg-only control and random waist-up spawn for the stability-priority task, add optional push disturbance in play-video evaluation, and use existing checkpoint-resume plumbing for continued training.
todos:
  - id: add-stability-task-flags
    content: Add leg-only control and non-controlled-joint random spawn config flags to stability-priority task config.
    status: completed
  - id: mask-waistup-torques
    content: Implement cfg-gated non-leg torque masking in r01_amp_env _compute_torques().
    status: completed
  - id: randomize-noncontrolled-joints
    content: Implement cfg-gated non-controlled joint position sampling from DOF limits during reset.
    status: completed
  - id: add-play-push-args
    content: Add push-disturbance CLI flags and config wiring in play.py while preserving default no-push behavior.
    status: completed
  - id: verify-resume-and-smoke-test
    content: Run syntax/lint and smoke checks, and verify existing checkpoint-resume command path remains valid.
    status: completed
isProject: false
---

# Leg-Only Control + Resume + Eval Push Plan

## Scope Confirmed

- Apply behavior **in-place** to `r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes_stability_priority`.
- Add disturbance to the **video flow in** [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/scripts/play.py`] using random push.
- Keep checkpoint continuation compatible with existing model weights by **keeping action dimension unchanged** and masking non-leg control at torque stage.

## Implementation Plan

- Add task-level feature flags and sampling knobs in [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes_stability_priority.py`]:
  - `env.leg_only_control = True`
  - `domain_rand.randomize_non_controlled_joint_pos = True`
  - `domain_rand.non_controlled_joint_pos_margin` (safety margin from hard limits)
  - optional per-episode switch probability if needed (default always-on)
- Implement cfg-gated leg-only torque masking in [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_env.py`]:
  - In `_compute_torques()`, after torque computation and before return, set non-leg DOF torques to zero when `cfg.env.leg_only_control` is true.
  - Use existing split from `self.leg_joint_dim` so all waist/arms/head joints are treated as non-controlled.
- Implement cfg-gated non-controlled joint random spawn in [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_env.py`]:
  - During reset flow, sample non-controlled joint positions from each joint’s available range using `self.dof_pos_limits` with configurable margin.
  - Keep leg joints on their original reset logic (AMP/motion/default path unchanged).
  - Re-apply sampled DOF state to simulator for affected env IDs.
- Add optional random push disturbance flags to video play in [`/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/scripts/play.py`]:
  - New args: `--enable_robot_push`, `--push_vel_xy`, `--push_ang_vel`, `--push_interval_min`, `--push_interval_max`.
  - Current default behavior remains unchanged (`push_robots=False`) unless flag is enabled.
  - When enabled, set `env_cfg.domain_rand.push_robots=True` and apply the provided push parameters before env creation.
- Use existing checkpoint continuation path (no structural model change needed):
  - `helpers.py` already supports `--resume` and `--checkpoint_path`.
  - `humanoid-gym/scripts/fuyao_train.sh` already maps `--checkpoint_path` to training resume.
  - Add a concise runbook section in commit notes (or PR body) for continued training commands.

## Validation

- Syntax/lint for touched files.
- Smoke checks:
  - task config loads and contains new flags,
  - torque masking branch activates only for stability-priority task,
  - reset randomization affects only non-controlled joints.
- Play-video check:
  - with `--enable_robot_push` confirms disturbance active,
  - without flag retains existing no-push behavior.

## Recommended Initial Ranges

- Non-controlled joint spawn margin from limits: `0.05` to `0.15` (fraction of joint range).
- Eval push translational magnitude (`max_push_vel_xy`): `0.2` to `0.6`.
- Eval push angular magnitude (`max_push_ang_vel`): `0.05` to `0.2`.
- Eval push interval range (seconds): `[3, 8]` to `[5, 10]`.
- Keep these disturbance values **evaluation-only** unless you explicitly want training domain-rand changed.

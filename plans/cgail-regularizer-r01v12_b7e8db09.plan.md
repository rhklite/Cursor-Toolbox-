---
name: cgail-regularizer-r01v12
overview: Add and test the practical C-GAIL discriminator regularizer on your current R01-v12 female-variant AMP training path, on a new branch with `cGil` suffix, with minimal-impact A/B controls.
todos:
  - id: branch-create
    content: Create new branch from current branch with suffix `cGil`.
    status: completed
  - id: cgail-loss
    content: Add optional C-GAIL discriminator regularization term into `amp_ppo.py` loss computation and logging.
    status: completed
  - id: cfg-wire
    content: Expose cGAIL hyperparameters through AMP config chain and set them in selected R01-v12 variant config.
    status: completed
  - id: smoke-test
    content: Run short smoke training and verify loss keys/metrics are healthy.
    status: completed
  - id: ab-compare
    content: Run baseline vs C-GAIL A/B and compare stability-oriented metrics.
    status: completed
isProject: false
---

# C-GAIL Regularizer Test Plan

## What C-GAIL is (targeted to implementation)

C-GAIL ("C-GAIL: Stabilizing Generative Adversarial Imitation Learning with Control Theory", arXiv:2402.16349) adds a control-inspired regularizer to the discriminator objective. In practical training, the paper keeps the policy objective unchanged and applies the regularizer to the discriminator only.

Practical discriminator term from the paper:

- Add `-(k/2) * (D(s,a) - 1/2)^2` to discriminator objective (equivalently a quadratic penalty centered at `0.5`)

In this repo, the closest integration point is AMP discriminator training in `[/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py)`, where discriminator losses are currently built as MSE + grad penalty.

## Implementation scope

- Keep current AMP setup and reward pipeline unchanged.
- Add C-GAIL-style discriminator regularization as an optional term gated by config.
- Target your current R01-v12 SA/full-scenes variant config path first: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py)`.

## Steps

1. Create working branch

- Checkout a new branch from your current branch, adding suffix `cGil` (as requested).

1. Add algorithm knobs (default-safe)

- In AMP algorithm config classes, add:
  - `cgail_reg_coef` (float, default `0.0`)
  - `cgail_target` (float, default `0.5`)
  - `cgail_apply_to` (initially `"both_policy_and_expert_batches"` to match batch usage)
- Set nonzero `cgail_reg_coef` only in your chosen R01-v12 female variant config; keep others unchanged.

1. Inject regularizer in discriminator loss path

- In `[/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py)`, after computing `policy_d` and `expert_d`, compute regularization term:
  - `cgail_reg = 0.5 * k * (mean((policy_d - t)^2) + mean((expert_d - t)^2))`
- Add `cgail_reg` into total loss with sign consistent with current minimization form.
- Log `cgail_reg` into `loss_dict` for TensorBoard/W&B comparability.

1. Wire config to runner/algorithm

- Ensure AMPPPO constructor receives new cGAIL parameters from runner/algorithm config chain without breaking existing tasks.

1. Sanity checks

- Run a short dry training (few iterations) on the selected R01-v12 task to verify:
  - no shape/runtime issues
  - `Loss/cgail_reg` appears in logs
  - discriminator stats (`AMP_pred_policy`, `AMP_pred_expert`) remain finite.

1. A/B experiment recipe

- Baseline run: identical config with `cgail_reg_coef=0.0`
- C-GAIL run: same seed + same everything, only `cgail_reg_coef>0`
- Compare early/mid training:
  - reward curve stability
  - `AMP` and `AMP_grad` oscillation amplitude
  - discriminator prediction spread.

## Key files to change

- `[/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/algo/amp_ppo/amp_ppo.py)`
- `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py)`
- Possibly base AMP config inheritance point if needed:
  - `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py)`

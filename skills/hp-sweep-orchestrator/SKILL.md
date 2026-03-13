---
name: hp-sweep-orchestrator
description: Orchestrates hyperparameter sweep training jobs on Fuyao. Use when the user mentions hyperparameter sweep, parameter search, training sweep, sweep jobs, or wants to deploy multiple training runs with different config values.
---

# Hyperparameter Sweep Orchestrator

## When to Use

Activate when user mentions:
- "sweep", "grid search", "hyperparameter search"
- "try different values of X"
- "run training with X = a, b, c"
- "compare learning rates"
- "deploy multiple training jobs"
- "parameter sweep on fuyao"

## Workflow Overview

```text
Prompt user for inputs (required questions first)
  -> Build sweep payload JSON
  -> Preview combos + get confirmation
  -> Run deploy_fuyao_sweep_dispatcher.sh --payload <file>
  -> Verify training started (verify_fuyao_jobs.sh)
  -> Report results
```

## Step 1: Interactive Required Input Questions

Ask required inputs explicitly in sequence:

### Required fields

1. **task**: task name.
   - Offer options from registered tasks in `humanoid-gym/humanoid/envs/__init__.py` and a default selection when available.
   - Ask for exact task name if user chooses custom.

2. **branch**: git branch to use.
   - Ask with default `current repo branch` when detectable.

3. **hp_specs**: parameters and values to sweep (`param=value1,value2` entries).
   - Ask repeatedly for `hp_specs` entries in `param=val1,val2` form.
   - Require at least one valid entry before proceeding.
   - A user mention of `hyperparameters` is acceptable as natural-language shorthand, but the payload key remains `hp_specs`.

### Optional fields
The orchestrator does not expose every dispatcher default interactively. Use dispatcher defaults for
`nodes=1`, `gpu_slice=<empty>`, `local_root`, `envs_init_rel`, `remote_root`, `remote_sweep_root`,
`run_root_base`, `docker_image`, and `rl_device` unless a manual payload path is used.

4. **patch_file_rel**: Config file to patch (default: SA config)
5. **queue/project/site**: Fuyao infrastructure params
6. **gpus_per_node**: GPU count per job
7. **dry_run**: User says "dry run", "preview", "don't submit"
8. **hp_class_map**: For custom params not in DEFAULT_CLASS_MAP
9. **max_parallel**: Parallel job count
10. **label_prefix**: Label prefix for combo naming
11. **continue_on_error**: Whether to treat failures as hard failure

## Step 2: Build Payload JSON

Write to `~/.cursor/tmp/sweep_payloads/sweep_<timestamp>.json`:

```json
{
  "task": "<parsed_task>",
  "branch": "<parsed_branch>",
  "patch_file_rel": "humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py",
  "hp_specs": ["learning_rate=1e-4,2e-4", "entropy_coef=0.01,0.005"],
  "experiment": "huh8/r01",
  "queue": "rc-wbc-4090-share",
  "project": "rc-wbc",
  "site": "fuyao_sh_n2",
  "max_parallel": 4,
  "label_prefix": "sweep",
  "continue_on_error": true,
  "dry_run": false
}
```

**Combo count**: product of all value counts. E.g., 3 learning_rates x 2 entropy_coefs = 6 combos.

## Step 3: Preview and Confirm

Show user a summary before executing:

```text
Sweep preview:
  Task:   r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes
  Branch: huh8/my-experiment
  Combos: 6 total
    1. learning_rate=1e-4, entropy_coef=0.01
    2. learning_rate=1e-4, entropy_coef=0.005
    3. learning_rate=2e-4, entropy_coef=0.01
    4. learning_rate=2e-4, entropy_coef=0.005
    5. learning_rate=3e-4, entropy_coef=0.01
    6. learning_rate=3e-4, entropy_coef=0.005
  GPUs: 6 x 1 = 6 GPUs total
  Queue: rc-wbc-4090-share

Proceed? (Confirm to deploy, or say 'dry run' to preview only)
```

Ask for confirmation. Do not submit without user approval.

## Step 4: Execute

```bash
bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --payload <payload_path>
```

Capture the output. Extract the `Run root:` line and share with user.

## Step 5: Verify Training

After dispatch completes, verify jobs are actually training (mandatory, not skippable):

```bash
bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --check-artifacts --poll-interval 60 --max-attempts 15
```

Do NOT report sweep success unless at least `TRAINING` verdict is reached for all jobs.
If any job stays in `SETUP`/`PENDING`/`WAITING` after polling completes, report a warning with
`fuyao log` commands for each unconfirmed job.

Report to user which jobs are confirmed training (with or without artifacts), which are pending, and which failed.

## Step 6: Cancel notes

This dispatcher does not implement `--cancel-sweep`.
If needed, gather submitted `job_name` from `<run_root>/logs/*.dispatch.log` and cancel manually via `fuyao cancel`.

## Known Hyperparameters (auto-mapped)

These params are automatically mapped to the correct Python config class by `hp_patcher.py`:

**Algorithm params** (PPO): `learning_rate`, `entropy_coef`, `gamma`, `lam`, `clip_param`, `num_learning_epochs`, `num_mini_batches`, `desired_kl`, `max_grad_norm`, `value_loss_coef`, `schedule`

**Symmetry params**: `mirror_loss_coeff`, `use_mirror_loss`, `use_data_augmentation`, `use_scaled_orthogonal_init`, `orthogonal_init_scale`

**Runner params**: `amp_task_reward_lerp`, `max_iterations`, `num_steps_per_env`

**Policy params**: `init_noise_std`

**Env params**: `frame_stack`, `num_envs`, `c_frame_stack`

**Reward params**: `tracking_sigma_lin_vel`, `soft_dof_vel_limit`, `soft_dof_pos_limit`

**Reward scale params**: `tracking_avg_ang_vel`, `torque_limits`, `stand_still`, `foot_distance_limit`

**Domain rand params**: `push_robots`, `max_push_vel_xy`, `randomize_base_mass`, `com_displacement_range`, `motor_strength_range`

For any param NOT in this list, include an `hp_class_map` in payload:

```json
{
  "hp_class_map": {
    "my_custom_param": "algorithm",
    "another_param": "rewards.scales"
  }
}
```

## NLP Parsing Examples

| User says | Parsed |
|-----------|--------|
| "sweep lr over 1e-4 and 2e-4" | `hp_specs: ["learning_rate=1e-4,2e-4"]` |
| "try entropy 0.01, 0.005, 0.001" | `hp_specs: ["entropy_coef=0.01,0.005,0.001"]` |
| "learning rate 3e-4, gamma 0.995" | `hp_specs: ["learning_rate=3e-4", "gamma=0.995"]` (single values, confirm)
| "compare mirror loss 0.1 vs 0.2 vs 0.5" | `hp_specs: ["mirror_loss_coeff=0.1,0.2,0.5"]` |
| "sweep amp reward lerp 0.2 to 0.5 in 0.1 steps" | `hp_specs: ["amp_task_reward_lerp=0.2,0.3,0.4,0.5"]` |
| "dry run with lr 1e-4" | `dry_run: true, hp_specs: ["learning_rate=1e-4"]` |

### Abbreviation Map

| Abbreviation | Full parameter name |
|-------------|-------------------|
| lr | learning_rate |
| ent, entropy | entropy_coef |
| clip | clip_param |
| mirror, mirror_loss | mirror_loss_coeff |
| amp_lerp, reward_lerp | amp_task_reward_lerp |
| iters, iterations | max_iterations |
| epochs | num_learning_epochs |
| mini_batches, minibatch | num_mini_batches |
| push_vel | max_push_vel_xy |

## Error Handling

- If task not found: show registered tasks list, ask user to pick
- If branch not specified: ask user
- If hp_specs empty: ask user what to sweep
- If patcher fails: show the error, suggest adding to hp_class_map
- If deploy fails: show dispatch log path, suggest checking SSH connectivity
- If verification shows failures: show `fuyao log` command for debugging

## File Locations

- Dispatcher: `~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh`
- Deploy single job script: `~/.cursor/scripts/deploy_fuyao.sh`
- HP Patcher: `~/.cursor/scripts/hp_patcher.py`
- Verify script: `~/.cursor/scripts/verify_fuyao_jobs.sh`
- Payloads written to: `~/.cursor/tmp/sweep_payloads/`
- Run artifacts: `~/.cursor/tmp/deploy_fuyao_sweep_runs/<sweep_id>/`

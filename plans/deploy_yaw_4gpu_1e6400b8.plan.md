---
name: Deploy Yaw 4GPU
overview: Prepare and run the Fuyao deploy command for the line-188 humanoid task, using one job with 4 GPUs and label `cgil-4`.
todos:
  - id: confirm-task
    content: Use task key `r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes` from env registry
    status: completed
  - id: run-deploy
    content: Run Fuyao deploy with label `cgil-4` and GPU override `--gpus-per-node=4`
    status: completed
  - id: verify-flags
    content: Validate logs show label, task, and effective 4-GPU setting
    status: completed
isProject: false
---

# Deploy Yaw With 4 GPUs

## What I confirmed

- The task on line 188 in `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py)` is `r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes`.
- The deploy wrapper in `[/home/huh/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh](/home/huh/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh)` hardcodes `--gpus-per-node=1`, so 4 GPUs must be injected via `--fuyao-args`.

## Planned command

- Execute inside the `isaacgym` container context (per workspace convention):
  - `bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh bash humanoid-gym/scripts/fuyao_deploy.sh --project=humanoid --label=cgil-4 --task=r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes --fuyao-args="--gpus-per-node=4"`

## Verification

- Confirm the deploy output includes:
  - `--label="cgil-4"`
  - `--task "r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes"`
  - effective `--gpus-per-node=4` in the final `fuyao deploy` invocation.
- If the CLI ignores the override due to duplicate flag precedence, follow up by patching the deploy script to make GPU count configurable (e.g., `--gpus-per-node` as explicit script arg) and re-run.

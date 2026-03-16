---
name: Fuyao Remote Submit Command
overview: Provide a ready-to-run remote-kernel command that submits your Fuyao training job via `fuyao_deploy.sh` with your specified project, site/queue, label, and task.
todos:
  - id: verify-flags
    content: Confirm `--queue` spelling and complete task argument formatting.
    status: pending
  - id: provide-remote-command
    content: Provide a single remote-kernel command using the Motion RL runner and deploy script.
    status: pending
isProject: false
---

# Fuyao Remote Submit Command

Use the Motion RL remote runner so the command executes in the `isaacgym` container workspace, then invoke your existing deploy wrapper with corrected flags and quoting.

- Use the remote executor: `bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh ...`
- Call your wrapper script: `/home/huh/software/motion_rl/legged_gym_ws/scripts/fuyao_deploy.sh`
- Pass your options:
  - `--project=rc-wbc`
  - `-f "--site=fuyao_sh_n2 --queue=rcwbc-4090 --experiment=<experiment_name>"`
  - `--label="my_first_fuyao_job"`
  - `--task r01_v111_amp_with_4dof_arms`

Command to run:

```bash
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh \
  bash /home/huh/software/motion_rl/legged_gym_ws/scripts/fuyao_deploy.sh \
  --project=rc-wbc \
  -f "--site=fuyao_sh_n2 --queue=rcwbc-4090 --experiment=<experiment_name>" \
  --label="my_first_fuyao_job" \
  --task r01_v111_amp_with_4dof_arms
```

Notes:

- Your original template had `--queu`; corrected to `--queue`.
- Keep `--experiment=<experiment_name>` as a placeholder and replace it with your actual experiment name.

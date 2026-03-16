---
name: Dry run fuyao deploy
overview: Submit a single training job via the sweep orchestrator (fuyao_deploy.sh) on the current branch, so the user can observe the full output of every bash command invoked during submission.
todos:
  - id: run-deploy
    content: "Run fuyao_deploy.sh with -y flag inside the isaacgym container and show full output"
    status: pending
isProject: false
---

# Deploy Single Training Job via Sweep Orchestrator

Submit one training job to Fuyao using [humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh) on the current branch (`huh/dev_r01_v12_sa_wholestate_female`). The user wants to see the end-to-end terminal output.

## Command

Run inside the isaacgym container via the skill runner:

```bash
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh \
  bash humanoid-gym/scripts/fuyao_deploy.sh \
    -p humanoid \
    -l wholestate_female \
    -t r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes \
    -j 1 \
    -y
```

- `-p humanoid` -- project
- `-l wholestate_female` -- label
- `-t r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes` -- task for this branch
- `-j 1` -- single job (no sweep)
- `-y` -- skip interactive confirmation

## What will happen

1. `fuyao --upgrade` -- upgrade the fuyao CLI
2. `update_repo_deps.sh` -- download model_files and other deps via git archive
3. `rsync` the repo to a temp directory
4. `fuyao deploy` -- submit the job to the `rc-wbc-4090` queue at `fuyao_sh_n2`

The user will see the live output of each step, including the final `fuyao deploy` command with all resolved arguments and the cluster's response (job ID, status, etc.).

## Important

This is a **real** deployment -- `fuyao_deploy.sh` has no dry-run flag. The job will actually be submitted to the Fuyao cluster. Since the previous attempt resulted in "nothing started," seeing the output will help diagnose whether the issue is with the queue, docker image, dependencies, or something else.

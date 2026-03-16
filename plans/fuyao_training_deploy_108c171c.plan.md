---
name: Fuyao training deploy
overview: Run a production-safe Fuyao training submission using the existing `deploy-fuyao` command with required inputs and preflight checks, then verify job startup.
todos:
  - id: collect-inputs
    content: Collect required experiment/task and confirm branch/label strategy.
    status: completed
  - id: resolve-runtime-options
    content: Decide resume/checkpoint pair and RL device default/override.
    status: completed
  - id: submit-deploy
    content: Run deploy-fuyao command with validated arguments and context routing.
    status: completed
  - id: verify-job-start
    content: Check fuyao info/log to confirm training process starts.
    status: completed
isProject: false
---

# Deploy To Fuyao For Training

## Scope

Use the existing command definition at `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)` to submit a remote-kernel training job and verify the run starts correctly.

## Execution Plan

- Confirm required inputs before submit:
  - `experiment`
  - `task` (must resolve to a registered task)
  - branch context (use current branch unless you specify another)
- Determine optional runtime settings:
  - `label` (if omitted, derive from branch by current command policy)
  - resume pair: `--resume` + `--checkpoint_path` (both or neither)
  - RL device (default `cuda:0`, override only if requested)
- Run deployment through the command workflow:
  - route via remote-kernel context detection and `/motion_rl` workdir policy
  - submit `fuyao deploy --remote-kernel ... /bin/bash humanoid-gym/scripts/fuyao_train.sh --task ...`
- Validate submission outcome:
  - capture job name/id
  - run follow-up checks: `fuyao info <job_name>` and `fuyao log <job_name>`
  - confirm training entrypoint launched (`humanoid-gym/scripts/fuyao_train.sh` -> `train.py`)

## Success Criteria

- Fuyao returns a valid job name/id.
- Job transitions out of pending and starts training command.
- No auth/workdir/argument validation errors.

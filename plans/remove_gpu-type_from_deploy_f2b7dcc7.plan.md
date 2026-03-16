---
name: Remove gpu-type from deploy
overview: Remove `--gpu-type` and `--gpu-slice` from all `fuyao deploy` command construction. These flags cause jobs to stall (`EXCLUSIVE`) or be rejected (`shared`) on the `rc-wbc-4090` queue. Successful jobs never pass them -- Fuyao infers GPU type from the queue name.
todos:
  - id: fix-deploy-script
    content: Remove --gpu-type and --gpu-slice from fuyao_deploy.sh command construction
    status: completed
  - id: fix-sweep-dispatcher
    content: Remove --gpu-type and --gpu-slice from sweep dispatcher fuyao deploy command
    status: completed
  - id: fix-skill-docs
    content: Remove gpu_type/gpu_slice references from deploy-fuyao and sweep-fuyao skill docs
    status: completed
  - id: fix-tests
    content: Update test_fuyao_deploy_gpu_config.sh and test_fuyao_deploy_e2e.sh to remove gpu_type assertions
    status: completed
  - id: cancel-and-retest
    content: Cancel stuck jobs, commit, push, sync, run E2E test to verify jobs schedule within ~20s
    status: completed
isProject: false
---

# Remove --gpu-type and --gpu-slice from Fuyao Deploy Pipeline

## Root Cause

Passing `--gpu-type=exclusive` to `fuyao deploy` sets `gpu_type: EXCLUSIVE` on the job, which the `rc-wbc-4090` queue does not support. Jobs stall in `JOB_RECEIVED` indefinitely. Successful jobs on this queue never pass `--gpu-type` -- Fuyao infers `gpu_type: 4090` from the queue name and schedules within seconds.

## Changes

### 1. `fuyao_deploy.sh` -- stop passing gpu flags to fuyao deploy

File: [humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh)

- Remove lines 174-182 (gpu_type_opt / gpu_slice_opt computation)
- Remove line 197 (`${gpu_type_opt}`) from the fuyao_cmd array
- Remove lines 199-201 (gpu_slice_opt conditional append)
- Remove the validation block at lines 386-397 (shared warning, slice consistency check)
- Keep CLI flag parsing (`--gpu_type`, `--gpu_slice`) and the `default_gpu_slice_for_gpus_per_node` function with a comment that they are reserved for future queue support
- Remove `gpu_type='exclusive'` default (line 18) and `gpu_slice=''` (line 19) -- set both to empty strings

### 2. Sweep dispatcher -- stop passing gpu flags

File: [~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh](~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh)

- Line 824: remove `--gpu-type "$GPU_TYPE"` from the deploy_cmd array
- Lines 830-832: remove `--gpu-slice` conditional append
- Lines 207-208: keep `GPU_TYPE`/`GPU_SLICE` emission for payload logging but do not pass to deploy command

### 3. Skill docs -- remove gpu_type references

[~/.cursor/skills/deploy-fuyao/SKILL.md](~/.cursor/skills/deploy-fuyao/SKILL.md):

- Remove `gpu_type` and `gpu_slice` from Optional Inputs
- Remove Multi-GPU Deployment subsection
- Remove GPU safety rule
- Remove `--gpu_type <shared|exclusive>` from multi-GPU command template and manual fallback

[~/.cursor/skills/sweep-fuyao/SKILL.md](~/.cursor/skills/sweep-fuyao/SKILL.md):

- Remove `gpu_type` line from Optional Inputs

### 4. Update tests

[humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh](humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh):

- Remove tests 2-5 (they assert `--gpu-type`/`--gpu-slice` in command output)
- Remove tests 11-16 (exclusive default, sweep dispatcher, skill doc assertions)
- Update `build_fuyao_cmd` to not include gpu_type_opt / gpu_slice_opt
- Keep test 1 (gpu_slice function mapping -- useful reference), tests 6-10 (validation logic)

[humanoid-gym/scripts/test_fuyao_deploy_e2e.sh](humanoid-gym/scripts/test_fuyao_deploy_e2e.sh):

- Remove `--gpu-type=exclusive` from the fuyao deploy command

### 5. Cancel stuck jobs, re-run E2E

- Cancel both stuck jobs: `fuyao cancel --job-name bifrost-2026031304091000-huh8` and `bifrost-2026031304211401-huh8`
- Commit, push, sync remote kernel
- Re-run `test_fuyao_deploy_e2e.sh` -- expect scheduling within ~20 seconds

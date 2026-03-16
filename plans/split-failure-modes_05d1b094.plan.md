---
name: split-failure-modes
overview: "Differentiate and address two independent failure modes: missing URDF assets in parallel worktree deploys, and this run's PhysX/CUDA memory crash during env reset."
todos:
  - id: classify-lockfile-failure
    content: Confirm and document that current lock file is PhysX/CUDA memory failure, not URDF load failure
    status: completed
  - id: asset-preflight-plan
    content: Plan preflight URDF asset existence check in parallel deploy wrapper flow
    status: completed
  - id: physx-canary-plan
    content: Plan low-memory and terrain-isolation canaries for full-scenes task
    status: completed
  - id: failure-taxonomy-plan
    content: Plan wrapper log classification for URDF-missing vs PhysX-memory failures
    status: completed
isProject: false
---

# Separate URDF vs PhysX Failure Modes

## What the new lock file shows

- This run is **not a URDF-load failure**: there is no `Failed to load ...urdf` message, and training progresses through motion dataset download, model construction, and env reset.
- The crash sequence is: `Invalid height samples shape` -> repeated `PxgCudaDeviceMemoryAllocator fail to allocate memory` -> PhysX internal CUDA kernel launch failures -> `CUDA driver error: an illegal memory access was encountered`.
- So this lock file points to a **runtime PhysX/CUDA memory/terrain issue**, distinct from earlier **missing-URDF-in-worktree** failures.

## Investigation and fix plan

- Validate/de-risk the deployment asset path in parallel wrapper flow ([/home/huh/.cursor/scripts/orchestrator_parallel.sh](/home/huh/.cursor/scripts/orchestrator_parallel.sh), [/home/huh/.cursor/scripts/fuyao_deploy_parallel_wrapper.py](/home/huh/.cursor/scripts/fuyao_deploy_parallel_wrapper.py), [/home/huh/.cursor/scripts/deploy_fuyao.sh](/home/huh/.cursor/scripts/deploy_fuyao.sh)):
  - add/verify a preflight check that each job root contains expected `resources/model_files/...urdf` before submit.
  - classify and tag failures as `ASSET_MISSING` when URDF check fails.
- Triage this run’s PhysX failure in task config path ([/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py), [/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_amp_config_with_arms.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_v12_amp_config_with_arms.py), [/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/r01_amp/r01_amp_config.py)):
  - run a canary with reduced memory pressure (`num_envs`, `amp_num_preload_transitions`) to confirm allocator-failure sensitivity.
  - isolate terrain path by toggling from `heightfield` to a simpler terrain mode in canary to test whether the `Invalid height samples shape` warning is causal.
- Improve observability:
  - add log pattern classification in wrapper so postmortem clearly distinguishes `URDF missing` vs `PhysX GPU OOM/illegal access`.

## Expected outcome

- We can independently stabilize parallel deploys against missing model assets and reduce false attribution to URDF for jobs that actually fail due to PhysX/CUDA memory/terrain instability.

---
name: Restore pre-merge add distributed
overview: Restore all files modified by `75a393ead` to their pre-merge (`2f9f1ed24`) versions, then surgically add only the distributed training features as a minimal patch. Work is done in the existing worktree at `/tmp/motion_rl_remerge` on the `remerge-gpu` branch.
todos:
  - id: restore-group-c
    content: Restore amp_on_policy_runner.py, amp_ppo.py, train.py, autoencoder_env.py to pre-merge versions
    status: completed
  - id: patch-runner
    content: Add distributed training features to amp_on_policy_runner.py (accelerator, iron_turbo, sync, broadcast, is_main_process guards)
    status: completed
  - id: patch-ppo
    content: Add distributed training features to amp_ppo.py (accelerator, sync_tensor, sync_gradients)
    status: completed
  - id: patch-train
    content: Add distributed training features to train.py (Accelerator, distributed seed, sys.path)
    status: completed
  - id: patch-autoencoder
    content: Add terrain_simplify and expanded autoencoder features to autoencoder_env.py
    status: completed
  - id: test-and-deploy
    content: Run all tests, push, sync remote, run E2E test, update branch pointer
    status: completed
isProject: false
---

# Restore Pre-Merge Files + Surgical Distributed Training Patch

## File Categories

Based on add/remove analysis of `75a393ead`:

### Group A: Additive-only or minimal changes (keep 75a393ead version as-is)

These files only ADD code without removing pre-existing features:

- `utils/helpers.py` (+6 -0) -- adds `--distributed` arg
- `envs/r01_amp/r01_amp_env.py` (+29 -0) -- adds `_randomize_non_controlled_joint_pos`, leg_only_control
- `scripts/play.py` (+104 -1) -- adds push visualization
- `utils/video_processor.py` (+31 -3) -- adds push overlay, type annotation fix
- `algo/amp_ppo/utils.py` (+5 -3) -- adds `@torch.jit.unused`, `.copy_()` fix

### Group B: Small distributed additions, need review (keep 75a393ead with minor guard restoration)

- `utils/task_registry.py` (+3 -2) -- adds `accelerator=` param passthrough. Safe.
- `algo/ppo/rollout_storage.py` (+3 -2) -- adds `standardize_tensor` import and `accelerator=` param. Safe.

### Group C: Core files that need RESTORE + SURGICAL ADDITIONS

These had destructive removals mixed with distributed additions:


| File                            | Approach                                                                                                                                                                                                                                              |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `motion_loader.py` (-167)       | Already restored in worktree. Done.                                                                                                                                                                                                                   |
| `amp_on_policy_runner.py` (-22) | Restore pre-merge, add: iron_turbo imports, `accelerator` param, `SyncNormalizerTorch` wrapper, `broadcast_parameters`, `is_main_process` guards, `wait_for_everyone`, `set_iteration`, `_sync_logging_metrics`, save/log gating by `is_main_process` |
| `amp_ppo.py` (-12)              | Restore pre-merge, add: iron_turbo imports, `accelerator` param, `sync_tensor`/`sync_gradients` calls, `accelerator.device` resolution                                                                                                                |
| `train.py` (-2)                 | Restore pre-merge, add: `accelerate` import, `--distributed` flow with `Accelerator()`, `get_distributed_seed`, `accelerator` passthrough, autoencoder sys.path setup                                                                                 |
| `autoencoder_env.py` (-138)     | Restore pre-merge, add: terrain_simplify import, expanded autoencoder logic                                                                                                                                                                           |


### Group D: New files (keep as-is)

- `algo/iron_turbo/` (all files) -- entirely new distributed training library

## Execution Steps (in worktree `/tmp/motion_rl_remerge`)

### Step 1: Restore Group C files to pre-merge versions

```bash
for f in amp_on_policy_runner.py amp_ppo.py; do
  git show 2f9f1ed24:humanoid-gym/humanoid/algo/amp_ppo/$f > humanoid-gym/humanoid/algo/amp_ppo/$f
done
git show 2f9f1ed24:humanoid-gym/humanoid/scripts/train.py > humanoid-gym/humanoid/scripts/train.py
git show 2f9f1ed24:humanoid-gym/humanoid/envs/r01_amp/r01_amp_autoencoder_env.py > humanoid-gym/humanoid/envs/r01_amp/r01_amp_autoencoder_env.py
```

### Step 2: Apply distributed training patch to each restored file

For each file, add ONLY the distributed training features from `75a393ead` while keeping all pre-existing features intact. Use the `75a393ead` version as reference for what to add.

Key additions per file:

- **amp_on_policy_runner.py**: `accelerator` param, iron_turbo imports, `SyncNormalizerTorch` wrap, `broadcast_parameters`, `is_main_process` guard on writer/save/log, `wait_for_everyone`, `_sync_logging_metrics`
- **amp_ppo.py**: `accelerator` param, iron_turbo imports, `sync_tensor`/`sync_gradients`, device resolution from accelerator
- **train.py**: `Accelerator` setup, `get_distributed_seed`, `accelerator` passthrough, sys.path for autoencoder
- **autoencoder_env.py**: terrain_simplify import, expanded autoencoder constructor logic from `75a393ead` (this file's additions are mostly new autoencoder features, not distributed training)

### Step 3: Run tests and E2E

- `python3 -m pytest tests/test_import_integrity.py -v`
- `bash scripts/test_fuyao_deploy_gpu_config.sh`
- Push, sync remote, run E2E test

### Step 4: Update original branch

Once E2E passes, update branch pointer and clean up worktree.

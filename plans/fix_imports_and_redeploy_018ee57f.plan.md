---
name: Fix imports and redeploy
overview: Fix the remaining broken import (`height_vae_nn`), harden the static import test to catch package-init gaps, cancel stale pending jobs, commit/push/sync, and redeploy the 4-GPU distributed training job.
todos:
  - id: fix-autoencoder-init
    content: Remove `from .height_vae_nn import *` from humanoid-gym/humanoid/utils/autoencoder/__init__.py
    status: completed
  - id: harden-import-test
    content: Update test_import_integrity.py to visit package __init__.py files for intermediate packages
    status: completed
  - id: run-tests
    content: Run static import integrity test locally to confirm all imports resolve
    status: completed
  - id: cancel-stale-jobs
    content: Cancel pending jobs 19395415 and 19395144 via fuyao CLI
    status: in_progress
  - id: commit-push-sync
    content: Commit, push to origin, sync remote kernel via git reset --hard
    status: pending
  - id: redeploy
    content: Redeploy 4-GPU distributed training job with same parameters
    status: pending
isProject: false
---

# Fix Broken Imports and Redeploy Training Job

## Current State

- Local and remote are at the same HEAD (`8e7aad2e`) on branch `huh/dev_r01_v12_sa_wholestate_female-balance-multi-GPU`
- Previous fixes already committed: `actor_critic_heightmap_embed`/`actor_critic_cross_attention` removed, `terrain_simplify.py` added, pre-flight import check added to `fuyao_train.sh`, `--gpu-type`/`--gpu-slice` added to deploy script
- Two pending jobs (`19395415`, `19395144`) contain stale code artifacts and will fail when scheduled

## Remaining Broken Import

**File:** [humanoid-gym/humanoid/utils/autoencoder/**init**.py](humanoid-gym/humanoid/utils/autoencoder/__init__.py) line 3

```python
from .height_vae_nn import *   # height_vae_nn.py does NOT exist
```

**Impact chain:**

1. `train.py` line 55: `import humanoid.utils.autoencoder.height_encoder_nn`
2. Python loads `autoencoder/__init__.py` first (package init)
3. `from .height_vae_nn import` * -> `ModuleNotFoundError`
4. Same crash via `envs/__init__.py` -> `r01_amp_autoencoder_env.py` -> any autoencoder submodule import

This also means the pre-flight check in `fuyao_train.sh` will catch and abort early, but the job still fails.

## Static Test Gap

[humanoid-gym/tests/test_import_integrity.py](humanoid-gym/tests/test_import_integrity.py) resolves `humanoid.utils.autoencoder.height_encoder_nn` directly to `height_encoder_nn.py` without visiting the package `__init__.py`. At runtime, Python loads the `__init__.py` first. The test should also visit `__init__.py` for every intermediate package in the import path.

## Execution Steps

### 1. Fix autoencoder/**init**.py

- Remove `from .height_vae_nn import` * (line 3)
- File has 4 lines total; result will be 3 lines

### 2. Harden test_import_integrity.py

- In `_visit()`, when a submodule is found (e.g. `utils/autoencoder/height_encoder_nn.py`), also visit the parent package `__init__.py` (e.g. `utils/autoencoder/__init__.py`) so broken package inits are caught
- Add a dedicated test case that validates all `__init__.py` files under `humanoid/` can be parsed and have resolvable relative imports

### 3. Run the static test locally

- `python3 -m pytest tests/test_import_integrity.py -v` must pass after both fixes

### 4. Cancel stale pending jobs

- Cancel `19395415` (`bifrost-2026031216443301-huh8`)
- Cancel `19395144` (`bifrost-2026031216123901-huh8`)
- These contain pre-fix code artifacts

### 5. Commit, push, sync remote

- Commit the two file changes
- `git push origin`
- SSH to remote kernel, `git fetch origin && git reset --hard origin/<branch>`

### 6. Redeploy

- Same parameters as the failed jobs:
  - `--project rc-wbc --label Multi-GPU --task r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes_stability_priority --experiment huh8/r01 --queue 4090 --seeds 42 --nnodes 1 --nproc_per_node 4 --distributed --yes`
- Via SSH to remote kernel using the deploy-fuyao skill contract

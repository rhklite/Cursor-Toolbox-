---
name: Redo GPU merge via worktree
overview: Use `git worktree` to redo the distributed training merge on a separate directory, properly resolving `motion_loader.py` to keep both the main line features (torso_projected_gravity, rigid link states, amp_scene_tag_ratio) and the distributed training additions (iron_turbo, download_files_if_needed, BOM handling, broadcast). Then cherry-pick our valid fix commits on top and validate with the test suite.
todos:
  - id: create-worktree
    content: Create git worktree at /tmp/motion_rl_remerge, reset to pre-merge 2f9f1ed24
    status: completed
  - id: redo-merge
    content: Re-merge e2a5037b4 with proper motion_loader.py resolution keeping both feature sets
    status: completed
  - id: cherry-pick-fixes
    content: Cherry-pick valid fix commits (import fixes, deploy fixes, tests)
    status: completed
  - id: validate
    content: Run test suite in worktree, then E2E test
    status: in_progress
  - id: update-branch
    content: Update branch pointer to worktree HEAD, push, clean up worktree
    status: pending
isProject: false
---

# Redo GPU Branch Merge via Git Worktree

## Problem

Merge `50735b30c` resolved `motion_loader.py` by taking the distributed training version wholesale, discarding:

- `torso_projected_gravity` + 12 rigid link states from `MOCAP_STATE_NAME_MAP`
- `amp_scene_tag_ratio` param and ratio-based sampling logic
- `get_torso_projected_gravity_batch` and optional rigid link state methods

This caused cascading runtime failures (`TypeError`, `ValueError: Unknown state name`).

## Approach

Use `git worktree` at `/tmp/motion_rl_remerge` to build the corrected branch without touching the working directory.

### Step 1: Create worktree and reset to pre-merge

```bash
git worktree add /tmp/motion_rl_remerge huh/dev_r01_v12_sa_wholestate_female-balance-multi-GPU
cd /tmp/motion_rl_remerge
git reset --hard 2f9f1ed24   # pre-merge state
```

### Step 2: Re-merge the distributed training commits

The merge had two parents:

- Parent 1: `2f9f1ed24` (main line, pre-merge)
- Parent 2: `e2a5037b4` (distributed training, tip = stale_timeout fix on top of `75a393ead`)

Re-merge parent 2 with manual resolution of `motion_loader.py`:

```bash
git merge e2a5037b4 --no-commit
```

For `motion_loader.py`, resolve by:

- **Keep** the main line's `MOCAP_STATE_NAME_MAP` (with torso_projected_gravity and rigid link states)
- **Keep** `amp_scene_tag_ratio` param, assignment, and ratio-based sampling logic
- **Add** `download_files_if_needed()` function and `dist` import from the distributed branch
- **Add** BOM-stripping `content.lstrip('\ufeff')` for JSON loading
- **Add** `broadcast_overwrite_from_src` call in preload_transitions
- **Keep** `torso_projected_gravity_dim`, `get_torso_projected_gravity_batch`, optional rigid link methods

For all other files, accept the merge result as-is (the other changes -- iron_turbo, train.py distributed support, etc. -- were correct).

### Step 3: Cherry-pick valid fix commits

From our 8 post-merge commits, cherry-pick only the ones that are still needed:

- `ef2d27074` -- import fixes + tests (terrain_simplify, autoencoder utils, pre-flight check)
- `211d31532` -- remaining autoencoder utils
- `58fafa1e1` -- remove --gpu-type from deploy commands
- `1e6676d87` -- route default queue to rc-wbc

Skip:

- `e1a097b02` (chore: commit before deploy) -- subsumed by re-merge
- `7e827cbac` + `8e7aad2ee` (gpu_type exclusive) -- reverted by `58fafa1e1`
- `302ec370e` (restore amp_scene_tag_ratio) -- already in the re-merge

### Step 4: Validate

- Run `python3 -m pytest tests/test_import_integrity.py -v` in worktree
- Run `bash scripts/test_fuyao_deploy_gpu_config.sh`
- Run E2E test to verify the full pipeline schedules and runs

### Step 5: Update branch pointer

Once validated, force-update the branch to the worktree's HEAD:

```bash
# From main repo
git fetch /tmp/motion_rl_remerge HEAD
git update-ref refs/heads/huh/dev_r01_v12_sa_wholestate_female-balance-multi-GPU FETCH_HEAD
```

Then clean up: `git worktree remove /tmp/motion_rl_remerge`

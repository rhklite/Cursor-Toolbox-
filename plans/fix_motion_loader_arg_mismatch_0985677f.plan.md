---
name: Fix motion loader arg mismatch
overview: Restore `amp_scene_tag_ratio` parameter to `BaseAMPLoader.__init__` that was accidentally dropped in commit `75a393ead` during the distributed training merge, causing a `TypeError` at runtime. Add a static test to catch signature mismatches between parent and child motion loader classes.
todos:
  - id: fix-base-loader
    content: Restore amp_scene_tag_ratio param and assignment in BaseAMPLoader.__init__
    status: completed
  - id: add-signature-test
    content: Add test_motion_loader_signatures to test_import_integrity.py validating super().__init__() compatibility
    status: completed
  - id: verify-e2e
    content: Run import integrity tests, commit, push, sync, and re-run E2E test
    status: completed
isProject: false
---

# Fix BaseAMPLoader / R01AMPLoader Signature Mismatch

## Root Cause

Commit `b923acd21` added `amp_scene_tag_ratio` to both `BaseAMPLoader.__init__` and `R01AMPLoader.__init__`. Commit `75a393ead` (distributed training merge) removed it from `BaseAMPLoader` but left `R01AMPLoader.super().__init__()` still passing it -- 9 args into an 8-param signature.

The parameter is actively used: `BaseAMPLoader` stores it as `self.amp_scene_tag_ratio` and uses it in `preload_transitions` to weight scene tag sampling ratios. Multiple configs set it (`r01_v12_amp_config_with_arms_and_head_full_scenes.py`, etc.) and `r01_amp_env.py` passes it to the loader constructor.

## Fix

Restore `amp_scene_tag_ratio=None` to `BaseAMPLoader.__init__` and restore `self.amp_scene_tag_ratio = amp_scene_tag_ratio` in the body. This is a 2-line change that re-aligns with the pre-`75a393ead` state.

File: [humanoid-gym/humanoid/envs/base/motion_loader.py](humanoid-gym/humanoid/envs/base/motion_loader.py)

```python
# line 64: add amp_scene_tag_ratio=None after amp_scene_tag_lists=None
def __init__(
    self, device, time_between_frames, motion_dataset,
    motion_dataset_version, motion_file_names,
    preload_transitions=False, num_preload_transitions=1000000,
    amp_scene_tag_lists=None,
    amp_scene_tag_ratio=None,   # <-- restore
):
```

```python
# line ~79: add self.amp_scene_tag_ratio after self.amp_scene_tag_dim
self.amp_scene_tag_ratio = amp_scene_tag_ratio   # <-- restore
```

## Test

Add a new test to [humanoid-gym/tests/test_import_integrity.py](humanoid-gym/tests/test_import_integrity.py) that statically validates `super().__init__()` call compatibility:

- Parse `R01AMPLoader.__init`__ and extract the `super().__init__(...)` call arguments
- Parse `BaseAMPLoader.__init`__ signature parameters
- Assert every positional arg in the super call maps to a valid parameter in the parent
- This catches the exact class of bug: child passes more args than parent accepts

Also extend the E2E test to catch runtime failures like this (it already does -- the `JOB_FAILED` status was correctly detected).

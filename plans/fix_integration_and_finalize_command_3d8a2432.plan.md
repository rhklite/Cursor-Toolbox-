---
name: Fix integration and finalize command
overview: Fix the three remaining blockers (missing model files after container restart, empty rigid shape props guard, model file re-download in play script), then run the integration test to completion, and finalize the play_motion_rl.sh command.
todos:
  - id: add-model-check
    content: Add model file existence check to play_motion_rl.sh before launching play script
    status: completed
  - id: integration-run
    content: Run full end-to-end integration test with restored model files
    status: completed
  - id: verify-curves
    content: Verify PlotJuggler curves auto-populate with live data (screenshot confirmation)
    status: completed
  - id: iterate-fixes
    content: If any step fails, diagnose and fix, then re-run until fully passing
    status: completed
isProject: false
---

# Fix Integration Blockers and Finalize /play-motion-rl

## Root cause chain discovered

The end-to-end test fails because of a cascade:

1. **Container restart wipes model files** -- the healthcheck runs `docker restart isaacgym`, which triggers the post-checkout git hook, which runs `update_repo_deps.sh`. That script does `rm -rf resources/model_files/` then re-downloads from GitLab. If the download fails (network/auth), the directory is left empty.
2. **Empty model files -> empty rigid shape props** -- IsaacGym loads a URDF that doesn't exist, producing an asset with 0 rigid shapes. The existing `rigid_shape_props_asset[1]` crashes with IndexError.
3. **Even with the index guard, collision groups fail** -- `_process_collision_group` can't find body names because the asset loaded from a missing URDF has no bodies.

The model files have just been re-downloaded successfully. The legged_robot.py guard is already in place. The only remaining step is to verify the integration test passes, then ensure `play_motion_rl.sh` handles this scenario.

## Changes

### 1. Add model file check to `play_motion_rl.sh`

Before launching the play script, verify the model files directory is populated. If empty, run `update_repo_deps.sh` to re-download:

```bash
# In play_motion_rl.sh, before docker exec play script
URDF_DIR="${REMOTE_WORKDIR}/resources/model_files/r01_v12_parallel_ankle/urdf"
if [ ! -d "${URDF_DIR}" ] || [ -z "$(ls -A "${URDF_DIR}" 2>/dev/null)" ]; then
  info "Model files missing — re-downloading..."
  bash "${REMOTE_WORKDIR}/scripts/update_repo_deps.sh" --force
fi
```

### 2. Keep the legged_robot.py guard (already applied)

The empty-list guard at line 1084 remains as a defensive measure. No further changes needed.

### 3. Run integration test to completion

With model files restored, re-run:

```bash
bash ~/.cursor/scripts/play_motion_rl.sh --checkpoint <path> --skip-health --no-pull
```

Verify: play script starts, UDP data flows, PlotJuggler layout loads, curves auto-populate.

### 4. Iterate if any new errors appear

If the test fails, diagnose and fix. Repeat until the full sequence succeeds with live data in PlotJuggler.

## Files to modify

- `[~/.cursor/scripts/play_motion_rl.sh](~/.cursor/scripts/play_motion_rl.sh)` -- add model file check before play script launch
- `[humanoid-gym/humanoid/envs/base/legged_robot.py](humanoid-gym/humanoid/envs/base/legged_robot.py)` -- already fixed, verify only

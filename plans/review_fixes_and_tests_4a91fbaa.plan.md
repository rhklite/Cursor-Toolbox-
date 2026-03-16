---
name: Review fixes and tests
overview: Fix 3 bugs found during code review (DOF-to-body naming, per-frame class creation, missing stdout flush) and write unit tests for all testable logic using mocked Isaac Gym dependencies.
todos:
  - id: fix-dof-map
    content: Fix _build_dof_body_map name convention to produce leg_l_link1 from leg_l_1
    status: completed
  - id: fix-arc-class
    content: Move _ArcGeom class to module level
    status: completed
  - id: fix-flush
    content: Add flush=True to all print() calls in event handlers
    status: completed
  - id: write-tests
    content: Write test_play_interactive.py with mocked isaacgym and all test cases
    status: completed
isProject: false
---

# Review Fixes and Tests for play_interactive.py

## Bugs to Fix

### 1. `_build_dof_body_map` wrong name transformation

Current: `dof_name.replace("_", "_link", 1)` -- for `leg_l_1` gives `leg_link_l_1`.
Expected: `leg_l_link1`.

Fix: instead of blind string replace, try `dof_index + 1` as primary strategy (works for serial kinematic chains), and use name matching as fallback. The R01 dof names follow patterns like `leg_l_1` through `leg_l_6`, `waist_1` through `waist_5`, `arm_l_1` through `arm_l_4`. Body names follow `leg_l_link1` through `leg_l_link6`, etc. The mapping is: strip trailing digit from dof name, insert `link` before digit.

```python
import re
m = re.match(r"(.+?)(\d+)$", dof_name)
if m:
    candidate = f"{m.group(1)}link{m.group(2)}"
```

### 2. `_ArcGeom` class per-frame allocation

Move to module level alongside `WireframeArrowGeometry`.

### 3. Missing stdout flush

Add `flush=True` to all `print()` calls in event handlers, or add `sys.stdout.flush()` at end of `_process_events`.

## Test File

Create [humanoid-gym/tests/test_play_interactive.py](humanoid-gym/tests/test_play_interactive.py).

Since `play_interactive.py` imports `isaacgym` at module level (unavailable on Mac), tests must mock the imports before importing the module. Use `sys.modules` patching to inject mock isaacgym, then import the target functions.

### Test Cases

**InteractiveState defaults:**

- `auto_eval` is True
- `mode` is MODE_VELOCITY (3)
- `push_vec_xy` is [0, 0], `push_yaw` is 0
- `failed_joints` is empty set
- `running` is True

**Step size computation:**

- `_compute_vel_steps` with known ranges returns 10% of abs(max)
- Zero range falls back to 0.1/10 = 0.01
- `_compute_push_step` and `_compute_push_ang_step` with mock env config

**DOF-to-body mapping (with fix):**

- Known dof_names + body_names produces correct index mapping
- Fallback to `i+1` when no name match

**Mode switching via events:**

- Events "mode_push", "mode_failure", "mode_velocity" set `state.mode` correctly

**Velocity mode WASD/QE:**

- W increments `user_commands[:, 0]` by `vel_steps["lin_vel_x"]`
- S decrements, A/D for y, Q/E for yaw
- Only active in velocity mode

**Push mode WASD/QE:**

- W/S increment/decrement `push_vec_xy[0]`
- A/D for `push_vec_xy[1]`
- Q/E for `push_yaw`
- Only active in push mode

**Failure mode Q/E:**

- Q decrements cursor, adds to `failed_joints`
- E increments cursor, adds to `failed_joints`
- Wraps around `num_dof`

**zero_all (Space):**

- Zeros `user_commands`, `push_vec_xy`, `push_yaw`
- Clears `failed_joints`
- Clears `failure_triggered` if present

**full_reset (R):**

- Calls `env.reset_idx`
- Zeros everything
- Clears `failure_triggered`

**Auto-eval toggle:**

- Toggle ON sets `push_robots = True`, `stability_curriculum_stage = 3`, `push_curriculum_frac = 1.0`
- Toggle OFF restores original values

**Action override for failed joints:**

- Actions at failed joint indices are set to 0.0
- Actions at non-failed indices are untouched

**Apply disturbances:**

- Linear push adds to `root_states[:, 7:9]`
- Yaw push adds to `root_states[:, 12]`
- Calls `set_actor_root_state_tensor_indexed`
- Sets `failure_triggered` if failed joints exist

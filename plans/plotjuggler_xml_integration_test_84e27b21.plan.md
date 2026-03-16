---
name: PlotJuggler XML integration test
overview: Fix the signal path mismatch in `r01_plus_amp_plotjuggler_limit_inspect.xml`, add `dof_pos_limits` emission to `RobotData`, write an automated XML-vs-UDP signal compatibility test, and run a manual validation in the Isaac Gym container.
todos:
  - id: add-dof-pos-limits
    content: Add `dof_pos_limits` dict (lower/upper per DOF) to `RLExtraInfo` in `robot_data.py`
    status: completed
  - id: fix-xml-paths
    content: Rewrite all curve names in `r01_plus_amp_plotjuggler_limit_inspect.xml` to match `RobotData.asdict()` flattened paths
    status: completed
  - id: write-test
    content: Create `test_plotjuggler_xml_signals.py` — offline test validating XML curve names against RobotData signal paths
    status: completed
  - id: manual-validation
    content: "Run live validation in Isaac Gym container (if available): capture UDP, diff against XML curves"
    status: completed
isProject: false
---

# PlotJuggler XML Integration Test

## Problem

The XML layout file [`r01_plus_amp_plotjuggler_limit_inspect.xml`](humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml) uses signal paths that do not match what `RobotData.asdict()` emits via UDP:

- XML uses `/learning_data/joint_positions[N]` -- code emits `/learning/rl_extra_info/joint_positions/<dof_name>`
- XML uses `/learning_data/dof_pos_limits[N][0|1]` -- code does **not** emit per-joint DOF position limits at all

The working reference layout [`r01_plotjuggler_full.xml`](humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml) correctly uses paths like `/learning/rl_obs_unscaled/gravity_vec_in_pelvis/x`.

## Step 1: Add `dof_pos_limits` emission to `RLExtraInfo`

In [`robot_data.py`](humanoid-gym/humanoid/envs/base/robot_data.py), inside `RLExtraInfo.__init__`, add a `dof_pos_limits` dict keyed by DOF name with `lower`/`upper` sub-keys, sourced from `env.dof_pos_limits`:

```python
self.dof_pos_limits = {}
for i in range(env.num_dofs):
    self.dof_pos_limits[env.dof_names[i]] = {
        "lower": env.dof_pos_limits[i, 0].item(),
        "upper": env.dof_pos_limits[i, 1].item(),
    }
```

Add the field declaration to the `RLExtraInfo` dataclass.

This produces UDP paths like `/learning/rl_extra_info/dof_pos_limits/leg_l_joint1/lower`.

## Step 2: Fix XML signal paths

Rewrite all `<curve name="..."/>` entries in `r01_plus_amp_plotjuggler_limit_inspect.xml`:

**DOF name mapping** (R01 Plus with Arms, 23 DOFs):
- Indices 0-5: `leg_l_joint1` through `leg_l_joint6`
- Indices 6-11: `leg_r_joint1` through `leg_r_joint6`
- Indices 12-14: `waist_yaw`, `waist_roll`, `waist_pitch`
- Indices 15-18: `arm_L_joint1` through `arm_L_joint4`
- Indices 19-22: `arm_R_joint1` through `arm_R_joint4`

**Replacements:**
- `/learning_data/joint_positions[N]` becomes `/learning/rl_extra_info/joint_positions/<dof_name>`
- `/learning_data/dof_pos_limits[N][0]` becomes `/learning/rl_extra_info/dof_pos_limits/<dof_name>/lower`
- `/learning_data/dof_pos_limits[N][1]` becomes `/learning/rl_extra_info/dof_pos_limits/<dof_name>/upper`

Also uncomment the `<previouslyLoaded_Streamer>` line to restore auto-connect.

**Note:** The exact DOF names (especially casing like `leg_l_` vs `leg_L_`) come from the URDF loaded by Isaac Gym. If the R01 Plus config uses lowercase (`leg_l_joint1`), use that. Verify by checking the config at [`r01_plus_amp_config.py`](humanoid-gym/humanoid/envs/r01_amp/r01_plus_amp_config.py) (lowercase) and [`r01_plus_amp_config_with_arms.py`](humanoid-gym/humanoid/envs/r01_amp/r01_plus_amp_config_with_arms.py) (arms use uppercase `arm_L_joint1`).

## Step 3: Write automated compatibility test

Add a test in [`humanoid-gym/tests/`](humanoid-gym/tests/) (e.g., `test_plotjuggler_xml_signals.py`):

1. Parse all `<curve name="..."/>` from each PlotJuggler XML under `datasets/tool/config/`
2. Build the set of valid flattened signal paths from `RobotData` and `R01RobotData` dataclass structure (recursive `dataclasses.fields()` traversal, with known DOF name lists from configs)
3. Assert every XML curve name exists in the valid signal path set
4. This test runs **offline** -- no Isaac Gym or GPU required

Key files to import/inspect:
- `robot_data.py` for `RobotData`, `RLExtraInfo`, `LearningData`
- `r01_robot_data.py` for `R01RobotData`, `R01LearningData`
- Config files for DOF name lists

## Step 4: Manual validation in Isaac Gym container

If the container is available, run a live test:

1. Start `play.py` or `visualize_r01_motion.py` inside the Isaac Gym container using the skill runner script
2. Capture UDP output on port 9870 using `match_udp_signals.py` from the PlotJuggler skill
3. Diff captured signal paths against XML curve names
4. Optionally open PlotJuggler on the host with the fixed XML layout

This step depends on container availability and a valid checkpoint; it may be skipped if the container is not running.

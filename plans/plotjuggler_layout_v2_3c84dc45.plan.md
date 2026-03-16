---
name: PlotJuggler Layout v2
overview: Generate a PlotJuggler layout XML for all motion_rl UDP signals (R01RobotData), organized into 11 tabs with a three-tier color system (gray=context, axis-color=measurement, orange=error), consistent reward term palette, and an overview dashboard.
todos:
  - id: verify-reactive-script
    content: Test PlotJuggler reactive script syntax for multi-source subtraction (ERR curves) using a minimal XML before generating the full layout
    status: completed
  - id: gen-layout-xml
    content: Generate the complete PlotJuggler XML with all 11 tabs, DockSplitter structure, curve elements, reactive scripts, and verified signal paths
    status: completed
  - id: place-file
    content: Write XML to humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml
    status: completed
isProject: false
---

# PlotJuggler Layout v2

## Scope

- Target: `R01RobotData.asdict()` payload from [robot_data.py](humanoid-gym/humanoid/envs/base/robot_data.py), [r01_robot_data.py](humanoid-gym/humanoid/envs/r01_amp/r01_robot_data.py)
- 23 DOFs: `leg_l_joint1-6`, `leg_r_joint1-6`, `waist_yaw/roll/pitch`, `arm_L_joint1-4`, `arm_R_joint1-4`
- Signal path convention: `/` for dict keys, `[index]` for JSON arrays
- UDP port `9870`, streamer: `UDP Server`
- Output: `humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml`
- Existing layout reference for XML schema: [r01_plus_amp_plotjuggler_limit_inspect.xml](humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml)

---

## Color System

### Three-tier hierarchy (Tabs 1-7, 9-10)

Instant read -- no legend needed:

- **Gray `#b0b0b0`** = context (commands, targets, PD-intent). Darker gray `#808080` for secondary context.
- **Axis colors** = actual measurements: X/Roll blue `#1f77b4`, Y/Pitch green `#2ca02c`, Z/Yaw red `#d62728`. Lighter variants for instantaneous vs smoothed: `#6baed6`, `#74c476`, `#fc9272`.
- **Orange `#ff7f0e`** = tracking error (computed error curves only).
- **Light gray `#cccccc`** = bound reference lines (REF_0.0, REF_1.0).

Per-joint quantity mapping (single-joint plots): Position=Blue, Velocity=Green, Torque=Red.
L/R arm overlay: Left=Blue `#1f77b4`, Right=Teal `#17becf`.

### Reward palette (Tab 0 dashboard, Tab 8, and per-tab reward subplots)

A separate categorical palette that avoids blue/green/red/orange/gray to prevent cross-tab confusion:

- `tracking_avg_lin_vel`: Purple `#9467bd`
- `tracking_avg_ang_vel`: Brown `#8c564b`
- `torques`: Pink `#e377c2`
- `dof_acc`: Olive `#bcbd22`
- `action_rate`: Teal `#17becf`
- `foot_distance_limit`: Gold `#e7ba52`
- `stand_still`: Magenta `#c5b0d5`
- `torque_limits`: Slate `#7f7f7f`
- `dof_vel_limits`: Coral `#ff9896`
- `dof_pos_limits`: Lime `#98df8a`
- `feet_contact_forces`: Plum `#c49c94`
- `torque_rate`: Sky `#aec7e8`
- `total_reward` (Row 2 only): Black `#000000`

These colors are used identically in Tab 8 Rows 1/3, in all per-tab reward subplots, and in the Tab 0 dashboard.

---

## Tabs (11 total)

### Tab 0: "Dashboard"

Single-screen health summary. The user glances here first.

**Layout:** 2x2 grid.

- **(top-left) "Velocity Error"**: `ERR_vel_x`, `ERR_vel_y`, `ERR_vel_yaw` -- all orange `#ff7f0e`, REF at 0.0
- **(top-right) "Body Tilt"**: `gravity_vec_in_pelvis/x` blue, `/y` green (deviation from [0,0,-1] indicates tilt)
- **(bottom-left) "Total Reward"**: `/learning/rl_extra_info/total_reward` -- black, REF at 0.0
- **(bottom-right) "Foot Contact"**: `feet_0_force/force` blue `#1f77b4`, `feet_1_force/force` teal `#17becf`

### Tab 1: "Velocity Tracking"

5 plots stacked. Three-tier colors.

- **Plot 1 "Vel X"**: cmd gray `#b0b0b0`, instantaneous light blue `#6baed6`, avg blue `#1f77b4`, ERR orange `#ff7f0e`
- **Plot 2 "Vel Y"**: cmd gray, instantaneous light green `#74c476`, avg green `#2ca02c`, ERR orange
- **Plot 3 "Vel Yaw"**: cmd gray, avg red `#d62728`, ERR orange
- **Plot 4 "Vel Z"**: actual red `#d62728` (no tracking pair)
- **Plot 5 "Velocity Rewards"**: `tracking_avg_lin_vel` purple `#9467bd`, `tracking_avg_ang_vel` brown `#8c564b`, `stand_still` magenta `#c5b0d5`, REF_1.0 + REF_0.0 light gray

### Tab 2: "Body Orientation"

2 columns (Pelvis | Torso), 3 rows + reward row. All Tier 2 measurement, axis colors (blue/green/red for roll/pitch/yaw or x/y/z).

- Plots 1-2: Euler angles. Plots 3-4: Gravity vector. Plots 5-6: Angular velocity.
- Plot 7: Reward subplot -- `orientation` purple `#9467bd`, `ang_vel_xy` brown `#8c564b`, REF_0.0

### Tab 3: "Left Leg Joints" / Tab 4: "Right Leg Joints"

6 joint plots + 1 reward. Position blue `#1f77b4`, velocity green `#2ca02c`.

- Reward subplot: `dof_pos_limits` lime `#98df8a`, `dof_vel_limits` coral `#ff9896`, `dof_acc` olive `#bcbd22`, REF_0.0

### Tab 5: "Waist and Arm Joints"

Waist: position blue, velocity green. Arms: L blue `#1f77b4`, R teal `#17becf`.

- Reward subplot: `waist_soft_limit` gold `#e7ba52`, `tracking_waist_yaw` purple `#9467bd`, REF_1.0 + REF_0.0

### Tab 6: "RL Actions and Targets"

12 plots (L/R x 6 joints). **Revised semantics** -- both targets are gray context, but the position deviation is reclassified:

- `rl_joint_target_position` -- gray `#b0b0b0` (target)
- `rl_actions` -- dark gray `#808080` (policy output)
- `joint_positions_difference` -- olive `#bcbd22` (deviation from default, NOT a tracking error -- avoid orange)

Reward subplot: `action_rate` teal `#17becf`, `default_joint_pos` purple `#9467bd`, REF_1.0 + REF_0.0

### Tab 7: "Joint Torques"

15 plots (L/R legs x 6 + waist x 3).

- `control_output/.../torque` -- gray `#b0b0b0` (PD-computed intent)
- `rl_clamped_.../torque` -- red `#d62728` (actually applied)

Reward subplot: `torques` pink `#e377c2`, `torque_limits` slate `#7f7f7f`, `torque_rate` sky `#aec7e8`, REF_0.0

### Tab 8: "Rewards"

**Key fix: split the overlay into two readable plots instead of one 12-curve mess.**

**Layout:** 4 rows.

- **Row 1 (~25%) "Tracking Rewards (per step)"**: Only the 2 exp-based tracking terms overlaid. These are bounded [0, scale], making the plot readable.
  - `scaled_rewards/tracking_avg_lin_vel` purple, `scaled_rewards/tracking_avg_ang_vel` brown
  - REF_0.0
- **Row 2 (~25%) "Penalty Terms (per step)"**: The 10 negative-scale penalty terms overlaid. All are <= 0, making the Y-axis coherent.
  - `scaled_rewards/torques`, `dof_acc`, `action_rate`, `foot_distance_limit`, `stand_still`, `torque_limits`, `dof_vel_limits`, `dof_pos_limits`, `feet_contact_forces`, `torque_rate` (reward palette colors)
  - REF_0.0
- **Row 3 (~15%) "Total Reward (per step)"**: Single curve.
  - `total_reward` black `#000000`, REF_0.0
- **Row 4 (~35%) "Cumulative Episode Rewards"**: All `episode_sums/<name>` overlaid. Same reward palette colors as Rows 1-2. Shows long-term impact per term.
  - REF_0.0

### Tab 9: "Foot Contact Forces"

L/R rows, magnitude + XYZ per foot. Axis colors for XYZ, red for magnitude.

- Reward subplot: `feet_contact_forces` plum `#c49c94`, `feet_air_time` gold `#e7ba52`, REF_0.0

### Tab 10: "Foot Cartesian State"

L/R columns, position/velocity/euler rows. Axis colors.

- Reward subplot: `foot_distance_limit` gold `#e7ba52`, `feet_vel` coral `#ff9896`, REF_0.0

---

## Reactive Scripts

### Reference lines

```xml
<snippet name="REF_1.0">
  <global_vars/>
  <equation>return 1.0</equation>
  <linked_source>/learning/rl_extra_info/raw_rewards/tracking_avg_lin_vel</linked_source>
</snippet>
<snippet name="REF_0.0">
  <global_vars/>
  <equation>return 0.0</equation>
  <linked_source>/learning/rl_extra_info/raw_rewards/torques</linked_source>
</snippet>
```

### Tracking error curves

**Risk:** PlotJuggler reactive script syntax for multi-source subtraction must be verified at implementation time. The known-working approach uses `$$SERIES$$` Lua notation. If the `<additional_source>` approach fails, fallback is PlotJuggler's built-in "Custom Series" dialog (`A - B` formula) which generates equivalent XML. Verify with a quick test before generating the full layout.

```
ERR_vel_x = /learning/rl_obs_unscaled/cmd/root_lin_vel_x - /learning/rl_extra_info/pelvis_lin_vel/lin_vel_x
ERR_vel_y = /learning/rl_obs_unscaled/cmd/root_lin_vel_y - /learning/rl_extra_info/pelvis_lin_vel/lin_vel_y
ERR_vel_yaw = /learning/rl_obs_unscaled/cmd/root_ang_vel_yaw - /learning/rl_extra_info/base_avg_vel/ang_vel_z
```

All rendered in orange `#ff7f0e`.

---

## Changes from v1

- **Added Tab 0 (Dashboard)**: 2x2 overview for instant health check
- **Fixed Tab 8**: Split 12-curve overlay into tracking (2 curves) + penalties (10 curves) on separate plots. Readability fixed.
- **Fixed color conflicts**: Reward palette now uses purple/brown/pink/olive/teal/gold/magenta/slate/coral/lime/plum/sky -- no overlap with blue/green/red/orange/gray tiers
- **Fixed Tab 6 semantics**: `joint_positions_difference` is now olive (not orange), correctly reflecting it as "deviation from default" rather than a tracking error
- **Specified reward subplot colors**: All per-tab reward curves now have explicit colors from the reward palette
- **Flagged reactive script risk**: Added fallback strategy for error curve implementation
- **Reward colors are consistent everywhere**: Same color per reward term across Tab 8, Tab 0, and per-tab subplots

## Excluded signals

- `*/system`, `*/timestamp`, `*/quaternion[0-3]`, `control_output/joint/*/kp|kd`, `learning/rl_obs_unscaled/current_joint_velocities/`*, `learning/rl_obs_unscaled/clipped_action_data/*`, `learning/rl_extra_info/joint_positions/*`, `control_input/cartesian/root_command/position[*]`

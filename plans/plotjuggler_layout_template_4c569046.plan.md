---
name: PlotJuggler Layout Template
overview: Create a comprehensive PlotJuggler layout XML covering all UDP signals from `RobotData.asdict()` (R01RobotData variant), organized into 10 functional tabs for real-time humanoid robot visualization.
todos:
  - id: gen-layout-xml
    content: Generate PlotJuggler XML layout file with all 10 tabs, proper DockSplitter structure, and curve elements using exact signal paths
    status: pending
  - id: gen-ref-and-error
    content: Add Reactive Script snippets for REF_1.0, REF_0.0 reference lines and ERR_vel_x/y/yaw tracking error curves; wire into reward subplots and velocity tracking plots with correct colors
    status: pending
  - id: verify-paths
    content: Cross-check all signal paths against RobotData.asdict() output structure to ensure array vs dict indexing is correct
    status: pending
  - id: place-file
    content: Write XML to humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml alongside existing layout
    status: pending
isProject: false
---

# PlotJuggler Layout Template for motion_rl UDP Signals

## Scope

- Targets `R01RobotData` payload (superset of base `RobotData`, adds `gravity_vec_in_torso`)
- Source: [robot_data.py](humanoid-gym/humanoid/envs/base/robot_data.py), [r01_robot_data.py](humanoid-gym/humanoid/envs/r01_amp/r01_robot_data.py)
- 23 DOFs: `leg_l_joint1-6`, `leg_r_joint1-6`, `waist_yaw/roll/pitch`, `arm_L_joint1-4`, `arm_R_joint1-4`
- Signal path convention: `/` for dict nesting, `[index]` for JSON arrays (matches existing layout in [r01_plus_amp_plotjuggler_limit_inspect.xml](humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml))
- Reward names use base config superset (12 terms from `R01AMPCfg`); user may add task-specific rewards post-generation
- UDP streamer on port `9870`
- Output file: `humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml`

---

## Global Color Palette

**Principle: Three-tier visual hierarchy.** The user reads any plot instantly without checking the legend:

1. **Gray = context** -- commands, targets, references. "What was the robot told to do?"
2. **Colored = measurement** -- actual state data. "What is the robot doing?"
3. **Orange = problem** -- tracking error, deviation. "How far off is it?"

PlotJuggler layout XML does not support per-curve line styles. The entire role convention is expressed through color.

### Tier 1: Context (commands, targets, references)

All commands and targets are gray, pushing them to the visual background.

- **Command / target**: `#b0b0b0`
- **Secondary target** (e.g., policy action alongside a position target): `#808080`
- **Bound reference lines** (REF_0.0, REF_1.0): `#cccccc`

### Tier 2: Measurement (actual state, per-axis hue)

Actual measurements use axis-consistent colors. Hue = which dimension; plot title = what quantity.

- **X / Forward / Roll**: Blue `#1f77b4`
- **Y / Lateral / Pitch**: Green `#2ca02c`
- **Z / Vertical / Yaw**: Red `#d62728`

For filtered/averaged variants of the same measurement, a lighter shade distinguishes instantaneous from filtered:

- **Instantaneous actual**: lighter shade (`#6baed6` for X, `#74c476` for Y, `#fc9272` for Z)
- **Smoothed / averaged actual**: standard shade (`#1f77b4`, `#2ca02c`, `#d62728`)

### Tier 3: Problem (error, deviation)

A single accent color everywhere. When you see orange, something is off.

- **Error / deviation**: Orange `#ff7f0e`

### Per-Joint Quantity Colors (single-joint plots, Tabs 3-7)

No X/Y/Z axis applies. Hue identifies the physical quantity:

- **Position**: Blue `#1f77b4`
- **Velocity**: Green `#2ca02c`
- **Torque (applied)**: Red `#d62728`

### Left / Right Body Distinction (arm overlay plots)

- **Left**: Blue `#1f77b4`
- **Right**: Teal `#17becf`

---

## Tab Layout (10 Tabs)

### Tab 1: "Velocity Tracking"

Compare commanded vs actual vs running-average velocities. The primary debugging view for locomotion policies.

**Layout:** 5 plots stacked vertically (4 state + 1 reward).

- **Plot 1 - "Linear Vel X (Fwd/Back)"**
  - `/learning/rl_obs_unscaled/cmd/root_lin_vel_x` -- gray `#b0b0b0` (command)
  - `/learning/rl_extra_info/pelvis_lin_vel/lin_vel_x` -- light blue `#6baed6` (instantaneous actual)
  - `/learning/rl_extra_info/base_avg_vel/lin_vel_x` -- blue `#1f77b4` (smoothed avg)
  - `ERR_vel_x` -- **orange `#ff7f0e`** (error = cmd - actual)
- **Plot 2 - "Linear Vel Y (Lateral)"**
  - `/learning/rl_obs_unscaled/cmd/root_lin_vel_y` -- gray `#b0b0b0`
  - `/learning/rl_extra_info/pelvis_lin_vel/lin_vel_y` -- light green `#74c476`
  - `/learning/rl_extra_info/base_avg_vel/lin_vel_y` -- green `#2ca02c`
  - `ERR_vel_y` -- **orange `#ff7f0e`** (error = cmd - actual)
- **Plot 3 - "Angular Vel Yaw"**
  - `/learning/rl_obs_unscaled/cmd/root_ang_vel_yaw` -- gray `#b0b0b0`
  - `/learning/rl_extra_info/base_avg_vel/ang_vel_z` -- red `#d62728` (smoothed avg)
  - `ERR_vel_yaw` -- **orange `#ff7f0e`** (error = cmd - avg)
- **Plot 4 - "Linear Vel Z (Vertical)"**
  - `/learning/rl_extra_info/pelvis_lin_vel/lin_vel_z` -- red `#d62728` (actual, no tracking pair)
- **Plot 5 - "Velocity Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/tracking_avg_lin_vel` -- exp-based, ref line at **1.0**
  - `/learning/rl_extra_info/raw_rewards/tracking_avg_ang_vel` -- exp-based, ref line at **1.0**
  - `/learning/rl_extra_info/raw_rewards/stand_still` -- penalty, ref line at **0.0**
  - `REF_1.0` (light gray `#cccccc`, constant 1.0)
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 2: "Body Orientation"

Monitor pelvis/torso orientation and angular velocity for stability analysis. All XYZ/RPY follow axis colors: Blue/Green/Red. No tracking pairs here -- all curves are Tier 2 (measurement).

**Layout:** 2 columns (Pelvis | Torso), 3 rows + reward row.

- **Plot 1 (L) - "Root Euler Angles"**
  - `euler[0]` -- blue `#1f77b4` (roll)
  - `euler[1]` -- green `#2ca02c` (pitch)
  - `euler[2]` -- red `#d62728` (yaw)
- **Plot 2 (R) - "Torso Euler Angles"** -- same colors
- **Plot 3 (L) - "Gravity in Pelvis Frame"**
  - `x` -- blue `#1f77b4`, `y` -- green `#2ca02c`, `z` -- red `#d62728`
- **Plot 4 (R) - "Gravity in Torso Frame"** -- same colors *(R01-only)*
- **Plot 5 (L) - "Pelvis Angular Velocity"**
  - `ang_vel_x` -- blue `#1f77b4`, `ang_vel_y` -- green `#2ca02c`, `ang_vel_z` -- red `#d62728`
- **Plot 6 (R) - "Torso Angular Velocity"** -- same colors
- **Plot 7 (full-width bottom) - "Orientation Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/orientation` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/ang_vel_xy` -- penalty, ref line at **0.0**
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 3: "Left Leg Joints"

**Layout:** 6 joint plots + 1 reward plot stacked vertically. All curves are Tier 2 (measurement). Position = Blue, Velocity = Green.

Each joint plot contains:

- `/state/joint/leg_l_joint<N>/position` -- blue `#1f77b4`
- `/state/joint/leg_l_joint<N>/velocity` -- green `#2ca02c`

Joints: `leg_l_joint1` through `leg_l_joint6`

- **Plot 7 (bottom) - "Leg Joint Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/dof_pos_limits` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/dof_vel_limits` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/dof_acc` -- penalty, ref line at **0.0**
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 4: "Right Leg Joints"

Same structure and colors as Tab 3 for `leg_r_joint1` through `leg_r_joint6`, with same reward subplot.

---

### Tab 5: "Waist and Arm Joints"

**Layout:** Left column (Waist, 3 plots) | Right column (Arms, 4 plots with L/R overlaid).

- **Waist plots** (Position = Blue, Velocity = Green):
  - `waist_yaw` - position `#1f77b4`, velocity `#2ca02c`
  - `waist_roll` - position `#1f77b4`, velocity `#2ca02c`
  - `waist_pitch` - position `#1f77b4`, velocity `#2ca02c`
- **Arm plots** (L/R overlay: Left = Blue, Right = Teal):
  - "Arm Joint 1": L `#1f77b4`, R `#17becf`
  - "Arm Joint 2": L `#1f77b4`, R `#17becf`
  - "Arm Joint 3": L `#1f77b4`, R `#17becf`
  - "Arm Joint 4": L `#1f77b4`, R `#17becf`
- **Bottom plot (full-width) - "Waist/Arm Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/waist_soft_limit` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/tracking_waist_yaw` -- exp-based, ref line at **1.0**
  - `REF_1.0` (light gray `#cccccc`, constant 1.0)
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 6: "RL Actions and Targets - Legs"

Policy output actions vs joint target positions. Targets are gray (Tier 1), deviation is orange (Tier 3).

**Layout:** 2 columns (Left Leg | Right Leg), 6 rows.

Each plot (12 total) contains:

- `/learning/rl_actions/<dof>` -- dark gray `#808080` (secondary target / policy output)
- `/learning/rl_joint_target_position/<dof>` -- gray `#b0b0b0` (position target)
- `/learning/rl_obs_unscaled/joint_positions_difference/<dof>` -- **orange `#ff7f0e`** (position deviation, most prominent)

Left: `leg_l_joint1-6` | Right: `leg_r_joint1-6`

- **Bottom plot (full-width) - "Action Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/action_rate` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/default_joint_pos` -- exp-based, ref line at **1.0**
  - `REF_1.0` (light gray `#cccccc`, constant 1.0)
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 7: "Joint Torques"

**Layout:** 2 columns (Left | Right), 6 rows for legs, then waist row below.

Each plot (15 total) overlays:

- `/control_output/joint/<dof>/torque` -- gray `#b0b0b0` (PD-computed, before clamping = "intended")
- `/learning/rl_clamped_total_open_chain_joint_torque/<dof>` -- red `#d62728` (clamped/effective = actual applied torque)
- Left column: `leg_l_joint1-6`
- Right column: `leg_r_joint1-6`
- Bottom row (3 plots): `waist_yaw`, `waist_roll`, `waist_pitch`
- **Bottom plot (full-width) - "Torque Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/torques` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/torque_limits` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/torque_rate` -- penalty, ref line at **0.0**
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 8: "Rewards"

Three vertically stacked views showing per-step breakdown, net reward, and cumulative episode impact. Each reward term uses the same color across all three plots so the user can trace a term from instantaneous contribution to cumulative effect.

**Reward term color assignments** (consistent across all three plots):

- `tracking_avg_lin_vel`: `#1f77b4`
- `tracking_avg_ang_vel`: `#ff7f0e`
- `torques`: `#2ca02c`
- `dof_acc`: `#d62728`
- `action_rate`: `#9467bd`
- `foot_distance_limit`: `#8c564b`
- `stand_still`: `#e377c2`
- `torque_limits`: `#7f7f7f`
- `dof_vel_limits`: `#bcbd22`
- `dof_pos_limits`: `#17becf`
- `feet_contact_forces`: `#aec7e8`
- `torque_rate`: `#ffbb78`

**Layout:** 3 rows stacked vertically.

- **Row 1 (~40%) - "Per-Step Reward Contributions"**
All 12 scaled reward terms overlaid on a single plot. Each curve = `scaled_rewards/<name>` = `raw_value * scale`. Positive curves push the total up (tracking rewards); negative curves pull it down (penalties). The user sees which terms dominate at each timestep.
  - All 12 `/learning/rl_extra_info/scaled_rewards/<name>` (colors above)
  - `REF_0.0` (light gray `#cccccc`, zero baseline)
- **Row 2 (~20%) - "Total Reward Per Step"**
Net reward = sum of all scaled terms. Clean single-curve view.
  - `/learning/rl_extra_info/total_reward` -- black `#000000` (distinct from all reward term colors)
  - `REF_0.0` (light gray `#cccccc`, zero baseline)
- **Row 3 (~40%) - "Cumulative Episode Rewards"**
Running total of each reward term across the episode (resets on episode boundary). Shows which terms accumulate the most positive/negative impact over time.
  - All 12 `/learning/episode_sums/<name>` (same colors as Row 1)
  - `REF_0.0` (light gray `#cccccc`, zero baseline)

---

### Tab 9: "Foot Contact Forces"

**Layout:** 2 rows (Left foot | Right foot), 2 plots per row. XYZ components follow axis color convention.

- **Row 1 - Left Foot:**
  - Plot 1 "L Force Magnitude": `/state/force_sensors/feet_0_force/force` -- red `#d62728`
  - Plot 2 "L Force XYZ": `force_x` blue `#1f77b4`, `force_y` green `#2ca02c`, `force_z` red `#d62728`
- **Row 2 - Right Foot:**
  - Plot 1 "R Force Magnitude": `/state/force_sensors/feet_1_force/force` -- red `#d62728`
  - Plot 2 "R Force XYZ": `force_x` blue `#1f77b4`, `force_y` green `#2ca02c`, `force_z` red `#d62728`
- **Row 3 (full-width) - "Contact Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/feet_contact_forces` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/feet_air_time` -- unbounded (no ref line)
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

### Tab 10: "Foot Cartesian State"

**Layout:** 2 columns (Left foot | Right foot), 3 rows. All XYZ/RPY follow axis color convention.

- **Row 1 - "Position XYZ":**
  - L: `[0]` blue `#1f77b4`, `[1]` green `#2ca02c`, `[2]` red `#d62728`
  - R: same colors
- **Row 2 - "Linear Velocity XYZ":**
  - L: `[0]` blue `#1f77b4`, `[1]` green `#2ca02c`, `[2]` red `#d62728`
  - R: same colors
- **Row 3 - "Euler Angles (RPY)":**
  - L: `[0]` blue `#1f77b4` (roll), `[1]` green `#2ca02c` (pitch), `[2]` red `#d62728` (yaw)
  - R: same colors
- **Row 4 (full-width) - "Foot Rewards"** *(associated raw rewards + reference lines)*
  - `/learning/rl_extra_info/raw_rewards/foot_distance_limit` -- penalty, ref line at **0.0**
  - `/learning/rl_extra_info/raw_rewards/feet_vel` -- penalty, ref line at **0.0**
  - `REF_0.0` (light gray `#cccccc`, constant 0.0)

---

## Reward-to-Tab Mapping Summary


| Reward Term            | Tab                         |
| ---------------------- | --------------------------- |
| `tracking_avg_lin_vel` | Tab 1 (Velocity Tracking)   |
| `tracking_avg_ang_vel` | Tab 1 (Velocity Tracking)   |
| `stand_still`          | Tab 1 (Velocity Tracking)   |
| `orientation`          | Tab 2 (Body Orientation)    |
| `ang_vel_xy`           | Tab 2 (Body Orientation)    |
| `dof_pos_limits`       | Tab 3/4 (Leg Joints)        |
| `dof_vel_limits`       | Tab 3/4 (Leg Joints)        |
| `dof_acc`              | Tab 3/4 (Leg Joints)        |
| `waist_soft_limit`     | Tab 5 (Waist & Arms)        |
| `tracking_waist_yaw`   | Tab 5 (Waist & Arms)        |
| `action_rate`          | Tab 6 (RL Actions)          |
| `default_joint_pos`    | Tab 6 (RL Actions)          |
| `torques`              | Tab 7 (Joint Torques)       |
| `torque_limits`        | Tab 7 (Joint Torques)       |
| `torque_rate`          | Tab 7 (Joint Torques)       |
| `feet_contact_forces`  | Tab 9 (Foot Forces)         |
| `feet_air_time`        | Tab 9 (Foot Forces)         |
| `foot_distance_limit`  | Tab 10 (Foot Cartesian)     |
| `feet_vel`             | Tab 10 (Foot Cartesian)     |
| All rewards combined   | Tab 8 (Rewards - dedicated) |


Note: Some rewards (e.g. `waist_soft_limit`, `feet_air_time`, `feet_vel`, `orientation`, `ang_vel_xy`, `default_joint_pos`) have scale=0 in the base R01AMPCfg but are active in derived configs (teleop, full-scenes). PlotJuggler tolerates missing curves, so these are safe to include.

---

## Reward Bound Analysis

All reward subplots use **raw_rewards** (`raw_value * sign(scale)`) so bounds are config-independent. Source: [r01_amp_env.py](humanoid-gym/humanoid/envs/r01_amp/r01_amp_env.py), [r01_v12_amp_env.py](humanoid-gym/humanoid/envs/r01_amp/r01_v12_amp_env.py), [r01_amp_teleop_env.py](humanoid-gym/humanoid/envs/r01_amp/r01_amp_teleop_env.py).

### Exp-based rewards -- bounded [0, 1], reference at 1.0

These use `exp(-error/sigma)`. Perfect tracking yields 1.0; increasing error decays toward 0.

- `tracking_avg_lin_vel`: `exp(-||cmd_xy - avg_vel_xy||^2 / sigma)`
- `tracking_avg_ang_vel`: `exp(-|cmd_yaw - avg_ang_vel_z|^2 / sigma)`
- `tracking_waist_yaw`: `exp(-|cmd - waist_pos|^2 / sigma)`
- `default_joint_pos`: `exp(-100 * clamp(yaw_roll_error - 0.1, 0, 50))`
- `torso_ang_vel_xy_penalty`: `exp(-ang_vel_error / sigma^2)`

### Penalty rewards -- bounded at 0 from below, reference at 0.0

These output >= 0 (before sign normalization), where 0 = no penalty. After raw normalization (multiplied by sign of negative scale), values are <= 0 in `raw_rewards`.

- `torques`: `sum(tau^2)` -- quadratic, unbounded above
- `dof_acc`: `sum(acc^2)` -- quadratic, unbounded above
- `action_rate`: `sum((a_t - a_{t-1})^2)` -- quadratic, unbounded above
- `torque_rate`: `sum((delta_tau / limit / dt)^2)` -- quadratic, unbounded above
- `stand_still`: `sum(|q - q_stand|) * [||cmd|| < 0.1]` -- abs, unbounded above
- `orientation`: `sum(gravity_xy^2)` -- quadratic, max ~ 2.0 (unit gravity)
- `ang_vel_xy`: `sum(omega_xy^2)` -- quadratic, unbounded above
- `dof_pos_limits`: `sum(clip(violation))` -- clipped, zero inside soft limits
- `dof_vel_limits`: `sum(clip(|vel| - limit))` -- clipped, zero below limit
- `torque_limits`: `sum(clip(|tau| - limit))` -- clipped, zero below limit
- `feet_contact_forces`: `sum(clip(force - max_force))` -- clipped, zero below threshold
- `foot_distance_limit`: `clip(dist - threshold, max=0) * -1` -- clipped, zero above threshold
- `waist_soft_limit`: `sum(clip(violation)^2)` -- clipped, zero inside limits
- `feet_vel`: `sum(vel^2)` -- quadratic, unbounded above

### Special case -- no single bound

- `feet_air_time`: `sum((air_time - 0.2) * first_contact) * sign(cmd)` -- can be positive or negative depending on air time vs 0.2s threshold and command direction. No useful single reference line.

### Reference line and error curve implementation

All reference lines and tracking error curves are implemented as PlotJuggler **Reactive Script** snippets under the `<plugin ID="Reactive Script Editor">` section.

**Reference lines** -- constant-value timeseries for reward bounds:

```xml
<snippet name="REF_1.0">
  <linked_source>/learning/rl_extra_info/raw_rewards/tracking_avg_lin_vel</linked_source>
  <script>return 1.0</script>
</snippet>
<snippet name="REF_0.0">
  <linked_source>/learning/rl_extra_info/raw_rewards/torques</linked_source>
  <script>return 0.0</script>
</snippet>
```

Rendered in light gray `#cccccc` -- the lightest element on any plot, pure background.

**Tracking error curves** -- computed difference between command and actual:

```xml
<snippet name="ERR_vel_x">
  <linked_source>/learning/rl_obs_unscaled/cmd/root_lin_vel_x</linked_source>
  <additional_source>/learning/rl_extra_info/pelvis_lin_vel/lin_vel_x</additional_source>
  <script>return value - v2</script>
</snippet>
<snippet name="ERR_vel_y">
  <linked_source>/learning/rl_obs_unscaled/cmd/root_lin_vel_y</linked_source>
  <additional_source>/learning/rl_extra_info/pelvis_lin_vel/lin_vel_y</additional_source>
  <script>return value - v2</script>
</snippet>
<snippet name="ERR_vel_yaw">
  <linked_source>/learning/rl_obs_unscaled/cmd/root_ang_vel_yaw</linked_source>
  <additional_source>/learning/rl_extra_info/base_avg_vel/ang_vel_z</additional_source>
  <script>return value - v2</script>
</snippet>
```

All error curves use **orange `#ff7f0e`** -- the universal Tier 3 "problem" color:

- `ERR_vel_x` = orange `#ff7f0e`
- `ERR_vel_y` = orange `#ff7f0e`
- `ERR_vel_yaw` = orange `#ff7f0e`

### Three-tier convention summary

- **Gray** (`#b0b0b0`, `#808080`): commands, targets, intent -- visual background
- **Blue / Green / Red** (`#1f77b4`, `#2ca02c`, `#d62728`): actual measurements -- the data
- **Orange** (`#ff7f0e`): error, deviation -- the alert
- **Light gray** (`#cccccc`): reward bound reference lines

Applied across:

- Tab 1: cmd = gray, actual = axis color, error = orange
- Tab 6: action + target = gray, position deviation = orange
- Tab 7: PD torque (intent) = gray, clamped torque (applied) = red

---

## Implementation Details

- Generate valid PlotJuggler XML using the structure from the existing [r01_plus_amp_plotjuggler_limit_inspect.xml](humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml) as the template for XML schema (DockSplitter, DockArea, plot, curve elements).
- Use the [plotjuggler-udp-fuzzy skill](~/.cursor/skills/plotjuggler-udp-fuzzy/SKILL.md) "Verified Exact" mode since all signal paths are deterministically derived from source code.
- Streamer: `UDP Server` on port `9870`.
- Signal paths not present in a given run (e.g. `gravity_vec_in_torso` for non-R01, or conditional waist commands) will simply not appear; PlotJuggler tolerates missing curves.

## Signals intentionally excluded from tabs

These signals exist in the payload but are not plotted (metadata, redundant, or rarely needed):

- `*/system` (string, not plottable)
- `*/timestamp` (internal offset, not useful for visualization)
- `*/quaternion[0-3]` (euler angles are used instead)
- `control_output/joint/*/kp`, `kd` (PD gains, typically constant)
- `learning/rl_obs_unscaled/current_joint_velocities/`* (redundant with `state/joint/*/velocity`)
- `learning/rl_obs_unscaled/clipped_action_data/`* (redundant with `learning/rl_actions/`*)
- `learning/rl_extra_info/joint_positions/`* (redundant with `state/joint/*/position`)
- ~~`learning/episode_sums/`*~~ -- now included in Tab 8 Row 3 (Cumulative Episode Rewards)
- `control_input/cartesian/root_command/position[*]` (typically zeros)

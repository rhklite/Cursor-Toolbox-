---
name: PlotJuggler Layout v4
overview: "Regenerate the PlotJuggler layout XML with 6 focused tabs: Dashboard, Velocity Tracking, Body Orientation, Feet, Rewards, Control Health. Drops per-joint, actions, torques, and upper body tabs in favor of aggregate error signals."
todos:
  - id: gen-v4-xml
    content: Write and run Python generation script to produce the 6-tab PlotJuggler layout XML with stability dashboard, simplified feet, control health, and custom math equations
    status: completed
  - id: verify-v4
    content: Verify tab count (6), plot counts, signal paths, color assignments, and custom math equations in the generated XML
    status: completed
  - id: cleanup-v4
    content: Delete the generation script, keep only the XML output at r01_plotjuggler_full.xml
    status: completed
isProject: false
---

# PlotJuggler Layout v4 -- 6 Tabs

## Scope

- Target: `R01RobotData.asdict()` from [robot_data.py](humanoid-gym/humanoid/envs/base/robot_data.py), [r01_robot_data.py](humanoid-gym/humanoid/envs/r01_amp/r01_robot_data.py)
- Signal path convention: `/` for dict keys, `[index]` for JSON arrays
- UDP port `9870`, streamer: `UDP Server`
- Output: [r01_plotjuggler_full.xml](humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml) (overwrites v2)

---

## Color System (unchanged from v2)

### Three-tier hierarchy (Tabs 0-2, 3)

- **Gray `#b0b0b0`** = context (commands, targets). Darker gray `#808080` for secondary.
- **Axis colors** = measurements: X blue `#1f77b4`, Y green `#2ca02c`, Z red `#d62728`. Lighter: `#6baed6`, `#74c476`, `#fc9272`.
- **Orange `#ff7f0e`** = tracking error.
- **Light gray `#cccccc`** = reference lines.

L/R body: Left blue `#1f77b4`, Right teal `#17becf`.

### Reward palette (Tabs 0, 3-5)

Avoids blue/green/red/orange/gray:

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
- `feet_air_time`: Dark gold `#b5890a`
- `feet_vel`: Coral `#ff9896`
- `total_reward`: Black `#000000`

---

## Tabs (6 total)

### Tab 0: "Dashboard"

Stability-focused overview. 3x2 grid (6 plots).

- **(0,0) "Body Tilt"**: `gravity_vec_in_pelvis/x` blue, `/y` green
- **(0,1) "Pelvis Angular Velocity"**: `ang_vel_x` blue, `ang_vel_y` green, `ang_vel_z` red
- **(1,0) "Velocity Tracking Error"**: `ERR_vel_x`, `ERR_vel_y`, `ERR_vel_yaw` all orange, REF_0.0
- **(1,1) "Foot Contact"**: `feet_0_force/force` blue, `feet_1_force/force` teal
- **(2,0) "Base Height"**: `/state/cartesian/root_in_world/position[2]` red
- **(2,1) "Total Reward"**: `total_reward` black, REF_0.0

### Tab 1: "Velocity Tracking"

5 plots stacked vertically.

- **"Vel X"**: cmd gray, instantaneous `#6baed6`, avg `#1f77b4`, ERR orange
- **"Vel Y"**: cmd gray, instantaneous `#74c476`, avg `#2ca02c`, ERR orange
- **"Vel Yaw"**: cmd gray, avg `#d62728`, ERR orange
- **"Vel Z"**: actual `#d62728` (no tracking pair)
- **"Velocity Rewards"**: `tracking_avg_lin_vel` purple, `tracking_avg_ang_vel` brown, `stand_still` magenta, REF_1.0 + REF_0.0

### Tab 2: "Body Orientation"

2 columns (Pelvis | Torso), 3 rows + reward row (7 plots).

- Plots 1-2: Euler angles (roll blue, pitch green, yaw red)
- Plots 3-4: Gravity vector (x blue, y green, z red)
- Plots 5-6: Angular velocity (x blue, y green, z red)
- Plot 7: `orientation` purple, `ang_vel_xy` brown, REF_0.0

### Tab 3: "Feet"

Foot forces + foot height. Simplified from v2/v3 (dropped foot euler, dropped per-axis foot velocity).

**Layout:** vertical split into [forces, height, reward] with weights [4, 2, 1].

- **Forces** (2 rows, L then R, each with magnitude + XYZ side by side):
  - L: magnitude red `#d62728`, XYZ blue/green/red
  - R: same
- **Foot Height** (1 row, 2 columns):
  - L: `/state/cartesian/foot_L_in_world/position[2]` blue
  - R: `/state/cartesian/foot_R_in_world/position[2]` teal
- **Reward subplot**: `feet_contact_forces` plum, `feet_air_time` dark gold `#b5890a`, `foot_distance_limit` gold, `feet_vel` coral, REF_0.0

### Tab 4: "Rewards"

4 rows (same structure as v2 Tab 8).

- **Row 1 (~25%) "Tracking Rewards"**: `scaled_rewards/tracking_avg_lin_vel` purple, `tracking_avg_ang_vel` brown, REF_0.0
- **Row 2 (~25%) "Penalty Terms"**: all 10 penalty scaled_rewards in reward palette colors, REF_0.0
- **Row 3 (~15%) "Total Reward"**: `total_reward` black, REF_0.0
- **Row 4 (~35%) "Cumulative Episode"**: all 12 `episode_sums/<name>` in reward palette colors, REF_0.0

### Tab 5: "Control Health"

Aggregated control error signals. 3 plots. All signals are raw_rewards bounded at 0 (no violation). Deviation from 0 = problem.

- **"Action Smoothness"**: `raw_rewards/action_rate` teal, `raw_rewards/dof_acc` olive, REF_0.0
- **"Joint Limit Violations"**: `raw_rewards/dof_pos_limits` lime, `raw_rewards/dof_vel_limits` coral, REF_0.0
- **"Torque Health"**: `raw_rewards/torques` pink, `raw_rewards/torque_limits` slate, `raw_rewards/torque_rate` sky, REF_0.0

---

## Custom Math Equations

Same as v2: `REF_1.0`, `REF_0.0` (constants), `ERR_vel_x`, `ERR_vel_y`, `ERR_vel_yaw` (subtractions using `$$series$$` notation with fallback to PlotJuggler Custom Series dialog).

---

## What was dropped (accessible via signal browser)

- Per-joint leg position/velocity (12 plots) -- drill down from Control Health if `dof_pos_limits` flags
- Per-joint actions/targets/deviation (12 plots) -- drill down if `action_rate` flags
- Per-joint torques PD vs clamped (15 plots) -- drill down if `torque_limits` flags
- Upper body waist/arm joints (7 plots) -- rarely needed for stability
- Foot euler angles and per-axis foot velocity -- low value for stability monitoring
- Waist rewards (`waist_soft_limit`, `tracking_waist_yaw`) and `default_joint_pos` from per-tab subplots -- still visible in Rewards tab Row 2/4

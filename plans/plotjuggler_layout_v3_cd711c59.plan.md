---
name: PlotJuggler Layout v3
overview: Regenerate the PlotJuggler layout XML with 8 consolidated tabs (down from 11), reordered by stability-monitoring priority, with a stability-focused dashboard as the first tab.
todos:
  - id: gen-v3-xml
    content: Write and run Python generation script to produce the 8-tab PlotJuggler layout XML with merged tabs, stability dashboard, and priority ordering
    status: pending
  - id: verify-v3
    content: Verify tab count, plot counts, signal paths, and color assignments in the generated XML
    status: pending
  - id: cleanup
    content: Delete the generation script, keep only the XML output
    status: pending
isProject: false
---

# PlotJuggler Layout v3 -- Consolidated Tabs

## Changes from v2

- **11 tabs reduced to 8** via four merges:
  - Left Leg + Right Leg → "Leg Joints" (L/R columns)
  - Foot Forces + Foot Cartesian → "Feet"
  - RL Actions + Joint Torques → "Joint Control"
  - Waist/Arms kept as low-priority "Upper Body" at the end
- **Dashboard redesigned for stability-under-disturbance**: 3x2 grid with body tilt, angular velocity, velocity error, foot contact, base height, total reward
- **Priority ordering**: stability monitoring first, analytical/debug tabs last

## Tab order (8 tabs)

### Tab 0: "Dashboard"

Stability-focused overview. The user's first glance answers: "Is the robot about to fall?"

**Layout:** 3 rows x 2 columns (6 plots).

- **(0,0) "Body Tilt"**: `/learning/rl_obs_unscaled/gravity_vec_in_pelvis/x` blue, `/y` green. Deviation from [0,0,-1] = tilting.
- **(0,1) "Pelvis Angular Velocity"**: `pelvis_ang_vel/ang_vel_x` blue, `ang_vel_y` green, `ang_vel_z` red. Rate of tilt change.
- **(1,0) "Velocity Tracking Error"**: `ERR_vel_x`, `ERR_vel_y`, `ERR_vel_yaw` all orange, REF_0.0.
- **(1,1) "Foot Contact"**: `feet_0_force/force` blue, `feet_1_force/force` teal. Ground contact maintained?
- **(2,0) "Base Height"**: `/state/cartesian/root_in_world/position[2]` red. Is the robot collapsing?
- **(2,1) "Total Reward"**: `total_reward` black, REF_0.0.

### Tab 1: "Velocity Tracking"

Unchanged from v2. 5 plots: Vel X, Vel Y, Vel Yaw, Vel Z, Velocity Rewards.

### Tab 2: "Body Orientation"

Unchanged from v2. 2 columns (Pelvis | Torso), 3 rows + reward row.

### Tab 3: "Leg Joints"

**Merged from v2 Tabs 3+4.** L/R columns, 6 rows (one per joint pair), + reward subplot.

**Layout:** vertical split into [main, reward]. Main = 2 columns x 6 rows.

Each plot shows the matching L and R joint in separate columns:

- Left column: `/state/joint/leg_l_joint<N>/position` blue, `/velocity` green
- Right column: `/state/joint/leg_r_joint<N>/position` blue, `/velocity` green

Reward subplot: `dof_pos_limits` lime, `dof_vel_limits` coral, `dof_acc` olive, REF_0.0.

### Tab 4: "Rewards"

Unchanged from v2. 4 rows: tracking (2 curves), penalties (10 curves), total, cumulative episode sums. Moved up in priority because reward analysis is critical for understanding stability policy behavior.

### Tab 5: "Feet"

**Merged from v2 Tabs 9+10.** Two rows: forces on top, cartesian state below.

**Layout:** vertical split into [forces, cartesian, reward].

- **Forces section** (2 rows, L then R, each with magnitude + XYZ plots):
  - L: magnitude red, XYZ blue/green/red
  - R: same
- **Cartesian section** (2 columns L/R, 3 rows: position, velocity, euler). Axis colors.
- **Reward subplot**: `feet_contact_forces` plum, `feet_air_time` gold, `foot_distance_limit` gold, `feet_vel` coral, REF_0.0.

### Tab 6: "Joint Control"

**Merged from v2 Tabs 6+7.** Actions on top, torques below, each with L/R columns for legs + waist row.

**Layout:** vertical split into [actions, torques, rewards].

- **Actions section** (2 columns x 6 rows for legs):
  - `rl_joint_target_position` gray, `rl_actions` dark gray, `joint_positions_difference` olive
- **Torques section** (2 columns x 6 rows for legs + 3 waist plots):
  - `control_output/.../torque` gray, `rl_clamped_...` red
- **Reward subplot**: `action_rate` teal, `default_joint_pos` purple, `torques` pink, `torque_limits` slate, `torque_rate` sky, REF_1.0 + REF_0.0.

### Tab 7: "Upper Body"

**Lowest priority.** Waist position/velocity + arm L/R overlays. Moved to the end.

Waist: 3 plots, position blue, velocity green.
Arms: 4 overlay plots, L blue, R teal.
Reward subplot: `waist_soft_limit` gold, `tracking_waist_yaw` purple, REF_1.0 + REF_0.0.

---

## Implementation

Regenerate [r01_plotjuggler_full.xml](humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml) using a Python generation script (write, run, delete). Same color system, reactive scripts, and custom math equations as v2. The only changes are:

1. Dashboard expanded from 2x2 to 3x2 (add angular velocity + base height)
2. Merge L/R leg tabs into one 2-column tab
3. Merge foot forces + cartesian into one tab
4. Merge actions + torques into one tab
5. Move waist/arms to Tab 7 (end)
6. Reorder tabs by stability priority

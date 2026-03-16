---
name: PlotJuggler v4 Fixes
overview: "Fix 5 bugs in the generated r01_plotjuggler_full.xml: merge foot height plots, fix REF linked sources, fix duplicate coral color, add missing reward terms to Rewards tab, and optionally improve Dashboard error readability."
todos:
  - id: fix-foot-height
    content: Merge L/R foot height into one overlaid plot in the Feet tab
    status: completed
  - id: fix-ref-source
    content: Change REF_0.0 and REF_1.0 linked_source to total_reward
    status: completed
  - id: fix-coral-dup
    content: "Change feet_vel color from #ff9896 to #e45756 in Feet and Rewards tabs"
    status: completed
  - id: fix-missing-rewards
    content: Add orientation, ang_vel_xy, waist_soft_limit, tracking_waist_yaw, default_joint_pos, feet_vel to Rewards tab plots
    status: completed
isProject: false
---

# PlotJuggler v4 Bug Fixes

Target file: [r01_plotjuggler_full.xml](humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml)

## Fix 1: Merge L/R Foot Height into one plot

Replace the two single-curve foot height plots (lines 235-250) with one plot containing both:

- `/state/cartesian/foot_L_in_world/position[2]` blue `#1f77b4`
- `/state/cartesian/foot_R_in_world/position[2]` teal `#17becf`

This changes the Feet tab forces section from `[4, 2, 1]` weights to `[5, 1, 1]` (forces get more space, height is one plot, reward is one plot).

## Fix 2: REF linked_source to total_reward

Change both REF snippets' `<linked_source>` from reward-specific signals to `/learning/rl_extra_info/total_reward`, which is always present regardless of config:

```xml
<snippet name="REF_1.0">
  <linked_source>/learning/rl_extra_info/total_reward</linked_source>
  ...
<snippet name="REF_0.0">
  <linked_source>/learning/rl_extra_info/total_reward</linked_source>
  ...
```

## Fix 3: Fix duplicate coral color

Change `feet_vel` from `#ff9896` (coral, same as `dof_vel_limits`) to `#e45756` (darker salmon) in both the Feet tab reward subplot and the Rewards tab penalty/cumulative plots.

## Fix 4: Add missing reward terms to Rewards tab

Add these potentially-active rewards to the Penalty Terms plot and Cumulative Episode plot:

- `orientation`: purple `#9467bd` (already assigned)
- `ang_vel_xy`: brown `#8c564b` (already assigned)
- `waist_soft_limit`: gold `#e7ba52`
- `tracking_waist_yaw`: (tracking term, add to Row 1 tracking plot) purple `#9467bd` -- conflict with `tracking_avg_lin_vel`. Use dark purple `#7b4ea3` instead.
- `default_joint_pos`: magenta `#c5b0d5` -- conflict with `stand_still`. Use dark magenta `#a07cc5` instead.
- `feet_vel`: darker salmon `#e45756` (from Fix 3)

This ensures the sum of visible scaled rewards matches `total_reward` for any config.

## Fix 5 (optional): Dashboard error readability

Accept current behavior: three orange ERR curves on one Dashboard plot. The Dashboard answers "is there error?" (yes/no). Per-axis detail is available on the Velocity Tracking tab. No change needed -- the current design is the right trade-off for a summary view.

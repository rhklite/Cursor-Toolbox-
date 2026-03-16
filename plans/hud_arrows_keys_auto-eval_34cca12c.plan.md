---
name: HUD arrows keys auto-eval
overview: Fix key remapping (Space=zero-all, R=full-reset), start with auto-eval ON, add 3D push/torque arrows with numerical labels via gymutil.draw_lines, add angular yaw push to push mode (Q/E), and keep cv2 HUD code as-is (user will fix container Qt).
todos:
  - id: remap-keys-v2
    content: "Remap: Space=zero-all, R=full-reset; remove Tab/Backspace/r_clear"
    status: pending
  - id: auto-eval-default
    content: Set auto_eval=True by default and apply config at startup
    status: pending
  - id: push-yaw
    content: Add push_yaw to state; Q/E in push mode adjust yaw; apply in _apply_disturbances
    status: pending
  - id: draw-arrows
    content: Draw linear push arrow and yaw torque arc via WireframeArrowGeometry every frame
    status: pending
  - id: update-docs
    content: Update docstring, banner, and console messages for new bindings
    status: pending
isProject: false
---

# HUD, Arrows, Key Remaps, Auto-Eval Default

## File to modify

- [humanoid-gym/humanoid/scripts/play_interactive.py](humanoid-gym/humanoid/scripts/play_interactive.py)

## 1. Key remapping


| Change    | Old                 | New                                               |
| --------- | ------------------- | ------------------------------------------------- |
| Space     | (unbound)           | Zero everything (velocity + push + failed joints) |
| R         | mode-specific clear | Full environment reset (was Tab)                  |
| Tab       | full reset          | (removed -- R takes over)                         |
| Backspace | zero velocity       | (removed -- Space takes over)                     |


Updated `_KEY_ACTIONS`:

```python
gymapi.KEY_SPACE: "zero_all",     # zeros velocity + push + failed joints
gymapi.KEY_R: "full_reset",       # full env reset (pose + clear all)
# remove KEY_BACKSPACE and KEY_TAB
```

In `_process_events`, the `"zero_all"` handler:

```python
user_commands[:, :4] = 0.0
state.push_vec_xy = [0.0, 0.0]
state.failed_joints.clear()
if hasattr(env, "failure_triggered"):
    env.failure_triggered[:] = False
```

The `"full_reset"` handler calls `_full_reset()` (same as current Tab).

Remove the `"r_clear"` handler entirely.

## 2. Start with auto-eval ON

Change `InteractiveState` default:

```python
auto_eval: bool = True
```

At startup after env creation, apply the auto-eval config immediately (same as `_toggle_auto_eval` ON path):

```python
state = InteractiveState()  # auto_eval=True by default
_toggle_auto_eval(env, state, orig_stage)  # won't toggle -- need to apply directly
```

Actually simpler: just set the config directly at startup since `auto_eval` starts True:

```python
env.cfg.domain_rand.push_robots = True
if hasattr(env.cfg.env, "stability_curriculum_stage"):
    env.cfg.env.stability_curriculum_stage = 3
if hasattr(env, "push_curriculum_frac"):
    env.push_curriculum_frac = 1.0
```

## 3. Angular yaw push in push mode

Add `push_yaw: float = 0.0` to `InteractiveState`.

In push mode, Q/E now adjust `state.push_yaw`:

```python
elif evt.action == "q":
    if state.mode == MODE_PUSH:
        state.push_yaw += push_ang_step
elif evt.action == "e":
    if state.mode == MODE_PUSH:
        state.push_yaw -= push_ang_step
```

`push_ang_step = max(abs(env.cfg.domain_rand.max_push_ang_vel), 0.1) / 10.0`

In `_apply_disturbances`, if `push_yaw` is non-zero:

```python
env.root_states[:, 12] += state.push_yaw  # ang_vel_z (yaw)
```

The `"zero_all"` handler also zeros `state.push_yaw`.

## 4. 3D push arrows in Isaac Gym viewer

Use the existing `WireframeArrowGeometry` from [humanoid-gym/humanoid/scripts/visualize_utils.py](humanoid-gym/humanoid/scripts/visualize_utils.py) (already used in `play.py` line 88-114).

### Linear push arrow

Draw a green arrow from the robot's torso showing the configured push direction and magnitude. Arrow length scales with magnitude. Drawn every frame when push vector is non-zero:

```python
from humanoid.scripts.visualize_utils import WireframeArrowGeometry

def _draw_push_arrows(env, state):
    if env.viewer is None:
        return
    env.gym.clear_lines(env.viewer)
    px, py = state.push_vec_xy
    mag = (px**2 + py**2) ** 0.5
    if mag > 1e-4:
        direction = np.array([px, py, 0.0]) / mag
        start = env.root_states[0, :3].detach().cpu().numpy() + [0, 0, 0.7]
        max_vel = getattr(env.cfg.domain_rand, "max_push_vel_xy", 1.0)
        arrow_len = 0.25 + 0.45 * min(mag / max(max_vel, 1e-6), 1.0)
        arrow = WireframeArrowGeometry(start, direction, length=arrow_len, ...)
        gymutil.draw_lines(arrow, env.gym, env.viewer, env.envs[0], identity_pose)
```

### Yaw torque arc

For angular push, draw a curved arc/ring around the robot's vertical axis. Use multiple short line segments forming a partial circle:

- Radius ~0.4m at torso height
- Arc length proportional to yaw magnitude
- Arrow head at the end showing rotation direction
- Color: blue for yaw torque (distinct from green linear push)

### Numerical labels

Since we can't render text in the Isaac Gym viewer, the numerical values are printed to console on each P press (already done) and shown in the cv2 HUD (when available).

## 5. Docstring and banner update

Update the docstring and startup banner to reflect new key mappings:

```
  Space  -- zero everything (velocity + push + failures)
  R      -- full environment reset
```

Remove references to Tab and Backspace.

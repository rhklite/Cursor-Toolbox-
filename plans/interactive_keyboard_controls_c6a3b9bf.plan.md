---
name: Interactive Keyboard Controls
overview: Add interactive keyboard controls (WASD velocity, QE yaw, R reset, P push) and a live OpenCV HUD to humanoid-gym's play environment, enabling real-time robot control during non-headless play.
todos:
  - id: register-keys
    content: Add keyboard event subscriptions (W/S/A/D/Q/E/0/R/P) in base_task.py __init__
    status: completed
  - id: handle-events
    content: Expand render() event loop in base_task.py to handle velocity, reset, and push actions
    status: completed
  - id: play-mode
    content: Set env_cfg.env.play_mode = True in play.py for non-headless runs
    status: completed
  - id: hud-overlay
    content: Add OpenCV HUD window in play.py play loop showing current commands
    status: completed
  - id: verify
    content: Run linter checks on modified files
    status: completed
isProject: false
---

# Interactive Keyboard Controls for humanoid-gym Play

## Files to Modify

- [humanoid-gym/humanoid/envs/base/base_task.py](humanoid-gym/humanoid/envs/base/base_task.py) -- register keyboard events and handle them in `render()`
- [humanoid-gym/humanoid/scripts/play.py](humanoid-gym/humanoid/scripts/play.py) -- set `play_mode = True` when not headless; integrate HUD display

## Keyboard Bindings

All velocity commands are **incremental** with step = `abs(range_max) / 10` (10% of the maximum velocity limit). Values are **not clamped** -- the robot can exceed 100% of its configured velocity limit.

- **W/S**: increment/decrement `lin_vel_x`
- **A/D**: increment/decrement `lin_vel_y`
- **Q/E**: increment/decrement `ang_vel_yaw`
- **0**: zero all commands
- **R**: reset all environments via `reset_idx(all_env_ids)`
- **P**: immediate random push (bypass counter logic)
- **ESC / V**: unchanged (quit / toggle viewer sync)

## Implementation Details

### 1. Register keyboard events in `base_task.py`

In `BaseTask.__init`__, after existing `subscribe_viewer_keyboard_event` calls (line 101), add subscriptions for keys R, P, W, S, A, D, Q, E, 0.

### 2. Handle events in `base_task.py` render()

Expand the event loop in `render()` (line 147) to handle the new actions. Use a `_user_command_dirty` flag so play.py knows when to update the HUD.

For the **push (P)**: bypass `_push_robots()` counter logic by directly applying a random velocity impulse to `root_states[:, 7:9]` (lin vel xy) and calling `set_actor_root_state_tensor`. This works even when `push_robots` config is False. Store the push vector for HUD display.

For **velocity commands**: read `self.command_ranges` dict (populated from `cfg.commands.ranges`), compute step = `abs(range_max) / 10`. Increment/decrement `self.commands[:, idx]` by this step. Do **not** clamp -- the value may exceed the configured range, allowing the user to push the robot beyond its trained velocity limits.

For **reset (R)**: call `self.reset_idx(torch.arange(self.num_envs, device=self.device))`.

### 3. Set play_mode in play.py

Add `env_cfg.env.play_mode = True` in `play()` when running non-headless. This prevents `_resample_commands` (line 422 of `legged_robot.py`) from overwriting keyboard-set commands.

When `--fixed_command` is active, it already overwrites `env.commands` each step in the play loop, so keyboard commands are harmlessly overridden (correct behavior).

### 4. HUD overlay

Create a lightweight OpenCV HUD window (`cv2.namedWindow` + `cv2.imshow`) in the play loop (non-headless only). Each frame, render a small black image with white text showing:

```
lin_vel_x:  0.30
lin_vel_y:  0.00
ang_vel_yaw: 0.10
[PUSH active: (0.2, -0.3)]
```

Update every render cycle via `cv2.waitKey(1)`. Teardown on exit.

### 5. Guard for headless mode

All keyboard and HUD code is gated on `self.headless == False` / `self.viewer is not None` to ensure no regressions in headless or `--fixed_command` mode.

## Reference Implementation

`legged_gym_ws/legged_gym/envs/base/legged_robot.py` lines 123-158 -- `_register_user_commands` and `_check_user_commands` provide the pattern, but we use incremental velocity instead of absolute, and place the logic in `base_task.py` so all humanoid-gym envs inherit it.

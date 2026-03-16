---
name: Critique play_interactive fixes
overview: Fix bugs and add UX improvements to play_interactive.py identified across 3 rounds of critique.
todos:
  - id: fix-resample
    content: Introduce user_commands tensor; mutate it in _process_keyboard_events; re-apply after env.step()
    status: pending
  - id: fix-cleanup
    content: Wrap main loop in try/finally; replace sys.exit with flag for graceful cleanup
    status: pending
  - id: fix-push-return
    content: Return push vector from _keyboard_push directly instead of reading root_states
    status: pending
  - id: fix-hud-timer
    content: Add persistent HUD status timer for PUSH/RESET (25 frames)
    status: pending
  - id: fix-zero-range
    content: Clamp vel step denominator with max(abs(range_max), 0.1)
    status: pending
  - id: ux-console-print
    content: Print velocity changes to console on each key press
    status: pending
  - id: ux-hud-pct
    content: Show percentage of max velocity in HUD
    status: pending
  - id: ux-focus-banner
    content: Add viewer focus reminder to startup banner
    status: pending
isProject: false
---

# Critique and Improvements for play_interactive.py

Three rounds of critique were performed. Findings are ordered by severity.

## Round 1 Findings

### R1-Critical: Auto-reset overwrites keyboard commands

`reset_idx()` in [legged_robot.py](humanoid-gym/humanoid/envs/base/legged_robot.py) line 254 calls `_resample_commands(env_ids)` **unconditionally** -- there is no `play_mode` guard. The `play_mode` guard on line 422 only protects periodic resampling in `_post_physics_step_callback`, not reset-triggered resampling.

When the robot falls and auto-resets, `check_termination` -> `reset_idx` -> `_resample_commands` fires, replacing the user's keyboard-set velocity commands with random values.

**Fix:** Maintain a separate `user_commands` tensor in the play loop. After every `env.step()`, unconditionally overwrite `env.commands[:, :4]` with the saved user commands. Keyboard events mutate `user_commands` instead of `env.commands` directly.

```python
user_commands = torch.zeros(env.num_envs, 4, device=env.device)

for i in range(total_steps):
    kb = _process_keyboard_events(env, vel_steps, push_vel_xy, user_commands)
    env.commands[:, :4] = user_commands
    obs, _, _, _, _, *_ = env.step(actions.detach())
    env.commands[:, :4] = user_commands  # restore after auto-reset resample
```

**Residual (accepted):** `compute_observations()` inside `env.step()` runs AFTER `reset_idx`, so for the one frame where an auto-reset occurs, the observations encode the resampled (not user) commands. This is a single-frame glitch that's negligible in practice and unfixable without modifying `legged_robot.py`.

### R1-Medium: HUD status is transient (1 frame)

PUSH and RESET indicators appear for only one frame (~20ms), making them invisible.

**Fix:** Add a `hud_status_timer` counter. When push/reset fires, set timer to 25 (~0.5s at 50Hz). Decrement each frame. Show extra HUD lines while timer > 0.

### R1-Medium: Zero command range makes axis uncontrollable

If `command_ranges["lin_vel_y"][1]` is 0 (some task configs set this), `_compute_vel_steps` returns 0, making that axis permanently stuck at zero.

**Fix:** Use `max(abs(range_max), 0.1)` as the base for step calculation.

### R1-Low: No console feedback on velocity changes

Pressing W/S/A/D/Q/E gives no console confirmation. The user must look at the HUD.

**Fix:** Print a single line after each velocity/zero key showing all three command values.

### R1-Low: HUD lacks velocity percentage context

The user sees `lin_vel_x: +0.30` but doesn't know if that's 30% or 3% of max.

**Fix:** Show percentage next to each value: `lin_vel_x: +0.30 (30%)`.

### R1-Low: Startup banner should note viewer focus

Isaac Gym viewer must have focus for keyboard events. The OpenCV HUD window can steal focus.

**Fix:** Add a line to the startup banner.

## Round 2 Findings

### R2-Medium: No graceful cleanup on exception or ESC

`sys.exit()` on ESC (line 80) bypasses `udp_client.close()` and `_destroy_hud()`. Any exception in the loop also leaks these resources.

**Fix:** Replace `sys.exit()` with a `running = False` flag. Wrap the main loop in `try/finally` that always calls `udp_client.close()` and `_destroy_hud()`.

### R2-Low: `_keyboard_push` return value is read indirectly

After `_keyboard_push`, the caller reads `env.root_states[0, 7:8]` to get the push vector for HUD display. But `_keyboard_push` already has the `push_xy` tensor. It should return it directly for clarity and correctness.

**Fix:** Have `_keyboard_push` return the push vector. The caller uses the returned value instead of reading root_states.

### R2-Accepted: Push replaces velocity rather than adding

`_keyboard_push` does `env.root_states[:, 7:9] = push_xy` (replaces existing velocity). A physical impulse should ADD to existing velocity. However, the original `_push_robots` in `legged_robot.py` also replaces velocity -- this is the codebase convention. Matching training disturbance semantics is more important for evaluation than physical correctness. **Accepted as-is.**

### R2-Accepted: Push does not include angular velocity

The keyboard push only applies linear velocity xy. The original `_push_robots` also applies angular velocity. Adding angular adds complexity with little interactive value. **Accepted as-is.**

## Round 3 Findings

### R3-Accepted: One-frame observation glitch on auto-reset

After auto-reset, `compute_observations()` runs inside `env.step()` with resampled (wrong) commands. The `user_commands` re-apply happens AFTER step returns. This means one frame of observations encodes wrong commands. This is inherent to the architecture (can't fix without modifying `legged_robot.py`) and negligible in practice. **Accepted as-is.**

### R3-Verified: Push timing is correct

The push is applied via `set_actor_root_state_tensor_indexed` before `env.step()`. Inside `env.step()`, `render()` does graphics, then `simulate()` runs with the pushed velocities. Both CPU and GPU code paths handle this correctly. **No issue.**

### R3-Verified: Command tensor slicing is safe

`env.commands[:, :4]` clips safely to actual tensor width if `num_commands < 4`. **No issue.**

## Files to Modify

- [humanoid-gym/humanoid/scripts/play_interactive.py](humanoid-gym/humanoid/scripts/play_interactive.py) -- all changes are in this single file

## Summary of Changes (8 items)

1. Introduce `user_commands` tensor; `_process_keyboard_events` mutates it; apply before and after every `env.step()`
2. Wrap main loop in `try/finally`; replace `sys.exit()` with `running` flag for graceful cleanup
3. Return push vector directly from `_keyboard_push`
4. Add `hud_status_timer` + `hud_status_lines` for persistent HUD status
5. Clamp step denominator to `max(abs(range_max), 0.1)` in `_compute_vel_steps`
6. Print velocity changes to console
7. Show `(XX%)` percentage in HUD
8. Add focus reminder to startup banner

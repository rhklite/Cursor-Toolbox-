---
name: Remap push add failure
overview: Remap push to key 1, add hardware failure trigger on key 2 that applies the full stability-priority failure event (zero commands + PD snap + push) regardless of training stage config.
todos:
  - id: remap-push
    content: Change push key from P to 1 in _KEY_ACTIONS, docstring, and banner
    status: pending
  - id: add-failure
    content: Add key 2 handler for hardware failure trigger with guard, push, and failure_triggered flag
    status: pending
  - id: hud-failure
    content: Show persistent FAILURE TRIGGERED in HUD while failure_triggered is True
    status: pending
isProject: false
---

# Remap Push to 1, Add Failure Trigger on 2

## File to Modify

- [humanoid-gym/humanoid/scripts/play_interactive.py](humanoid-gym/humanoid/scripts/play_interactive.py)

## Change 1: Remap push from P to 1

In `_KEY_ACTIONS` (line 33-43), replace `gymapi.KEY_P: "push"` with `gymapi.KEY_1: "push"`. Update docstring and banner accordingly.

## Change 2: Add failure trigger on key 2

### Key binding

Add `gymapi.KEY_2: "trigger_failure"` to `_KEY_ACTIONS`.

### What the failure does (always full, no stage gating)

When key 2 is pressed:

1. **Zero all velocity commands** -- `user_commands[:, :4] = 0.0` (once the critique fixes are applied)
2. **Set `failure_triggered` flag** -- `env.failure_triggered[:] = True`, which activates the PD snap logic in `_compute_torques` (arm/head joints snap to default pose via PD control)
3. **Apply failure push** -- additive velocity teleport using the task's configured `max_push_vel_xy` and `max_push_ang_vel` (bypass curriculum, use full strength):

```python
def _keyboard_trigger_failure(env, user_commands):
    if not hasattr(env, "failure_triggered"):
        print("[failure] env does not support failure triggering (not a stability_priority task)")
        return None
    all_ids = torch.arange(env.num_envs, device=env.device)
    env.failure_triggered[:] = True
    user_commands[:, :4] = 0.0

    max_vel = env.cfg.domain_rand.max_push_vel_xy
    max_ang = env.cfg.domain_rand.max_push_ang_vel
    push_lin = torch_rand_float(-max_vel, max_vel, (env.num_envs, 2), device=env.device)
    env.root_states[:, 7:9] += push_lin
    if max_ang > 1e-2:
        push_ang = torch_rand_float(-max_ang, max_ang, (env.num_envs, 3), device=env.device)
        env.root_states[:, 10:13] += push_ang
    env_ids_int32 = all_ids.to(dtype=torch.int32)
    env.gym.set_actor_root_state_tensor_indexed(...)
    return push_lin[0]
```

Key differences from the basic push (key 1):

- Push is **additive** (`+=`) matching `_apply_failure_push` in `r01_v12_amp_stability_priority_env.py` line 138, not replacement like the basic push
- Includes **angular velocity** component
- Sets `failure_triggered = True` which changes torque behavior: arm/head joints go from zero-torque to PD-snap-to-default
- Zeros velocity commands (robot should stop and balance)
- Uses the task's **configured push magnitudes** (not the `--push_vel_xy` CLI arg)

### Guard for non-stability-priority tasks

If the env lacks `failure_triggered` (e.g., running with a basic AMP task), print a warning and skip. The key becomes a no-op for tasks that don't implement the failure model.

### Recovery via R (reset)

Pressing R already calls `env.reset_idx()`, which in `R01V12AMPStabilityPriorityEnv.reset_idx` (line 41) sets `failure_triggered[env_ids] = False`. So reset naturally clears the failure state.

### HUD

Show `FAILURE TRIGGERED` in the HUD while `env.failure_triggered` is True (persistent, not timer-based, since failure lasts until reset).

## Updated Key Map


| Key   | Action                                                        |
| ----- | ------------------------------------------------------------- |
| W / S | increment / decrement lin_vel_x                               |
| A / D | increment / decrement lin_vel_y                               |
| Q / E | increment / decrement ang_vel_yaw                             |
| 0     | zero all commands                                             |
| **1** | **push (random velocity impulse)**                            |
| **2** | **trigger hardware failure (zero commands + PD snap + push)** |
| R     | reset all environments (clears failure state)                 |
| ESC   | quit                                                          |
| V     | toggle viewer sync                                            |

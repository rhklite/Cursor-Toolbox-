---
name: Auto-eval toggle and backspace
overview: Add auto-eval toggle (key 4) that re-enables training disturbances on top of manual controls, and remap zero-velocity from 0 to Backspace.
todos:
  - id: add-auto-eval
    content: Add auto_eval boolean to InteractiveState and key 4 toggle handler
    status: completed
  - id: toggle-config
    content: Save original config; toggle push_robots, stability_curriculum_stage, push_curriculum_frac on key 4
    status: completed
  - id: hud-auto-eval
    content: Show [AUTO EVAL] indicator in HUD when enabled
    status: completed
  - id: remap-backspace
    content: Change zero-velocity from KEY_0 to KEY_BACKSPACE in _KEY_ACTIONS
    status: completed
isProject: false
---

# Auto-Eval Toggle and Backspace Remap

## File to modify

- [humanoid-gym/humanoid/scripts/play_interactive.py](humanoid-gym/humanoid/scripts/play_interactive.py)

## Changes

### 1. Auto-eval toggle (key 4)

Add a boolean `auto_eval` to `InteractiveState` (default `False`). Key 4 toggles it on/off. This is NOT a mode -- it's an overlay that stacks with whichever mode (1/2/3) is active.

When `auto_eval` is toggled **ON**:

- Set `env.cfg.domain_rand.push_robots = True` -- enables automatic counter-based pushes from the base `_push_robots()` (for non-stability-priority envs) or from the training pipeline
- For stability_priority envs: set `env.cfg.env.stability_curriculum_stage = 3` and `env.push_curriculum_frac = 1.0` -- T_fail already fires naturally (it checks `episode_length_buf >= t_fail_step` every step), this just ensures full failure behavior (PD snap + push)
- Print `[auto-eval] ON`

When `auto_eval` is toggled **OFF**:

- Set `env.cfg.domain_rand.push_robots = False`
- For stability_priority envs: restore `stability_curriculum_stage` to original value, reset `push_curriculum_frac = 0.0`
- Print `[auto-eval] OFF`

All manual controls (velocity, push vector, failed joints, P, R, Tab) continue working. Auto disturbances stack on top.

### 2. HUD indicator

When `auto_eval` is True, show `[AUTO EVAL]` in the HUD header alongside the mode name:

```
[VELOCITY MODE] [AUTO EVAL]
```

### 3. Remap zero-velocity from 0 to Backspace

In `_KEY_ACTIONS`:

- Remove `gymapi.KEY_0: "zero"`
- Add `gymapi.KEY_BACKSPACE: "zero"`

### 4. Save and restore original config values

At startup (before overriding configs), save the original `stability_curriculum_stage` value so it can be restored when toggling auto-eval off:

```python
orig_stage = getattr(env_cfg.env, "stability_curriculum_stage", 1)
```

## Updated Key Map


| Key           | Action                                  |
| ------------- | --------------------------------------- |
| 1/2/3         | Switch mode (push / failure / velocity) |
| **4**         | **Toggle auto-eval ON/OFF**             |
| **Backspace** | **Zero velocity commands** (was key 0)  |
| WASD/QE       | Mode-dependent controls                 |
| P             | Apply all disturbances                  |
| R             | Clear active mode's config              |
| Tab           | Full environment reset                  |
| ESC           | Quit                                    |
| V             | Toggle viewer sync                      |

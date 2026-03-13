# Play Motion RL

Launch a PlotJuggler + Isaac Gym play session for UDP telemetry visualization testing.

Invoke as `/play-motion-rl`.

## Required inputs

Collect from the user if not provided:

- `--task`: task name from the registry (e.g. `r01_v12_amp_with_4dof_arms_and_head_full_scenes`)
- `--checkpoint`: path to a `.pt` checkpoint file (local Mac path or remote path on huh.desktop.us)

## Optional inputs

- `--layout`: PlotJuggler layout XML (local Mac path or remote path; default: `r01_plus_amp_plotjuggler_limit_inspect.xml`). Local files are auto-copied to the remote.
- `--total_steps`: total play steps (default: `100000000`)
- `--skip-health`: skip the container healthcheck if the container is known to be running
- `--pull`: pull latest changes on the remote motion_rl repo before launching (skips interactive prompt)
- `--no-pull`: skip the pull step (skips interactive prompt)
- Without `--pull` or `--no-pull`, the script prompts the user interactively
- `--interactive`: use `play_interactive.py` instead of `play.py` for keyboard-driven control (W/S/A/D velocity, Q/E yaw, R reset, P push, OpenCV HUD)
- `--push_vel_xy`: max push velocity for keyboard push in interactive mode (default: `1.0`)

## Execution

1. Run the orchestrator script (background it since play.py is long-running):

```bash
bash ~/.cursor/scripts/play_motion_rl.sh \
  --task <task> \
  --checkpoint <path> \
  [--layout <xml>] \
  [--total_steps <n>] \
  [--skip-health] \
  [--pull | --no-pull] \
  [--interactive] \
  [--push_vel_xy <f>]
```

2. Monitor the output. The script runs these steps sequentially:
   - Container healthcheck (restart + sshd + GPU + display)
   - Interactive pull prompt (unless `--pull` or `--no-pull`)
   - Checkpoint resolution (local -> SCP, remote -> validate)
   - Layout resolution (local -> SCP, remote -> validate, or use default)
   - PlotJuggler launch (--nosplash, no --publish)
   - play.py (or play_interactive.py with `--interactive`) launch in isaacgym container

3. Report pass/fail for each step.

4. On success, remind the user:
   - In PlotJuggler: **Streaming -> Start: UDP Server**, port **9870**, protocol **JSON**
   - Plots may need manual signal drag if layout signal names don't match the current UDP schema
   - If `--interactive`: use WASD/QE/0/R/P keys in the Isaac Gym viewer; command HUD appears in a separate OpenCV window

## Interactive mode keyboard bindings

| Key | Action |
|-----|--------|
| W / S | increment / decrement lin_vel_x (10% of max per press) |
| A / D | increment / decrement lin_vel_y |
| Q / E | increment / decrement ang_vel_yaw |
| 0 | zero all velocity commands |
| R | reset all environments |
| P | immediate random push |
| ESC | quit |
| V | toggle viewer sync |

Velocity increments are 10% of abs(range_max) and are uncapped (can exceed 100% of the trained limit).

## Failure hints

- Container healthcheck failure: run `/restart-isaacgym` separately to debug
- PlotJuggler crash: check `/tmp/plotjuggler.log` on huh.desktop.us
- play.py / play_interactive.py crash: check terminal output for Python traceback
- SSH connection refused: container sshd may not be up; the healthcheck should handle this

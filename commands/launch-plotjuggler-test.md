# Launch PlotJuggler Test

Launch a PlotJuggler + Isaac Gym play.py session for UDP telemetry visualization testing.

Invoke as `/launch-plotjuggler-test`.

## Required inputs

Collect from the user if not provided:

- `--task`: task name from the registry (e.g. `r01_v12_amp_with_4dof_arms_and_head_full_scenes`)
- `--checkpoint`: path to a `.pt` checkpoint file (local Mac path or remote path on huh.desktop.us)

## Optional inputs

- `--layout`: PlotJuggler layout XML on the remote host (default: `r01_plus_amp_plotjuggler_limit_inspect.xml`)
- `--total_steps`: total play steps (default: `100000000`)
- `--skip-health`: skip the container healthcheck if the container is known to be running
- `--pull`: pull latest changes on the remote motion_rl repo before launching (skips interactive prompt)
- `--no-pull`: skip the pull step (skips interactive prompt)
- Without `--pull` or `--no-pull`, the script prompts the user interactively

## Execution

1. Run the orchestrator script (background it since play.py is long-running):

```bash
bash ~/.cursor/scripts/launch_plotjuggler_test.sh \
  --task <task> \
  --checkpoint <path> \
  [--layout <xml>] \
  [--total_steps <n>] \
  [--skip-health]
```

2. Monitor the output. The script runs these steps sequentially:
   - Container healthcheck (restart + sshd + GPU + display)
   - Checkpoint resolution (local -> SCP, remote -> validate)
   - PlotJuggler launch (--nosplash, no --publish)
   - play.py launch in isaacgym container

3. Report pass/fail for each step.

4. On success, remind the user:
   - In PlotJuggler: **Streaming -> Start: UDP Server**, port **9870**, protocol **JSON**
   - Plots may need manual signal drag if layout signal names don't match the current UDP schema

## Failure hints

- Container healthcheck failure: run `/restart-isaacgym` separately to debug
- PlotJuggler crash: check `/tmp/plotjuggler.log` on huh.desktop.us
- play.py crash: check terminal output for Python traceback
- SSH connection refused: container sshd may not be up; the healthcheck should handle this

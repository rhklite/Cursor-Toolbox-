# Play Motion RL

Launch a PlotJuggler + Isaac Gym play.py session for UDP telemetry visualization testing.

Invoke as `/play-motion-rl`.

## Agent workflow

The user primarily invokes this via agent prompt. The agent handles all interactive decisions before calling the script with pre-set flags (the script has no TTY when run by the agent).

### Step 1: Pre-check for existing processes

Run (readonly):

```bash
ssh huh.desktop.us "pgrep -af 'play.*\.py.*--task' 2>/dev/null"
```

### Step 2: If existing process found

Ask the user: replace or refresh?

- **Replace**: kill existing play.py and launch a new one. Requires `--task` and `--checkpoint`. Pass `--replace` to the script.
- **Refresh**: keep existing play.py, just relaunch PlotJuggler (optionally with a new layout). Does NOT require `--task` or `--checkpoint`. Pass `--refresh` to the script.

### Step 3: Collect inputs

- If **fresh launch or replace**: collect `--task` and `--checkpoint` from the user if not provided.
- If **refresh**: only ask about `--layout` if the user wants a different one.
- Ask about `--pull` / `--no-pull` (skip for refresh).

### Step 4: Run the script

```bash
bash ~/.cursor/scripts/play_motion_rl.sh \
  --task <task> \
  --checkpoint <path> \
  [--layout <xml>] \
  [--total_steps <n>] \
  [--skip-health] \
  [--pull | --no-pull] \
  [--replace | --refresh] \
  [--interactive] \
  [--push_vel_xy <value>]
```

Background the command since play.py is long-running. Monitor output and report pass/fail for each step.

### Step 5: Report results

On success, remind the user:
- In PlotJuggler: **Streaming -> Start: UDP Server**, port **9870**, protocol **JSON**
- Plots may need manual signal drag if layout signal names don't match the current UDP schema

## Required inputs

Only required for fresh launch or replace (not refresh):

- `--task`: task name from the registry
- `--checkpoint`: path to .pt checkpoint (local Mac or remote path; local files auto-SCP)

## Optional inputs

- `--layout`: PlotJuggler layout XML (local or remote path; default: `r01_plus_amp_plotjuggler_limit_inspect.xml`). Local files auto-SCP.
- `--total_steps`: total play steps (default: `100000000`)
- `--skip-health`: skip container healthcheck
- `--pull` / `--no-pull`: pull latest changes on remote repo (or skip). Without either flag, the script prompts interactively (falls through to skip when agent runs it).
- `--replace`: kill existing play.py and launch new one (bypasses prompt)
- `--refresh`: keep existing play.py, just refresh PlotJuggler (bypasses prompt)
- `--interactive`: use play_interactive.py with keyboard control
- `--push_vel_xy`: max push velocity for interactive mode (default: 1.0)

## Failure hints

- Container healthcheck failure: run `/restart-isaacgym` separately to debug
- PlotJuggler crash: check `/tmp/plotjuggler.log` on huh.desktop.us
- play.py crash: check terminal output for Python traceback
- SSH connection refused: container sshd may not be up; the healthcheck handles this
- `--refresh` with no existing process: script exits with error

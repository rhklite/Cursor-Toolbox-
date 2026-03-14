# Play Motion RL

Launch a PlotJuggler + Isaac Gym play.py session for UDP telemetry visualization testing.

Invoke as `/play-motion-rl`.

## Agent workflow

The user primarily invokes this via agent prompt. The agent handles all interactive decisions before calling the script with pre-set flags (the script has no TTY when run by the agent).

### Step 1: Pre-check for existing processes

Run (readonly):

```bash
docker exec isaacgym bash -c "pgrep -af 'play.*\.py.*--task' 2>/dev/null"
```

### Step 2: If existing process found

Ask the user: replace or refresh?

- **Replace**: kill existing play.py and launch a new one. Requires `--checkpoint` (or default task is used if `--task` is omitted). Pass `--replace` to the script.
- **Refresh**: keep existing play.py, just relaunch PlotJuggler + streaming + layout. Does NOT require `--task` or `--checkpoint`. Pass `--refresh` to the script.

### Step 3: Collect inputs

- If **fresh launch or replace**: collect `--checkpoint` from the user; `--task` is optional and defaults to `r01_v12_amp_with_4dof_arms_and_head_full_scenes` when not provided.
- If **refresh**: only ask about `--layout` if the user wants a different one.
- Ask about `--pull` / `--no-pull` (skip for refresh).

### Step 4: Run the script

```bash
bash ~/.cursor/scripts/play_motion_rl.sh \
  --checkpoint <path> \
  [--task <task>] \
  [--layout <xml>] \
  [--total_steps <n>] \
  [--skip-health] \
  [--pull | --no-pull] \
  [--replace | --refresh] \
  [--interactive]
```

Background the command since play.py is long-running. Monitor output and report pass/fail for each step.

### Step 5: Report results

On success, the script auto-starts UDP streaming on port 9870 (JSON) and loads the layout after data is flowing. No manual steps needed. If the automation fails, the script prints fallback instructions.

## Required inputs

Only required for fresh launch or replace (not refresh):

- `--checkpoint`: path to .pt checkpoint (must exist on huh.desktop.us)

## Optional inputs

- `--layout`: PlotJuggler layout XML (default: `humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml`).
- `--task`: task name from the registry (default: `r01_v12_amp_with_4dof_arms_and_head_full_scenes`)
- `--total_steps`: total play steps (default: `100000000`)
- `--skip-health`: skip container healthcheck
- `--pull` / `--no-pull`: pull latest changes on repo (or skip). Without either flag, the script prompts interactively (falls through to skip when agent runs it).
- `--replace`: kill existing play.py and launch new one (bypasses prompt)
- `--refresh`: keep existing play.py, just refresh PlotJuggler (bypasses prompt)
- `--interactive`: use play_interactive.py with modal keyboard control (1=push, 2=failure, 3=velocity, P=apply, Tab=reset). Interactive mode is enabled by default.

## Failure hints

- Container healthcheck failure: run `/restart-isaacgym` separately to debug
- PlotJuggler crash: check `/tmp/plotjuggler.log` on huh.desktop.us
- play.py crash: check terminal output for Python traceback
- Streaming not auto-starting: check `~/.cursor/scripts/pj_clicker.py` and `python-xlib` installation
- `--refresh` with no existing process: script exits with error

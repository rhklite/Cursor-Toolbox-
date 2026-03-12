# Play Motion RL

Run Motion RL commands with automatic routing from local, `huh.desktop.us`, or inside the `isaacgym` container.

Invoke as `/play-motion-rl <command> [args...]`.

## Routing behavior

- If already inside container context, run directly in:
  - `/home/huh/software/motion_rl`
- If running on host machine with local Docker `isaacgym` container, run via:
  - `docker exec -u huh isaacgym /bin/bash -lc "..."`
- Otherwise, route through SSH alias `isaacgym`:
  - `bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh ...`

The command prints a route line:
- `route: direct-container`
- `route: host-docker-exec`
- `route: ssh-routed (isaacgym)`

## Runner command

Use:

```bash
bash ~/.cursor/scripts/play_motion_rl.sh <command> [args...]
```

## `play.py` policy

For `humanoid-gym/humanoid/scripts/play.py` only:
- auto-add defaults if absent:
  - `DISPLAY=:1`
  - `--resume`
  - `--total_steps 100000000`
- require:
  - `--task <value>`
  - `--load_run <value>`

If required `play.py` args are missing, command exits with a clear error.

## Examples

```bash
bash ~/.cursor/scripts/play_motion_rl.sh pwd
bash ~/.cursor/scripts/play_motion_rl.sh python -V
bash ~/.cursor/scripts/play_motion_rl.sh ls -la
bash ~/.cursor/scripts/play_motion_rl.sh python humanoid-gym/humanoid/scripts/play.py --task r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes --load_run huh_onboard
```

## Failure hints

- If SSH route fails, run:
  - `bash ~/.cursor/skills/isaacgym-ssh-recovery/scripts/recover-isaacgym-ssh.sh`
- If Docker route fails on host, verify `isaacgym` container is running.

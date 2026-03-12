---
name: motion-rl-isaacgym-exec
description: Executes shell commands inside the isaacgym container for the Motion RL workspace. Use when the user mentions Motion RL, motion_rl, isaacgym-motion_rl workspace, or asks to run commands in that workspace.
---

# Motion RL IsaacGym Execute

## When to use

Use this skill when the user asks to execute commands for Motion RL work.

Trigger phrases include:
- "motion rl workspace"
- "motion_rl"
- "isaacgym-motion_rl"
- "run this command in container"

## Default behavior

For command execution requests in Motion RL context:
1. Run the command inside container alias `isaacgym`.
2. Use workspace path `/home/huh/software/motion_rl` inside the container.
3. Treat this as the default unless the user explicitly asks to run on local host.
4. Prefer the helper script for consistent behavior.

### play.py policy (only for `humanoid-gym/humanoid/scripts/play.py`)

When executing `play.py`, apply the following defaults and prompts:

1. Auto-append defaults if user did not provide them:
   - `DISPLAY=:1`
   - `--resume`
   - `--total_steps 100000000`
2. If missing, ask the user before executing:
   - `--task`
   - `--load_run`
3. Device handling:
   - If device flags are not provided, default to GPU behavior (do not append CPU flags).
   - If the request is ambiguous about device preference and could affect results, ask whether to use CPU or GPU.
4. Scope:
   - These rules apply only to `play.py` execution and should not be forced on other commands.

## Command runner

Use:

```bash
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh <command> [args...]
```

Examples:

```bash
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh pwd
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh python -V
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh ls -la
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh DISPLAY=:1 python humanoid-gym/humanoid/scripts/play.py --task r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes --resume --load_run huh_onboard --total_steps 100000000
```

## If container SSH is down

If `ssh isaacgym` fails, first run:

```bash
bash ~/.cursor/skills/isaacgym-ssh-recovery/scripts/recover-isaacgym-ssh.sh
```

Then retry the Motion RL command.

If the user asks to restart/reboot/bring up the isaacgym container, route that request to the merged recovery skill entrypoint:

```bash
bash ~/.cursor/skills/isaacgym-ssh-recovery/scripts/recover-isaacgym-ssh.sh
```

Note: the command runner already auto-invokes:

```bash
bash ~/.cursor/skills/isaacgym-ssh-recovery/scripts/ensure-isaacgym-ssh.sh
```

before connecting, so explicit recovery is usually only needed for troubleshooting.

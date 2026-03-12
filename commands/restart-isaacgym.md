# Restart IsaacGym

Restart IsaacGym Docker and validate SSH, GPU, and display readiness.

Invoke as `/restart-isaacgym`.

## Defaults

- jump host: `huh.desktop.us`
- container name: `isaacgym`
- ssh alias: `isaacgym`
- ssh port: `22022`
- healthcheck script on jump host: `~/.cursor/scripts/restart_isaacgym_healthcheck.sh`

## Execution Policy

- If invoked from local machine:
  1. Run local prechecks:
     - `ssh -o BatchMode=yes -o ConnectTimeout=12 huh.desktop.us "echo jump_host_ok"`
     - `ssh -G isaacgym >/dev/null`
  2. Run remote restart and health checks on jump host:
     - `ssh huh.desktop.us "bash ~/.cursor/scripts/restart_isaacgym_healthcheck.sh"`
  3. Run local alias verification:
     - `ssh -o ConnectTimeout=12 isaacgym "hostname && whoami"`

- If invoked on `huh.desktop.us`:
  1. Run:
     - `bash ~/.cursor/scripts/restart_isaacgym_healthcheck.sh`

## Required Result Format

Return concise pass/fail status for:
- local prechecks
- container restart
- SSH service
- GPU
- display readiness
- local `ssh isaacgym` verification (when invoked locally)

If any step fails, include one-line immediate next action.

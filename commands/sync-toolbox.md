# Sync Toolbox

Synchronize Cursor toolbox assets (`rules`, `commands`, `skills`, `agents` for sub-agents, relevant `scripts`) across:
- local machine
- `huh.desktop.us`
- `isaacgym`

Use `~/.ssh/config` aliases as the source of host definitions.

## Invocation

- `/sync-toolbox` (interactive apply)
- `/sync-toolbox --dry-run` (preview only)
- `/sync-toolbox --destinations local,isaacgym --async` (approved-target async apply)

## Agent workflow

1. Run:
   - `bash ~/.cursor/scripts/sync_toolbox.sh discover --json-out ~/.cursor/tmp/sync_toolbox_state/latest_conflicts.json`
2. Read the generated conflict report.
3. For each conflict:
   - Show per-source short differences.
   - Ask user which source should win, or skip.
   - Include an explicit prompt option to choose the most recently edited source.
4. Build a resolution file and run:
   - `bash ~/.cursor/scripts/sync_toolbox.sh apply --resolution-file <path> --destinations <csv_hosts|all> --async`
   - Apply performs SSH to each destination and runs `git pull`/merge in each host's `~/.cursor` against the toolbox GitHub origin.
5. Print final verification summary.

## Conflict prompt format requirements

For each source of the conflicting file:
- Use plain English bullets.
- Maximum 5 bullets.
- Maximum 10 words per bullet.

## Notes

- Always back up overwritten files.
- Sync script scope includes `~/.cursor/agents/*` for sub-agent definitions.
- Sync script scope includes `~/.cursor/scripts/*.sh` used by skills/commands.
- Continue when a host is unreachable; report skipped targets.
- Never hardcode host IPs; rely on SSH aliases.

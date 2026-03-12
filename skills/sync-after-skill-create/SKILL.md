---
name: sync-after-skill-create
description: Legacy fallback for toolbox sync guidance. Prefer the personal rule `~/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc` for primary behavior when editing toolbox assets.
---

# Sync After Skill Create Or Modify

## Status

This skill is now a fallback. Primary sync behavior is defined by:

- `~/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc`

Use this skill only if that rule is unavailable in the current environment.

## When To Apply

Apply this workflow when the task includes:
- creating a new skill
- modifying an existing skill under `~/.cursor/skills/` or `.cursor/skills/`
- generating or updating `SKILL.md`
- creating a command under `~/.cursor/commands/` or `.cursor/commands/`
- modifying a command under `~/.cursor/commands/` or `.cursor/commands/`
- creating a rule under `~/.cursor/rules/` or `.cursor/rules/`
- modifying a rule under `~/.cursor/rules/` or `.cursor/rules/`

## Fallback Workflow (Mirror Rule Behavior)

1. Complete the requested create/modify task first (skill, command, or rule).
2. Detect whether toolbox files changed in `skills`, `commands`, or `rules`.
3. If no relevant toolbox files changed, skip synchronization and state that explicitly.
4. If relevant toolbox files changed, invoke `SyncOrchestrator` and provide:
   - changed file list/diffs
   - host-purpose context for `local`, `huh.desktop.us`, `isaacgym`, and `Huh8.remote_kernel.fuyao`
5. `SyncOrchestrator` must run parallel reviewers:
   - `RemotePolicyReviewer` per host
   - `SecurityReviewer` per host
6. Respect gating outcomes:
   - block/skip hosts are excluded
   - prompt hosts require explicit user confirmation; include a `mark all` option to approve all prompt-gated hosts at once
   - apply/pass hosts are approved
7. Execute sync for approved hosts only:
   - `bash ~/.cursor/scripts/sync_toolbox.sh apply --resolution-file <path> --destinations <csv_hosts> --async`
8. After successful apply, print synced destinations:
   - First line must be exactly: `successfully synced to`
   - Then list each destination that synced from `~/.cursor/scripts/.sync_toolbox_state/operations.json`.
   - Include each destination once, preserving readable order.
9. Report final status with short counts:
   - identical
   - partial
   - conflicts
   - unreachable
10. Always include one brief final line:
   - `Office Sync Action: <1-2 sentence sync outcome>`

## Guardrails

- Do not hardcode hostnames, IPs, or ports.
- Rely on `~/.ssh/config` aliases used by `sync_toolbox.sh`.
- If a host is unreachable, continue and report skipped targets.
- Keep conflict summaries plain English, max 5 bullets, max 10 words each.
- Treat `local` as a full sync peer (not control-plane-only).

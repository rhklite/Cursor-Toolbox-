---
name: Deprecate orchestrator update deploy
overview: Deprecate hp-sweep-orchestrator in favor of sweep-fuyao, add a `record-deploy` CLI subcommand, and update deploy-fuyao to use the native tracker CLI instead of the external script.
todos:
  - id: deprecate-orchestrator
    content: Add deprecation notice to hp-sweep-orchestrator SKILL.md, remove tracker integration section
    status: pending
  - id: cli-record-deploy
    content: Add record-deploy subcommand to tracker_cli.py
    status: completed
  - id: update-deploy-skill
    content: Update deploy-fuyao SKILL.md to use native tracker CLI path
    status: completed
  - id: commit-push
    content: Commit and push changes on huh8/sweep-auto-record
    status: completed
isProject: false
---

# Deprecate Orchestrator and Integrate Deploy Auto-Record

## 1. Delete `hp-sweep-orchestrator`

Delete the entire skill directory at `~/.cursor/skills/hp-sweep-orchestrator/`.

## 2. Add `record-deploy` CLI subcommand

[tracker_cli.py](tracker_cli.py) currently has `record-sweep` and `update-sweep-status` but no `record-deploy`. Add:

- A `cmd_record_deploy` handler that reads JSON (via `--json` / `--json-file` / stdin) and calls `tracker_auto_record.record_deploy()`
- A `record-deploy` subparser entry

This mirrors the existing `record-sweep` subcommand pattern, reusing the `_read_json_input()` helper already in the CLI.

## 3. Update [deploy-fuyao SKILL.md](~/.cursor/skills/deploy-fuyao/SKILL.md)

The skill currently calls:

```bash
python3 ~/.cursor/scripts/tracker_auto_record.py record-deploy --json-file <path>
```

Replace with:

```bash
python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py record-deploy --json-file <path>
```

Also update the Post-Submit Report's `update-status` hint to use the native CLI path and `set-status` subcommand.

## 4. Commit and push on `huh8/sweep-auto-record`

Single commit on the existing feature branch.
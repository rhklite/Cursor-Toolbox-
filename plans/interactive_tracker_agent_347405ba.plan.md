---
name: Interactive Tracker Agent
overview: Rewrite the global skill at `~/.cursor/skills/policy-lineage-tracker/SKILL.md` into a comprehensive conversational agent contract, and add a lightweight `graph-summary` CLI command to support context-aware guided interactions.
todos:
  - id: graph-summary-store
    content: Add `build_summary(graph)` to tracker_store.py -- computes node counts, per-task rollups, and 5 most-recent nodes
    status: completed
  - id: graph-summary-cli
    content: Add `graph-summary` subcommand to tracker_cli.py and wire it as `graph_summary` action in apply-intent
    status: completed
  - id: rewrite-skill
    content: Rewrite ~/.cursor/skills/policy-lineage-tracker/SKILL.md with full interactive agent contract (trigger, context-first, guided flows, confirmation gate, post-action, error handling, multi-step hints)
    status: completed
  - id: smoke-test
    content: Run `tracker_cli.py graph-summary` to verify the new command works against the existing store
    status: completed
isProject: false
---

# Interactive Policy Lineage Tracker Agent

## Current State

The existing `[SKILL.md](~/.cursor/skills/policy-lineage-tracker/SKILL.md)` is a minimal procedural contract: "parse NL to JSON, call CLI, report result." It has no conversational guidance, no state awareness, and no inline display behavior. The CLI (`[tracker_cli.py](tracker_cli.py)`) already supports all write operations via `apply-intent`, plus `list-nodes` and `show-node` for reads, plus `export-mermaid` and `export-excel-xml`.

## What Changes

### 1. Add `graph-summary` CLI command (tracker_cli.py + tracker_store.py)

A new subcommand that returns a compact JSON overview the agent can quickly consume at the start of every conversation turn:

```json
{
  "task_count": 2,
  "mutation_count": 5,
  "run_count": 8,
  "tasks": [
    { "id": "task_r01_v12", "name": "R01 v12 base", "status": "active", "mutations": 3, "runs": 5 }
  ],
  "recent_nodes": [
    { "id": "run_xxx", "type": "run", "name": "Trial 1", "status": "finished", "updated_at": "..." }
  ]
}
```

- In `[tracker_store.py](tracker_store.py)`: add `build_summary(graph) -> dict` that computes counts, per-task rollups, and the 5 most recently updated nodes.
- In `[tracker_cli.py](tracker_cli.py)`: add `graph-summary` subcommand and wire `"graph_summary"` as a new action in `cmd_apply_intent`.

### 2. Rewrite the global SKILL.md

Replace `[~/.cursor/skills/policy-lineage-tracker/SKILL.md](~/.cursor/skills/policy-lineage-tracker/SKILL.md)` with a full interactive agent contract covering:

**A. Trigger detection** -- same phrase list but broader (also match "I trained...", "new experiment", "checkpoint at...", etc.).

**B. Context-first protocol** -- on every activation the agent MUST run `graph-summary` first and present the user with a short status line ("You have 2 tasks, 5 mutations, 8 runs. Most recent: run_xxx finished 10 min ago.").

**C. Guided flows per action** -- for each action type, define the exact sequence of clarifying questions the agent should ask when information is missing:

```
create_task:
  required: task_id, name
  ask-if-missing: description, repo_task, tags

record_mutation:
  required: mutation_id, task_id, name
  context: show existing tasks for user to pick from
  ask-if-missing: parent_ids (show recent runs/mutations), delta, notes, tags

attach_run:
  required: run_id, mutation_id, name
  context: show mutations under selected task
  ask-if-missing: command, checkpoint, metrics, status, tags

set_status:
  required: node_id, status
  context: show matching nodes, offer valid statuses

spawn_batch:
  required: mutation_id, spec
  ask-if-missing: execute flag, individual run specs

export_all:
  no questions needed
```

**D. Confirmation gate** -- after gathering all fields, the agent MUST show the assembled intent JSON to the user and wait for explicit approval before executing.

**E. Post-action protocol** -- after every successful write:

1. Auto-run `export_all` via the CLI.
2. Read the exported mermaid file and display the diagram inline as a fenced mermaid code block.
3. Show a compact markdown table of the affected nodes.

**F. Error handling** -- if the CLI returns `{"ok": false, "error": "..."}`, display the error clearly and suggest corrective action.

**G. Multi-step workflow hints** -- after certain actions, proactively suggest the natural next step:

- After `create_task` -> "Would you like to record the first mutation?"
- After `record_mutation` -> "Ready to attach a run or spawn a batch?"
- After `attach_run` with metrics -> "Want to promote this mutation or try another run?"

### 3. Files changed (summary)

- `[tracker_store.py](tracker_store.py)` -- add `build_summary()` function (~25 lines)
- `[tracker_cli.py](tracker_cli.py)` -- add `cmd_graph_summary` + `graph_summary` action + parser entry (~30 lines)
- `[~/.cursor/skills/policy-lineage-tracker/SKILL.md](~/.cursor/skills/policy-lineage-tracker/SKILL.md)` -- full rewrite (~200 lines)


---
name: Auto-record sweeps integration
overview: Absorb the external `tracker_auto_record.py` into the tracker repo as a native `record-sweep` CLI command and SDK method, add sweep grouping to the dashboard, and update the sweep-fuyao skill to use the native path -- with a critique of the current skill prompt and fixes for its edge cases.
todos:
  - id: feature-branch
    content: Create feature/sweep-auto-record branch from main
    status: completed
  - id: absorb-script
    content: Copy tracker_auto_record.py into repo, remove sys.path hack, add to Dockerfile
    status: completed
  - id: sdk-record-sweep
    content: Add record_sweep() to tracker_sdk.py with idempotency and batch write
    status: completed
  - id: store-metadata-lookup
    content: Add find_by_metadata() to tracker_store.py for sweep_id lookup
    status: completed
  - id: cli-record-sweep
    content: Add record-sweep and update-sweep-status subcommands to tracker_cli.py
    status: completed
  - id: dashboard-sweep-view
    content: Add sweep grouping, sweep summary panel, and sweep_id column to dashboard
    status: completed
  - id: update-sweep-fuyao-skill
    content: Update sweep-fuyao SKILL.md to use native CLI with deduplication/idempotency clauses
    status: completed
  - id: update-hp-sweep-skill
    content: Add Experiment Tracker Integration section to hp-sweep-orchestrator SKILL.md
    status: completed
  - id: commit-push
    content: Commit all changes and push feature branch
    status: completed
isProject: false
---

# Auto-Record Fuyao Sweeps into Experiment Tracker

## Current State

**What exists:**

- `tracker_auto_record.py` lives at `~/.cursor/scripts/` as an external script that hard-codes `sys.path.insert(0, "/Users/HanHu/software/policy-lineage-tracker")`. It handles `record-sweep`, `record-deploy`, and `update-status`.
- The `sweep-fuyao` skill already has an "Experiment Tracker Integration" section that calls `tracker_auto_record.py record-sweep` after dispatch.
- The tracker CLI (`tracker_cli.py`) and SDK (`tracker_sdk.py`) have no sweep-specific commands or methods.
- The dashboard has zero sweep awareness (no grouping, filtering, or sweep views).

**What's broken / fragile:**

- The recording script is external to the repo and hard-codes an absolute path.
- Sweeps appear as individual unrelated mutations in the dashboard.
- No deduplication: re-running the skill creates duplicate mutations.
- No automatic status reconciliation when jobs finish.
- `hp-sweep-orchestrator` skill has no tracker integration at all.

---

## Critique of the `sweep-fuyao` SKILL.md Tracker Integration Prompt

### Edge cases the current prompt misses

1. **Deduplication** -- If the agent runs twice for the same sweep (retry, crash recovery), duplicate mutations are created. The prompt should require the agent to check for existing mutations matching the `sweep_id` before recording.
2. **Store root mismatch** -- The prompt never specifies `--store-root`. The `policy-lineage-tracker` skill uses `~/.local/share/motion-rl-tracker`, while `tracker_auto_record.py` defaults to `~/.exp-tracker`. If these differ, recordings go to the wrong store and won't appear on the dashboard.
3. **Concurrent writes** -- Two sweeps dispatched simultaneously could race on `graph.json`. The prompt doesn't mention serialization or retries.
4. **Partial recording failure** -- If 8 of 10 combos record successfully but 2 fail, the prompt says "list as warnings." But there's no way to resume/retry just the 2 failed combos without re-recording all 10.
5. **Status lifecycle gap** -- The prompt says to set status `"running"` but never defines when or how to transition to `"completed"` / `"failed"`. The `update-status` command exists but the prompt only mentions it in the Post-Submit Report as a copy-paste hint. There should be a `--verify-and-update` step that checks job status and batch-updates all mutations.
6. **Missing `command` field** -- The prompt requires `command` per combo but the dispatcher doesn't always expose the full training command in an easily parseable way. If the command is missing, the prompt should allow `""` rather than failing.
7. **No task creation guard** -- If the task doesn't exist in the tracker, `tracker_auto_record.py` creates it implicitly. But the prompt doesn't mention this, and the auto-created task has minimal metadata (no `base_config`, `description`, etc.).
8. **Branch as linkage** -- The prompt stores `branch` in metadata but there's no way to filter mutations by branch in the dashboard, making it hard to see "all experiments on branch X."
9. `**hp-sweep-orchestrator` excluded** -- The sister skill has identical sweep dispatch output but zero tracker integration. The prompt improvements should be reusable across both skills.
10. **No idempotency key** -- The `mutation_id` is generated with a timestamp + UUID, making every call unique. There's no stable idempotency key derived from `(sweep_id, combo_name)`.

---

## Plan

### 1. Create feature branch

```bash
git checkout -b feature/sweep-auto-record main
```

### 2. Absorb `tracker_auto_record.py` into the repo

- Copy `~/.cursor/scripts/tracker_auto_record.py` into the repo root as [tracker_auto_record.py](tracker_auto_record.py)
- Remove the hard-coded `sys.path.insert` hack; use relative imports or make it a sibling module
- Add it to the Docker image in the Dockerfile `COPY` line

### 3. Add `record-sweep` subcommand to [tracker_cli.py](tracker_cli.py)

Add a native CLI subcommand that wraps the sweep recording logic:

```
tracker record-sweep --json-file <path>
tracker record-sweep --json '<json>'
```

This calls the SDK method (step 4) and outputs `{ok, task_id, sweep_id, results}` to stdout.

### 4. Add `record_sweep()` to [tracker_sdk.py](tracker_sdk.py)

```python
def record_sweep(
    task: str,
    combos: list[dict],
    *,
    sweep_id: str = "",
    branch: str = "",
    hp_specs_summary: str = "",
    run_root: str = "",
    parent_mutation_id: str = "",
    dry_run: bool = False,
    store_root: str | None = None,
) -> dict:
```

Key behaviors:

- **Ensure task exists** (create with minimal data if not)
- **Derive idempotency key** from `(sweep_id, combo_name)` -- skip combos that already have a matching mutation, enabling safe retries
- **Atomic batch write** -- write all mutations in one `_save()` call to avoid partial state
- **Tag all mutations** with `sweep:<sweep_id>` for dashboard grouping
- **Store `sweep_id`, `branch`, `combo_name`, `combo_index`** in mutation metadata

### 5. Add `update-sweep-status` to [tracker_cli.py](tracker_cli.py)

Batch-update all mutations in a sweep by querying metadata `sweep_id`:

```
tracker update-sweep-status --sweep-id <id> --json '{"status":"completed","metrics":{...}}'
```

Or per-mutation: `tracker set-status --node-id <mutation_id> --status completed`

### 6. Dashboard sweep grouping in [dashboard_server.py](dashboard_server.py)

- Add a "Sweeps" filter/view in the sidebar that groups mutations by `metadata.sweep_id`
- Show sweep summary: combo count, succeeded/failed/running counts, branch, HP grid
- Click a sweep to expand and see individual mutations
- Add a `sweep_id` column to the inspector table

### 7. Update [sweep-fuyao SKILL.md](~/.cursor/skills/sweep-fuyao/SKILL.md)

Replace the external script path with the native CLI:

```bash
# Old:
python3 ~/.cursor/scripts/tracker_auto_record.py record-sweep --json-file <path>

# New:
python3 <PROJECT_DIR>/tracker_cli.py record-sweep --json-file <path>
```

Add these clauses to the "Experiment Tracker Integration" section:

- **Deduplication:** "Before recording, the CLI checks for existing mutations with matching `sweep_id + combo_name`. Duplicates are skipped."
- **Store root:** "Always pass `--store-root ~/.exp-tracker` (or whatever the configured root is)."
- **Idempotency:** "Safe to re-run -- duplicate combos are skipped, new ones are added."
- **Status reconciliation:** "After verification, if all jobs are terminal, run `tracker update-sweep-status --sweep-id <id> --status completed`."

### 8. Add same tracker integration to `hp-sweep-orchestrator` SKILL.md

Copy the Experiment Tracker Integration section from sweep-fuyao into `hp-sweep-orchestrator/SKILL.md` with the same payload format and native CLI path.

---

## Files changed


| File | Change |
| ---- | ------ |


- [tracker_cli.py](tracker_cli.py) -- Add `record-sweep` and `update-sweep-status` subcommands
- [tracker_sdk.py](tracker_sdk.py) -- Add `record_sweep()` with idempotency and batch write
- [tracker_store.py](tracker_store.py) -- Add `find_by_metadata()` helper for sweep_id lookup; sweep tag support
- [dashboard_server.py](dashboard_server.py) -- Add sweep grouping view, sweep_id filter, sweep summary panel
- [tracker_auto_record.py](tracker_auto_record.py) -- Absorb from `~/.cursor/scripts/`, remove path hack, delegate to SDK
- [Dockerfile](Dockerfile) -- Add `tracker_auto_record.py` to COPY
- `~/.cursor/skills/sweep-fuyao/SKILL.md` -- Update to native CLI, add deduplication/idempotency/store-root clauses
- `~/.cursor/skills/hp-sweep-orchestrator/SKILL.md` -- Add Experiment Tracker Integration section


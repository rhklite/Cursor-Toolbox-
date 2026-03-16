---
name: Test sweep auto-record
overview: Add test cases to `tests/test_tracker.py` covering the new sweep recording, deploy recording, idempotency, status updates, metadata lookup, and CLI subcommands.
todos:
  - id: write-tests
    content: Add all test cases to tests/test_tracker.py
    status: completed
  - id: run-tests
    content: Run test suite and verify all pass
    status: completed
  - id: commit-push
    content: Commit and push on huh8/sweep-auto-record
    status: completed
isProject: false
---

# Test Cases for Sweep Auto-Record Features

All tests go in [tests/test_tracker.py](tests/test_tracker.py), following the existing pattern: `unittest.TestCase` with `tempfile.TemporaryDirectory` as store root, `_capture_json()` for CLI output.

## Test groups

### 1. `find_by_metadata()` (store layer)

- `**test_find_by_metadata_returns_matching_nodes**` -- Create 2 mutations with `metadata.sweep_id = "sw1"` and 1 without. Assert `find_by_metadata(graph, "sweep_id", "sw1")` returns exactly 2.
- `**test_find_by_metadata_filters_by_node_type**` -- Create a task and mutation both with same metadata key. Assert `node_type="mutation"` filters out the task.
- `**test_find_by_metadata_empty_on_no_match**` -- Assert returns `[]` for a nonexistent key.

### 2. `record_sweep()` (SDK layer)

- `**test_record_sweep_creates_task_and_mutations**` -- Call `record_sweep(task="MyTask", combos=[...], sweep_id="sw-test", branch="main")` on an empty store. Assert task auto-created, all combos become mutations, return has `ok=True`, correct `succeeded` count.
- `**test_record_sweep_idempotent_skips_duplicates**` -- Call `record_sweep` twice with same `sweep_id` and combos. Assert second call has `skipped > 0`, `succeeded == 0`, total mutations unchanged.
- `**test_record_sweep_partial_retry**` -- Record 2 combos, then re-call with 3 combos (same sweep_id). Assert the new combo is added, original 2 are skipped.
- `**test_record_sweep_missing_task_returns_error**` -- Call with `task=""`. Assert `ok=False`.
- `**test_record_sweep_empty_combos_returns_error**` -- Call with `combos=[]`. Assert `ok=False`.
- `**test_record_sweep_dry_run_sets_planned**` -- Call with `dry_run=True`. Assert all created mutations have `status="planned"`.
- `**test_record_sweep_tags_include_sweep_id**` -- Assert created mutations have `sweep:<sweep_id>` in tags.

### 3. `update_sweep_status()` (SDK layer)

- `**test_update_sweep_status_updates_all**` -- Record a sweep, then call `update_sweep_status(sweep_id, "completed")`. Assert all mutations now have `status="completed"`.
- `**test_update_sweep_status_nonexistent_sweep**` -- Call with unknown sweep_id. Assert `ok=False`.

### 4. CLI `record-sweep` subcommand

- `**test_cli_record_sweep_via_json_flag**` -- Call `cmd_record_sweep` with `--json` inline payload. Assert `ok=True` in captured JSON output.

### 5. CLI `record-deploy` subcommand

- `**test_cli_record_deploy_creates_mutation**` -- Call `cmd_record_deploy` with a deploy payload. Assert `ok=True`, `mutation_id` present, task auto-created.
- `**test_cli_record_deploy_missing_branch**` -- Call with `branch=""`. Assert `ok=False`.

### 6. CLI `update-sweep-status` subcommand

- `**test_cli_update_sweep_status**` -- Record a sweep via SDK, then call `cmd_update_sweep_status`. Assert `ok=True`, correct `updated` count.


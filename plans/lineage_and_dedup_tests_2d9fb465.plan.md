---
name: Lineage and dedup tests
overview: Add test cases for deploy idempotency (job_name dedup), parent-child lineage auto-resolution, explicit parent override, cross-skill lineage chains, and delta recording.
todos:
  - id: write-lineage-tests
    content: Add 8 lineage/dedup test cases to tests/test_tracker.py
    status: completed
  - id: run-tests
    content: Run full test suite and verify all pass
    status: completed
  - id: commit-push
    content: Commit and push
    status: completed
isProject: false
---

# Test Cases for Parent-Child Lineage and Deploy Idempotency

All tests go in [tests/test_tracker.py](tests/test_tracker.py) inside the existing `SweepAutoRecordTests` class.

## Test groups

### 1. Deploy idempotency (`record_deploy` job_name dedup)

- `**test_record_deploy_idempotent_by_job_name**` -- Call `record_deploy` twice with same `job_name`. Assert second call returns `skipped: True` and the same `mutation_id`. Assert total mutations = 1.
- `**test_record_deploy_no_dedup_without_job_name**` -- Call `record_deploy` twice with `job_name=""`. Assert both succeed and create 2 mutations (no dedup when job_name is empty).

### 2. Parent auto-resolution (single deploys)

- `**test_deploy_auto_parent_links_to_previous**` -- Record deploy_1 then deploy_2 on the same task + branch. Assert deploy_2 has `derives_from` edge pointing to deploy_1.
- `**test_deploy_no_parent_on_first_deploy**` -- Record a single deploy on a fresh task + branch. Assert no `derives_from` edges for that mutation.

### 3. Explicit parent override

- `**test_deploy_explicit_parent_overrides_auto**` -- Record deploy_1 and deploy_2 independently, then record deploy_3 with `parent_mutation_id = deploy_1`. Assert deploy_3's parent is deploy_1 (not deploy_2 which is more recent).

### 4. Sweep parent auto-resolution

- `**test_sweep_auto_parent_links_to_previous_mutation**` -- Record a deploy, then a sweep on the same task + branch. Assert all sweep combos have `derives_from` edge pointing to the deploy.

### 5. Cross-skill lineage chain

- `**test_deploy_then_sweep_then_deploy_chain**` -- Record deploy_1, then a sweep (3 combos), then deploy_2 on the same branch. Assert deploy_1 exists, sweep combos link to deploy_1, and deploy_2 links to one of the sweep combos (verifying the chain is connected end-to-end).

### 6. Deploy with delta

- `**test_deploy_records_delta**` -- Call `record_deploy` with `delta={"train.lr": 0.003}`. Assert the created mutation's data contains the delta.


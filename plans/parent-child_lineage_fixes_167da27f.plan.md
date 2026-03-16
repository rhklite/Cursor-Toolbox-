---
name: Parent-child lineage fixes
overview: "Fix parent-child lineage in deploy-fuyao and sweep-fuyao tracker integration: add explicit `parent_mutation_id` to payloads, document auto-resolution, fix post-sweep parent ambiguity, and ensure store-root consistency."
todos:
  - id: deploy-skill-payload
    content: "Update deploy-fuyao SKILL.md: add parent_mutation_id, delta, store-root, lineage note"
    status: completed
  - id: sweep-skill-payload
    content: "Update sweep-fuyao SKILL.md: add parent_mutation_id, store-root to CLI invocation"
    status: completed
  - id: deploy-idempotency
    content: Add job_name dedup to record_deploy in tracker_auto_record.py
    status: completed
  - id: commit-push
    content: Commit and push on huh8/sweep-auto-record
    status: completed
isProject: false
---

# Fix Parent-Child Lineage in Fuyao Tracker Integration

## Critique of the user's prompt

The prompt says "for each job deployed, it automatically records it into the experiment tracker, hooked up to the parent and child nodes." Both skills already call the tracker CLI after dispatch. The underlying code already auto-resolves parents via `_find_latest_mutation(task_id, branch)`. So the recording and parent linkage already works in the common case. What's missing:

### Edge cases not considered

1. **Post-sweep parent ambiguity** -- After a sweep records 10 mutations, the next deploy on the same branch picks "the latest mutation" as parent. But all 10 sweep combos were created within the same second, so the parent is effectively random among them. The parent should instead be the sweep's first combo or no parent at all (since the sweep is a parallel fan-out, not a linear chain). Fix: after recording a sweep, store the `sweep_id` as a "sweep group" and use it to skip sweep combos when resolving the parent for the *next* deploy.
2. **Explicit parent override** -- Neither skill's payload template includes `parent_mutation_id`. The auto-resolution works for linear chains, but if the user wants to branch from a specific mutation (e.g., "deploy based on combo_3 results"), they have no way to specify it. Fix: add `parent_mutation_id` as an optional field in both payload templates with a note that it's auto-resolved if omitted.
3. **Store root mismatch** -- `deploy-fuyao` doesn't pass `--store-root`, so it uses the CLI default (`~/.local/share/motion-rl-tracker`). `sweep-fuyao` documents passing `--store-root ~/.exp-tracker`. If they differ, deploys and sweeps land in different stores with no cross-visibility. Fix: both skills must pass the same `--store-root`.
4. **No idempotency for single deploys** -- `record-sweep` has dedup via `sweep_id + combo_name`. `record-deploy` has no dedup: retrying creates a duplicate mutation. Fix: add optional `deploy_id` to the payload for idempotent single deploys (derived from `job_name` or `label + timestamp`).
5. **Cross-skill lineage undocumented** -- A user might: deploy -> sweep -> deploy -> sweep. The lineage chain works via branch-based auto-resolution, but neither skill documents this flow or the expected graph shape.
6. **Deploy delta is always empty** -- Single deploys never include a `delta` (HP changes). The mutation is recorded with no `delta`, making the lineage graph less informative. The skill should instruct the agent to include `delta` if the user mentioned specific parameter changes.

## Changes

### 1. Update [deploy-fuyao SKILL.md](~/.cursor/skills/deploy-fuyao/SKILL.md) payload

Add to the JSON payload template:

- `"parent_mutation_id": ""` (optional, auto-resolved if empty)
- `"delta": {}` (optional, include if user specified HP changes)

Add `--store-root ~/.exp-tracker` to the CLI invocation.

Add a "Lineage" note explaining auto-parent resolution and how to override.

### 2. Update [sweep-fuyao SKILL.md](~/.cursor/skills/sweep-fuyao/SKILL.md) payload

Add to the JSON payload template:

- `"parent_mutation_id": ""` (optional, auto-resolved if empty)

Ensure `--store-root ~/.exp-tracker` is in the CLI invocation.

### 3. Fix post-sweep parent resolution in [tracker_sdk.py](tracker_sdk.py)

In `record_sweep()`, after creating all combos, tag the last combo as `sweep_head: true` in metadata. In the parent auto-resolution logic, when multiple mutations exist on the same branch at the same timestamp, prefer the one tagged `sweep_head`.

Alternatively (simpler): skip this for now and document that after a sweep, the parent of the next deploy may point to any combo. The user can override with `parent_mutation_id` if precise control is needed.

### 4. Add idempotency to `record-deploy` in [tracker_auto_record.py](tracker_auto_record.py)

Check for existing mutation with matching `metadata.job_name` before creating. If found, skip and return the existing `mutation_id`.

### 5. Commit and push on `huh8/sweep-auto-record`


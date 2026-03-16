---
name: Sweep Parent Enforcement
overview: Enforce parent-node linkage for sweep combos, enhance cascade delete messaging for sweep parents, and add batch artifact download across all sweep children from the parent node inspector.
todos:
  - id: enforce-parent
    content: In record_sweep, reject sweep dispatch when no parent mutation is resolvable (error out instead of creating orphan combos)
    status: completed
  - id: delete-modal-sweep
    content: Enhance showDeleteModal to specifically identify and call out sweep combo children in the confirmation message
    status: completed
  - id: sweep-artifacts-api
    content: Add GET /api/sweep-children-artifacts endpoint that returns artifact_links for all sweep children of a parent node
    status: completed
  - id: batch-download-js
    content: Add downloadSweepArtifactsZip JS function that fetches all artifacts from sweep children and creates a single ZIP with combo subfolders
    status: completed
  - id: sweep-panel-ui
    content: Render Sweep Artifacts section on parent node inspector with batch download button (only when sweep children exist)
    status: completed
  - id: skill-updates
    content: Update deploy-fuyao, sweep-fuyao, and fuyao-job-manager skill files with artifact linking guidance
    status: completed
isProject: false
---

# Sweep Parent Enforcement, Cascade Delete, and Batch Artifact Download

Three interconnected changes to improve sweep workflow ergonomics.

## 1 -- Enforce parent requirement for sweep combos

**File:** [tracker_auto_record.py](tracker_auto_record.py)

In `record_sweep`, after parent auto-resolution (lines 232-243), if `parent_ids` is still empty, return an error instead of creating orphan mutations:

```python
if not parent_ids:
    return {
        "ok": False,
        "error": "Sweep combos must derive from a parent mutation. "
                 "Provide parent_mutation_id or deploy to this task+branch first.",
    }
```

This guarantees every sweep combo has a `derives_from` edge to a parent. The parent is resolved via:

- Explicit `parent_mutation_id` in the payload, OR
- Auto-resolution: latest mutation on the same task + branch

If neither exists, the sweep is rejected with a clear error.

**Test:** Add a test case in [tests/test_artifact_links.py](tests/test_artifact_links.py) (or a new test file) verifying that `record_sweep` with no resolvable parent returns `ok: false`.

## 2 -- Enhanced delete modal for sweep parents

**File:** [dashboard_server.py](dashboard_server.py)

The `showDeleteModal` function (line 1095) already handles cascade deletion with confirmation. Enhance it to specifically identify sweep children when present.

In the `hasChildren` branch, check if any descendants have `deploy_type === "sweep"` in their metadata. The descendant refs from `state.detail.descendants` only contain id/name/type/status -- not metadata. So the check needs the full graph data.

**Approach:** When building the modal, filter `state.fullGraph.nodes` for descendants whose `data.metadata.deploy_type === "sweep"`. If sweep combos are found, add a specific callout:

```
"This will also delete N sweep combo mutations (sweep: SWEEP_ID)."
```

The confirm button text changes to "Delete parent + N sweep combos" when sweep children are present.

No backend changes needed -- `delete_node_cascade` already handles this correctly.

## 3 -- Batch artifact download for sweep parent

This is the largest change. On a parent node's inspector, when its children are sweep combos with linked artifacts, show a "Download All Sweep Artifacts" button.

### 3a -- New API endpoint

**File:** [dashboard_server.py](dashboard_server.py) (server-side handler in `do_GET`)

Add `GET /api/sweep-children-artifacts?node_id=PARENT_ID`:

- Load graph, find all children of `node_id` via `get_children()`
- Filter children whose `data.metadata.deploy_type === "sweep"`
- For each sweep child, extract `data.metadata.artifact_links` and `data.metadata.combo_label`
- Return:

```json
{
  "ok": true,
  "parent_id": "...",
  "children": [
    {
      "node_id": "mut_...",
      "combo_label": "r01-v12-0001-lr_1e3",
      "artifact_links": { "model": [...], "video": [...], "analysis": [...] }
    }
  ]
}
```

### 3b -- Client-side batch download JS

**File:** [dashboard_server.py](dashboard_server.py) (JS section)

Add `downloadSweepArtifactsZip(parentNodeId)`:

- Calls `/api/sweep-children-artifacts?node_id=PARENT_ID`
- For each child with artifact_links, fetches all files (model, video, analysis)
- Organizes into subfolders per combo: `{combo_label}/{filename}`
- Creates a single ZIP via JSZip and triggers browser download
- Shows progress toast: "Packaging combo N/M: filename..."

### 3c -- Inspector UI integration

**File:** [dashboard_server.py](dashboard_server.py) (inspector rendering, around line 1948)

On the parent mutation inspector (the node whose children are sweep combos), after the existing Artifacts panel, add a "Sweep Artifacts" section:

- Check: does this node have sweep children? Use `state.detail.descendants` to see if any descendant has a name starting with "Sweep:" (the naming convention from `record_sweep` line 286: `f"Sweep: {combo_label}"`)
- If yes, render a "Download All Sweep Artifacts" button calling `downloadSweepArtifactsZip(nodeId)`
- Also show the list of sweep children with individual artifact links

**Scope guard:** This section only renders when descendants are sweep combos (checking `deploy_type` or name prefix). Regular child mutations do not trigger this UI.

## 4 -- Skill file updates

**Files:**

- [deploy-fuyao SKILL.md](/home/huh/.cursor/skills/deploy-fuyao/SKILL.md) -- Add artifact linking follow-up command in Post-Submit Report
- [sweep-fuyao SKILL.md](/home/huh/.cursor/skills/sweep-fuyao/SKILL.md) -- Add artifact linking follow-up command in Post-Submit Report
- [fuyao-job-manager SKILL.md](/home/huh/.cursor/skills/fuyao-job-manager/SKILL.md) -- Mention `link-job-artifacts` as alternative to `pull`

## Files changed

- [tracker_auto_record.py](tracker_auto_record.py) -- enforce parent requirement in `record_sweep`
- [dashboard_server.py](dashboard_server.py) -- enhanced delete modal, new API endpoint, batch download JS, sweep artifacts panel
- [deploy-fuyao/SKILL.md](/home/huh/.cursor/skills/deploy-fuyao/SKILL.md) -- post-submit artifact linking guidance
- [sweep-fuyao/SKILL.md](/home/huh/.cursor/skills/sweep-fuyao/SKILL.md) -- post-submit artifact linking guidance
- [fuyao-job-manager/SKILL.md](/home/huh/.cursor/skills/fuyao-job-manager/SKILL.md) -- mention link-job-artifacts


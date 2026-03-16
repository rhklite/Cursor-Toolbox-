---
name: local-first-sync-workflow
overview: "Align the toolbox sync guidance so it explicitly enforces: if currently in an SSH session, return to local/top-level shell first, then run sync from local environment only."
todos:
  - id: update-rule-ssh-exit
    content: Add explicit SSH-session exit-to-local precondition in sync toolbox rule.
    status: completed
  - id: update-command-local-first
    content: Rewrite sync-toolbox command doc to local-first, local-only workflow with SSH exit behavior.
    status: completed
  - id: consistency-check
    content: Review docs for contradictions and remove remote-destination examples for this workflow.
    status: completed
isProject: false
---

# Local-First Sync Toolbox Plan

## Goal

Update the toolbox sync guidance so the workflow is explicit and unambiguous:

- detect SSH session context
- if in SSH session, return to local shell first
- run sync from local machine environment only

## Findings from Current State

- Rule file is already local-only but does not explicitly define SSH-session exit behavior: `[/home/huh/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc](/home/huh/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc)`
- Command doc still describes multi-host workflow and remote destinations: `[/home/huh/.cursor/commands/sync-toolbox.md](/home/huh/.cursor/commands/sync-toolbox.md)`
- Sync script itself supports multi-host discovery/apply and is not local-only by design: `[/home/huh/.cursor/scripts/sync_toolbox.sh](/home/huh/.cursor/scripts/sync_toolbox.sh)`

## Planned Changes

1. Update rule wording to explicitly add SSH-exit precondition:

- Add a step such as: "If current shell is an SSH/remote session, return to local/top-level shell before invoking sync."
- Keep local-only apply command (`--destinations local`).

1. Update `/sync-toolbox` command doc to local-first semantics:

- Replace multi-host framing with local-first workflow.
- Add explicit context detection guidance and remediation:
  - remote/ssh session -> exit to local shell
  - local shell -> proceed
- Adjust invocation examples to local-only destination.

1. Decide whether script behavior should remain generic:

- Keep script unchanged (recommended) and enforce local-first behavior in rule/command docs.
- Optionally document that local-only policy is a workflow constraint, not a hard script limitation.

1. Validation pass:

- Confirm updated docs consistently state local-first + SSH-exit behavior.
- Ensure no remaining contradictory examples mention remote destinations for this workflow.

## Files to Update

- `[/home/huh/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc](/home/huh/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc)`
- `[/home/huh/.cursor/commands/sync-toolbox.md](/home/huh/.cursor/commands/sync-toolbox.md)`

## Notes

- No script-level code change is required unless you want hard enforcement inside `sync_toolbox.sh` itself (which would alter broader script capabilities).

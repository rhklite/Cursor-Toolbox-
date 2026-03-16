---
name: sync-toolbox-rule
overview: Convert the existing sync-after-skill behavior into a personal Cursor rule that applies only when working with toolbox files, preserving the same gated sync workflow and safety constraints.
todos:
  - id: create-rule-file
    content: Create personal rule .mdc file under ~/.cursor/rules with toolbox-file scoped frontmatter.
    status: completed
  - id: port-workflow
    content: Port sync workflow requirements from sync-after-skill-create skill into concise rule instructions.
    status: completed
  - id: validate-scope
    content: Validate rule applies only to toolbox file work and preserves required sync output format.
    status: completed
  - id: optional-deduplicate
    content: Optionally deprecate or reduce overlap in existing sync-after-skill-create skill after rule adoption.
    status: completed
isProject: false
---

# Convert Sync Workflow To Personal Rule

## Goal

Create a personal Cursor rule that replaces the current skill-based guidance for toolbox syncing, and activates only when toolbox assets are involved.

## Source Behavior To Preserve

Use the existing logic from `[/Users/HanHu/.cursor/skills/sync-after-skill-create/SKILL.md](/Users/HanHu/.cursor/skills/sync-after-skill-create/SKILL.md)`:

- trigger after creating/modifying skills, commands, or rules
- skip sync when no toolbox files changed
- invoke `SyncOrchestrator` with host-purpose context
- enforce policy/security gating (`apply/skip/prompt`)
- sync approved hosts only via async apply
- standard post-sync reporting format (`successfully synced to`, counts, `Office Sync Action`)

## New Rule File

Create a personal rule file:

- `[/Users/HanHu/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc](/Users/HanHu/.cursor/rules/sync-toolbox-after-toolbox-edits.mdc)`

## Rule Frontmatter

Configure as file-scoped (not global):

- `description`: concise statement of sync policy
- `alwaysApply: false`
- `globs`: toolbox patterns so rule loads only for relevant work:
  - `**/.cursor/skills/**`
  - `**/.cursor/commands/**`
  - `**/.cursor/rules/**`

## Rule Content

Author concise instructions (rule-sized, not skill-sized) covering:

- when to trigger sync
- minimal required host context
- gating behavior and confirmation requirement for prompt hosts
- exact reporting requirements after apply
- guardrails (no hardcoded hosts/IPs; continue on unreachable hosts)

## Validation

- Verify `.mdc` frontmatter parses and scope is file-targeted.
- Confirm rule text keeps required output phrases unchanged.
- Confirm behavior remains equivalent to current skill workflow.

## Follow-up Cleanup (Optional)

After confirming the rule works as intended, optionally deprecate or trim overlap in `[/Users/HanHu/.cursor/skills/sync-after-skill-create/SKILL.md](/Users/HanHu/.cursor/skills/sync-after-skill-create/SKILL.md)` to avoid duplicated guidance.
---
name: sync after skill creation
overview: Create a personal workflow skill that, whenever the agent is asked to create a new skill, finishes by invoking `sync_toolbox` so rules/commands/skills stay synchronized across your configured machines.
todos:
  - id: create-sync-after-skill-skill
    content: Add personal skill file with trigger-focused frontmatter and workflow steps.
    status: completed
  - id: embed-sync-toolbox-workflow
    content: Define post-skill-creation sync steps using existing sync_toolbox script.
    status: completed
  - id: validate-discoverability
    content: Verify skill discoverability and expected invocation behavior for future skill-creation requests.
    status: completed
isProject: false
---

# Build `sync-after-skill-create` Skill

## Goal

Add a personal Cursor skill that is applied during skill-creation workflows and explicitly runs your existing `sync_toolbox` flow after creating or updating any skill files.

## Files To Add

- `[/Users/HanHu/.cursor/skills/sync-after-skill-create/SKILL.md](/Users/HanHu/.cursor/skills/sync-after-skill-create/SKILL.md)`

## Files To Reference

- `[/Users/HanHu/.cursor/scripts/sync_toolbox.sh](/Users/HanHu/.cursor/scripts/sync_toolbox.sh)`
- `[/Users/HanHu/.cursor/commands/sync-toolbox.md](/Users/HanHu/.cursor/commands/sync-toolbox.md)`
- `[/Users/HanHu/.cursor/skills-cursor/create-skill/SKILL.md](/Users/HanHu/.cursor/skills-cursor/create-skill/SKILL.md)`

## Implementation Steps

1. Create the new personal skill directory and `SKILL.md` with valid frontmatter:
  - `name: sync-after-skill-create`
  - description includes trigger terms like “create skill”, “new SKILL.md”, and “author skill”.
2. In the skill body, define the workflow:
  - Follow the normal skill-authoring process.
  - After writing any new or changed skill files, run:
    - `bash ~/.cursor/scripts/sync_toolbox.sh discover`
    - Resolve conflicts if any.
    - `bash ~/.cursor/scripts/sync_toolbox.sh apply --interactive`
  - Finish by reporting convergence status.
3. Add guardrails in the skill text:
  - If no skill files changed, skip sync.
  - If hosts are unreachable, continue and report skipped targets.
  - Do not hardcode host/IP data; rely on `~/.ssh/config` via existing script.
4. Keep wording concise so the skill is discoverable and can be auto-selected for future “create skill” requests.

## Validation

- Confirm the skill file is discoverable under `~/.cursor/skills/`.
- Dry test with a mock skill-creation request and verify the generated workflow includes calling `sync_toolbox`.
- Confirm output includes a short final sync status (conflicts/partial/identical/unreachable).

## Data Flow

```mermaid
flowchart TD
  userRequest[UserRequestsSkillCreation] --> applySkill[ApplySyncAfterSkillCreate]
  applySkill --> createOrEdit[CreateOrEditNewSkillFiles]
  createOrEdit --> discover[RunSyncToolboxDiscover]
  discover --> resolve[ResolveConflictsIfPresent]
  resolve --> applySync[RunSyncToolboxApplyInteractive]
  applySync --> verify[ReportConvergenceStatus]
```




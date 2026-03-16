---
name: IsaacGym Restart Trigger Merge
overview: Keep restart and recovery as one skill, but make restart intent the primary trigger context so Cursor reliably routes requests like “restart Isaac Gym container” to the merged skill.
todos:
  - id: update-recovery-trigger-context
    content: Edit isaacgym-ssh-recovery SKILL.md to make restart intent primary trigger while keeping merged restart+recovery behavior.
    status: completed
  - id: align-motion-rl-doc
    content: Adjust motion-rl-isaacgym-exec SKILL.md reference text to route restart requests to the merged recovery skill.
    status: completed
  - id: verify-doc-and-command-paths
    content: Validate updated trigger wording and referenced helper command paths are correct.
    status: completed
isProject: false
---

# Make Restart The Primary Trigger

## Goal

Update the merged `isaacgym-ssh-recovery` skill so restart requests are first-class triggers while preserving recovery behavior.

## Changes

- Update `[/Users/HanHu/.cursor/skills/isaacgym-ssh-recovery/SKILL.md](/Users/HanHu/.cursor/skills/isaacgym-ssh-recovery/SKILL.md)`:
  - Rewrite frontmatter `description` to explicitly include restart intent (not just SSH failure).
  - Expand `## When to use` with direct phrases such as:
    - restart isaacgym container
    - restart Isaac Gym
    - bring isaacgym back up
    - reboot isaacgym container
  - Clarify that restart + SSH revalidation are intentionally merged into one workflow.
- Keep script behavior merged (no split into a new skill):
  - `[/Users/HanHu/.cursor/skills/isaacgym-ssh-recovery/scripts/ensure-isaacgym-ssh.sh](/Users/HanHu/.cursor/skills/isaacgym-ssh-recovery/scripts/ensure-isaacgym-ssh.sh)`
  - `[/Users/HanHu/.cursor/skills/isaacgym-ssh-recovery/scripts/recover-isaacgym-ssh.sh](/Users/HanHu/.cursor/skills/isaacgym-ssh-recovery/scripts/recover-isaacgym-ssh.sh)`
- Add a brief note in `[/Users/HanHu/.cursor/skills/motion-rl-isaacgym-exec/SKILL.md](/Users/HanHu/.cursor/skills/motion-rl-isaacgym-exec/SKILL.md)` that restart requests should use the recovery skill entrypoint.

## Verification

- Confirm `SKILL.md` wording now prioritizes restart intent in both frontmatter and trigger bullets.
- Smoke check that helper command documented in skill remains valid:
  - `bash ~/.cursor/skills/isaacgym-ssh-recovery/scripts/recover-isaacgym-ssh.sh`
- Validate no conflicting trigger language remains in Motion RL skill docs.


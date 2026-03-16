---
name: deploy fuyao branch sync
overview: Extend `/deploy-fuyao` with a pre-deploy branch sync/push safeguard outside remote kernel, enforce `/motion_rl` workdir handling, and add interactive default/custom label logic derived from branch name.
todos:
  - id: add-branch-sync-stage
    content: Add pre-deploy branch selection, upstream tracking, and non-remote-kernel dirty-tree commit/push/merge safeguard flow.
    status: completed
  - id: enforce-motion-rl-workdir
    content: Add `/motion_rl` verification for direct mode and explicit `cd /root/motion_rl &&` for SSH deploy execution.
    status: completed
  - id: add-label-interaction
    content: Add default label derivation from branch (`strip huh8/`) plus custom-label confirmation prompts and override behavior.
    status: completed
  - id: preserve-existing-deploy-rules
    content: Retain fixed deploy defaults and auth retry flow; update reporting fields to include branch/workdir/final-label.
    status: completed
isProject: false
---

# Update `/deploy-fuyao` With Branch Sync + Label Workflow

## Scope

Update the command definition in `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)` to add:

- pre-deploy branch sync behavior outside remote kernel
- `/motion_rl` directory enforcement
- default label derivation from branch name (`strip huh8/`)
- interactive custom-label confirmation flow

## Planned behavior changes

1. **Add branch input + preflight prompts**

- Require/collect branch name for the run.
- If branch is under-specified, ask user to clarify before any git/deploy commands.

1. **Outside-remote-kernel branch safeguard flow**

- Treat current local branch (or specified branch) on non-remote-kernel machine as source branch for sync/push.
- Set local branch to track corresponding upstream on `origin`.
- If working tree is dirty, run standard safety flow before deploy:
  - commit local changes (normal commit flow)
  - push branch to `origin`
  - merge/sync against upstream `origin/<branch>` as safeguard
- Keep this as a pre-deploy gate before `fuyao deploy` routing.

1. **Remote-kernel behavior**

- Keep existing direct-vs-SSH deploy routing logic.
- In direct mode, no local-machine push/merge safeguard is required.

1. **Project directory enforcement (`/motion_rl`)**

- Add explicit verification that deploy runs under `/motion_rl` project path.
- Direct mode: validate current path is under `/motion_rl`; otherwise fail with corrective message.
- SSH mode: execute with explicit remote workdir (`cd /root/motion_rl && fuyao deploy ...`).

1. **Default label derivation from branch**

- Default label is derived from branch name by stripping prefix `huh8/`.
  - Example: `huh8/r01` -> default label `r01`.
- If user explicitly passes `label`, that overrides derived default.

1. **Interactive label confirmation before push/deploy**

- Before pushing, ask user whether to use a custom label.
- If yes, ask whether to use a non-default label and show the computed default label.
- If user confirms non-default label, prompt for custom label value.
- Otherwise keep derived default label.

1. **Preserve existing deploy invariants**

- Keep all fixed `fuyao deploy` defaults unchanged unless user explicitly overrides.
- Preserve auth-retry logic (`fuyao login` then retry) by execution path.
- Extend post-submit output to include execution path, workdir, branch used, and final label used.

## Validation checklist

- Command spec includes explicit branch-sync gate outside remote kernel.
- `/motion_rl` enforcement appears in both direct and SSH paths.
- Label flow includes derived-default + optional user-defined override prompts.
- Prefix stripping rule is exactly `huh8/`.
- Existing deploy defaults and retry semantics remain intact.


---
name: Normalize Fuyao Experiment
overview: Set the deploy command experiment value to `huh8/r01` consistently and document exactly how `/deploy-fuyao` executes on different machine contexts.
todos:
  - id: normalize-experiment-value
    content: Update deploy-fuyao command text to use lowercase `huh8/r01` consistently.
    status: pending
  - id: preserve-command-semantics
    content: Ensure no routing/flag behavior changes beyond experiment value normalization.
    status: pending
  - id: verify-active-definitions
    content: Confirm only active command definitions were updated (exclude transcripts/log artifacts).
    status: pending
  - id: document-machine-behavior
    content: Report current execution behavior for local, huh.desktop.us, isaacgym, and Huh8.remote_kernel.fuyao.
    status: pending
isProject: false
---

# Normalize `deploy-fuyao` Experiment And Execution Behavior

## Target Value

Use this exact experiment value everywhere in command defaults/examples:

- `huh8/r01`

## Files To Update

- Primary Cursor command definition: `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)`
- Optional consistency touchpoint (if any duplicated command text exists in synced command docs/rules): scan and align only active command definitions, not transcripts/log snapshots.

## Planned Changes

- Replace any non-lowercase or variant experiment examples/defaults with `huh8/r01` in `/deploy-fuyao` command content.
- Keep the command structure unchanged (remote-kernel flags, queue/site/image defaults, task/run handling), only normalize experiment value.
- Add/clarify one explicit note in command docs:
  - “Experiment must be lowercase and currently defaults/examples use `huh8/r01`.”

## Current `deploy-fuyao` Execution Behavior (As-Is)

From the command definition in `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)`:

- **Routing decision**
  - If current host FQDN equals target remote-kernel FQDN, run deploy directly.
  - Otherwise route through SSH: `ssh Huh8.remote_kernel.fuyao "cd /root/motion_rl && fuyao deploy ..."`.
- **Per-machine behavior**
  - `Huh8.remote_kernel.fuyao` target context: direct execution in current shell, with `/motion_rl` path policy.
  - `local` machine: non-target context, so SSH routing to `Huh8.remote_kernel.fuyao`.
  - `huh.desktop.us`: non-target context, so SSH routing to `Huh8.remote_kernel.fuyao`.
  - `isaacgym`: non-target context, so SSH routing to `Huh8.remote_kernel.fuyao`.
- **Workdir policy**
  - Direct mode requires current `pwd` under `/motion_rl`.
  - SSH mode always executes from `/root/motion_rl` on remote-kernel host.
- **Non-remote-kernel safeguard**
  - For non-target contexts, command workflow includes branch sync/push safeguards before deploy.

## Validation Plan

- Verify `/deploy-fuyao` doc now shows `--experiment=huh8/r01` in required input examples and baseline command template.
- Confirm no active command definitions still advertise other experiment variants.
- Provide a concise “machine behavior matrix” summary in final output after edits.

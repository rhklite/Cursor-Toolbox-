---
name: Deploy Fuyao Script Workflow
overview: Build a single Cursor-managed shell script that SSHes to remote kernel, strictly syncs remote branch to origin/<branch>, and submits Fuyao deploy with validated arguments and consistent defaults.
todos:
  - id: add-wrapper
    content: Create `~/.cursor/scripts/deploy_fuyao.sh` with strict arg parsing, SSH entry, branch sync, and deploy execution.
    status: pending
  - id: interactive-commit-gate
    content: Implement local dirty-worktree interactive commit prompt before push.
    status: pending
  - id: strict-remote-sync
    content: Implement remote `fetch + checkout + reset --hard origin/<branch>` and SHA verification.
    status: pending
  - id: wire-command
    content: Update `~/.cursor/commands/deploy-fuyao.md` to call the canonical wrapper script.
    status: pending
  - id: validate-flow
    content: Run help/dry-run/smoke checks for parsing, sync contract, and composed deploy command.
    status: pending
  - id: sync-toolbox
    content: Run local toolbox sync workflow and report destinations + outcome.
    status: completed
isProject: false
---

# Build Deterministic `deploy_fuyao` Script

## Target Outcome

Create one canonical script (in Cursor command/script location) that enforces this sequence every run:

1. SSH to remote kernel
2. Sync remote branch to `origin/<branch>` with strict reset
3. Submit Fuyao deploy with validated inputs and stable defaults

## Behavior Contract

- **Remote entry:** always connect through configured SSH alias and run under canonical remote repo root (e.g. `/root/motion_rl`).
- **Branch synchronization:**
  - required input: `--branch <name>`
  - local side: if working tree is dirty, run interactive commit prompt flow; continue only after user confirms commit or clean state exists
  - local side: push branch to origin
  - remote side: `git fetch origin`, checkout branch, then hard align to `origin/<branch>` (`strict_reset`)
  - print and verify remote SHA after sync
- **Deploy composition:**
  - required input: `--task`
  - optional input: `--label` (default policy preserved)
  - keep current known deploy defaults (image/site/queue/gpu flags/etc.) in one place
  - allow explicit overrides via passthrough args
  - echo final deploy command and submit via `fuyao deploy ...`
  - print job receipt + follow-up commands

## Files to Change

- Add canonical wrapper script at `[/home/huh/.cursor/scripts/deploy_fuyao.sh](/home/huh/.cursor/scripts/deploy_fuyao.sh)`
- Update command entry at `[/home/huh/.cursor/commands/deploy-fuyao.md](/home/huh/.cursor/commands/deploy-fuyao.md)` to invoke the wrapper script as single path

## Verification

- Run wrapper `--help` and a dry-run mode to verify argument parsing and composed command.
- Verify sync logic path:
  - dirty local tree triggers interactive commit gate
  - clean tree pushes branch
  - remote branch is reset to `origin/<branch>` and SHA is printed
- Validate deploy invocation includes expected defaults + your explicit overrides.

## Safety/Failure Handling

- Fail fast on missing required args, SSH failure, git push failure, or remote sync mismatch.
- If interactive commit is declined, stop before deploy.
- Never continue to deploy when branch sync step fails.

## Post-change housekeeping

- Because this edits Cursor toolbox files (`~/.cursor/commands`, `~/.cursor/scripts`), run local toolbox sync workflow afterward and report result.

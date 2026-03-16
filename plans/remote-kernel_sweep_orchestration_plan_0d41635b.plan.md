---
name: Remote-Kernel Sweep Orchestration Plan
overview: Revise the sweep design to run hyperparameter patching and submission on the remote kernel while preserving deploy_fuyao.sh-style structured arguments and validation.
todos:
  - id: define-orchestrator-contract
    content: Design and implement orchestrator.sh prompts, combo generation, and task-registry preflight validation
    status: completed
  - id: define-runner-contract
    content: Add deploy_fuyao.sh remote-exec mode that preserves CLI format while skipping git sync/push
    status: completed
  - id: add-registry-safety
    content: Implement remote temp-repo patch workflow, parallel cap, logging, and failure handling
    status: completed
  - id: finalize-prompt-line
    content: Add usage/help examples and final summary/rerun output for failed combinations
    status: completed
isProject: false
---

# Remote-Kernel Sweep Orchestration Plan

## Goal

Implement a sweep orchestrator that validates task registration, creates per-combo temporary remote repos, patches hard-coded hyperparameters in task files, and submits Fuyao jobs in parallel without creating many origin branches.

## Key Design Decisions

- Keep `deploy_fuyao.sh` as the structured deploy interface, but add a **remote-exec mode** that skips local push/sync steps.
- Run sweep mutation + submission on remote kernel only.
- Validate task existence from [`/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py`](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py) before launching jobs.

## Files To Change

- [`/home/huh/.cursor/scripts/orchestrator.sh`](/home/huh/.cursor/scripts/orchestrator.sh) (new)
- [`/home/huh/.cursor/scripts/deploy_fuyao.sh`](/home/huh/.cursor/scripts/deploy_fuyao.sh) (extend with remote-exec mode)

## Implementation Steps

1. Extend `deploy_fuyao.sh` with a mode (for example `--skip-git-sync true`) that:
   - skips local dirty-tree checks, local push, and remote `reset --hard origin/<branch>`
   - only performs SSH connectivity + final remote `fuyao deploy ...` command composition/execution
   - preserves existing argument schema/formatting so orchestrator can reuse it consistently
2. Create `orchestrator.sh` interactive flow to collect:
   - base deploy args (`task`, experiment/queue/resources, label prefix, dry-run, max parallelism)
   - hyperparameter sweep definitions as patch rules against hard-coded values in task file(s)
3. Add preflight validation in `orchestrator.sh`:
   - confirm provided task is registered in `humanoid-gym/humanoid/envs/__init__.py`
   - validate patch targets/rules are parseable and non-empty
4. Implement remote temp-repo workflow per combo:
   - push current branch once (single baseline)
   - on remote, create a per-combo work directory/repo copy from baseline
   - patch hyperparameters in the combo-specific task file(s)
   - call `deploy_fuyao.sh` in skip-sync mode for submission
5. Run combo submissions in bounded parallel workers:
   - one worker per combo, capped by `max_parallel`
   - per-combo logs + exit codes
   - continue-on-error mode with final failure summary
6. Print final report:
   - total combos, submitted/succeeded/failed
   - per-combo label + log path
   - exact rerun command for failed combos

## Flow

```mermaid
flowchart TD
  collectInput["Collect sweep input"] --> validateTask["Validate task in envsInit"]
  validateTask --> pushBaseline["Push baseline branch once"]
  pushBaseline --> expandGrid["Expand hyperparameter combos"]
  expandGrid --> remotePatch["Create remote temp repo and patch task file"]
  remotePatch --> submitDeploy["Call deploy_fuyao.sh skip-sync mode"]
  submitDeploy --> gatherResults["Collect statuses and logs"]
  gatherResults --> summaryOut["Final sweep summary"]
```

## Acceptance Criteria

- Orchestrator blocks if task is not found in `envs/__init__.py` registrations.
- Sweep can submit many combos without pushing one branch per combo.
- Hyperparameters are patched in remote temp repos only, leaving local repo clean.
- Deploy submission still uses `deploy_fuyao.sh` argument structure.
- Parallel execution is capped and a clear success/failure summary is produced.

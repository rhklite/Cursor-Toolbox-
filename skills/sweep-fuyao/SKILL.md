---
name: sweep-fuyao
description: Deterministic dispatch and verification of Fuyao hyperparameter sweeps.
---

# Sweep Fuyao (Canonical Skill)

Use this as the canonical execution contract for `/sweep-fuyao`.

## Core Reliability Rules

- Ask for required inputs before any action.
- Do not dispatch without explicit `task` + `branch` + at least one `hp_specs`.
- Never dispatch without explicit user confirmation.
- Prefer explicit, reproducible shell commands over inference.
- Use this skill as the single source of truth for prompt order, defaults, and dispatch path.

## Required Inputs

- `task` (registered task name)
- `branch` (git branch to sync to remote kernel repo before sweep)
- `hp_specs` (at least one `param=value1,value2`)

## Optional Inputs (defaults)

- `patch_file_rel` (default: `humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py`)
- `experiment` (default: `huh8/r01`)
- `ssh_alias` (default: `remote.kernel.fuyo`)
- `queue` (default: `rc-wbc-4090-share`)
- `project` (default: `rc-wbc`)
- `site` (default: `fuyao_sh_n2`)
- `gpus_per_node` (default: `1`)
- `gpu_type` (default: `shared`)
- `priority` (default: `normal`)
- `max_parallel` (default: `4`)
- `label_prefix` (default: `sweep`)
- `continue_on_error` (default: `true`)
- `dry_run` (default: `false`)
- `hp_class_map` (default: empty)

## Argument Prompt Contract (Selectable Questions)

Collect required inputs and optional overrides with selectable prompts.

Precedence order:

1. explicit values provided by user in invocation/message
2. answers from selectable questions
3. documented defaults/derivation

Prompt order when multiple required inputs are missing:

1. `branch`
2. `task`
3. `hp_specs`

### `branch` prompt contract

- Build branch candidates from local `git branch --format='%(refname:short)'`.
- If available branches are more than 12, show the current branch first (if present), then alphabetical, trimmed.
- Present a single-select list with `Enter custom branch`.
- If custom branch is chosen, ask one follow-up free-form question and require non-empty value.

### `task` prompt contract

- Follow matching/validation workflow from **Task Validation (Mandatory + Fuzzy Match)**.
- If exact/case-insensitive matching does not resolve one concrete task:
  - present a selectable choice list and an `Enter custom task` option.
  - require explicit user selection before dispatch.

### `hp_specs` prompt contract

- Ask repeatedly for `param=value1,value2` entries.
- Present a single-select question each turn with defaults:
  1. `learning_rate=1e-4,2e-4,3e-4`
  2. `entropy_coef=0.01,0.005`
  3. `gamma=0.99,0.995`
  4. `Enter custom spec`
- On custom, ask one follow-up free-form question for `param=value1,value2`.
- Reject malformed specs and re-prompt that step.
- Continue prompting until at least one valid spec is confirmed and user chooses to stop adding more.

## Deterministic Workflow

1. Resolve `branch`, `task`, and `hp_specs` through the prompt contract above.
2. Resolve optional overrides only when explicitly requested.
3. Validate resolved task through `humanoid-gym/humanoid/envs/__init__.py` using exact/case-insensitive/substring matching.
4. Build payload at `~/.cursor/tmp/sweep_payloads/<timestamp>.json`.
5. Build and show sweep preview (combo count, combo list, resource estimate).
6. Ask for explicit confirmation. Do not dispatch on cancel/unclear confirmation.
7. On confirmation, set payload field `confirm_dispatch: true`.
8. Execute:

```bash
bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --payload <payload_file>
```

9. Report `run_root`.
10. Run one of:

```bash
bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --once
```

## Post-Submit Report

- selected/derived payload fields
- `run_root`
- dispatch status
- next checks:
  - `fuyao log <job_name>`
  - `bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --poll-interval 30 --max-attempts 10`

## Manual fallback behavior

- If branch discovery fails, ask for custom branch input.
- Never execute dispatch unless all required fields are resolved and user has confirmed.
- Keep `hp_spec` terminology aligned to `hp_specs` payload key (`param=value1,value2`).

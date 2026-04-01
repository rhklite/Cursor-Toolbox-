# Fuyao Hyperparameter Sweep (User Command)

Deploy and dispatch parallel hyperparameter sweep jobs on Fuyao.
Invoke as `/sweep-fuyao`.

## Required Inputs

Collect these values before execution:

- `branch` (git branch to sync to remote kernel repo before sweep dispatch)
- `task` (must be a registered task name)
- `hp_specs` (at least one `param=value1,value2` entry)

Optional:

- `patch_file_rel` (default: `humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py`)
- `experiment` (default: `default/experiment`)
- `ssh_alias` (default: `CLUSTER_SSH_ALIAS`)
- `queue` (default: `rc-wbc-4090`)
- `project` (default: `rc-wbc`)
- `site` (default: `fuyao_sh_n2`)
- `gpus_per_node` (default: `1`)
- `priority` (default: `normal`)
- `max_parallel` (default: `4`)
- `label_prefix` (default: `sweep`)
- `continue_on_error` (default: `true`)
- `dry_run` (default: `false`)
- `hp_class_map` (optional JSON map)

## Argument Prompt Contract (Selectable Questions)

Collect inputs with selectable questions before any script or dispatch action.
For required inputs, ask if missing.

Precedence order:

1. explicit values provided by user in invocation/message
2. answers from selectable questions
3. documented defaults/derivation

Prompt order when multiple required inputs are missing:

1. `branch`
2. `task`
3. `hp_specs`

### `branch` prompt contract

- Source branch candidates from:
  - `git branch --format='%(refname:short)'`
- If more than 12 branches are available:
  - show current branch first (if present), then alphabetical, trimmed to 12
- Present a single-select question with:
  - candidate branches
  - `Enter custom branch`
- If user selects custom, ask one follow-up free-form question for the branch name.

### `task` prompt contract

- Follow matching/validation workflow from **Task Validation (Mandatory + Fuzzy Match)**.
- If exact/case-insensitive matching does not resolve one concrete task:
  - present single-select choices of best task candidates
  - include `Enter custom task`
  - require explicit user selection before sweep dispatch

### `hp_specs` prompt contract (required)

- Ask repeatedly for `param=value1,value2` entries.
- Present a single-select question each turn with defaults:
  1. `learning_rate=1e-4,2e-4,3e-4`
  2. `entropy_coef=0.01,0.005`
  3. `gamma=0.99,0.995`
  4. `Enter custom spec`
- On custom, ask one follow-up free-form question for `param=value1,value2`.
- Reject malformed specs and re-prompt that step.
- Continue prompting until at least one valid spec is confirmed and user chooses to stop adding more.

### Optional input prompt behavior

- Resolve optional overrides only when explicitly requested by the user.

## Baseline Command Pattern

Always execute sweep dispatch through:

```bash
bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --payload <payload_file>
```

Do not execute direct helper commands for sweep without this dispatcher.

## Task Validation (Mandatory + Fuzzy Match)

`task` is mandatory and must be validated against registered tasks.

- Preferred source: `humanoid-gym/humanoid/envs/__init__.py`
- Parse names from `task_registry.register("...")`
- Matching workflow:
  1. exact match
  2. case-insensitive exact match
  3. substring / close matches
  4. if ambiguous, present choices and require explicit selection
- Do not dispatch until task is resolved to one concrete registered value.

## Defaults

Use these defaults unless user explicitly overrides:

- `patch_file_rel=humanoid-gym/humanoid/envs/r01_amp/r01_v12_sa_amp_config_with_arms_and_head_full_scenes.py`
- `experiment=default/experiment`
- `ssh_alias=CLUSTER_SSH_ALIAS`
- `queue=rc-wbc-4090`
- `project=rc-wbc`
- `site=fuyao_sh_n2`
- `gpus_per_node=1`
- `priority=normal`
- `max_parallel=4`
- `label_prefix=sweep`
- `continue_on_error=true`
- `dry_run=false`
- `hp_class_map=<empty>`
- fixed defaults:
  - `nodes=1`
  - `local_root=<auto-detected git root>`
  - `envs_init_rel=humanoid-gym/humanoid/envs/__init__.py`
  - `remote_root=/root/project_repo`
  - `remote_sweep_root=/tmp/fuyao_sweeps`
  - `run_root_base=~/.cursor/tmp/deploy_fuyao_sweep_runs`
  - `docker_image=infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347`
  - `rl_device=cuda:0`

### Label alias map helpers (optional)

- `bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --print-label-map` shows the deterministic short-name mapping used for sweep labels.
- `bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --print-label-map-json` shows the same mapping in JSON.
- `bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --check-label-aliases` runs a deterministic alias regression demo.

## Execution Workflow

1. Resolve `branch`, `task`, and at least one `hp_specs` entry via **Argument Prompt Contract (Selectable Questions)**.
2. If user chooses to customize, resolve optional fields in the same selectable style.
3. Validate `task` from humanoid registry and resolve ambiguity if needed.
4. Build payload to `~/.cursor/tmp/sweep_payloads/<timestamp>.json`.
5. Build and show sweep preview (combo count, combo list, resource estimate).
6. Ask explicit confirmation to proceed.
7. On confirmation, set payload field `confirm_dispatch: true`.
8. Execute:

```bash
bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --payload <payload_file>
```

9. Report output `run_root` to the user.
10. Run verification:

```bash
bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --once
```

If jobs are still pending:

```bash
bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --poll-interval 30 --max-attempts 10
```

11. If user asks to cancel, dispatcher does not expose `--cancel-sweep`; gather job names from `<run_root>/logs/*.dispatch.log` and cancel with `fuyao cancel <job_name>`.

## Post-Submit Output

Report:

- selected/derived `task`, `branch`
- selected `hp_specs`
- whether dry-run or live dispatch
- `run_root` path
- dispatch status (success/failed)
- preview and optional next commands: `verify_fuyao_jobs.sh` and `fuyao log <job_name>`

Notes:

- Generated sweep labels now use readable short parameter aliases from the map (for example, `learning_rate` becomes `lr`), while full hyperparameter specs remain in payload metadata for auditability.

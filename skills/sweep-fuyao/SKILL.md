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
- `queue` (default: `rc-wbc-4090`)
- `project` (default: `rc-wbc`)
- `site` (default: `fuyao_sh_n2`)
- `gpus_per_node` (default: `1`)
- `priority` (default: `normal`)
- `max_parallel` (default: `4`)
- `label_prefix` (default: `auto` — auto-derived from task name, user-confirmed via prompt contract below)
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
4. `label_prefix`

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

### `label_prefix` prompt contract

- After `task` is resolved, auto-derive a suggested label by: splitting the task name on `_`, dropping noise words (`with`, `and`, `full`, `scenes`, `the`, `for`, `plus`, `a`, `an`), joining the first 5 remaining segments with `-`, and truncating to 24 characters.
  Example: `r01_v12_sa_amp_with_4dof_arms_and_head_full_scenes` produces `r01-v12-sa-amp-4dof`.
- Present a single-select prompt with:
  1. The auto-derived label as the first option.
  2. `Enter custom label`.
- If custom is chosen, ask one follow-up free-form question and require a non-empty value.
- If the user already provided `label_prefix` explicitly in the invocation, skip this prompt.

## Deterministic Workflow

1. Pre-flight: verify SSH alias exists:
   - Run `ssh -G <ssh_alias> >/dev/null 2>&1` (default: `remote.kernel.fuyo`)
   - If it fails, stop and tell the user: "SSH alias `<ssh_alias>` is not configured in `~/.ssh/config`. Add it before sweeping."
2. Resolve `branch`, `task`, and `hp_specs` through the prompt contract above.
3. Resolve optional overrides only when explicitly requested.
4. Validate resolved task through `humanoid-gym/humanoid/envs/__init__.py` using exact/case-insensitive/substring matching.
5. Build payload at `~/.cursor/tmp/sweep_payloads/<timestamp>.json`.
6. Build and show sweep preview (combo count, combo list, resource estimate).
7. Ask for explicit confirmation. Do not dispatch on cancel/unclear confirmation.
8. On confirmation, set payload field `confirm_dispatch: true`.
9. Execute:

```bash
bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --payload <payload_file>
```

10. Report `run_root`.
11. Verify training actually started (mandatory, not skippable):

```bash
bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --check-artifacts --poll-interval 60 --max-attempts 15
```

The skill must NOT report sweep success unless at least `TRAINING` verdict is reached for all jobs.
If any job stays in `SETUP`/`PENDING`/`WAITING` after polling completes, report a warning with
`fuyao log` commands for each unconfirmed job.

## Experiment Tracker Integration (Post-Sweep)

Run this step **after a successful sweep dispatch** (Step 8 completed without errors and `run_root` was reported). Tracker failures must not cause the agent to report the sweep as failed, abort remaining steps, or omit the Post-Submit Report. Always continue to the Post-Submit Report regardless of tracker outcome.

**If `dry_run` is `true`**, still record to the tracker but set `"dry_run": true` in the payload. The script will create mutations with status `"planned"` instead of `"running"`.

1. **Collect per-combo data** from the run_root directory. For each combo:
   - Read `<run_root>/status/<combo_name>.json` to get `job_name`, `combo_label`, and `status`.
   - If the status file is missing, read `<run_root>/artifacts/<combo_name>/dispatch_receipt.json` as fallback.
   - If no structured data is available, parse `<run_root>/logs/<combo_name>.dispatch.log` for `job_name=<value>` lines and `bifrost-\d{16,}-[A-Za-z0-9_-]+` patterns (use the **last** match).
   - If no data source exists for a combo, include it with `job_name: ""` and emit a warning listing the combos with missing data.
   - For combos that **failed at dispatch** (status file shows failure, or dispatch_receipt has `"submitted": false`), set `"dispatched": false` in the combo object. The tracker will record these as `"failed"` instead of `"running"`.

2. **Compute delta for each combo.** Each combo represents a specific HP configuration. Parse the hp_specs and the combo's parameter values to build a `delta` dict mapping `param_name` to the specific value used for that combo (e.g., `{"train.learning_rate": 0.001, "train.entropy_coef": 0.005}`).

3. **Build the tracker payload** as a JSON object. All string values must be valid JSON (escape `"`, `\`, and control characters):

```json
{
  "task": "<resolved registered task name>",
  "branch": "<branch>",
  "project": "<project>",
  "queue": "<queue>",
  "experiment": "<experiment>",
  "sweep_id": "<sweep_id from dispatcher output>",
  "run_root": "<run_root>",
  "label_prefix": "<label_prefix>",
  "hp_specs_summary": "<original hp_specs as a human-readable string>",
  "dry_run": false,
  "parent_mutation_id": "",
  "combos": [
    {
      "combo_name": "combo_0001",
      "job_name": "bifrost-...",
      "delta": {"train.learning_rate": 0.001},
      "combo_label": "r01-v12-sa-amp-4dof-0001-lr_1e3",
      "command": "<training command for this combo>",
      "dispatched": true
    },
    {
      "combo_name": "combo_0002",
      "job_name": "",
      "delta": {"train.learning_rate": 0.003},
      "combo_label": "r01-v12-sa-amp-4dof-0002-lr_3e3",
      "command": "",
      "dispatched": false
    }
  ]
}
```

4. **Write the payload** to `~/.cursor/tmp/tracker_sweep_<timestamp>.json` using the Write tool, then run:

```bash
python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py record-sweep --store-root ~/.exp-tracker --json-file ~/.cursor/tmp/tracker_sweep_<timestamp>.json
```

Field notes:
- `parent_mutation_id` — optional. If empty, auto-resolved to the latest mutation on the same task + branch. Set explicitly to link the sweep to a specific parent deploy or combo.

5. **Check the result.** Run the command without `|| true`. After execution, check the exit code. If non-zero or the output contains `"ok": false`, capture the error, emit a warning "Tracker recording failed: <error>. Sweep dispatch itself succeeded.", and proceed to the Post-Submit Report. On success, extract `task_id`, `sweep_id`, and per-combo `mutation_id`s. Combos with `"skipped": true` were already recorded (idempotent retry) and should be noted, not treated as errors.

6. **Do NOT prompt the user or wait for confirmation** for the tracker step. This is fully automatic.

### Idempotency & Deduplication

- The `record-sweep` command checks for existing mutations matching `sweep_id + combo_name` in metadata. Duplicate combos are skipped, making retries safe.
- If the agent crashes mid-recording and is re-invoked, only unrecorded combos are created.
- Always pass the same `sweep_id` from the dispatcher output when re-running.

### Store Root

- Always pass `--store-root ~/.exp-tracker` (or the configured store root) to ensure recordings land in the same store as the dashboard.
- If omitted, the CLI defaults to `~/.local/share/motion-rl-tracker`.

### Tracker Error Handling

- If the CLI exits non-zero or returns `"ok": false`, display a warning and continue.
- Individual combo failures should be listed as warnings but do not block the report.
- If the CLI script is missing or Python is unavailable, skip and warn.
- Never retry automatically — the user can re-record manually via the policy-lineage-tracker skill.

## Job Registry Integration (Post-Sweep)

After a successful sweep dispatch, register all successfully dispatched combos in the local job registry. For each combo with a valid `job_name`:

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py registry --add <job_name> \
  --sweep-id "<sweep_id>" \
  --label "<combo_label>" \
  --task "<task>" \
  --queue "<queue>" \
  --gpus "<gpus_per_node>"
```

This step is non-blocking. If it fails for any combo, warn and continue. Do NOT skip the Post-Submit Report.

After all registry writes, push to huh.desktop.us:

```bash
scp ~/.cursor/tmp/fuyao_job_registry.json huh.desktop.us:~/.cursor/tmp/fuyao_job_registry.json
```

If the push fails (SSH unreachable), warn and continue.

## Post-Submit Report

- selected/derived payload fields
- `run_root`
- dispatch status
- **tracker:** `task_id`, per-combo `mutation_id`s (if tracker recording succeeded), or "tracker recording skipped/failed"
- **registry:** N jobs registered / skipped / failed
- next checks:
  - `fuyao log <job_name>`
  - `bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --check-artifacts --poll-interval 60 --max-attempts 15`
- if tracker succeeded: "To update all combo statuses when sweep completes: `python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py update-sweep-status --sweep-id <sweep_id> --status completed`"
- if tracker succeeded: "To update a single combo: `python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py set-status --node-id <mutation_id> --status completed`"
- if tracker succeeded: "To link artifacts for each combo after evaluation: `python3 ~/software/Experiment-Tracker-/tracker_cli.py link-job-artifacts --store-root ~/.exp-tracker --job-name <job_name>` (run once per combo job_name). Or use the dashboard Sweep Artifacts panel on the parent node to batch-download all combo artifacts."

## Manual fallback behavior

- If branch discovery fails, ask for custom branch input.
- Never execute dispatch unless all required fields are resolved and user has confirmed.
- Keep `hp_spec` terminology aligned to `hp_specs` payload key (`param=value1,value2`).

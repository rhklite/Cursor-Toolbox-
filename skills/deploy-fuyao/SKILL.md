---
name: deploy-fuyao
description: Deterministic Fuyao deployment flow with strict validation, branch sync, and confirmation.
---

# Deploy Fuyao (Canonical Skill)

Use this as the canonical execution contract for `/deploy-fuyao`.
This skill should be treated as mandatory instruction; only fallback is manual mode.

## Core Reliability Rules

- Ask for missing required inputs before any action.
- Never execute a deploy if `task` is unresolved.
- Never execute a deploy without explicit user confirmation.
- Prefer explicit, reproducible shell commands over inference.
- Use this skill as the single source of truth for `branch`, `task`, and defaults.

## Required Inputs

- `branch` (git branch to sync to remote kernel)
- `task` (registered task name)
- `experiment` (default: `huh8/r01`)

## Optional Inputs (defaults)

- `label` (default: remove one leading `huh8/` from `branch`)
- `project` (default: `rc-wbc`)
- `queue` (default: `rc-wbc-4090`; always use fully-qualified name, never bare aliases like `4090`)
- `yes` flag (default: `--yes`)

## Deterministic Workflow

1. Resolve `branch`, `task`, and `experiment` first.
2. Resolve `label`:
   - if user provided `label`, use it.
   - otherwise derive `label` from `branch` by stripping one leading `huh8/`.
3. Validate `task` against `humanoid-gym/humanoid/envs/__init__.py` using registered values from `task_registry.register("...")`.
4. Validate `task` in this order:
   - exact match
   - case-insensitive exact match
   - close/substring matches
   - if ambiguous, present choices and require explicit selection
5. Ensure local branch state:
   - checkout selected local branch
   - run `git status --porcelain` to check for uncommitted changes in `humanoid-gym/`
   - if uncommitted changes exist in training code, **stop and warn the user**. Do NOT proceed with deploy until the user commits or discards them. Deploying with uncommitted changes means the remote will not match the local working directory.
   - set upstream `origin/<branch>` if needed
   - `git push` that branch to origin
6. Pre-flight: verify SSH alias exists:
   - Run `ssh -G Huh8.remote_kernel.fuyao >/dev/null 2>&1`
   - If it fails, stop and tell the user: "SSH alias `Huh8.remote_kernel.fuyao` is not configured in `~/.ssh/config`. Add it before deploying."
7. Ensure remote kernel SSH target:
   - Use `Huh8.remote_kernel.fuyao`
   - `cd /root/motion_rl`
   - `git fetch origin`
   - checkout `<branch>` or create from `origin/<branch>`
   - `git reset --hard origin/<branch>`
8. Ask for explicit confirmation to submit before running SSH deploy command.
9. Execute exactly:

```bash
SSH_ALIAS="Huh8.remote_kernel.fuyao"
ssh "${SSH_ALIAS}" 'set -euo pipefail; cd /root/motion_rl; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project <project> --label <label> --task <task> --experiment <experiment> --queue <queue> --yes'
```

For multi-GPU distributed training, append `--distributed --nproc_per_node <N>`:

```bash
ssh "${SSH_ALIAS}" 'set -euo pipefail; cd /root/motion_rl; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project <project> --label <label> --task <task> --experiment <experiment> --queue <queue> --distributed --nproc_per_node <N> --yes'
```

**Queue safety rule**: The `--queue` value passed here MUST be the fully-qualified Fuyao queue name (e.g. `rc-wbc-4090`), never a bare alias like `4090`. Do NOT pass `--site`; the deploy script resolves site from the queue name internally. Do NOT pass `--gpu-type` or `--gpu-slice`; Fuyao infers GPU type from the queue name.

9. If command fails with auth symptoms:
   - `ssh-add -l`
   - `ssh "${SSH_ALIAS}" 'ssh-add -l'`
   - `ssh "${SSH_ALIAS}" 'ssh -T git@gitlab-adc.xiaopeng.link'`
   - Retry only after fixing auth.

## Experiment Tracker Integration (Post-Deploy)

Run this step **after a successful deploy** (Step 8 exits 0 and output does not contain `ERROR` or `FAILED`). If Step 9 triggers a retry, run the tracker after the successful retry, not after the initial failure. Tracker failures must not cause the agent to report the deployment as failed, abort remaining steps, or omit the Post-Submit Report. Always continue to the Post-Submit Report regardless of tracker outcome.

1. **Extract `job_name`** from the deploy command's stdout/stderr output. Search for all matches of `bifrost-\d{16,}-[A-Za-z0-9_-]+` and use the **last** match. If no match is found, set `job_name` to `""` and emit a warning: "Could not extract job_name from deploy output."

2. **Build the tracker payload** as a JSON object and write it to a temp file using the Write tool. All string values must be valid JSON (escape `"`, `\`, and control characters). Use the **resolved** SSH alias (after fallback), not the shell template:

```json
{
  "task": "<resolved registered task name>",
  "branch": "<branch>",
  "label": "<label>",
  "project": "<project>",
  "queue": "<queue>",
  "site": "<site if known, else empty>",
  "experiment": "<experiment>",
  "command": "ssh Huh8.remote_kernel.fuyao 'set -euo pipefail; cd /root/motion_rl; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project rc-wbc --label dev_r01_v12 --task HuhR01V12SAAmpV0 --experiment huh8/r01 --queue rc-wbc-4090 --yes'",
  "job_name": "<extracted job_name or empty string>",
  "parent_mutation_id": "",
  "delta": {}
}
```

*(The command field above is an example — substitute actual resolved values.)*

Field notes:
- `parent_mutation_id` — optional. If empty, auto-resolved to the latest mutation on the same task + branch. Set explicitly to link to a specific parent (e.g. a sweep combo that produced the best result).
- `delta` — optional. Include if the user mentioned specific HP or config changes for this deploy (e.g. `{"train.learning_rate": 0.003}`). Leave `{}` if unknown.

3. **Write the payload** to `~/.cursor/tmp/tracker_deploy_<timestamp>.json` using the Write tool, then run:

```bash
python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py record-deploy --store-root ~/.exp-tracker --json-file ~/.cursor/tmp/tracker_deploy_<timestamp>.json
```

4. **Check the result.** Run the command without `|| true`. After execution, check the exit code. If non-zero or the output contains `"ok": false`, capture the error, emit a warning "Tracker recording failed: <error>. Deployment itself succeeded.", and proceed to the Post-Submit Report. On success (`"ok": true`), extract `task_id` and `mutation_id` for the Post-Submit Report. If the output contains `"skipped": true`, the deploy was already recorded (idempotent retry) — note this, don't treat it as an error.

5. **Do NOT prompt the user or wait for confirmation** for the tracker step. This is fully automatic.

### Lineage (Parent-Child Chain)

Each recorded deploy becomes a mutation node linked to its parent via `derives_from` edges:

- **Auto-resolution** (default): the tracker finds the most recent mutation on the same `task + branch` and links to it. This creates a linear chain: deploy_1 -> deploy_2 -> deploy_3.
- **After a sweep**: the auto-resolved parent may point to any sweep combo (they share a timestamp). To link to a specific combo, set `parent_mutation_id` explicitly.
- **Cross-skill lineage**: deploys from `/deploy-fuyao` and sweeps from `/sweep-fuyao` on the same branch automatically form a connected lineage graph.
- **First deploy on a branch**: if no previous mutation exists for this task + branch, the deploy becomes a root mutation under the task (no parent).

### Idempotency

If `job_name` is non-empty and a mutation with the same `job_name` already exists in metadata, the deploy is skipped and the existing `mutation_id` is returned. Safe to retry.

### Tracker Error Handling

- If the CLI exits non-zero or returns `"ok": false`, display a warning and continue.
- If the script is missing or Python is unavailable, skip and warn.
- Never retry the tracker call automatically — the user can re-record manually via the policy-lineage-tracker skill.

## Job Registry Integration (Post-Deploy)

After a successful deploy, register the job in the local registry so `fuyao-job-manager` can track and protect it:

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py registry --add <job_name> \
  --sweep-id "" \
  --label "<label>" \
  --task "<task>" \
  --queue "<queue>" \
  --gpus "<gpus_per_node>"
```

This step is non-blocking. If it fails, warn and continue to the Post-Submit Report.

## Post-Submit Report

- execution path used (`ssh->(resolved deploy alias)`)
- workdir used (`/root/motion_rl`)
- branch used
- deployment status
- returned job name/id
- `site`, `queue`, `project`, `label`
- **tracker:** `task_id`, `mutation_id` (if tracker recording succeeded), or "tracker recording skipped/failed"
- **registry:** registered / skipped / failed
- follow-up commands: `fuyao info --job-name <job_name>` and `fuyao log --job-name <job_name>`
- if tracker succeeded: "To update status when job completes: `python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py set-status --node-id <mutation_id> --status completed`"

## Manual Fallback (When Skill Resolution Is Not Available)

Use this exact command only if you cannot invoke the skill contract:

```bash
SSH_ALIAS="Huh8.remote_kernel.fuyao"
ssh "${SSH_ALIAS}" 'set -euo pipefail; cd /root/motion_rl; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project <project> --label <label> --task <task> --experiment <experiment> --queue <queue> --yes'
```

For multi-GPU manual fallback, append: `--distributed --nproc_per_node <N>`

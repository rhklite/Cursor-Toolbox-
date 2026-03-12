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
- `site` (default: `fuyao_sh_n2`)
- `queue` (default: `rc-wbc-4090`)
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
   - set upstream `origin/<branch>` if needed
   - `git push` that branch to origin
6. Ensure remote kernel SSH target:
   - Prefer `Huh8.remote_kernel.fuyao`, fallback to `remote.kernel.fuyo`
   - `cd /root/motion_rl`
   - `git fetch origin`
   - checkout `<branch>` or create from `origin/<branch>`
   - `git reset --hard origin/<branch>`
7. Ask for explicit confirmation to submit before running SSH deploy command.
8. Execute exactly:

```bash
SSH_ALIAS="Huh8.remote_kernel.fuyao"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_ALIAS}" "echo ok" >/dev/null 2>&1; then
  SSH_ALIAS="remote.kernel.fuyo"
fi
ssh "${SSH_ALIAS}" 'set -euo pipefail; cd /root/motion_rl; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project <project> --label <label> --task <task> --experiment <experiment> --site <site> --queue <queue> --yes'
```

9. If command fails with auth symptoms:
   - `ssh-add -l`
   - `ssh "${SSH_ALIAS}" 'ssh-add -l'`
   - `ssh "${SSH_ALIAS}" 'ssh -T git@gitlab-adc.xiaopeng.link'`
   - Retry only after fixing auth.

## Post-Submit Report

- execution path used (`ssh->(resolved deploy alias)`)
- workdir used (`/root/motion_rl`)
- branch used
- deployment status
- returned job name/id
- `site`, `queue`, `project`, `label`
- follow-up commands: `fuyao info --job-name <job_name>` and `fuyao log --job-name <job_name>`

## Manual Fallback (When Skill Resolution Is Not Available)

Use this exact command only if you cannot invoke the skill contract:

```bash
SSH_ALIAS="Huh8.remote_kernel.fuyao"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_ALIAS}" "echo ok" >/dev/null 2>&1; then
  SSH_ALIAS="remote.kernel.fuyo"
fi
ssh "${SSH_ALIAS}" 'set -euo pipefail; cd /root/motion_rl; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project <project> --label <label> --task <task> --experiment <experiment> --site <site> --queue <queue> --yes'
```

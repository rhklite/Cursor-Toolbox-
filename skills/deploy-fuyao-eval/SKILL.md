---
name: deploy-fuyao-eval
description: Deploy eval-only Fuyao jobs for existing checkpoints without any training.
---

# Deploy Fuyao Eval-Only (Canonical Skill)

Use this skill when the user wants to run evaluation from an existing checkpoint on Fuyao.
This skill never launches training.

## When to Use

Activate on requests like:
- "Run torque survey on Fuyao using this checkpoint"
- "Evaluate checkpoint on Fuyao"
- "Deploy eval-only job"
- "Test model on Fuyao without retraining"

## Hard Rules

- Never call humanoid-gym/scripts/fuyao_train.sh.
- Never call humanoid-gym/scripts/fuyao_deploy.sh for eval-only jobs.
- Always use ~/.cursor/scripts/fuyao_deploy_eval.sh.
- Require explicit confirmation before non-dry-run submission.

## Required Inputs

- task (registered task name)
- checkpoint (local path) or checkpoint_remote (remote-kernel path)

## Optional Inputs and Defaults

- eval_type: torque_survey (default), standard, custom
- custom_cmd: required only when eval_type is custom
- branch: optional remote branch sync
- project: rc-wbc
- experiment: huh8/r01
- queue: rc-wbc-4090
- site: auto from queue unless provided
- label: auto-generated if omitted
- yes: include --yes when user confirms submission
- passthrough eval args after `--`

## Deterministic Workflow

1. Resolve required inputs and optional overrides.
2. Validate task against humanoid-gym/humanoid/envs/__init__.py registration names.
3. Confirm checkpoint location mode:
   - local path: use --checkpoint
   - remote kernel path: use --checkpoint-remote
4. Build dry-run command first and show user preview.
5. Ask explicit confirmation.
6. Execute non-dry-run command after confirmation.
7. Parse output for job_name (bifrost-*).
8. Report job_name and follow-up commands.

## Command Template

```bash
bash ~/.cursor/scripts/fuyao_deploy_eval.sh \
  --task <task> \
  [--checkpoint <local_ckpt> | --checkpoint-remote <remote_ckpt>] \
  --eval-type <torque_survey|standard|custom> \
  [--custom-cmd "<cmd>"] \
  [--branch <branch>] \
  [--label <label>] \
  [--project <project>] \
  [--experiment <experiment>] \
  [--queue <queue>] \
  [--site <site>] \
  --yes \
  -- <eval_passthrough_args>
```

Dry-run preview:

```bash
bash ~/.cursor/scripts/fuyao_deploy_eval.sh <same args> --dry-run
```

## Torque Survey Example

```bash
bash ~/.cursor/scripts/fuyao_deploy_eval.sh \
  --task r01_v12_amp_with_4dof_arms_and_head_full_scenes \
  --checkpoint /Users/HanHu/.cursor/tmp/fuyao_artifacts/bifrost-2026031307552101-huh8/model_15000.pt \
  --eval-type torque_survey \
  --label pengfei-torque-rerun \
  --project rc-wbc \
  --experiment huh8/r01 \
  --queue rc-wbc-4090 \
  --yes \
  -- \
  --push_magnitudes "0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.4,0.45,0.5" \
  --push_directions "0,45,90,135,180,225,270,315" \
  --push_ang_magnitudes "" \
  --trials_per_condition 10 \
  --report_suffix pengfei_fuyao
```

## Post-Submit Report

- execution path used
- branch used (if provided)
- task and eval_type
- checkpoint source mode
- queue and site
- deployment status
- job_name
- follow-up commands:
  - ssh remote.kernel.fuyao 'fuyao info --job-name <job_name>'
  - ssh remote.kernel.fuyao 'fuyao log --job-name <job_name> --all-containers --no-interactive --tail 200'

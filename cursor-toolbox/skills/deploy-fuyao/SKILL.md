---
name: deploy-fuyao
description: Deterministic remote deployment flow for Fuyao jobs with validation, branch sync, and explicit confirmation.
---

# Deploy Fuyao

## Role

Use this skill as the canonical contract for /deploy-fuyao.

## Required inputs

- branch
- task
- experiment (default: default/experiment)

## Optional inputs

- label (default: branch suffix)
- project (default: default-project)
- queue (default: default-queue)
- ssh_alias (default: CLUSTER_SSH_ALIAS)
- remote_root (default: /root/project_repo)

## Deterministic workflow

1. Resolve branch, task, and experiment.
2. Resolve label from user input or branch suffix.
3. Validate task against humanoid-gym/humanoid/envs/__init__.py task_registry entries.
4. Ensure local branch is clean, committed, and pushed to origin.
5. Ensure SSH alias is configured: ssh -G <ssh_alias>.
6. Sync remote repo to origin/<branch> with strict reset.
7. Ask explicit confirmation before submit.
8. Execute deploy over SSH:

```bash
SSH_ALIAS="CLUSTER_SSH_ALIAS"
ssh "${SSH_ALIAS}" 'set -euo pipefail; cd /root/project_repo; bash --noprofile --norc ./humanoid-gym/scripts/fuyao_deploy.sh --project <project> --label <label> --task <task> --experiment <experiment> --queue <queue> --yes'
```

9. If auth fails, verify ssh-agent and remote git auth, then retry.

## Post-submit report

Report:
- execution path and workdir
- resolved branch, task, label, project, queue, experiment
- submission status and job_name if available
- follow-up commands: fuyao info and fuyao log

## Out of scope in shared package

- No experiment tracker recording.
- No job registry writes.

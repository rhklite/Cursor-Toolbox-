---
name: sweep-fuyao
description: Deterministic dispatch and verification flow for Fuyao hyperparameter sweeps.
---

# Sweep Fuyao

## Role

Use this skill as the canonical contract for /sweep-fuyao.

## Required inputs

- branch
- task
- hp_specs (one or more param=value1,value2 entries)

## Optional inputs

- patch_file_rel
- experiment (default: default/experiment)
- ssh_alias (default: CLUSTER_SSH_ALIAS)
- remote_root (default: /root/project_repo)
- queue, project, site, gpus_per_node, priority
- max_parallel, label_prefix, continue_on_error, dry_run

## Deterministic workflow

1. Resolve required inputs with explicit prompts.
2. Validate task against humanoid-gym/humanoid/envs/__init__.py.
3. Build payload file under ~/.cursor/tmp/sweep_payloads/.
4. Show combo preview and ask explicit confirmation.
5. Dispatch via:

```bash
bash ~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh --payload <payload_file>
```

6. Report run_root from dispatcher output.
7. Verify jobs with:

```bash
bash ~/.cursor/scripts/verify_fuyao_jobs.sh --run-root <run_root> --check-artifacts --poll-interval 60 --max-attempts 15
```

## Post-submit report

Report:
- resolved branch, task, hp_specs
- dry-run or live dispatch
- run_root
- dispatch summary (success/failed per combo)
- next verification and logging commands

## Out of scope in shared package

- No experiment tracker recording.
- No job registry writes.

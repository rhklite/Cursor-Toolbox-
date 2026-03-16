---
name: Compare Fuyao Commands
overview: Compare the sample multi-GPU Fuyao command against the repo’s default deploy command in humanoid-gym/scripts/fuyao_deploy.sh and report exact flag differences.
todos:
  - id: extract-existing
    content: Extract deploy flags from humanoid-gym/scripts/fuyao_deploy.sh
    status: completed
  - id: compare-flags
    content: Compare sample command flags against existing baseline
    status: completed
  - id: report-diff
    content: Return concise differences and implications
    status: completed
isProject: false
---

# Compare Fuyao Deploy Commands

## Baseline Used

- Existing Cursor baseline is the deploy command embedded in [humanoid-gym/scripts/fuyao_deploy.sh](/home/huh/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh):
  - `fuyao deploy --docker-image=${fuyao_image} --nodes=1 --gpus-per-node=1 --site=fuyao_sh_n2 --queue=rc-wbc-4090 --label="${label_str}" --project="${project}" ...`

## Comparison Scope

- Normalize both commands to Fuyao CLI flags only (exclude trailing train-script args).
- Group differences into:
  - Flags present only in sample
  - Flags present only in existing baseline
  - Same flags with different values

## Output

- Provide a concise, flag-by-flag diff and a short note about practical impact (resource type, queue behavior, metadata fields).

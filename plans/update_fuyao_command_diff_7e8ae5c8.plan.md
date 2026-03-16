---
name: Update Fuyao Command Diff
overview: Prepare an updated deploy command by applying only GPU sharing/slice and queue changes, then provide a side-by-side comparison with the sample command.
todos:
  - id: extract-baseline-flags
    content: Use existing script baseline as source command
    status: pending
  - id: apply-requested-changes
    content: Apply only GPU type/slice and queue updates
    status: pending
  - id: render-side-by-side
    content: Present updated full command vs example in table
    status: pending
isProject: false
---

# Update Fuyao Command And Compare

## Source Baseline

- Use the existing deploy invocation in [humanoid-gym/scripts/fuyao_deploy.sh](/home/huh/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh):
  - `fuyao deploy --docker-image=${fuyao_image} --nodes=1 --gpus-per-node=1 --site=fuyao_sh_n2 --queue=rc-wbc-4090 --label="${label_str}" --project="${project}" ...`

## Requested Adjustments (Only)

- Set GPU type to shared by adding `--gpu-type=shared`.
- Set GPU slice to match GPUs-per-node semantics:
  - if `--gpus-per-node=1`, use `--gpu-slice=1of4`
  - if `--gpus-per-node=N` (N != 1), use `--gpu-slice=Nof4`
- Update queue from `rc-wbc-4090` to `rc-wbc-4090-share`.
- Keep all other flags/arguments unchanged.

## Output Format

- Provide a side-by-side markdown table with:
  - Post-updated full deploy command
  - Example command
- Add a short note that the current concrete value remains `1of4` because baseline uses `--gpus-per-node=1`.

---
name: Fix Fuyao Multi-GPU Pending
overview: Fix `humanoid-gym/scripts/fuyao_deploy.sh` which omits `--gpu-type` and `--gpu-slice` when deploying multi-GPU jobs, causing Fuyao to leave them in Pending indefinitely. Add pre-flight validation and a test script that exercises all GPU/queue configurations.
todos:
  - id: fix-deploy-script
    content: Add --gpu-type, --gpu-slice, --dry-run flags and auto-compute logic to fuyao_deploy.sh
    status: completed
  - id: add-validation
    content: Add validate_gpu_config() pre-flight checks to fuyao_deploy.sh
    status: completed
  - id: write-tests
    content: Create test_fuyao_deploy_gpu_config.sh with 6 GPU config test cases
    status: completed
  - id: update-skill
    content: Update deploy-fuyao SKILL.md to document new GPU flags
    status: completed
isProject: false
---

# Fix Fuyao Multi-GPU Jobs Stuck in Pending

## Root Cause

`[humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh)` is the deploy entrypoint used by the deploy-fuyao skill (via SSH). When `--distributed --nproc_per_node=4` is passed, it correctly sets `--gpus-per-node=4` but **never passes `--gpu-type` or `--gpu-slice`** to the `fuyao deploy` command (lines 160-173):

```146:173:humanoid-gym/scripts/fuyao_deploy.sh
    if [ "$distributed" = "true" ]; then
        nodes_opt="--nodes=${nnodes}"
        gpus_opt="--gpus-per-node=${nproc_per_node}"
    fi
    # ...
    fuyao deploy --docker-image=${fuyao_image} \
        ${nodes_opt} \
        ${gpus_opt} \
        --site="${site}" \
        # ... NO --gpu-type, NO --gpu-slice
```

Without `--gpu-type` and `--gpu-slice`, Fuyao's scheduler cannot properly allocate 4 GPUs on the `rc-wbc-4090` queue, resulting in jobs stuck in Pending.

In contrast, `[~/.cursor/scripts/deploy_fuyao.sh](~/.cursor/scripts/deploy_fuyao.sh)` (used by sweep dispatcher) handles this correctly:

- Always passes `--gpu-type=${GPU_TYPE}` (default: `shared`)
- Auto-computes `--gpu-slice` from `gpus_per_node` (4 -> `4of4`)

## Fix Plan

### 1. Add `--gpu-type` and `--gpu-slice` to `fuyao_deploy.sh`

In `[humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh)`:

- Add new variables: `gpu_type='shared'`, `gpu_slice=''`
- Add CLI flags: `--gpu_type`, `--gpu_slice` to `getopt`
- Add `default_gpu_slice_for_gpus_per_node()` function (same logic as `deploy_fuyao.sh` lines 94-106: 1->1of4, 2->2of4, 3->3of4, 4->4of4)
- When `distributed=true`, auto-compute `gpu_slice` from `nproc_per_node` if not explicitly set
- Pass `--gpu-type=${gpu_type}` and `--gpu-slice=${gpu_slice}` (when non-empty) to the `fuyao deploy` command

### 2. Add pre-flight validation function

Add a `validate_gpu_config()` function to `fuyao_deploy.sh` (called before `deploy_single_job`):

- **Error** if `nproc_per_node > 1` but `distributed` is `false`
- **Error** if `nproc_per_node` is not in {1, 2, 3, 4}
- **Warning** if `nproc_per_node == 4` and `gpu_type == shared` (entire node needed on shared queue; suggest adding `--gpu_type exclusive` or expect longer Pending times)
- **Error** if `gpu_slice` is explicitly set but inconsistent with `nproc_per_node`

### 3. Write test script

Create `[humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh](humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh)`:

Test cases (each invokes `fuyao_deploy.sh` with `--yes` and captures the rendered command without actually submitting):


| #   | Config                                                          | Expected                                                          |
| --- | --------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1   | `--distributed --nproc_per_node 4 -q 4090`                      | `--gpu-type=shared --gpu-slice=4of4 --gpus-per-node=4` in command |
| 2   | `--distributed --nproc_per_node 2 -q 4090`                      | `--gpu-type=shared --gpu-slice=2of4 --gpus-per-node=2`            |
| 3   | `--distributed --nproc_per_node 4 --gpu_type exclusive -q 4090` | `--gpu-type=exclusive` and NO `--gpu-slice`                       |
| 4   | `--nproc_per_node 4` (no `--distributed`)                       | Error: "multi-GPU requires --distributed"                         |
| 5   | `--nproc_per_node 5 --distributed`                              | Error: "unsupported gpus-per-node value"                          |
| 6   | Single GPU default                                              | `--gpu-type=shared --gpu-slice=1of4 --gpus-per-node=1`            |


Implementation approach:

- Add a `--dry-run` flag to `fuyao_deploy.sh` that prints the `fuyao deploy` command without executing
- Test script captures dry-run output and greps for expected flags
- Each test case prints PASS/FAIL, script exits non-zero on any failure

### 4. Update deploy-fuyao skill

Update `[~/.cursor/skills/deploy-fuyao/SKILL.md](~/.cursor/skills/deploy-fuyao/SKILL.md)` to:

- Document `--gpu_type` and `--gpu_slice` as optional inputs
- Default `gpu_type` to `shared`; note that `exclusive` is recommended for 4-GPU jobs on non-share queues
- Add a note that multi-GPU requires `--distributed`

## Files Changed

- `humanoid-gym/scripts/fuyao_deploy.sh` -- add `--gpu-type`, `--gpu-slice`, `--dry-run`, validation
- `humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh` -- new test script
- `~/.cursor/skills/deploy-fuyao/SKILL.md` -- document new flags

---
name: Deploy Script Multi-GPU
overview: Enable single-node multi-GPU training in `humanoid-gym/scripts/fuyao_deploy.sh` without requiring manual distributed mode knowledge while keeping current single-GPU behavior by default and minimizing behavioral risk.
todos:
  - id: normalize-gpu-defaults
    content: "Keep current defaults but add an explicit derived mode: compute `effective_distributed = explicit_distributed || (nproc_per_node > 1)` and use it for all launch decisions."
    status: in_progress
  - id: validate-params
    content: Add parsing validation in `humanoid-gym/scripts/fuyao_deploy.sh` for integer-only `--nnodes` and `--nproc_per_node`, and reject unsupported `nnodes>1` in the single-node scope.
    status: pending
  - id: update-cli-contract
    content: Update usage text and examples in `humanoid-gym/scripts/fuyao_deploy.sh` to make `nproc_per_node`/`gpus-per-node` the user-facing knob for multi-GPU and document the auto-enable behavior.
    status: pending
  - id: resource-summary
    content: Enhance the confirmation output in `humanoid-gym/scripts/fuyao_deploy.sh` to print derived distributed state and `total_gpus = nnodes * nproc_per_node` before deployment.
    status: pending
  - id: docs-sync
    content: Update quick-start snippets in [humanoid-gym/humanoid/algo/iron_turbo/README.md](humanoid-gym/humanoid/algo/iron_turbo/README.md) and [humanoid-gym/humanoid/algo/iron_turbo/doc/migration.md](humanoid-gym/humanoid/algo/iron_turbo/doc/migration.md) to use the new ergonomics.
    status: pending
  - id: post-train-guard
    content: (Optional) Add distributed main-process guard for post-train upload/eval logic in [humanoid-gym/scripts/fuyao_train.sh](humanoid-gym/scripts/fuyao_train.sh) after broader distributed rollout.
    status: pending
isProject: false
---

## Objective
- Turn on multi-GPU support ergonomics by making GPU-per-node selection the primary control and deriving distributed mode automatically when needed.
- Preserve existing default path (1 GPU, non-distributed) and keep scheduler-facing queue/site mapping unchanged.
- Add guardrails so multi-GPU requests are validated before deployment and clearly surfaced to users.

## Scope
- Primary file: [humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh)
- Documentation updates: [humanoid-gym/humanoid/algo/iron_turbo/README.md](humanoid-gym/humanoid/algo/iron_turbo/README.md), [humanoid-gym/humanoid/algo/iron_turbo/doc/migration.md](humanoid-gym/humanoid/algo/iron_turbo/doc/migration.md)
- Optional follow-up for robustness: [humanoid-gym/scripts/fuyao_train.sh](humanoid-gym/scripts/fuyao_train.sh)

## Proposed change sequence
- Add a single `effective_distributed` computation in `humanoid-gym/scripts/fuyao_deploy.sh` after argument parsing.
  - `effective_distributed = explicit_distributed || (nproc_per_node > 1)`.
  - Keep default `nproc_per_node=1` and `nnodes=1`.
- Validate inputs before building `fuyao deploy` args:
  - `nnodes` and `nproc_per_node` must be positive integers.
  - Current script scope is single-node by design: enforce `nnodes=1` (or fail with explicit message) until multi-node rendezvous is intentionally implemented.
  - Use early exit with clear user-facing message before any deployment command is assembled.
- Update CLI behavior and help text in the deploy script:
  - Keep `--nproc_per_node` documented.
  - Add `--gpus-per-node` as an alias for clarity if desired.
  - Show derived values in `--help`: "set nproc_per_node` to enable auto-distributed" and current defaults.
- In resource assembly in `deploy_single_job`, wire derived state:
  - `gpus_opt` should use derived `nproc_per_node`.
  - `extra_train_args` should include `--distributed --nnodes ... --nproc_per_node ...` when `effective_distributed` is true.
  - Display confirmation summary including total GPUs (`nnodes x nproc_per_node`) so users know exactly what is being requested.
- Update user-facing docs/examples:
  - Change distributed example lines to highlight the common pattern `--nproc_per_node=<n>` as the GPU-per-node knob and remove the need to manually pass `--distributed`.
  - Add one short note that `--nnodes > 1` is currently not supported in this script path unless multi-node launcher changes are added.

## Current data flow
```mermaid
flowchart TD
Client[

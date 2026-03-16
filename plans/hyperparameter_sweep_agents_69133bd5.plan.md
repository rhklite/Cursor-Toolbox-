---
name: Hyperparameter sweep agents
overview: Define a two-agent system for hyperparameter sweeps with clear responsibilities, then provide a concise prompt line the user can reuse.
todos:
  - id: define-orchestrator-contract
    content: "Specify orchestrator inputs/outputs: objective, constraints, sweep strategy, and stop criteria"
    status: completed
  - id: define-runner-contract
    content: "Specify execution runner contract: launch API, status events, retries/checkpoints, and artifact reporting"
    status: completed
  - id: add-registry-safety
    content: Define shared run registry schema plus resource guards and concurrency limits
    status: completed
  - id: finalize-prompt-line
    content: Finalize one copy-ready line describing the two-agent setup and robustness requirements
    status: completed
isProject: false
---

# Hyperparameter Sweep Agent Setup

## Goal

Create a reliable multi-job sweep setup where one agent plans experiments and another executes training jobs in parallel with observability and safety controls.

## Recommended Components

- **Orchestrator agent**
  - Collect objectives/constraints (metric target, budget, max runtime, compute limits).
  - Generate sweep spec (search space, sampling strategy, seeds, stop criteria).
  - Dispatch jobs in batches and monitor progress.
  - Adapt sweep based on partial results (prune poor regions, expand promising ones).
- **Execution agent (runner pool)**
  - Launch and manage training jobs in parallel from orchestrator-issued configs.
  - Handle retries, resume/checkpoint logic, and failure isolation.
  - Stream structured metrics/logs/artifacts back to orchestrator.
- **Shared experiment registry (strongly recommended)**
  - Single source of truth for run state: queued/running/succeeded/failed/pruned.
  - Stores params, metrics, checkpoints/artifact paths, and reason for termination.
- **Resource/safety layer (strongly recommended)**
  - Concurrency caps per GPU/CPU, memory guards, timeout limits.
  - Duplicate-run prevention and idempotent job launch keys.
- **Selection/reporting step**
  - Rank top-k trials with reproducibility metadata.
  - Emit final recommendation and rerun script for best config.

## Minimal Workflow

1. User defines objective and constraints.
2. Orchestrator creates initial trial set.
3. Execution agent runs trials in parallel with caps.
4. Metrics feed back continuously.
5. Orchestrator updates next trial batch.
6. Stop at budget/time/plateau and produce best config + report.

## Suggested Prompt Line (copy-ready)

"Create two cooperating agents for a hyperparameter sweep: (1) an Orchestrator that defines search space, budgets, and stop rules, then schedules/adapts trials based on incoming metrics; and (2) an Execution Runner that launches jobs in parallel with retries/checkpointing and reports structured results to a shared experiment registry."

## Optional Stronger Version (if you want robustness)

"Include failure handling, resource-aware concurrency limits, duplicate-trial prevention, and a final top-k summary with exact rerun commands for the best configuration."

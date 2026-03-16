---
name: Update Fuyao Deploy Wrapper
overview: Modify the humanoid Fuyao deploy wrapper so one command consistently provisions a remote kernel and starts training immediately with the expected defaults, matching the workflow discussed with your coworker.
todos:
  - id: refactor-command-build
    content: Refactor Fuyao deploy command construction in humanoid-gym/scripts/fuyao_deploy.sh using argument arrays and explicit remote-kernel defaults.
    status: pending
  - id: add-guardrails-and-confirmation
    content: Add conflict checks and print resolved final Fuyao command/flags in confirmation output.
    status: pending
  - id: update-help-and-readme
    content: Update usage examples and scripts README to state that deploy also starts training remotely.
    status: pending
  - id: run-smoke-verification
    content: Run help/argument-path checks and one minimal smoke submission path validation instructions.
    status: pending
isProject: false
---

# Update `fuyao_deploy.sh` for End-to-End Remote Training

## Goal

Make `humanoid-gym/scripts/fuyao_deploy.sh` the single source of truth for remote deployment + training launch, so users do not need to manually reason about a second execution step.

## What to change

- Update `[/Users/HanHu/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh](/Users/HanHu/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh)` to enforce a **remote-kernel training mode by default**.
- Introduce explicit default Fuyao runtime flags inside the script (instead of relying on users to pass long `--fuyao-args` manually), including:
  - `--remote-kernel`
  - default docker image
  - default GPU/site/queue settings
  - `--yes` passthrough behavior
- Keep `--fuyao-args` as an **override/append** mechanism for advanced users.

## Why this fixes the confusion

- Today, users see Fuyao deploy flags but cannot tell if training starts automatically.
- In current code, training does start because deploy calls:

```102:113:/Users/HanHu/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh
fuyao deploy --docker-image=${fuyao_image} \
    --nodes=1 \
    --gpus-per-node=1 \
    --site=fuyao_sh_n2 \
    --queue=rc-wbc-4090 \
    ... /bin/bash humanoid-gym/scripts/fuyao_train.sh \
    --label "${label_str}" \
    --task "${task_name}" \
```

- And that remote script immediately launches training:

```94:99:/Users/HanHu/software/motion_rl/humanoid-gym/scripts/fuyao_train.sh
python humanoid/scripts/train.py --task $task_name --run_name "${task_name}_${new_label}" --headless ${resume} ${checkpoint_path} "${other_args[@]}"
...
bash scripts/fuyao_evaluate.sh --task $task_name
```

## Implementation steps

- Refactor command assembly in `deploy_single_job()`:
  - Build Fuyao CLI args in arrays to avoid quoting bugs and accidental argument splitting.
  - Merge defaults + user overrides deterministically.
- Add guardrails:
  - Validate incompatible/conflicting user overrides (e.g., duplicate queue/site/remote-kernel flags).
  - Print final resolved Fuyao command in confirmation output for transparency.
- Improve `usage()` and examples:
  - Add a clear section: “This command deploys **and starts training** in remote kernel.”
  - Add one canonical example mirroring your coworker’s recommended remote-kernel usage.
- Update docs touchpoint:
  - Add a short note in `[/Users/HanHu/software/motion_rl/humanoid-gym/scripts/README.md](/Users/HanHu/software/motion_rl/humanoid-gym/scripts/README.md)` clarifying that `fuyao_deploy.sh` already executes `fuyao_train.sh` remotely.

## Validation plan

- Dry-run style verification (without submitting real jobs):
  - `--help` output reflects remote-kernel default behavior.
  - confirmation section prints resolved command and includes remote-kernel flags.
- Functional smoke submission (single low-cost run):
  - submit `-j 1 -t <task> -y` and confirm job logs show execution of `humanoid-gym/scripts/fuyao_train.sh` and `train.py` startup.
- Regression checks:
  - multi-job seed handling unchanged.
  - resume model path flow unchanged.
  - custom `--fuyao-args` still works.

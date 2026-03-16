---
name: fuyao deploy mismatch check
overview: Compare documented Fuyao deploy flow with current humanoid-gym deploy scripts, identify mismatches causing 'uploaded but not training', and define a minimal validation/fix sequence.
todos:
  - id: confirm-cli-contract
    content: Unify and document project/experiment argument contract between guide and deploy script.
    status: completed
  - id: fix-pretrain-boot
    content: Guard cron startup in fuyao_train.sh so pre-training setup cannot terminate job unexpectedly.
    status: completed
  - id: doc-command-sync
    content: Update deploy command examples to match real flags and remove typo/conflicts.
    status: completed
  - id: runtime-verification
    content: Define and run a minimal end-to-end validation proving training actually starts on Fuyao.
    status: completed
isProject: false
---

# Align Fuyao Deploy With Training Intent

## What the documentation expects

- Submit from `motion_rl` using `bash scripts/fuyao_deploy.sh ... --task <task>` under `humanoid-gym` flow.
- Use an existing Fuyao experiment/project and receive a running training job plus notification.
- Reference command in the PDF includes `-f "--site=fuyao_sh_n2 --queu=rc-wbc-4090 --experiment=<experiment_name>"`.

## Mismatches identified

- The PDF sample uses `--queu` (missing `e`), which does not match normal `--queue` usage.
- The PDF text says experiment should be filled after `--project`, but the sample also passes `--experiment=...` in `-f`; this is internally inconsistent with current script behavior.
- Current deploy script already hardcodes `--site` and `--queue`, then appends user `--fuyao-args`; duplicated/conflicting flags are possible.
- Most likely runtime break: remote train entry script uses `set -e` and runs `service cron start` without installing `cron` first (unlike the legacy legged script), so job can exit before `train.py` starts.

## Files to validate/update

- `/Users/HanHu/software/motion_rl/humanoid-gym/scripts/fuyao_deploy.sh`
- `/Users/HanHu/software/motion_rl/humanoid-gym/scripts/fuyao_train.sh`
- `/Users/HanHu/sync/notes/[XA 103905] CU-5 M3_ motion_rl 上手指南 之 humanoid-gym 篇.pdf`
- `/Users/HanHu/software/motion_rl/legged_gym_ws/scripts/fuyao_train.sh` (reference behavior)

## Proposed implementation sequence (after approval)

1. Normalize deploy CLI semantics in `fuyao_deploy.sh` so docs and script agree on one project/experiment flag strategy.
2. Harden `fuyao_train.sh` preflight (ensure/install `cron` or guard `service cron start`) so training cannot fail before `python humanoid/scripts/train.py`.
3. Add clear stderr logging around pre-training setup to distinguish "deployment succeeded" from "training process started".
4. Update documentation command examples to remove `--queu` typo and align with actual script options (`--project`, `--task`, optional `--fuyao-args`).
5. Validate with one dry submission command and expected state transitions (submitted -> running -> first train logs/metrics).

## Validation checklist

- `fuyao history` shows submitted job with expected label/project.
- Fuyao job log contains executed `python humanoid/scripts/train.py ...` command.
- First checkpoint/log directory appears under `/model` sync path.
- No early exit at cron setup stage.

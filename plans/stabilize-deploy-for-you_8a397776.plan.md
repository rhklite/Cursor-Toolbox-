---
name: stabilize-deploy-for-you
overview: "Make the next `/deploy-fuyao` run deterministic by fixing the command contract and wrapper script behaviors that caused failures, while keeping the flow: resolve branch/task/label, sync branch, then submit and report job status."
todos:
  - id: resolve-alias-contract
    content: Update deploy-fuyao command contract fallback behavior and fix top-level experiment/queue/site argument contract.
    status: completed
  - id: fix-deploy-defaults
    content: Adjust fuyao_deploy.sh defaults for seeds, nproc aliases, experiment default, and queue/site handling.
    status: completed
  - id: harden-confirmation
    content: Restore interactive confirmation flow in fuyao_deploy.sh when --yes is not set.
    status: completed
  - id: deconflict-args
    content: Sanitize/fail on duplicated scheduler args from --fuyao-args and keep one authoritative source.
    status: completed
  - id: update-postsubmit
    content: Fix post-submit check commands in the command contract and ensure job name/id summary includes actionable follow-up calls.
    status: completed
  - id: verify-orchestrated-sync
    content: After confirmed edits, sync changed toolbox files per .cursor toolbox sync policy and run targeted verification checks.
    status: completed
isProject: false
---

# Stabilize deploy-for-you flow

## Objective snapshot
- User goal: prevent repeatable deployment failures in `/deploy-fuyao`.
- Constraints: keep the same command intent (branch validation, task validation, branch sync, SSH deploy), keep local changes minimal, and preserve existing defaults unless they are causing failures.
- Success criteria: a deployment with no manual fallback steps should complete when inputs are valid, and report how to run immediate `fuyao info` and `fuyao log` checks.

## Issues discovered during the last run
1. The SSH command in the command contract hard-fails when `Huh8.remote_kernel.fuyao` is not resolvable, forcing a manual switch to `remote.kernel.fuyo`.
2. The command contract passes `--experiment` only through `--fuyao-args`, but `humanoid-gym/scripts/fuyao_deploy.sh` requires `--experiment` as a top-level value; missing top-level caused `Error: experiment name cannot be empty`.
3. Seed handling is brittle because seed override is enabled by default while `--seeds` is optional in the command flow.
4. `--gpus-per-node` compatibility and parsing behavior around `--nproc_per_node` are inconsistent; this is why `--gpus-per-node` attempts failed in the run.
5. Queue and site arguments were injected in multiple layers, creating duplicated scheduling args in one call.
6. The script prints a confirmation block but does not actually read user input (`REPLY=y`), so the `--yes` bypass behavior is not enforceable.
7. Post-submit guidance in the command contract is not aligned with CLI usage we observed (`fuyao info -n/ -n` was rejected, while `--job-name` works; same for `fuyao log`).

## Proposed changes
- Update command contract to use a resolved alias with fallback and avoid fragile argument placement.
  - `~/.cursor/commands/deploy-fuyao.md:81-87` currently hardcodes `ssh Huh8.remote_kernel.fuyao ...`.
  - `~/.cursor/commands/deploy-fuyao.md:143-155` currently documents outdated follow-up commands.
- Update `humanoid-gym/scripts/fuyao_deploy.sh` argument handling and defaults.
  - `humanoid-gym/scripts/fuyao_deploy.sh:185-218` needs experiment and queue-related default behavior alignment.
  - `humanoid-gym/scripts/fuyao_deploy.sh:186-239` add robust parsing for queue/site/nproc flags.
  - `humanoid-gym/scripts/fuyao_deploy.sh:320-324` change seed policy so single-job runs do not require manual `--seeds`.
  - `humanoid-gym/scripts/fuyao_deploy.sh:326-370` replace fixed confirmation with real interactive prompt when `--yes` is not set.

## Implementation plan
1. Fix deploy contract baseline command and reporting
   - In `[.../.cursor/commands/deploy-fuyao.md](~/.cursor/commands/deploy-fuyao.md)` add explicit alias resolution and fallback (`Huh8.remote_kernel.fuyao || remote.kernel.fuyo`) before execution.
   - Keep command intent but move `--experiment` to a top-level argument and leave queue/site only in dedicated flow (no duplicate scheduling keys in `--fuyao-args`).
   - Update post-submit checks to `fuyao info --job-name <job_name>` and `fuyao log --job-name <job_name>`.

2. Make seed handling safe by default
   - In `[humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh)` set default seed behavior so `num_jobs=1` can run without `--seeds`.
   - Keep strict validation for multi-job: enforce `--seeds` count only when `num_jobs>1`.
   - Validate seed list is numeric and non-empty.

3. Make queue/site and nproc options unambiguous
   - In `[humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh)` treat `--queue` as:
     - full queue name (current default from command, e.g. `rc-wbc-4090`) or
     - legacy shorthand (`4090|l20|a100`) for backward compatibility.
   - Add explicit `--site` option and conflict-safe handling when both site is set via `--site` and inside `--fuyao-args`.
   - Support both `--nproc_per_node` and `--gpus-per-node` consistently.
   - Reject conflicting `--nproc_per_node`/`--gpus-per-node` values with a clear error.

4. Restore true pre-submit confirmation semantics
   - In `[humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh:326-370)`, replace `REPLY=y` with user input when not `--yes`.
   - Ensure `--yes` remains the explicit non-interactive override path.

5. Reduce ambiguity in command assembly and report exact job identifiers
   - In `[humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh:147-160)` sanitize or reject duplicate scheduler keys from `--fuyao-args` so only one source controls `--queue/--site/--nodes/--gpus-per-node`.
   - Keep a canonical submission summary block: branch/task/label/experiment/site/queue/project and parsed `job name/id` if available.

## Files to change
- `~/.cursor/commands/deploy-fuyao.md`
- `humanoid-gym/scripts/fuyao_deploy.sh`
- (optional after these two are edited) `~/.cursor/skills/deploy-fuyao/SKILL.md` if wording drift appears between skill and command behavior.

## Validation checklist before rollout
1. Run dry-run validation with default branch/task/label values and verify:
   - no alias resolution failure for default SSH host.
   - `--experiment` is sent top-level.
   - one-GPU run submits without `--seeds`.
   - two+ GPU run with `--gpus-per-node` works.
2. Confirm `fuyao info --job-name` and `fuyao log --job-name` usage is printed in final output.
3. Execute one small real run in non-critical mode to verify job submission output includes `job name` and `job id` and the new parsing is stable.

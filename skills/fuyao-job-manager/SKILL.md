---
name: fuyao-job-manager
description: Manage Fuyao jobs post-dispatch — cancel, status, pull artifacts from OSS, query FFF, and manage the job registry. Use when the user mentions cancelling jobs, checking job status, downloading checkpoints/logs/videos, or managing the job registry.
---

# Fuyao Job Manager

## When to Use

Activate when user mentions:
- "cancel job", "stop job", "kill job", "cancel stale jobs"
- "check job status", "are my jobs running", "job status"
- "download checkpoint", "pull artifacts", "get training logs", "pull videos"
- "show job registry", "what jobs are running", "list registered jobs"
- "find artifacts on FFF", "compare metrics", "fuyao file finder"
- "protect job", "unprotect job", "sync registry"

## Backing Script

All operations go through:

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py <subcommand> [options]
```

## Subcommands

### status — Check job status

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py status [--sweep-id ID | --job-name NAME | --all-running] [--json]
```

Workflow:
1. Parse user intent: specific job, sweep, or all running.
2. Run the command.
3. Present the output table to the user.

To resolve "my latest sweep": read the registry (`registry --list --json`), parse `dispatched_at` timestamps, take the most recent `sweep_id`.

### cancel — Cancel jobs with safety guard

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py cancel [--sweep-id ID | --job-name NAME | --stale | --label-pattern PATTERN] [--force] [--dry-run] [--yes]
```

Workflow:
1. Parse user intent into target selector.
2. Always run with `--dry-run` first and show the preview to the user.
3. Require explicit user confirmation before running without `--dry-run`.
4. When running for real, the script prompts `Proceed? [y/N]` unless `--yes` is passed.
5. If the script reports protected jobs are blocked, inform the user and ask if they want `--force`.
6. Report results.

Safety rules:
- NEVER skip the dry-run preview step.
- NEVER pass `--force` unless the user explicitly confirms.
- NEVER pass `--yes` without showing the dry-run preview first and getting user approval.
- When using `--stale`, always show the protected set that will NOT be cancelled.
- Cross-reference the job registry before any cancel. If registry is empty, warn the user.

Cancel signal values (passed via `--signal N`):
- 1: Model issue, config issue
- 2: Training process looks abnormal
- 3: Loss value is on the wrong track
- 4: Loss value is hard to converge
- 5: Dataset issue
- 6: Early stop
- 7: Others (default)

### pull — Download artifacts from OSS

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py pull [--job-name NAME | --sweep-id ID] --type [checkpoints|logs|videos|onnx|metrics|all] [--pattern REGEX] [--output-dir DIR]
```

Workflow:
1. Parse what the user wants to download and from which job(s).
2. Run the command.
3. Report downloaded file count and output directory.

**Alternative — link-based tracking:** Instead of downloading artifacts locally, use `link-job-artifacts` to store OSS download URLs on the tracker node. The dashboard then provides direct download links and client-side ZIP packaging. Prefer this for evaluation artifacts (checkpoints, videos, analysis):

```bash
python3 ~/software/Experiment-Tracker-/tracker_cli.py link-job-artifacts --store-root ~/.exp-tracker --job-name <job_name>
```

Type mapping from user language:
- "checkpoint", "model", "weights", ".pt" -> `--type checkpoints`
- "video", "mp4", "recording" -> `--type videos`
- "onnx", "deployment model" -> `--type onnx`
- "metrics", "csv", "results" -> `--type metrics`
- "logs", "training log" -> `--type logs`
- "everything", "all artifacts" -> `--type all`
- "link artifacts", "store artifact links" -> use `link-job-artifacts` CLI instead

### pull-logs — Fetch training stdout

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py pull-logs [--job-name NAME | --sweep-id ID] [--tail N] [--save DIR]
```

### tensorboard — Stub for future expansion

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py tensorboard [--job-name NAME | --sweep-id ID]
```

Currently prints the OSS path where TensorBoard files would be. Inform the user this is not yet implemented.

### fff — Query Fuyao File Finder

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py fff [--list | --compare | --download] [--job-name NAME] [--label LABEL] [--user USER] [--sweep-id ID]
```

### registry — Manage the job registry

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py registry [--list | --protect JOB | --unprotect JOB | --add JOB | --remove JOB | --clear | --add-batch FILE | --sync] [--json]
```

Key behaviors:
- `--list`: show the registry table (add `--json` for JSON output).
- `--protect/--unprotect`: toggle protection flag.
- `--add`: register a new job (used by deploy/sweep skills post-dispatch).
- `--remove`: delete a specific job from the registry.
- `--clear`: wipe the entire registry (requires confirmation in skill workflow).
- `--add-batch FILE`: register multiple jobs atomically from a JSON file. The file must contain a JSON list of job objects.
- `--sync`: reconcile registry with live fuyao status. Jobs in terminal states (cancelled, completed, failed) are automatically unprotected.

## Registry File

Location: `~/.cursor/tmp/fuyao_job_registry.json`

The registry is the single source of truth for which jobs are tracked and protected. It is:
- Written by `deploy-fuyao` and `sweep-fuyao` skills after dispatch.
- Read by this skill before any cancel operation.
- Updated by `--sync` to reflect live fuyao status.
- Writes are atomic (temp file + rename) to prevent corruption.
- File locking (fcntl.flock) prevents concurrent corruption.

## Defaults

- `--ssh-alias`: `remote.kernel.fuyo`
- `--signal`: `7` (Others)
- `--tail`: `100`
- `--type`: `all`
- Download timeout: 600s per file
- SSH retry: 2 attempts per command
- Artifact download dir: `~/.cursor/tmp/fuyao_artifacts/{job_name}/`

## Error Handling

- If SSH fails: retries once, then reports the error.
- If OSS listing fails: warns and skips that job.
- If registry is empty on cancel: warns the user that no jobs are tracked.
- If FFF API fails: reports the error and suggests direct OSS download.
- If corrupt registry file: logs warning and returns empty registry (never crashes).
- If invalid regex in --label-pattern or --pattern: reports error with message, does not crash.
- If non-numeric --gpus: reports error, does not crash.

## NLP Parsing Examples

| User says | Parsed command |
|-----------|---------------|
| "cancel all stale jobs" | `cancel --stale --dry-run` (then `--yes` after confirmation) |
| "cancel the tslv 0.5 jobs" | `cancel --label-pattern tslv_0.5 --dry-run` |
| "what's the status of my sweep" | `status --sweep-id <latest_sweep_id>` |
| "download checkpoints from job X" | `pull --job-name X --type checkpoints` |
| "get the training logs" | `pull-logs --sweep-id <latest_sweep_id>` |
| "show my job registry" | `registry --list` |
| "sync registry" | `registry --sync` |
| "are my jobs still running" | `status --all-running` |
| "remove job X from registry" | `registry --remove X` |
| "clear the registry" | `registry --clear` |

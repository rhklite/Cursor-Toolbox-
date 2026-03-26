---
name: fuyao-job-manager
description: Manage Fuyao jobs post-dispatch — cancel, status, pull artifacts from OSS, query FFF, manage the job registry, and query training ETA. Use when the user mentions cancelling jobs, checking job status, downloading checkpoints/logs/videos, managing the job registry, or asking about training progress, ETA, or when jobs will finish.
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
- "is the poll daemon running", "check daemon status", "restart poll daemon", "show daemon logs"
- "ETA", "how long", "when will training finish", "training progress", "time remaining", "when done"

## Backing Scripts

Most operations go through:

```bash
python3 ~/.cursor/scripts/fuyao_job_manager.py <subcommand> [options]
```

ETA queries use a dedicated script (see below):

```bash
python3 ~/.cursor/scripts/fuyao_eta.py [--job-name NAME ...] [--all-running] [--sweep-id ID]
```

## ETA Query — fuyao_eta.py

### Purpose

Deterministic training progress and ETA query. The script does ALL the work. The agent is a passthrough only.

### CLI

```bash
python3 ~/.cursor/scripts/fuyao_eta.py --job-name NAME [NAME ...]   # explicit jobs
python3 ~/.cursor/scripts/fuyao_eta.py --all-running                # all running jobs
python3 ~/.cursor/scripts/fuyao_eta.py --sweep-id ID                # from local registry
python3 ~/.cursor/scripts/fuyao_eta.py --parallel N --tail N        # optional tuning
```

### Output

Human-readable table with columns: LABEL, PROGRESS, REMAINING, EST COMPLETION (PT).
Labels are resolved from fuyao info — the bifrost job name is never shown to the user.

### Agent Workflow (MINIMAL LLM INVOLVEMENT)

1. If user provides bifrost job names or a screenshot containing job names:
   - Extract the bifrost names (e.g. bifrost-2026032615402001-huh8)
   - Run: `python3 ~/.cursor/scripts/fuyao_eta.py --job-name <names...>`
   - Print the script's stdout verbatim. STOP.

2. If user says "all running jobs" or provides no specific target:
   - Run: `python3 ~/.cursor/scripts/fuyao_eta.py --all-running`
   - Print the script's stdout verbatim. STOP.

3. If user provides a sweep ID:
   - Run: `python3 ~/.cursor/scripts/fuyao_eta.py --sweep-id <id>`
   - Print the script's stdout verbatim. STOP.

4. If user provides no target and it is ambiguous:
   - Ask the user: "Please provide bifrost job names, a sweep ID, or say 'all running'."
   - Do NOT guess or run --all-running without confirmation.

**CRITICAL: Agent MUST NOT interpret, summarize, add commentary, or reformat the script output. Print it verbatim.**

### NLP triggers -> command mapping

- "ETA of my jobs" / "when will training finish" / "training progress" -> determine targets, run fuyao_eta.py, print verbatim
- "ETA of [screenshot with job list]" -> extract bifrost names, pass as --job-name
- "ETA of all running" -> --all-running
- "ETA of sweep multigpu-tslv-20260325-1012" -> --sweep-id multigpu-tslv-20260325-1012

---

## Subcommands — fuyao_job_manager.py

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

**Local registry:** `~/.cursor/tmp/fuyao_job_registry.json`

The local registry is a dispatch record written by `deploy-fuyao` and `sweep-fuyao` skills after dispatch. It is NOT the source of truth for job status.

**Server registry (authoritative):** `~/software/Experiment-Tracker-/fuyao_job_registry.json` on huh.desktop.us

The server-side polling daemon (`~/software/Experiment-Tracker-/fuyao_poll_daemon.py`) owns the authoritative registry. It:
- Ingests new jobs from `~/software/Experiment-Tracker-/inbox/` (pushed by `~/.cursor/scripts/fuyao_push_inbox.sh`)
- Polls fuyao job status every 5 minutes using parallel SSH (up to 10 workers)
- Links artifacts via `tracker_cli.py link-job-artifacts` when a job becomes terminal
- Bulk-downloads artifacts when all tracked jobs are terminal (all types for completed, logs/metrics only for failed)
- Exits when all jobs reach terminal state

Local `registry --sync` remains available for manual one-shot status checks but does not affect the server registry.

Registry properties:
- Writes are atomic (temp file + rename) to prevent corruption.
- File locking (fcntl.flock) prevents concurrent corruption.

## Defaults

- `--ssh-alias`: `remote.kernel.fuyao`
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

## Server Daemon Management

The polling daemon runs on huh.desktop.us and is started automatically by `fuyao_push_inbox.sh` after dispatch.

To check daemon status:

```bash
ssh huh.desktop.us 'PID=$(cat ~/software/Experiment-Tracker-/fuyao_poll_daemon.pid 2>/dev/null) && kill -0 $PID 2>/dev/null && echo "Running (pid $PID)" || echo "Not running"'
```

To restart the daemon:

```bash
ssh huh.desktop.us 'cd ~/software/Experiment-Tracker- && rm -f fuyao_poll_daemon.pid && nohup python3 fuyao_poll_daemon.py > /dev/null 2>&1 &'
```

To view daemon logs:

```bash
ssh huh.desktop.us 'tail -50 ~/software/Experiment-Tracker-/fuyao_poll_daemon.log'
```

To run a single poll cycle without starting the daemon:

```bash
ssh huh.desktop.us 'cd ~/software/Experiment-Tracker- && python3 fuyao_poll_daemon.py --once'
```

## NLP Parsing Examples

- "ETA of my running jobs" -> `fuyao_eta.py --all-running`, print verbatim
- "when will training finish" / "how long left" -> `fuyao_eta.py --all-running`, print verbatim
- "ETA of [screenshot]" -> extract bifrost names, `fuyao_eta.py --job-name <names...>`, print verbatim
- "cancel all stale jobs" -> `cancel --stale --dry-run` (then `--yes` after confirmation)
- "cancel the tslv 0.5 jobs" -> `cancel --label-pattern tslv_0.5 --dry-run`
- "what's the status of my sweep" -> `status --sweep-id <latest_sweep_id>`
- "download checkpoints from job X" -> `pull --job-name X --type checkpoints`
- "get the training logs" -> `pull-logs --sweep-id <latest_sweep_id>`
- "show my job registry" -> `registry --list`
- "sync registry" -> `registry --sync`
- "are my jobs still running" -> `status --all-running`
- "remove job X from registry" -> `registry --remove X`
- "clear the registry" -> `registry --clear`
- "is the poll daemon running" -> daemon status check (SSH to huh.desktop.us)
- "check daemon status" -> daemon status check
- "restart poll daemon" -> daemon restart (SSH to huh.desktop.us)
- "show daemon logs" -> `tail` daemon log file

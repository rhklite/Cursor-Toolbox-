---
name: pull-training-artifacts
description: Pull evaluation artifacts from completed Fuyao training jobs to the destination host. Use when the user mentions pulling artifacts, downloading training results, getting eval videos, downloading checkpoints from completed jobs, or fetching training outputs.
---

# Pull Training Artifacts

## When to Use

Activate when user mentions:
- "pull artifacts", "download artifacts", "get artifacts"
- "pull training results", "download training outputs"
- "get eval videos", "download eval", "pull eval"
- "download checkpoints from completed jobs"
- "fetch training outputs", "pull completed jobs"
- "get the results from training"

Do NOT activate for:
- ETA queries (use fuyao-job-manager / fuyao_eta.py instead)
- Live log streaming (use fuyao_job_manager.py pull-logs)
- Job status checks (use fuyao_job_manager.py status)

## Backing Script

```bash
python3 ~/.cursor/scripts/pull_training_artifacts.py <options>
```

## CLI

```bash
# Explicit job names
python3 ~/.cursor/scripts/pull_training_artifacts.py --job-names NAME1 NAME2 ...

# All completed jobs in a sweep (from server registry)
python3 ~/.cursor/scripts/pull_training_artifacts.py --sweep-id SWEEP_ID

# All completed jobs in the server registry
python3 ~/.cursor/scripts/pull_training_artifacts.py --all-completed

# Dry run — show resolved jobs without downloading
python3 ~/.cursor/scripts/pull_training_artifacts.py --all-completed --dry-run

# Link artifacts in experiment tracker after download
python3 ~/.cursor/scripts/pull_training_artifacts.py --sweep-id ID --link

# Full (non-selective) download
python3 ~/.cursor/scripts/pull_training_artifacts.py --job-names NAME --no-selective
```

## Options

- --job-names: Explicit bifrost job names (space-separated)
- --sweep-id: Resolve completed jobs from server registry by sweep ID
- --all-completed: Pull all jobs with status "completed" in the server registry
- --dest-host: Destination SSH host (default: huh.desktop.us)
- --dest-dir: Remote destination directory (default: ~/fuyao_artifacts)
- --no-selective: Download all artifacts, not just eval + best checkpoint
- --link: Run tracker_cli.py link-job-artifacts on the server after download
- --dry-run: Show resolved jobs without downloading
- --server-host: Server hosting the authoritative registry (default: huh.desktop.us)

## Agent Workflow (MINIMAL LLM INVOLVEMENT)

1. If user provides explicit job names:
   - Run: `python3 ~/.cursor/scripts/pull_training_artifacts.py --job-names <names...>`
   - Print stdout verbatim. STOP.

2. If user provides a sweep ID:
   - Run: `python3 ~/.cursor/scripts/pull_training_artifacts.py --sweep-id <id>`
   - Print stdout verbatim. STOP.

3. If user says "all completed" or "pull everything that's done":
   - Run: `python3 ~/.cursor/scripts/pull_training_artifacts.py --all-completed`
   - Print stdout verbatim. STOP.

4. If user wants tracker integration:
   - Append `--link` to the command.

5. If ambiguous which jobs to pull:
   - Run `--all-completed --dry-run` first to show available jobs.
   - Ask the user to confirm or narrow scope.

**CRITICAL: Agent MUST NOT interpret, summarize, add commentary, or reformat the script output. Print it verbatim.**

## NLP Triggers -> Command Mapping

- "pull artifacts from my completed jobs" -> --all-completed
- "download training results for sweep X" -> --sweep-id X
- "get eval artifacts from job Y" -> --job-names Y
- "pull everything that's done" -> --all-completed
- "what completed jobs have artifacts?" -> --all-completed --dry-run
- "pull artifacts and link them" -> --all-completed --link
- "download all artifacts (not selective)" -> --all-completed --no-selective

## Output

The script prints:
1. A table of resolved jobs (label, status, sweep ID)
2. Streaming output from the download pipeline (OSS -> kernel -> local -> dest host)
3. Per-job file counts and sizes
4. Summary with total jobs processed

## Download Pipeline

The script delegates to pull_fuyao_artifacts.sh which:
1. Downloads from OSS to the fuyao kernel via xrobot_dataset.download_artifacts
2. Selectively rsyncs eval dirs + best checkpoint (or full tree with --no-selective)
3. Transfers to dest-host via rsync
4. Cleans up temp files on the fuyao kernel

Default selective mode pulls: metadata.json, eval directories, model_20000.pt, and the highest-numbered best_k_value checkpoint. All other .pt files are excluded.

## Artifacts Destination

Downloaded artifacts land at `<dest-host>:<dest-dir>/<job-name>/` (default: huh.desktop.us:~/fuyao_artifacts/<job-name>/).

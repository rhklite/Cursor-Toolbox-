# Link Fuyao Artifacts (User Command)

Discover Fuyao OSS artifacts for a completed job and store download links on the corresponding tracker node. Invoke as `/link-fuyao-artifacts`.

## Required Inputs

Collect this value before execution:

- `job_name` (Fuyao job name, e.g. `bifrost-2026031401372101-huh8`)

Optional:

- `--checkpoint-name` (checkpoint folder name for fallback URL construction when metadata.json is unavailable)
- `--dry-run` (show what would be linked without writing)

## Execution

1. Activate the conda environment and run the CLI:

```bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate exp-tracker
cd ~/software/Experiment-Tracker-
python3 tracker_cli.py link-job-artifacts --job-name <job_name> [--checkpoint-name <name>] [--dry-run]
```

2. Parse the JSON output. On success (`"ok": true`), report:
   - Node ID that was updated
   - Category counts (model, video, analysis)
   - Whether it was a dry run

3. On failure (`"ok": false`), report the error message. Common causes:
   - No mutation node found with that job_name (job was not recorded via deploy/sweep)
   - metadata.json unavailable and no checkpoint-name provided (results in empty links)

## After Linking

- The dashboard will show an Artifacts panel on the mutation's inspector with grouped download links
- Model files (.pt, .onnx) get direct download links
- Video files (.mp4) get direct download links with inline preview
- Analysis files (.csv, .json, .pdf, .png) get individual links and a Download Analysis ZIP button

## Discovery from Context

If the user does not provide a job_name, try to discover it from:

1. Recent job registry entries via `python3 ~/.cursor/scripts/fuyao_job_manager.py status --all --json`
2. The most recent completed job for the current branch
3. Ask the user if discovery fails

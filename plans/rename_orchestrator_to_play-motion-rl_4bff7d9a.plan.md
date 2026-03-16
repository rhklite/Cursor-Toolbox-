---
name: Rename orchestrator to play-motion-rl
overview: Replace the old play-motion-rl command and script with the new orchestrator, and remove the now-redundant launch-plotjuggler-test files.
todos:
  - id: replace-script
    content: Overwrite play_motion_rl.sh with launch_plotjuggler_test.sh contents
    status: completed
  - id: replace-command
    content: Overwrite play-motion-rl.md with launch-plotjuggler-test.md contents (update command name)
    status: completed
  - id: delete-old
    content: Delete launch_plotjuggler_test.sh and launch-plotjuggler-test.md
    status: completed
  - id: sync-rename
    content: Commit, push, and sync toolbox
    status: completed
isProject: false
---

# Rename Orchestrator to play-motion-rl

## File operations

1. **Overwrite** `~/.cursor/scripts/play_motion_rl.sh` with the contents of `~/.cursor/scripts/launch_plotjuggler_test.sh`, plus:
  - Add local-path detection for `--layout` (same logic as `--checkpoint`): if the file exists locally, SCP it to `huh.desktop.us:~/software/motion_rl/` and use the remote path; otherwise treat as a remote path
  - Keep the hardcoded default (`r01_plus_amp_plotjuggler_limit_inspect.xml` in the repo, updated via `--pull`)
2. **Overwrite** `~/.cursor/commands/play-motion-rl.md` with the contents of `~/.cursor/commands/launch-plotjuggler-test.md`, updating the command name to `/play-motion-rl` and documenting the local-layout SCP behavior
3. **Delete** `~/.cursor/scripts/launch_plotjuggler_test.sh`
4. **Delete** `~/.cursor/commands/launch-plotjuggler-test.md`

## Sync

Commit, push, and sync to remote hosts.

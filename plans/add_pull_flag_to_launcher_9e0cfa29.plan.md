---
name: Add pull flag to launcher
overview: Add an opt-in --pull flag to launch_plotjuggler_test.sh that runs git pull --ff-only on the remote motion_rl repo before launching, and update the command doc.
todos:
  - id: add-pull-flag
    content: Add --pull flag, variable, and git pull step to launch_plotjuggler_test.sh
    status: completed
  - id: update-command-doc
    content: Add --pull to launch-plotjuggler-test.md optional inputs
    status: completed
  - id: sync-pull
    content: Commit, push, and sync toolbox
    status: completed
isProject: false
---

# Add --pull Flag to PlotJuggler Test Launcher

## Changes to `~/.cursor/scripts/launch_plotjuggler_test.sh`

Four edits:

1. **Usage text** (line 26): add `--pull` and `--no-pull` option descriptions
2. **Arg parser** (line 39 area): add `PULL_REPO=""` variable (empty = prompt), `--pull` sets it to `1`, `--no-pull` sets it to `0`
3. **New step between healthcheck and checkpoint resolution** (after line 67):
  - If `PULL_REPO` is empty (no flag given) AND stdin is a TTY: prompt the user with `"Pull latest changes for motion_rl on remote? [y/N] "`
  - If `PULL_REPO` is empty and NOT a TTY: default to skip (non-interactive safety)
  - If `PULL_REPO=1` (or user answered y): run `ssh huh.desktop.us "git -C /home/huh/software/motion_rl pull --ff-only"`, warn on failure but don't abort
  - If `PULL_REPO=0` (or user answered n/empty): skip with info message

```bash
if [[ -z "${PULL_REPO}" ]]; then
  if [[ -t 0 ]]; then
    read -rp $'\033[1;34m[INFO]\033[0m  Pull latest changes for motion_rl on remote? [y/N] ' pull_answer
    [[ "${pull_answer}" =~ ^[Yy]$ ]] && PULL_REPO=1 || PULL_REPO=0
  else
    PULL_REPO=0
  fi
fi
if [[ "${PULL_REPO}" -eq 1 ]]; then
  info "Pulling latest changes on ${JUMP_HOST}:${REMOTE_WORKDIR}..."
  if ssh "${JUMP_HOST}" "git -C '${REMOTE_WORKDIR}' pull --ff-only"; then
    ok "Repo updated"
  else
    err "git pull --ff-only failed (divergent or uncommitted changes?). Continuing with current state."
  fi
else
  info "Skipping repo pull"
fi
```

1. **Update `err` call for pull failure**: use a warning instead of exiting — the pull failure is non-fatal (continues with current repo state)

## Changes to `~/.cursor/commands/launch-plotjuggler-test.md`

Add `--pull` and `--no-pull` to the optional inputs list. Note that without either flag, the script prompts interactively.

## Sync

Commit, push, and sync to remote hosts.

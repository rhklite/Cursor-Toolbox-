---
name: Integrate PJ automation into play-motion-rl
overview: Rewrite `play_motion_rl.sh` to run locally (no SSH to self), use the proven streaming-first/layout-second workflow with `pj_clicker.py` as an internal helper, and use `docker exec` for container operations. The `/play-motion-rl` Cursor command becomes a single-operation launch with zero manual steps.
todos:
  - id: move-clicker
    content: Move ~/Downloads/pj_clicker.py to ~/.cursor/scripts/pj_clicker.py
    status: pending
  - id: rewrite-shell
    content: 'Rewrite play_motion_rl.sh: remove SSH, use local exec + docker exec, streaming-first workflow with pj_clicker.py'
    status: pending
  - id: update-command-doc
    content: 'Update play-motion-rl.md: remove SSH/xdotool references, update agent workflow for local execution'
    status: pending
  - id: verify-layout
    content: Verify r01_plotjuggler_full.xml has no previouslyLoaded_Streamer
    status: pending
  - id: end-to-end-test
    content: Run /play-motion-rl end-to-end and verify curves auto-populate
    status: pending
isProject: false
---

# Integrate PlotJuggler Automation into /play-motion-rl

## Current problems with `play_motion_rl.sh`

1. **SSH to self times out** -- the script SSHes to `huh.desktop.us` for every operation, but `hostname` IS `huh.desktop.us`. The hostname resolves to an external AWS IP, so SSH to self hangs.
2. **Wrong PlotJuggler launch order** -- starts PJ with `--layout` before streaming, causing empty curves (snap PJ removes unresolved curve references).
3. **xdotool logic is dead code** -- xdotool isn't installed, `previouslyLoaded_Streamer` crashes the snap PJ, and the SSH-based dialog accepter never runs.
4. `**ISAACGYM_RUNNER` via SSH fails -- the `isaacgym` SSH alias has `RequestTTY force` + `RemoteCommand`, which conflicts with passing commands.

## Solution

Rewrite `[~/.cursor/scripts/play_motion_rl.sh](~/.cursor/scripts/play_motion_rl.sh)` with three key changes:

### Change 1: Local execution (no SSH)

Since we ARE on `huh.desktop.us`, replace every `ssh "${JUMP_HOST}" "cmd"` with direct local execution. Replace the `ISAACGYM_RUNNER` SSH script with `docker exec isaacgym bash -c "cd $WORKDIR && cmd"`.

### Change 2: Streaming-first, layout-second workflow

The proven flow from the integration test:

```
Old (broken):                         New (fixed):
7. Start PJ WITH --layout             7. Start PJ WITHOUT --layout (--nosplash only)
7b. xdotool dialog accepter           7b. pj_clicker.py start-streaming
    (never works)                          (clicks Start, accepts UDP dialog)
8. Start play script                  8. Start play script (docker exec)
                                      8b. Wait for data (~10s)
                                      8c. pj_clicker.py load-layout <xml>
                                           (layout loads with active signals -> curves auto-populate)
```

### Change 3: `pj_clicker.py` as internal helper

Move `~/Downloads/pj_clicker.py` to `[~/.cursor/scripts/pj_clicker.py](~/.cursor/scripts/pj_clicker.py)`. The shell script calls it directly -- the user never touches it.

## Specific edits to `play_motion_rl.sh`

**Remove:** `JUMP_HOST`, `ISAACGYM_RUNNER`, `HAS_XDOTOOL` variables; all `ssh "${JUMP_HOST}" ...` calls; step 0 (xdotool check); step 7b (xdotool accepter); all xdotool-related banner logic.

**Add:** `PJ_CLICKER="${HOME}/.cursor/scripts/pj_clicker.py"` variable.

**Replace pattern** (throughout the script):

- `ssh "${JUMP_HOST}" "pgrep ..."` -> `pgrep ...`
- `ssh "${JUMP_HOST}" "pkill ..."` -> `pkill ...`
- `ssh "${JUMP_HOST}" "test -f ..."` -> `test -f ...`
- `ssh "${JUMP_HOST}" "git -C ..."` -> `git -C ...`
- `ssh "${JUMP_HOST}" "bash ${HEALTHCHECK_SCRIPT}"` -> `bash ${HEALTHCHECK_SCRIPT}`
- `scp "${CHECKPOINT}" "${JUMP_HOST}:..."` -> `cp "${CHECKPOINT}" ...`
- `bash "${ISAACGYM_RUNNER}" ... &` -> `docker exec -d isaacgym bash -c "cd ${REMOTE_WORKDIR} && DISPLAY=:1 python ..." &` (background detached)

**Rewrite step 7** (PlotJuggler launch):

```bash
DISPLAY=:1 nohup plotjuggler --nosplash > ${PJ_LOG} 2>&1 &
PJ_PID=$!
# wait for PJ to be ready...
```

**Add step 7b** (start streaming):

```bash
DISPLAY=:1 python3 "${PJ_CLICKER}" start-streaming
```

**Add step 8b-8c** (after play script confirmed running):

```bash
sleep 10  # wait for UDP data to flow
DISPLAY=:1 python3 "${PJ_CLICKER}" load-layout "${REMOTE_LAYOUT}"
```

**Update banners** -- remove all "Manual step" / xdotool conditional messages; always show "Streaming: auto-started".

## Files to modify

- **Move** `~/Downloads/pj_clicker.py` -> `~/.cursor/scripts/pj_clicker.py`
- **Rewrite** `~/.cursor/scripts/play_motion_rl.sh` (local execution + streaming-first workflow)
- **Update** `~/.cursor/commands/play-motion-rl.md` (remove SSH references, remove manual streaming step, update Step 1 to use local `pgrep` instead of SSH)
- **Verify** `r01_plotjuggler_full.xml` has no `previouslyLoaded_Streamer` (already done)

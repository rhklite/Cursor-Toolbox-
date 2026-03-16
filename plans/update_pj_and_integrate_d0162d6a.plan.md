---
name: Update PJ and integrate
overview: Update PlotJuggler from snap 3.15.0 to AppImage 3.16.0, re-test the previouslyLoaded_Streamer approach, and then carry out the play_motion_rl.sh rewrite using whichever PlotJuggler automation method works.
todos:
  - id: download-pj
    content: Download PlotJuggler 3.16.0 AppImage, make executable, install to PATH
    status: completed
  - id: test-streamer
    content: 'Re-test previouslyLoaded_Streamer with 3.16.0: add to layout XML, launch, check for crash and empty-placeholder behavior'
    status: completed
  - id: decide-branch
    content: 'Based on test: decide Branch A (previouslyLoaded_Streamer works) or Branch B (pj_clicker streaming-first)'
    status: completed
  - id: rewrite-script
    content: 'Rewrite play_motion_rl.sh: remove SSH, use docker exec, integrate chosen PlotJuggler automation, point to AppImage'
    status: completed
  - id: move-clicker
    content: Move pj_clicker.py to ~/.cursor/scripts/
    status: completed
  - id: update-docs
    content: Update play-motion-rl.md command doc
    status: completed
  - id: end-to-end
    content: Run /play-motion-rl end-to-end and verify curves auto-populate with 3.16.0
    status: completed
isProject: false
---

# Update PlotJuggler and Integrate into /play-motion-rl

## Phase 1: Update PlotJuggler to 3.16.0

Current: snap PlotJuggler 3.15.0 (rev 182) -- has `map::at` crash in `UDP_Server::start()` during `previouslyLoaded_Streamer` auto-start.

Target: PlotJuggler 3.16.0 AppImage (released March 10, 2026). No 22.04 .deb available; AppImage is the right choice for Ubuntu 22.04.

**Steps:**

1. Download `PlotJuggler-3.16.0-x86_64.AppImage` from GitHub releases to `~/Downloads/`
2. `chmod +x` and move to `/usr/local/bin/plotjuggler-3.16.0` (or `~/bin/`)
3. Create a `plotjuggler` wrapper/symlink so the new version is used by default
4. Kill any running snap PlotJuggler

Note: The AppImage is standalone (no ROS2 plugins bundled like the snap). The UDP Server plugin and JSON parser are built-in, which may actually fix the crash since there's no snap confinement interfering with plugin loading.

## Phase 2: Re-test previouslyLoaded_Streamer

With 3.16.0, test if `previouslyLoaded_Streamer name="UDP Server"` in the layout XML works without crashing:

1. Add `<previouslyLoaded_Streamer name="UDP Server"/>` back to `r01_plotjuggler_full.xml`
2. Launch PJ 3.16.0 with `--nosplash --layout r01_plotjuggler_full.xml`
3. Click "Yes" on "Start streaming?" dialog (or automate)
4. Accept UDP config dialog
5. Check if PJ crashes or stays alive
6. If alive: check if the "missing timeseries" dialog offers "Create empty placeholders" (upstream source has this as the default button)

**Branch A (3.16.0 fixes the crash + has empty placeholders):**
The original simpler approach works. No `pj_clicker.py` needed. The flow becomes:

- Start PJ with `--layout` (includes `previouslyLoaded_Streamer`)
- Dialogs auto-accepted (3 x Enter)
- Start play script
- Curves auto-populate when data arrives

**Branch B (3.16.0 still crashes or still removes curves):**
Continue with the proven `pj_clicker.py` approach (streaming-first, layout-second).

## Phase 3: Rewrite play_motion_rl.sh (either branch)

Core changes regardless of which branch:

- **Remove all SSH** -- run locally since we ARE `huh.desktop.us`
- **Replace `ISAACGYM_RUNNER`** -- use `docker exec isaacgym bash -c "cd $WORKDIR && cmd"` directly
- **Point to AppImage** -- use new `plotjuggler` binary path instead of snap
- **Update PlotJuggler launch** -- based on branch A or B result

**If Branch A:**

- Launch PJ WITH `--layout` (includes `previouslyLoaded_Streamer`)
- Use `pj_clicker.py` (or python-xlib inline) to send 3x Enter for dialog acceptance
- Start play script
- Banners show "Streaming: auto-started"

**If Branch B:**

- Launch PJ WITHOUT `--layout`
- `pj_clicker.py start-streaming`
- Start play script, wait for data
- `pj_clicker.py load-layout <xml>`

**Either way:**

- Move `pj_clicker.py` from `~/Downloads/` to `~/.cursor/scripts/`
- Update `~/.cursor/commands/play-motion-rl.md`
- Remove all xdotool / SSH / dead code

## Files

- **Download** `PlotJuggler-3.16.0-x86_64.AppImage` -> `~/Downloads/` then install
- **Modify** `r01_plotjuggler_full.xml` -- add/remove `previouslyLoaded_Streamer` based on test result
- **Move** `~/Downloads/pj_clicker.py` -> `~/.cursor/scripts/pj_clicker.py`
- **Rewrite** `~/.cursor/scripts/play_motion_rl.sh`
- **Update** `~/.cursor/commands/play-motion-rl.md`

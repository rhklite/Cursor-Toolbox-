---
name: PlotJuggler python-xlib automation
overview: Replace the broken previouslyLoaded_Streamer + xdotool approach with a Python automation script using python-xlib/xtest that starts streaming and loads the layout in the correct order (streaming first, then layout), solving the empty curves problem.
todos:
  - id: write-pj-clicker
    content: Write ~/Downloads/pj_clicker.py with start-streaming, load-layout, and full-sequence subcommands using python-xlib xtest
    status: completed
  - id: calibrate-coords
    content: Take screenshots and calibrate exact button coordinates (Start streaming button, Layout load button) relative to PlotJuggler window
    status: completed
  - id: integration-test
    content: 'Run full integration test: pj_clicker.py start-streaming, verify data flows, load layout, verify curves populate'
    status: completed
  - id: update-shell-script
    content: 'Modify play_motion_rl.sh: launch PJ without layout, use pj_clicker.py for streaming + layout loading, remove xdotool/previouslyLoaded_Streamer logic (deferred until clicker is proven)'
    status: completed
isProject: false
---

# PlotJuggler Automation via python-xlib

## Problem discovered during integration test

The snap PlotJuggler (v182) has two bugs that prevent the original plan from working:

1. `**previouslyLoaded_Streamer` crashes with `std::out_of_range: map::at` in `UDP_Server::start()` during layout load -- the snap version's parser factory doesn't register "json" before the streamer attempts to use it.
2. **Loading layout before streaming removes curves** -- the snap version's "missing curves" dialog only has an OK button (removes curves), not the "Create empty placeholders" option found in the upstream source.

## Root cause of empty curves

The correct order MUST be: **(1) start streaming -> (2) wait for data -> (3) load layout**. When the layout is loaded while signals are already known, curves bind immediately and auto-populate.

## Solution

Write a Python automation script (`~/Downloads/pj_clicker.py`) using `python-xlib` (already installed) with the `xtest` extension to send synthetic mouse clicks and keyboard events to PlotJuggler. This replaces both `previouslyLoaded_Streamer` and `xdotool`. Runs locally on huh.desktop.us (lab3.pxing.us) where PlotJuggler runs on DISPLAY=:1 via NoMachine.

### Script capabilities

The script will have these subcommands:

- `start-streaming` -- click the Start button in PlotJuggler's Streaming section, accept the UDP config dialog (Enter)
- `load-layout <path>` -- click the Layout load button, type the file path in the file dialog, press Enter
- `full-sequence <layout_path>` -- start streaming, wait for data (poll Timeseries List), then load layout

### How it works

1. Use `wmctrl -lG` to find PlotJuggler window position/size
2. Calculate absolute coordinates of target buttons from known relative offsets within the PlotJuggler window:

- **Start button**: relative offset ~(35, 120) from window top-left (in the Streaming row)
- **Layout load button**: relative offset ~(65, 98) from window top-left (folder icon)

1. Use `python-xlib` XTEST extension to send:

- `fake_input(ButtonPress/ButtonRelease)` at the target coordinates for mouse clicks
- `fake_input(KeyPress/KeyRelease)` for keyboard events (Enter, typing file paths)

1. Take verification screenshots between steps to confirm success

### Integration with `play_motion_rl.sh`

Modify the script flow:

```
Current (broken):                    New (fixed):
1. Start PJ WITH layout              1. Start PJ WITHOUT layout
2. previouslyLoaded_Streamer          2. Run pj_clicker.py start-streaming
   -> CRASHES                         3. Start play script
3. Start play script                  4. Wait for data (sleep or poll)
4. Manual streaming start             5. Run pj_clicker.py load-layout <xml>
5. Curves empty                       6. Curves auto-populate
```

### Files to create/modify

**Phase 1 (this session):**

- **Create** `~/Downloads/pj_clicker.py` -- Python automation script using python-xlib xtest
- **Verify** `r01_plotjuggler_full.xml` does NOT contain `previouslyLoaded_Streamer` (already done)
- **Integration test** -- prove the streaming-first, layout-second flow works end-to-end

**Phase 2 (after clicker is proven):**

- **Modify** `~/.cursor/scripts/play_motion_rl.sh` -- integrate pj_clicker.py, remove xdotool logic
- **Modify** `~/.cursor/commands/play-motion-rl.md` -- update docs
- **Move** pj_clicker.py from ~/Downloads/ to its permanent location

### Coordinate calibration

The button offsets will be determined empirically:

1. Script starts by getting window geometry from wmctrl
2. Click at estimated offset, take screenshot, verify
3. If coordinates are wrong, the script can be adjusted by examining the PlotJuggler screenshot

Screen: 2560x1440. PlotJuggler window: x=875, y=404, w=1058, h=830 (from current session).

### Dependencies

- `python-xlib` (already installed)
- `wmctrl` (already installed)
- `ImageMagick` `import` command (already available, for verification screenshots)

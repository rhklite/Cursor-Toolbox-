---
name: Fix PlotJuggler Remote Layout
overview: Remove the previouslyLoaded_Streamer element from the layout XML on the remote host to prevent the dialog and crash, then relaunch PlotJuggler.
todos:
  - id: fix-remote-xml
    content: Comment out previouslyLoaded_Streamer in the layout XML on huh.desktop.us
    status: completed
  - id: relaunch-pj
    content: Kill and relaunch PlotJuggler on huh.desktop.us with --nosplash (no --publish)
    status: completed
isProject: false
---

# Fix PlotJuggler Layout Crash on Remote Host

## Root Cause

The layout XML at `~/software/motion_rl/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml` on the **remote host** (`huh.desktop.us`) still has line 233:

```xml
<previouslyLoaded_Streamer name="UDP Server"/>
```

This triggers a "use previous data source?" dialog on launch. Clicking "Yes" calls `UDP_Server::start()` which crashes (`std::out_of_range`) because the `<plugin ID="UDP Server"/>` element (line 219) has no saved port/protocol config.

The local Mac copy was already fixed but the remote has its own working copy of the repo.

## Steps

### 1. Comment out the previouslyLoaded_Streamer line on the remote host

```bash
ssh huh.desktop.us "sed -i 's|<previouslyLoaded_Streamer name=\"UDP Server\"/>|<!--<previouslyLoaded_Streamer name=\"UDP Server\"/>-->|' ~/software/motion_rl/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml"
```

### 2. Kill any lingering PlotJuggler and relaunch

```bash
ssh huh.desktop.us "pkill -f plotjuggler"
ssh huh.desktop.us "DISPLAY=:1 nohup plotjuggler --nosplash --layout <path> > /tmp/plotjuggler.log 2>&1 &"
```

### 3. User manually starts UDP Server

After PlotJuggler opens cleanly (no dialog, no crash): **Streaming -> Start: UDP Server**, port 9870, JSON.

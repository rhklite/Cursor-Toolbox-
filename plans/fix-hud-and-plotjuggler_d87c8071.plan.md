---
name: fix-hud-and-plotjuggler
overview: Install missing X11 session libraries inside the isaacgym container so the OpenCV Qt/xcb GUI backend works, set DISPLAY correctly in the launcher, and re-run end-to-end to confirm both PlotJuggler layout loading and HUD window creation.
todos:
  - id: install-libsm-libice
    content: Install libsm6 and libice6 inside the isaacgym container via docker exec
    status: completed
  - id: verify-cv2-gui
    content: Verify cv2 GUI window creation works inside container with DISPLAY=:1
    status: completed
  - id: rerun-launcher
    content: Re-run play_motion_rl.sh with latest checkpoint and confirm HUD status=enabled and PlotJuggler layout loaded
    status: completed
isProject: false
---

# Fix HUD and PlotJuggler Layout Loading

## Root cause

The OpenCV HUD window fails because Qt's xcb platform plugin cannot load inside the isaacgym container:

```
Cannot load library .../libqxcb.so: (libSM.so.6: cannot open shared object file)
```

OpenCV in the container is built with **Qt5 GUI** support and the xcb plugin exists, but `libSM6` (X Session Management) and `libICE6` (Inter-Client Exchange) are not installed.

Additionally, the container was created with `DISPLAY=` (empty) because the host had no `$DISPLAY` set at container creation time. The launcher currently defaults to `:1`, which matches the host's active X server (`/tmp/.X11-unix/X1`, confirmed via `xrandr`).

## Fixes

### 1. Install missing X11 session libs in container

Run inside the isaacgym container (as root or via docker exec):

```bash
apt-get update && apt-get install -y libsm6 libice6
```

This is a one-time fix. These are tiny X11 protocol libraries (~100KB total).

File: None (container runtime fix via `docker exec`)

### 2. Ensure DISPLAY=:1 is passed to play_interactive.py

The launcher at `[~/.cursor/scripts/play_motion_rl.sh](/Users/HanHu/.cursor/scripts/play_motion_rl.sh)` already sets `DISPLAY_VAR` and passes it to the isaacgym runner. However, `run-in-isaacgym-motion-rl.sh` uses plain `ssh isaacgym` which does not forward `DISPLAY`. The env var must be prepended to the command.

Current launcher line (L264-270):

```bash
bash "${ISAACGYM_RUNNER}" \
  DISPLAY=${DISPLAY_VAR} \
  python "${PLAY_SCRIPT}" ...
```

The runner script escapes args and runs `ssh isaacgym "cd ... && DISPLAY=:1 python ..."` -- this should work. Verify it does by checking container-side `echo $DISPLAY` during launch.

### 3. Verify and re-run

- Confirm `libSM.so.6` loads: `ssh isaacgym 'DISPLAY=:1 python3 -c "import cv2; cv2.namedWindow(\"t\"); cv2.destroyAllWindows(); print(\"ok\")"'`
- Re-run full launcher: `bash ~/.cursor/scripts/play_motion_rl.sh --checkpoint <latest> --skip-health --no-pull --replace`
- Confirm logs show `[hud] status=enabled`
- Confirm PlotJuggler layout loads (PID check + layout basename in summary)

---
name: Launch IsaacGym PlotJuggler Test
overview: Copy a local checkpoint to the remote host, launch PlotJuggler on huh.desktop.us as the UDP receiver, then launch play.py inside the isaacgym container to stream telemetry for the r01_v12_amp_with_4dof_arms_and_head_full_scenes task.
todos:
  - id: scp-checkpoint
    content: SCP model_9442_best_k_value=52.954.pt from local ~/Downloads to huh.desktop.us:~/software/motion_rl/
    status: completed
  - id: launch-plotjuggler
    content: Launch PlotJuggler on huh.desktop.us with existing layout XML (backgrounded)
    status: completed
  - id: launch-play
    content: Launch play.py in isaacgym container with --checkpoint_path and task r01_v12_amp_with_4dof_arms_and_head_full_scenes
    status: completed
  - id: verify-streaming
    content: Verify both processes are running and UDP telemetry is flowing
    status: completed
isProject: false
---

# Launch Isaac Gym + PlotJuggler Test

## Context

- **Task**: `r01_v12_amp_with_4dof_arms_and_head_full_scenes` (line 188 of `[humanoid-gym/humanoid/envs/__init__.py](humanoid-gym/humanoid/envs/__init__.py)`)
- **Checkpoint**: `/Users/HanHu/Downloads/model_9442_best_k_value=52.954.pt` (local Mac)
- **Hosts**: `isaacgym` (container, port 22022 via huh.desktop.us) and `huh.desktop.us` (bare metal, port 22) — same physical machine (10.160.64.142)
- **Network**: Container uses `--network=host`, so UDP to `127.0.0.1:9870` from inside the container reaches PlotJuggler on the host
- **Layout XML**: `[humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml](humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml)`

## Steps

### 1. Copy checkpoint to remote host

SCP from local Mac to `huh.desktop.us:~/software/motion_rl/` so it's visible inside the container at `/home/huh/software/motion_rl/model_9442_best_k_value=52.954.pt`.

```bash
scp ~/Downloads/model_9442_best_k_value=52.954.pt huh.desktop.us:~/software/motion_rl/
```

### 2. Launch PlotJuggler on huh.desktop.us (receiver first)

SSH to `huh.desktop.us` and launch PlotJuggler with the existing layout XML (backgrounded).

```bash
ssh huh.desktop.us "DISPLAY=:1 plotjuggler --layout ~/software/motion_rl/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml"
```

### 3. Launch play.py in the isaacgym container (sender)

Use the motion-rl-isaacgym-exec skill runner with:

```bash
bash ~/.cursor/skills/motion-rl-isaacgym-exec/scripts/run-in-isaacgym-motion-rl.sh \
  DISPLAY=:1 python humanoid-gym/humanoid/scripts/play.py \
  --task r01_v12_amp_with_4dof_arms_and_head_full_scenes \
  --checkpoint_path /home/huh/software/motion_rl/model_9442_best_k_value=52.954.pt \
  --resume \
  --total_steps 100000000
```

## Known Gotchas

- **Layout signal mismatch (medium)**: The existing layout XML references paths like `/learning_data/joint_positions[0]`, but the current `UDPClient` may emit signals under a different schema (e.g., `/learning/rl_extra_info/joint_positions/<dof_name>`). If plots appear empty, drag signals from the PlotJuggler data tree into plots manually, or load a matching layout later.
- **UDP Server manual start (low)**: PlotJuggler may not auto-start the UDP listener. If no data appears, go to Streaming -> Start and select UDP Server on port 9870 (JSON format).
- **No code changes**: This is a pure execution task. No source files are modified.

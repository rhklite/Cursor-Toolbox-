---
name: Inspect Agent in PlotJuggler
overview: Set up and verify a live PlotJuggler UDP stream from the currently running agent, then inspect key behavior signals (command tracking, joints, rewards, torques) using either manual plots or the prebuilt layout.
todos:
  - id: verify_stream_endpoint
    content: Verify sender/listener are in same network namespace and both use UDP 9870
    status: completed
  - id: start_udp_streamer
    content: Start UDP JSON streamer in PlotJuggler and confirm data tree arrival
    status: completed
  - id: inspect_core_signals
    content: Plot command-vs-actual velocity, then joint/reward/torque signals
    status: completed
  - id: load_optional_layout
    content: Load provided PlotJuggler XML layout for faster joint-limit analysis
    status: completed
isProject: false
---

# Inspect Agent Behavior via PlotJuggler

## What I found

- Your runtime already has the UDP publishing path in place:
  - `udp_client = UDPClient()` and `udp_client.send_data(robot_data.asdict())` in `[/home/huh/software/motion_rl/humanoid-gym/humanoid/scripts/play.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/scripts/play.py)`.
  - Default endpoint is `127.0.0.1:9870` in `[/home/huh/software/motion_rl/humanoid-gym/humanoid/utils/udp_client.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/utils/udp_client.py)`.
- Installed PlotJuggler version is `3.15.0`, which matches the latest release line, so no upgrade is required right now.

## Execution plan

1. Confirm your running agent process is actually sending UDP from the same machine namespace where PlotJuggler is listening.
2. Start PlotJuggler and create a streamer:

- `Streaming -> Start: UDP Server`
- Protocol: UDP
- Port: `9870`
- Message type: JSON

1. Verify that the data tree appears (`state`, `control_input`, `control_output`, `learning`).
2. Inspect the guide’s core behavior pairs first:

- `learning.rl_obs_unscaled.cmd.root_lin_vel_x` (command)
- `learning.rl_extra_info.pelvis_lin_vel.lin_vel_x` (actual)

1. Add deeper diagnostics as needed:

- Joint tracking: `state.joint.<joint>.position`, `state.joint.<joint>.velocity`
- Reward decomposition: `learning.rl_extra_info.scaled_rewards.*`, `learning.rl_extra_info.total_reward`
- Actuation stress: `control_output.joint.<joint>.torque`

1. Optional: load the prebuilt layout file for joint-limit focused inspection:

- `[/home/huh/software/motion_rl/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml](/home/huh/software/motion_rl/humanoid-gym/datasets/tool/config/r01_plus_amp_plotjuggler_limit_inspect.xml)`

## If no data appears

- Check sender/listener endpoint mismatch (especially container vs host namespace).
- If the agent runs in Docker, either:
  - run PlotJuggler in the same network namespace, or
  - send UDP to host IP (not `127.0.0.1` inside container).
- Keep `UDPClient` host/port aligned with PlotJuggler listener settings.

## Relevant code references

- UDP send path: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/scripts/play.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/scripts/play.py)`
- UDP client defaults: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/utils/udp_client.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/utils/udp_client.py)`
- Data schema for signal names: `[/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/base/robot_data.py](/home/huh/software/motion_rl/humanoid-gym/humanoid/envs/base/robot_data.py)`
- Tutorial PDF: `[/home/huh/software/motion_rl/notes/[XA 184910] CU-5_ [Tutorial] 使用PlotJuggler查看motion_rl UDP数据.pdf](/home/huh/software/motion*rl/notes/[XA 184910] CU-5* [Tutorial] 使用PlotJuggler查看motion_rl UDP数据.pdf)`

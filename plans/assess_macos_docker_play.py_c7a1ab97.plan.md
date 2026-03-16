---
name: Assess macOS Docker play.py
overview: Determine whether `play.py` can run on Apple Silicon macOS without code changes when using this repository’s Docker workflow, and identify hard blockers plus feasible no-code alternatives.
todos:
  - id: verify-entrypoints
    content: Confirm both play.py scripts depend on Isaac Gym runtime
    status: completed
  - id: verify-docker-runtime
    content: Confirm container launch requires NVIDIA runtime and Linux GPU stack
    status: completed
  - id: state-compatibility-verdict
    content: Deliver yes/no answer with specific blockers and alternatives
    status: completed
isProject: false
---

# Assess `play.py` on Apple Silicon + Docker

## What I checked

- Read both entry scripts: `[/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/scripts/play.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/scripts/play.py)` and `[/Users/HanHu/software/motion_rl/legged_gym_ws/legged_gym/scripts/play.py](/Users/HanHu/software/motion_rl/legged_gym_ws/legged_gym/scripts/play.py)`.
- Verified install/runtime assumptions in `[/Users/HanHu/software/motion_rl/humanoid-gym/README.md](/Users/HanHu/software/motion_rl/humanoid-gym/README.md)`, `[/Users/HanHu/software/motion_rl/humanoid-gym/setup.py](/Users/HanHu/software/motion_rl/humanoid-gym/setup.py)`, and Docker files.
- Checked Docker run requirements in `[/Users/HanHu/software/motion_rl/docker/isaacgym/container_config.sh](/Users/HanHu/software/motion_rl/docker/isaacgym/container_config.sh)` and image base in `[/Users/HanHu/software/motion_rl/docker/isaacgym/Dockerfile](/Users/HanHu/software/motion_rl/docker/isaacgym/Dockerfile)`.

## Key constraints found

- `play.py` stacks import/use Isaac Gym (`isaacgym`, `isaacgym.torch_utils`) and project utilities that also import Isaac Gym APIs.
- Project dependency explicitly requires `isaacgym` in `[/Users/HanHu/software/motion_rl/humanoid-gym/setup.py](/Users/HanHu/software/motion_rl/humanoid-gym/setup.py)`.
- Repo docs target NVIDIA CUDA + Linux userspace (NVIDIA driver, `pytorch-cuda`, Linux `.so` troubleshooting).
- Official container launch in this repo hard-requires NVIDIA Docker runtime:
  - `--gpus=all`
  - `--runtime=nvidia`
  - NVIDIA CUDA base images / Linux x86_64 stack.

## Decision logic

- If running Docker on Apple Silicon macOS **without** NVIDIA GPU passthrough, this repo’s Isaac Gym workflow cannot run as-is.
- CPU flags (`--sim_device cpu --rl_device cpu`) reduce compute device use but do **not** remove Isaac Gym native runtime/platform requirements.

## Expected conclusion to present

- **No**: You cannot reliably run repository `play.py` on Apple Silicon macOS in Docker **without code/workflow changes**.
- **Yes with no code changes only if** you run inside a Linux x86_64 + NVIDIA GPU environment (local Linux workstation or remote GPU server/container) and use this repo normally.

## Practical no-code alternatives

- Use remote Linux NVIDIA machine and run the same container/image there.
- Use this repo’s IsaacSim/Mujoco pathways only if they are already configured to avoid Isaac Gym runtime requirements for your exact task; otherwise this still needs workflow changes.

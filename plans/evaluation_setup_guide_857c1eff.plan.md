---
name: Evaluation Setup Guide
overview: Set up the Isaac Gym Docker container, download the pre-trained checkpoint from the PDF guide, and run `play.py` to evaluate the `r01_plus_amp_with_4dof_arms` task.
todos:
  - id: create-container
    content: Create and enter the isaacgym Docker container via `bash scripts/docker_run.sh`
    status: pending
  - id: download-checkpoint
    content: Download model_15000.pt into humanoid-gym/logs/r01_plus_amp_with_4dof_arms/example/
    status: pending
  - id: run-evaluation
    content: Run play.py with --task r01_plus_amp_with_4dof_arms --load_run=example
    status: pending
isProject: false
---

# Evaluation Setup for humanoid-gym

## Prerequisites (already satisfied)

Your machine meets the requirements from the PDF guide:
- **GPU**: 2x NVIDIA RTX 3090 Ti (24GB each) -- exceeds the 10GB minimum
- **Docker image**: `isaacgym:2025.05.16` is already pulled locally
- **Docker login**: Credentials for `xrobot-infra-registry` are embedded in [`scripts/docker_login.sh`](scripts/docker_login.sh)

## Step 1: Create and enter the Isaac Gym Docker container

Run the interactive container launcher from the repo root. Select **isaacgym** when prompted:

```bash
cd /home/huh/software/rl/motion_rl
bash scripts/docker_run.sh
# Select: isaacgym
```

This will:
- Pull the image if needed (already cached locally)
- Create a container named `isaacgym`
- Run the [`entrypoint.sh`](docker/isaacgym/entrypoint.sh) which installs `humanoid-gym` and `rsl_rl` via pip, sets up git hooks, and downloads repo dependencies (robot model files)
- Drop you into a bash shell at `/home/<user>/software/motion_rl/`

**Note**: An existing container `isaacgym_dejun_motion_rl` exists from another user. The script will create a fresh `isaacgym` container for you. If a container named `isaacgym` already exists, use the `-u` flag to recreate it: `bash scripts/docker_run.sh -u`.

## Step 2: Download the pre-trained checkpoint

Per the PDF guide, download `model_15000.pt` into the expected directory. Run these commands **inside the container**:

```bash
cd humanoid-gym
mkdir -p logs/r01_plus_amp_with_4dof_arms/example/
wget -O logs/r01_plus_amp_with_4dof_arms/example/model_15000.pt \
  "https://xrobot.xiaopeng.link/resource/xrobot-log/user-upload/fuyao/guomh/bifrost-2025051107240410-guomh/model_15000.pt"
```

## Step 3: Run play.py to evaluate

Still inside the container, from the `humanoid-gym/` directory:

```bash
python humanoid/scripts/play.py --task r01_plus_amp_with_4dof_arms --load_run=example
```

This will:
- Load the `r01_plus_amp_with_4dof_arms` task environment with Isaac Gym
- Load the `model_15000.pt` checkpoint from `logs/r01_plus_amp_with_4dof_arms/example/`
- Launch a visualization window showing the humanoid robot executing the trained policy

If you need to run **without GPU rendering** (e.g., insufficient GPU memory for both sim + rendering), add CPU flags:

```bash
python humanoid/scripts/play.py --task r01_plus_amp_with_4dof_arms \
  --load_run=example --rl_device cpu --sim_device cpu
```

## Notes

- The container's working directory is `/home/<user>/software/motion_rl/`. You must `cd humanoid-gym` before running scripts.
- The [`docker/isaacgym/container_config.sh`](docker/isaacgym/container_config.sh) mounts `/home/huh/software/rl/` into the container, so your local repo files are shared.
- The entrypoint script downloads robot model files from the internal GitLab (via [`repo_deps/model_files.conf`](repo_deps/model_files.conf)). This requires GitLab SSH access. If it fails, the container will still start but evaluations requiring URDF/mesh assets may error.

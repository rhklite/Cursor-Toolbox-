---
name: Setup motion_rl local clone
overview: Create a local `software` directory under your Mac home and clone `motion_rl` from your existing default remote. If the repo already exists, update it with pull instead of re-cloning.
todos:
  - id: create-software-dir
    content: Create `/Users/HanHu/software` if it does not already exist
    status: completed
  - id: clone-or-pull-motion-rl
    content: Clone `motion_rl` from default remote, or pull if local repo already exists
    status: completed
  - id: verify-checkout
    content: Verify directory, remote URL, and repo status
    status: completed
isProject: false
---

# Clone motion_rl Under Home

## Goal

Set up a local checkout at `/Users/HanHu/software/motion_rl` using your current default remote:
`git@gitlab-adc.xiaopeng.link:robotics/motion_control/rl/motion_rl.git`.

## Steps

- Ensure home-level target exists: create `/Users/HanHu/software` if missing.
- If `/Users/HanHu/software/motion_rl` does not exist, run `git clone` from the remote into that path.
- If the repo already exists, run `git -C /Users/HanHu/software/motion_rl pull` to sync latest changes.
- Verify with:
  - `ls -la /Users/HanHu/software`
  - `git -C /Users/HanHu/software/motion_rl remote -v`
  - `git -C /Users/HanHu/software/motion_rl status`

## Notes

- This plan uses your selected location (local Mac home) and your default `motion_rl` source discovered from your existing isaacgym checkout.


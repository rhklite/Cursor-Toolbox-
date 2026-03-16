---
name: deploy fuyao motion rl dir
overview: Verify Motion RL project path assumptions and update `/deploy-fuyao` so execution explicitly validates and uses a `/motion_rl` working directory in both direct and SSH paths.
todos:
  - id: add-workdir-requirements
    content: Add project-directory verification rules under `/motion_rl` to deploy command docs.
    status: pending
  - id: wire-direct-and-ssh-workdir
    content: Update execution workflow so direct path validates pwd and SSH path prepends `cd /root/motion_rl &&`.
    status: pending
  - id: update-reporting-and-errors
    content: Add workdir reporting and clear directory-mismatch corrective guidance.
    status: pending
isProject: false
---

# Enforce `/motion_rl` Workdir in `/deploy-fuyao`

## What I verified

- Current command definition at `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)` contains routing (`direct` vs `ssh`) but does not require or set a project working directory.
- Workspace history/config evidence indicates Motion RL paths are under `.../motion_rl`, including remote-kernel path `/root/motion_rl` and other environments like `/home/huh/software/motion_rl`.

## Files to update

- `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)`

## Planned changes

- Add a **Project Directory Verification** section before execution that requires working directory to be under `/motion_rl`.
- Define explicit workdir behavior by execution path:
  - **Direct mode**: verify current `pwd` is under `/motion_rl`; if not, fail with a clear corrective message.
  - **SSH mode**: run deploy as `ssh Huh8.remote_kernel.fuyao "cd /root/motion_rl && fuyao deploy ..."` so remote execution always uses Motion RL project root.
- Update workflow ordering to include a new step between host detection and deploy execution:
  - host detection -> workdir validation/selection -> deploy execution.
- Update quoting guidance to include safe quoting for `cd /root/motion_rl && <deploy>` in SSH mode.
- Extend post-submit reporting with a `workdir` field (e.g., `workdir: /root/motion_rl` in SSH mode, or current direct-mode path).
- Add failure guidance for directory mismatch (e.g., `cd /root/motion_rl` then rerun), without changing any existing fixed deploy defaults.

## Validation checks after update

- Confirm command text explicitly blocks direct execution when outside `/motion_rl`.
- Confirm SSH branch always includes `cd /root/motion_rl && ...`.
- Confirm existing fixed defaults, override policy, and auth-retry flow remain unchanged except for workdir handling.


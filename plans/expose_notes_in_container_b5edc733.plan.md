---
name: Expose notes in container
overview: Make external notes visible in Docker without adding notes into the repo or modifying shared .gitignore. Use container bind mounts and local git exclude rules only.
todos:
  - id: add-notes-bind-mount
    content: Update isaacgym and isaacsim container configs to mount /home/huh/software/notes into ${docker_dir}/notes
    status: completed
  - id: normalize-notes-symlink
    content: Ensure motion_rl/notes symlink points to ../notes so it resolves consistently in host and container
    status: completed
  - id: local-ignore-only
    content: Add notes entry to .git/info/exclude to avoid touching shared .gitignore
    status: completed
  - id: recreate-and-verify
    content: Recreate container and verify notes path visibility from both symlink and direct mount
    status: completed
isProject: false
---

# Expose external notes in container

## Goal

Make `/home/huh/software/notes` visible inside your Docker containers while keeping it outside the `motion_rl` repository and avoiding changes to shared ignore rules.

## Why it fails today

Current container startup mounts only the repo root (`host_dir=.../motion_rl`) into the container via `-v ${host_dir}:${docker_dir}:rw` in:

- [docker/isaacgym/container_config.sh](/home/huh/software/motion_rl/docker/isaacgym/container_config.sh)
- [docker/isaacsim/container_config.sh](/home/huh/software/motion_rl/docker/isaacsim/container_config.sh)

Because `notes` points to `/home/huh/software/notes` (outside `motion_rl`), that target is not present in the container unless mounted separately.

## Implementation

- Add an explicit bind mount in both container configs for your notes directory:
  - host: `/home/huh/software/notes`
  - container: `${docker_dir}/notes`
- Keep or update `motion_rl/notes` symlink to point to `../notes` (preferred portable link) so it resolves on both host and container.
- Add local-only ignore entry in `.git/info/exclude` for `notes` (and optionally `motion_rl.code-workspace` if desired), so no shared `.gitignore` change is needed.

## Validation

- Recreate container (`scripts/docker_run.sh -u`), enter container, and verify:
  - `ls -la ${HOME}/software/notes`
  - `ls -la ${HOME}/software/motion_rl/notes`
  - create a test file in `notes` from host or container and confirm visibility both sides.

## Rollback

- Remove the added `-v /home/huh/software/notes:${docker_dir}/notes:rw` lines and recreate container.

---
name: Flatten notes location
overview: Move the real notes directory to live directly under motion_rl and remove the extra indirection from chained symlinks.
todos:
  - id: verify-source
    content: Confirm the real source notes directory and backup readiness
    status: completed
  - id: replace-link
    content: Remove repo-root notes symlink and move notes content into motion_rl/notes
    status: completed
  - id: compat-link
    content: Optionally add legacy symlink from old location to new path
    status: completed
  - id: validate
    content: Verify directory/symlink targets and file accessibility
    status: completed
isProject: false
---

# Move `notes` into `motion_rl`

## Goal

Have one canonical notes path at `[/home/huh/software/motion_rl/notes](/home/huh/software/motion_rl/notes)` instead of the current chain through `[/home/huh/software/notes](/home/huh/software/notes)` and `[/home/huh/Documents/notes](/home/huh/Documents/notes)`.

## Current state

- `[/home/huh/software/motion_rl/notes](/home/huh/software/motion_rl/notes)` is a symlink to `../notes`.
- `[/home/huh/software/notes](/home/huh/software/notes)` is a symlink to `/home/huh/Documents/notes`.

## Planned steps

1. Back up or verify content at `[/home/huh/Documents/notes](/home/huh/Documents/notes)` before changing links.
2. Remove only the symlink at `[/home/huh/software/motion_rl/notes](/home/huh/software/motion_rl/notes)` (not the target content).
3. Move the real notes directory into `[/home/huh/software/motion_rl/notes](/home/huh/software/motion_rl/notes)`.
4. Optionally keep compatibility by creating a symlink from old path `[/home/huh/Documents/notes](/home/huh/Documents/notes)` pointing to the new location.
5. Validate with `ls -ld` and a quick file open from both new and optional legacy paths.

## Expected outcome

- `motion_rl/notes` is a real directory (not a symlink chain).
- Moving `motion_rl` later does not depend on external `../notes` layout.

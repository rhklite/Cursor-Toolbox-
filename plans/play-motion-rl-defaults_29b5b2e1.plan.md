---
name: play-motion-rl-defaults
overview: Update the `/play-motion-rl` wrapper defaults so a new launch uses the registry task at line 188, loads the latest full PlotJuggler layout, and runs interactive mode by default.
todos:
  - id: set-default-task-line-188
    content: Set `play_motion_rl.sh` default task to `r01_v12_amp_with_4dof_arms_and_head_full_scenes` (task registry line 188).
    status: completed
  - id: set-default-layout-full-xml
    content: Switch launcher default layout path from `r01_plus_amp_plotjuggler_limit_inspect.xml` to `r01_plotjuggler_full.xml`.
    status: completed
  - id: set-interactive-default-true
    content: Make `INTERACTIVE=1` default in `play_motion_rl.sh` and update docs/help text accordingly.
    status: completed
  - id: update-command-docs
    content: Synchronize `~/.cursor/commands/play-motion-rl.md` argument defaults and required-input wording with the new launcher defaults.
    status: completed
isProject: false
---

## Goal

Align command defaults with your requested baseline and avoid manual flags for the common case.

- Set default task to the registry entry on line 188 of the task registry:
  - `r01_v12_amp_with_4dof_arms_and_head_full_scenes` ([humanoid-gym/humanoid/envs/**init**.py](/Users/HanHu/software/motion_rl/humanoid-gym/humanoid/envs/__init__.py)).
- Point default PlotJuggler layout to the newest full XML layout file:
  - `/home/huh/software/motion_rl/humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml` (local workspace path).
- Make interactive mode the default in the launcher so `play_interactive.py` is selected when no interactive flag is supplied.
- Keep explicit override behavior available for callers that still pass flags, and update command docs so required/optional arguments match the new default behavior.

### Files and concrete edits

- `~/.cursor/scripts/play_motion_rl.sh`
  - Change `DEFAULT_LAYOUT` near line 10 from `r01_plus_amp_plotjuggler_limit_inspect.xml` to `r01_plotjuggler_full.xml`.
  - Add/ensure a `DEFAULT_TASK` value of `r01_v12_amp_with_4dof_arms_and_head_full_scenes` and initialize `TASK` with it when not supplied.
  - Initialize `INTERACTIVE=1` (default on) and keep existing `--interactive` parsing behavior.
  - Update `usage()` text lines 23-31 to reflect layout and interactive defaults.
  - Adjust required-arg enforcement so `--task` is no longer mandatory when a default exists.
- `~/.cursor/commands/play-motion-rl.md`
  - Update the `--layout` default text to `r01_plotjuggler_full.xml`.
  - Update docs around optional inputs to reflect interactive-on-by-default behavior.
  - Update any mention that `--task` is strictly required unless a default is intended to be inferred from wrapper defaults.

## Validation checklist

- Confirm `bash ~/.cursor/scripts/play_motion_rl.sh --checkpoint <path>` launches with:
  - `task=r01_v12_amp_with_4dof_arms_and_head_full_scenes`
  - `layout=humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml`
  - script selected: `play_interactive.py`.
- Confirm explicit `--layout` and (if retained) explicit `--task` override the defaults correctly.

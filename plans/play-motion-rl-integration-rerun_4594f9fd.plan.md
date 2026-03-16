---
name: play-motion-rl-integration-rerun
overview: Re-run the launch using current `/play-motion-rl` defaults and validate that task/layout/interactive defaults are honored while using the latest checkpoint in `~/Downloads`.
todos: []
isProject: false
---

## Scope

Update and run a verification pass that uses the existing defaults in `~/.cursor/scripts/play_motion_rl.sh` without changing files.

## File and command references

- `[~/.cursor/scripts/play_motion_rl.sh](/Users/HanHu/.cursor/scripts/play_motion_rl.sh)`: current defaults are already set to `TASK=r01_v12_amp_with_4dof_arms_and_head_full_scenes`, `LAYOUT=${REMOTE_WORKDIR}/humanoid-gym/datasets/tool/config/r01_plotjuggler_full.xml`, and `INTERACTIVE=1`.
- `[~/.cursor/scripts/play_motion_rl.sh](/Users/HanHu/.cursor/scripts/play_motion_rl.sh)` launch path for checkpoints is around the `Resolve checkpoint` section and local file upload block.
- `[~/.cursor/commands/play-motion-rl.md](/Users/HanHu/.cursor/commands/play-motion-rl.md)` shows current usage defaults and required arguments.
- `[/Users/HanHu/software/motion_rl/humanoid-gym/tests/test_plotjuggler_xml_signals.py](/Users/HanHu/software/motion_rl/humanoid-gym/tests/test_plotjuggler_xml_signals.py)` can be used as a quick offline compatibility check if you also want local validation.

## Execution plan

```mermaid
flowchart TD
    A[Pick checkpoint from ~/Downloads] --> B[Build command using defaults]
    B --> C[Run play_motion launcher with --checkpoint]
    C --> D[Capture startup log and selected script]
    D --> E{Run assertions}
    E -->|Pass| F[Confirm defaults and PlotJuggler play start]
    E -->|Needs attention| G[Collect failure mode and logs]
```

1. Select latest checkpoint in `~/Downloads` (most recent `*.pt`) and use it as the `--checkpoint` value.
2. Run `bash ~/.cursor/scripts/play_motion_rl.sh --checkpoint <latest_checkpoint_path>` and wait for launch logs.
3. Confirm output shows:
   - task is `r01_v12_amp_with_4dof_arms_and_head_full_scenes` (default when `--task` is omitted),
   - layout path resolves to `r01_plotjuggler_full.xml`,
   - interactive play branch is used (`play_interactive.py`).
4. If needed for stronger regression coverage, run a paired offline test: `cd /Users/HanHu/software/motion_rl/humanoid-gym && python3 -m pytest tests/test_plotjuggler_xml_signals.py -k full`.
5. Report pass/fail with any launcher, checkpoint upload, PlotJuggler, or script selection errors.

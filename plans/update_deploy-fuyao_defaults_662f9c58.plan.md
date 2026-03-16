---
name: Update deploy-fuyao Defaults
overview: Update `/deploy-fuyao` defaults so experiment is lowercase `huh8/r01`, and resource knobs (`nodes`, `gpus-per-node`) are defaults (not hard-locked), with priority defaulting to normal.
todos:
  - id: set-experiment-default
    content: Set experiment default/value wording to lowercase `huh8/r01` in deploy-fuyao command definition.
    status: completed
  - id: make-resource-defaults-overridable
    content: Update nodes and gpus-per-node from fixed constants to defaults with explicit override allowance.
    status: completed
  - id: confirm-priority-default
    content: Ensure priority remains default `normal` and documented as overrideable.
    status: completed
  - id: verify-routing-unchanged
    content: Preserve and verify existing per-machine routing behavior documentation remains intact.
    status: completed
isProject: false
---

# Update `deploy-fuyao` Defaults

## Goal

Adjust the Cursor command definition so defaults are practical and overridable:

- experiment default: `huh8/r01` (lowercase)
- nodes default: `1` (override allowed)
- gpus-per-node default: `1` (override allowed)
- priority default: `normal`

## Planned Changes

- Update `[/Users/HanHu/.cursor/commands/deploy-fuyao.md](/Users/HanHu/.cursor/commands/deploy-fuyao.md)`:
  - Replace experiment example/default wording with explicit lowercase `huh8/r01`.
  - Change wording from fixed/constant resource values to **defaults** for:
    - `--nodes=1`
    - `--gpus-per-node=1`
  - Keep `--priority=normal` as default behavior (still overrideable by explicit user request).
- Keep all existing routing behavior unchanged:
  - direct on target remote-kernel host
  - SSH route from other hosts to `Huh8.remote_kernel.fuyao` with `cd /root/motion_rl`

## Behavior Specification (After Update)

- If user does not specify resource overrides:
  - use `--nodes=1 --gpus-per-node=1 --priority=normal`
- If user specifies overrides:
  - use user values for nodes/GPU-per-node/priority
- If user does not specify experiment:
  - default to `huh8/r01`

## Validation

- Confirm command doc now explicitly states `huh8/r01` lowercase default.
- Confirm wording for nodes and GPUs-per-node is “default” (not fixed/constant).
- Confirm priority is documented as default `normal` and remains overrideable.

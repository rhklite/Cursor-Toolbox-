---
name: Fix Priority Fallback Bug
overview: Ensure dictation mode reliably falls back to the next configured microphone when a higher-priority device disconnects, instead of leaving macOS system default active.
todos:
  - id: inspect-current-switching-failures
    content: Confirm exact failure points in run_sas/set_input/set_input_background and current state-update flow.
    status: completed
  - id: harden-switchaudio-command-resolution
    content: Implement binary path fallback and return-code-aware command handling in menubar app.
    status: completed
  - id: enforce-verified-dictation-fallback
    content: Update dictation polling/manual selection to verify switch success before trusting UI state.
    status: completed
  - id: run-priority-regression-checks
    content: Validate disconnect fallback scenarios and command-failure diagnostics with list/current checks.
    status: completed
isProject: false
---

# Fix Priority Fallback to Next Device

## Findings

- Priority selection logic exists and is correct in `[/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/input_source_menubar.py](/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/input_source_menubar.py)`: `pick_prioritized_input()` scans `PRIORITY_INPUTS` in order.
- The bug is likely in switch application reliability, not ordering:
  - `run_sas()` does not check non-zero return codes.
  - `set_input_background()` is fire-and-forget with no verification.
  - Menubar app hardcodes `SWITCH_AUDIO_SOURCE = "/Users/HanHu/bin/SwitchAudioSource"` while launcher script supports PATH fallback.

## Implementation Plan

- Update command execution robustness in `[/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/input_source_menubar.py](/Users/HanHu/Documents/script/MacOS-Audio-input-source.-Switch-script--main/input_source_menubar.py)`:
  - Resolve `SwitchAudioSource` path with fallback (`/Users/HanHu/bin/SwitchAudioSource` else `SwitchAudioSource` in PATH).
  - Add return-code/stderr-aware command wrapper for set/read operations.
  - Log failed set attempts with target device and command error.
- Make dictation fallback deterministic in the same file:
  - In `_poll_dictation()`, when current device is not the chosen priority, apply set and then verify with `get_current_input()`.
  - If set fails, retry once synchronously and keep polling next interval instead of accepting stale state.
  - Keep matching behavior in `pick_prioritized_input()` unchanged (order already correct).
- Improve async/manual switch path consistency:
  - Use the same robust setter for background/manual selection, or keep background but schedule immediate verification before updating menu state.
- Add focused regression checks:
  - Scenario A: `Yeti X` disconnected, `Blue Snowball` connected -> input becomes `Blue Snowball`.
  - Scenario B: both external devices disconnected, built-in connected -> input becomes `MacBook Pro Microphone`.
  - Scenario C: command failure (bad binary path) -> clear log entry and no false “switched” state in UI.

## Validation

- Run `./Input_source.sh --list` and `./Input_source.sh --current` during disconnect/reconnect transitions.
- Confirm menubar dictation mode converges to next priority within one poll interval.
- Check `/tmp/input_source_menubar.log` for explicit failure diagnostics (only when failure is induced).


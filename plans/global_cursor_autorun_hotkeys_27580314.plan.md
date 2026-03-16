---
name: Global Cursor AutoRun Hotkeys
overview: Add global Cursor keybindings so Option+Shift+1 sets Ask Every Time and Option+Shift+2 sets Run Everything across all projects, with command-ID verification to handle Cursor version differences.
todos:
  - id: discover-command-ids
    content: Identify exact Cursor command IDs for Ask Every Time and Run Everything in current version
    status: completed
  - id: update-user-keybindings
    content: Add global alt+shift+1 and alt+shift+2 mappings in user keybindings.json
    status: cancelled
  - id: validate-hotkeys
    content: Verify both hotkeys switch Auto Run mode and persist across projects
    status: cancelled
isProject: false
---

# Global Cursor Auto-Run Hotkeys

## Goal

Configure global (user-level) Cursor hotkeys:

- `Option+Shift+1` -> Ask Every Time
- `Option+Shift+2` -> Run Everything

This applies across all Cursor projects by editing user keybindings, not workspace settings.

## Files and Scope

- Primary file: `[/Users/HanHu/Library/Application Support/Cursor/User/keybindings.json](/Users/HanHu/Library/Application%20Support/Cursor/User/keybindings.json)`
- Optional verification context: `[/Users/HanHu/Library/Application Support/Cursor/User/settings.json](/Users/HanHu/Library/Application%20Support/Cursor/User/settings.json)`

## Implementation Plan

1. Verify the exact Cursor command IDs for switching Auto Run mode (from Keyboard Shortcuts UI / command search) because IDs can vary slightly by Cursor version.
2. Add two global keybinding entries in `keybindings.json` mapping:
  - `alt+shift+1` -> Ask Every Time command
  - `alt+shift+2` -> Run Everything command
3. Ensure the bindings are user-level only (not workspace-level) so they apply globally.
4. Validate behavior in a chat/composer session by toggling modes with both hotkeys.
5. If Cursor lacks explicit per-mode commands in this version, bind nearest equivalent commands and document the exact resulting behavior.

## Validation

- Open Cursor command palette/Auto Run controls and confirm the mode changes immediately after each hotkey press.
- Confirm the behavior is present when opening a different project/folder.
- Check for conflicts in Keyboard Shortcuts and adjust `when` clauses only if required.

## Notes

- Your requested shortcuts may conflict with existing editor/navigation shortcuts; if so, we will override only the conflicting specific command and keep changes minimal.


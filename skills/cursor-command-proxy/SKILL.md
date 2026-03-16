---
name: cursor-command-proxy
description: >-
  Execute Cursor Command Palette commands and keyboard shortcuts via voice/natural language.
  Use when the user asks to toggle UI elements, switch agent modes, change models,
  open previews, connect to SSH hosts, maximize chat, or run any editor command
  hands-free. Triggers on phrases like "switch to ask mode", "open markdown preview",
  "toggle sidebar", "connect to my server", "change model", or "run command [X]".
---

# Cursor Command Proxy

Translates natural-language requests into Cursor editor commands via macOS osascript keystroke simulation.

## Prerequisites

- macOS only (uses `osascript` and `System Events`)
- Cursor must have Accessibility permissions: **System Settings > Privacy & Security > Accessibility**
- SSH hosts configured in `~/.ssh/config` (for remote connections)

## How to execute a command

### Step 1: Match the request

Read [commands-reference.md](commands-reference.md) and match the user's intent to a known command.

### Step 2: Choose the method

- **Layer 1 (direct shortcut)**: If the command has a known shortcut in `commands-reference.md`, use `scripts/send_shortcut.sh`.
- **Layer 2 (palette relay)**: If no shortcut exists, use `scripts/cmd_palette.sh` with the Command Palette text, then auto-promote (see below).
- **Model selection**: For "switch to [model name]", use `scripts/select_model.sh` with the search term and position from the "Known models" table in `commands-reference.md`. Do NOT use `cmd_palette.sh` for model switching — the model picker is a dropdown, not a palette secondary input.
- **Settings change**: If the command is a settings change (font size, theme), use the `update-cursor-settings` skill instead.
- **SSH connection**: For "connect to [host]", prefer CLI: `cursor --remote ssh-remote+HOSTNAME /path`

### Step 3: Execute

**Layer 1 example** (toggle sidebar):
```bash
bash ~/.cursor/skills/cursor-command-proxy/scripts/send_shortcut.sh "b" "command down"
```

**Layer 2 example** (open markdown preview):
```bash
bash ~/.cursor/skills/cursor-command-proxy/scripts/cmd_palette.sh "Markdown Preview Enhanced: Open Preview to the Side"
```

**Model selection** (focus chat, open picker, search, arrow to position, confirm):
```bash
bash ~/.cursor/skills/cursor-command-proxy/scripts/select_model.sh "opus" 2
bash ~/.cursor/skills/cursor-command-proxy/scripts/select_model.sh "gemini" 1 "Experiment-Tracker"
```
The optional third argument is a window title substring for multi-window setups.
See the "Known models" table in [commands-reference.md](commands-reference.md) for search terms and positions.

## Quick reference (most common commands)

| User says | Method | Script call |
|---|---|---|
| "agent mode" | shortcut | `send_shortcut.sh "i" "command down"` |
| "plan mode" | shortcut | `send_shortcut.sh "l" "command down"` |
| "ask mode" / "chat mode" | shortcut | `send_shortcut.sh "a" "control down" "shift down"` |
| "switch model" / "model picker" | shortcut | `send_shortcut.sh "m" "control down" "shift down"` |
| "switch to [model]" | model script | `select_model.sh "<search>" <pos>` (see commands-reference.md) |
| "maximize chat" | shortcut | `send_shortcut.sh "x" "control down" "shift down"` |
| "toggle sidebar" | shortcut | `send_shortcut.sh "b" "command down"` |
| "zoom in" | shortcut | `send_shortcut.sh "=" "command down"` |
| "zoom out" | shortcut | `send_shortcut.sh "-" "command down"` |
| "reset zoom" | shortcut | `send_shortcut.sh "0" "command down"` |
| "format document" | shortcut | `send_shortcut.sh "f" "shift down" "option down"` |
| "word wrap" | shortcut | `send_shortcut.sh "z" "option down"` |
| "open settings" | shortcut | `send_shortcut.sh "," "command down"` |
| "markdown preview" | palette | `cmd_palette.sh "Markdown Preview Enhanced: Open Preview to the Side"` |
| "connect to [host]" | CLI | `cursor --remote ssh-remote+HOST /path` |

For the full mapping, see [commands-reference.md](commands-reference.md).

## Auto-promotion: Layer 2 to Layer 1

When a command is executed via palette relay (Layer 2), promote it to Layer 1 so it's instant next time.

### Promotion workflow

1. **Identify the command ID**: Search Cursor's source or default keybindings for the internal command ID matching the palette text. Known command IDs are listed at the bottom of [commands-reference.md](commands-reference.md).

2. **Assign a shortcut**: Read [commands-reference.md](commands-reference.md) "Auto-promotion shortcut pool" section. Pick the next `free` slot. Pools in order of preference:
   - `ctrl+shift+[1-9]`
   - `ctrl+shift+f[1-12]`
   - `ctrl+alt+[1-9]`

3. **Add keybinding**: Append to `~/Library/Application Support/Cursor/User/keybindings.json`:
   ```json
   {
       "key": "<assigned shortcut>",
       "command": "<command ID>"
   }
   ```

4. **Update commands-reference.md**: Add the command to the Layer 1 table and mark the pool slot as `used` with the command name.

5. **Export keybindings**: Run `bash ~/.cursor/scripts/sync_keybindings.sh export` to update the canonical copy.

6. **Report to user**: Tell them: "Executed [command]. Assigned `<shortcut>` for future use. Say 'change that shortcut' if you want a different one."

### Changing an assigned shortcut

If the user asks to change a shortcut:
1. Update the entry in `keybindings.json`
2. Update the pool table and Layer 1 table in `commands-reference.md`
3. Run `bash ~/.cursor/scripts/sync_keybindings.sh export`

## SSH host connections

For "connect to [hostname]":

1. **CLI method (preferred)**: `cursor --remote ssh-remote+HOSTNAME /workspace/path`
2. **Palette fallback**: `cmd_palette.sh "Remote-SSH: Connect to Host..." "hostname"`

Known hosts (from `~/.ssh/config`):
- `huh.desktop.us` -- Remote desktop
- `isaacgym` -- IsaacGym container
- `Richard.laptop.personal` -- Personal laptop
- `huh.laptop.us` -- Work laptop

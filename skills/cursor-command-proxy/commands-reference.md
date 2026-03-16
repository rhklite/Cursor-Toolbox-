# Commands Reference

## Pre-mapped commands (Layer 1)

Commands with known shortcuts. The agent uses `scripts/send_shortcut.sh` for these.

### Agent mode switching

| Natural Language Triggers | Command ID | Shortcut | send_shortcut.sh args |
|---|---|---|---|
| "switch to agent mode", "agent mode" | `composerMode.agent` | Cmd+I | `"i" "command down"` |
| "switch to plan mode", "plan mode" | `composerMode.plan` | Cmd+L | `"l" "command down"` |
| "switch to ask mode", "ask mode", "chat mode" | `composerMode.chat` | Ctrl+Shift+A | `"a" "control down" "shift down"` |
| "open model picker", "switch model", "change model" | `composer.openModelToggle` | Ctrl+Shift+M | `"m" "control down" "shift down"` |

### Model selection (via select_model.sh)

The model picker is a dropdown, not a palette input. Use `scripts/select_model.sh` to select a specific model. Do NOT use `cmd_palette.sh` for this.

Known models (search term and 1-based position in filtered results):

| User says | Search term | Position | select_model.sh call |
|---|---|---|---|
| "switch to opus max" | opus | 1 | `select_model.sh "opus" 1` |
| "switch to opus" | opus | 2 | `select_model.sh "opus" 2` |
| "switch to sonnet" | sonnet | 1 | `select_model.sh "sonnet" 1` |
| "switch to gpt-4o" | gpt-4o | 1 | `select_model.sh "gpt-4o" 1` |
| "switch to o3" | o3 | 1 | `select_model.sh "o3" 1` |
| "switch to gemini" | gemini | 1 | `select_model.sh "gemini" 1` |

If the model is not listed, open the model picker manually and note the search term and position, then add it to this table.
| "maximize chat", "maximize agent", "full screen chat" | `composer.maxMode` | Ctrl+Shift+X | `"x" "control down" "shift down"` |

### UI toggles

| Natural Language Triggers | Command ID | Shortcut | send_shortcut.sh args |
|---|---|---|---|
| "toggle sidebar", "hide sidebar", "show sidebar" | `workbench.action.toggleSidebarVisibility` | Cmd+B | `"b" "command down"` |
| "toggle terminal", "open terminal", "close terminal" | `workbench.action.terminal.toggleTerminal` | Ctrl+\` | *use cmd_palette.sh* |
| "toggle unified sidebar" | `workbench.action.toggleUnifiedSidebarFromKeyboard` | Opt+Cmd+S | `"s" "option down" "command down"` |

### Zoom

| Natural Language Triggers | Command ID | Shortcut | send_shortcut.sh args |
|---|---|---|---|
| "zoom in", "make it bigger", "bigger text" | `workbench.action.zoomIn` | Cmd+= | `"=" "command down"` |
| "zoom out", "make it smaller", "smaller text" | `workbench.action.zoomOut` | Cmd+- | `"-" "command down"` |
| "reset zoom", "normal zoom", "default zoom" | `workbench.action.zoomReset` | Cmd+0 | `"0" "command down"` |

### Editor commands

| Natural Language Triggers | Command ID | Shortcut | send_shortcut.sh args |
|---|---|---|---|
| "format document", "format this file" | `editor.action.formatDocument` | Shift+Opt+F | `"f" "shift down" "option down"` |
| "toggle word wrap", "word wrap" | `editor.action.toggleWordWrap` | Opt+Z | `"z" "option down"` |
| "close tab", "close this file" | `workbench.action.closeActiveEditor` | Cmd+W | `"w" "command down"` |
| "split editor", "split view" | `workbench.action.splitEditor` | Cmd+\\ | `"\\\\" "command down"` |
| "open settings", "settings" | `workbench.action.openSettings` | Cmd+, | `"," "command down"` |
| "zen mode", "focus mode" | `workbench.action.toggleZenMode` | Cmd+K Z | *two-step: see note* |

Note for Zen mode: This is a chord shortcut (Cmd+K then Z). Use `cmd_palette.sh "View: Toggle Zen Mode"` instead.

### Settings-based commands

These are handled by editing `settings.json` directly (via the existing `update-cursor-settings` skill), not via osascript.

| Natural Language Triggers | Setting Key |
|---|---|
| "increase font size", "bigger font" | `editor.fontSize` (increment) |
| "decrease font size", "smaller font" | `editor.fontSize` (decrement) |
| "high contrast theme", "switch to high contrast" | `workbench.colorTheme` |
| "dark theme", "light theme" | `workbench.colorTheme` |

## Palette-only commands (Layer 2)

Commands without known shortcuts. The agent uses `scripts/cmd_palette.sh` for these. After first use, the agent auto-promotes them to Layer 1 by assigning a shortcut.

| Natural Language Triggers | Command Palette Text |
|---|---|
| "open markdown preview", "preview markdown" | `Markdown Preview Enhanced: Open Preview to the Side` |
| "connect to [host]" | `Remote-SSH: Connect to Host...` (or use CLI: `cursor --remote ssh-remote+HOST PATH`) |
| "toggle explorer", "show explorer" | `View: Toggle Explorer` |
| "toggle minimap" | `View: Toggle Minimap` |
| "go to line [N]" | `Go to Line/Column...` |
| "reopen closed tab" | `View: Reopen Closed Editor` |

## Auto-promotion shortcut pool

When the agent promotes a Layer 2 command to Layer 1, it assigns the next free shortcut from this pool.

### Pool: Ctrl+Shift+[number]

| Slot | Status | Assigned Command |
|---|---|---|
| `ctrl+shift+1` | free | |
| `ctrl+shift+2` | free | |
| `ctrl+shift+3` | free | |
| `ctrl+shift+4` | free | |
| `ctrl+shift+5` | free | |
| `ctrl+shift+6` | free | |
| `ctrl+shift+7` | free | |
| `ctrl+shift+8` | free | |
| `ctrl+shift+9` | free | |

### Pool: Ctrl+Shift+F[number]

| Slot | Status | Assigned Command |
|---|---|---|
| `ctrl+shift+f1` | free | |
| `ctrl+shift+f2` | free | |
| `ctrl+shift+f3` | free | |
| `ctrl+shift+f4` | free | |
| `ctrl+shift+f5` | free | |
| `ctrl+shift+f6` | free | |
| `ctrl+shift+f7` | free | |
| `ctrl+shift+f8` | free | |
| `ctrl+shift+f9` | free | |
| `ctrl+shift+f10` | free | |
| `ctrl+shift+f11` | free | |
| `ctrl+shift+f12` | free | |

### Pool: Ctrl+Alt+[number]

| Slot | Status | Assigned Command |
|---|---|---|
| `ctrl+alt+1` | free | |
| `ctrl+alt+2` | free | |
| `ctrl+alt+3` | free | |
| `ctrl+alt+4` | free | |
| `ctrl+alt+5` | free | |
| `ctrl+alt+6` | free | |
| `ctrl+alt+7` | free | |
| `ctrl+alt+8` | free | |
| `ctrl+alt+9` | free | |

## Known Cursor command IDs (reference)

All available composer mode commands discovered from Cursor source:

- `composerMode.agent` -- Agent mode
- `composerMode.plan` -- Plan mode
- `composerMode.chat` -- Ask/Chat mode
- `composerMode.edit` -- Edit mode
- `composerMode.debug` -- Debug mode
- `composerMode.project` -- Project mode
- `composerMode.spec` -- Spec mode
- `composerMode.triage` -- Triage mode
- `composer.openModelToggle` -- Open model picker
- `composer.cycleModel` -- Cycle to next model
- `composer.maxMode` -- Maximize/minimize chat panel
- `composer.openModeMenu` -- Open mode selection menu
- `composer.openAsPane` -- Open chat as pane
- `composer.openAsBar` -- Open chat as bar
- `composer.toggleChatAsEditor` -- Toggle chat as editor tab

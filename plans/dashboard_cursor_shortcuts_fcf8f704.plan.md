---
name: Dashboard Cursor Shortcuts
overview: Add an "Open in Cursor" menu bar item to the PLT app and a Cursor task to open the dashboard in Cursor's Simple Browser.
todos:
  - id: menubar-item
    content: Add 'Open in Cursor' menu item to menubar_app.py
    status: completed
  - id: cursor-task
    content: Create .vscode/tasks.json with 'Open Dashboard' task
    status: completed
isProject: false
---

# Dashboard Cursor Shortcuts

## 1. Menu bar item: "Open in Cursor"

In `[menubar_app.py](/Users/HanHu/software/policy-lineage-tracker/menubar_app.py)`, add a new menu item between "Open Dashboard" and the separator. It will use the `cursor` CLI (at `/usr/local/bin/cursor`) to open the Simple Browser:

```python
rumps.MenuItem("Open in Cursor", callback=self._open_in_cursor),
```

The callback runs:

```bash
cursor --open-url "http://127.0.0.1:8765"
```

This opens (or focuses) the dashboard URL inside Cursor's Simple Browser panel.

## 2. Cursor task in `.vscode/tasks.json`

Create `[.vscode/tasks.json](/Users/HanHu/software/policy-lineage-tracker/.vscode/tasks.json)` with a task labeled **"Open Dashboard"** so it appears in `Cmd+Shift+P` > "Tasks: Run Task". The task runs the same `cursor --open-url` command. It also ensures the server is started first (in case the menu bar app isn't running).
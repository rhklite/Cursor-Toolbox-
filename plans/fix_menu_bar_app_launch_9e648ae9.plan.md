---
name: Fix Menu Bar App Launch
overview: Fix the menu bar app so it handles port conflicts gracefully (reuse or kill stale server) and reliably launches from Finder double-click.
todos:
  - id: kill-stale
    content: Kill stale Python process on port 8765
    status: completed
  - id: fix-menubar
    content: "Update menubar_app.py: kill stale port holder on startup, add error notification, auto-open browser on first launch"
    status: completed
isProject: false
---

# Fix Menu Bar App Launch

The app code is correct and runs fine. It failed because a previous Python server was already occupying port 8765, and since `LSUIElement` hides the app from the Dock, the crash was silent.

## Changes to `[menubar_app.py](/Users/HanHu/software/policy-lineage-tracker/menubar_app.py)`

- **On startup**, check if port 8765 is already bound. If so, kill the existing process (it's a stale instance of this same server) before starting a new one.
- **Wrap server start** in a try/except so a port conflict produces a user-visible `rumps.notification()` instead of a silent crash.
- **Auto-open** the dashboard in the browser on first launch so the user gets immediate feedback that it's working.

## Kill stale server + cleanup

- Kill PID 49983 (the stale process currently holding port 8765) as part of execution.


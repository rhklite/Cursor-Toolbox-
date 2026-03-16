---
name: Hide Python Dock Icon
overview: Set the NSApplication activation policy to "accessory" before rumps starts, so no Python icon appears in the Dock.
todos: []
isProject: false
---

# Hide Python Dock Icon

The Python rocket icon in the Dock appears because the Python framework registers its own GUI presence independently of the `.app` bundle's `LSUIElement` plist key. The fix is to explicitly set the process's activation policy to **accessory** via AppKit before `rumps` starts the run loop.

## Change in `[menubar_app.py](/Users/HanHu/software/policy-lineage-tracker/menubar_app.py)`

Add these lines **before** `DashboardApp().run()` (around line 89-90):

```python
from AppKit import NSApplication, NSApplicationActivationPolicyAccessory
NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyAccessory)
```

This tells macOS the process is a background/accessory app -- it will only appear in the menu bar, never in the Dock. The `LSUIElement` plist key is kept as a fallback but the Python-level call is what actually prevents the Dock icon.

Single-file change, ~3 lines added.
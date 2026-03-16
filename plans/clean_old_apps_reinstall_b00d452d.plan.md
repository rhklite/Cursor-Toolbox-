---
name: Clean old apps reinstall
overview: Remove all deprecated/stale experiment tracker app bundles from system and project build directories, then rebuild and reinstall the current app.
todos:
  - id: remove-system
    content: Remove /Applications/Experiment Tracker.app
    status: completed
  - id: remove-build
    content: Remove stale build/dist artifacts (build/Experiment Tracker.app, build/bdist.*, dist/Policy Tracker.app, dist/)
    status: completed
  - id: rebuild-install
    content: Run build_app.sh to rebuild and install to ~/Applications and /Applications
    status: completed
isProject: false
---

# Clean Old Apps and Reinstall

## What exists now


| Location | Description | Status |
| -------- | ----------- | ------ |


- `/Applications/Experiment Tracker.app` -- Old version (Mar 11), no icon, stale launch script (4674 B vs current 4223 B). **Remove.**
- `~/Applications/Experiment Tracker.app` -- Installed earlier this session with icon, but from a direct copy (not via `build_app.sh`). **Will be replaced by fresh build.**
- `build/Experiment Tracker.app/` -- Leftover osacompile output with default `applet.icns`. **Remove.**
- `build/bdist.macosx-10.9-universal2/` -- Old py2app build artifacts from the deprecated "Policy Tracker" era. **Remove.**
- `dist/Policy Tracker.app/` -- Deprecated py2app bundle under the old name. **Remove.**

## Steps

1. **Remove deprecated apps from system folders**
  - `rm -rf /Applications/Experiment\ Tracker.app`
2. **Remove stale build artifacts from the repo**
  - `rm -rf build/Experiment\ Tracker.app`
  - `rm -rf build/bdist.macosx-10.9-universal2`
  - `rm -rf dist/Policy\ Tracker.app`
  - Remove leftover `dist/.DS_Store`; if `dist/` is now empty, remove it too.
3. **Rebuild and install via [build_app.sh](build_app.sh)**
  - Runs `osacompile` to produce a fresh `build/Experiment Tracker.app`
  - Copies `AppIcon.icns` into the built bundle and sets `CFBundleIconFile`
  - Installs to `~/Applications` and `/Applications`


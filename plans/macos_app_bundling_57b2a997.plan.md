---
name: macOS App Bundling
overview: Bundle the Policy Lineage Tracker as a self-contained macOS .app using py2app (for the menubar GUI) with the CLI embedded inside the bundle, so the whole thing can be drag-and-dropped into /Applications on any Mac.
todos:
  - id: requirements
    content: Create requirements.txt with rumps and pyobjc-framework-Cocoa
    status: completed
  - id: setup-py
    content: Create setup.py with py2app configuration, Info.plist overrides, and data file includes
    status: completed
  - id: cli-wrapper
    content: Create bin/tracker shell wrapper script that uses the bundled Python interpreter to run tracker_cli.py
    status: completed
  - id: menubar-cli-install
    content: Add 'Install CLI Tool' menu item to menubar_app.py that symlinks the CLI to /usr/local/bin/tracker
    status: completed
  - id: remove-old-app
    content: Delete the old Policy Tracker.app shell-script bundle
    status: completed
  - id: build-script
    content: Create build_app.sh script to automate the py2app build and optionally produce a .dmg
    status: completed
  - id: gitignore
    content: Update .gitignore with build/ and dist/ directories
    status: completed
  - id: test-build
    content: Run the build and verify the .app launches correctly
    status: completed
isProject: false
---

# macOS App Bundle for Policy Lineage Tracker

## Current State

- Pure Python app with 3 source modules: `tracker_store.py`, `tracker_cli.py`, `dashboard_server.py`
- macOS menubar app: `menubar_app.py` (uses `rumps` + `PyObjC/AppKit`)
- No external static assets (HTML dashboard is inline in `dashboard_server.py`)
- Existing `Policy Tracker.app` is a hardcoded shell script that only works on your machine
- No `requirements.txt` or `setup.py` exists yet

## Approach: py2app

**py2app** is the standard macOS Python bundler and works best with `rumps`/`PyObjC` apps. It embeds a Python interpreter and all dependencies into a self-contained `.app` bundle.

```
Policy Tracker.app/
  Contents/
    MacOS/
      Policy Tracker        <-- native launcher (py2app generates this)
    Resources/
      lib/                  <-- bundled Python + packages
      bin/tracker            <-- CLI wrapper script
      __boot__.py
      ...
    Info.plist
```

The CLI will be embedded inside the `.app` bundle at `Contents/Resources/bin/tracker`. The menubar app will include an "Install CLI" menu item that symlinks it to `/usr/local/bin/tracker` for terminal access.

## Steps

### 1. Create `requirements.txt`

- `rumps`
- `pyobjc-framework-Cocoa`

### 2. Create `setup.py` for py2app

- Entry point: `menubar_app.py`
- Include data files: all Python source modules
- Configure `Info.plist` (LSUIElement=true for menubar-only app, bundle ID, version)
- Set app name to "Policy Tracker"

### 3. Add an app icon

- Create a basic `.icns` icon file so the app looks professional in Finder/Launchpad (can use a simple placeholder or skip if not desired)

### 4. Embed CLI inside the bundle

- Create a `bin/tracker` shell wrapper at `Contents/Resources/bin/tracker` that uses the bundled Python to run `tracker_cli.py`
- Add an "Install CLI Tool" menu item to `menubar_app.py` that symlinks the wrapper to `/usr/local/bin/tracker`

### 5. Replace the old `Policy Tracker.app`

- Delete the existing shell-script-based `.app` since py2app will generate a proper one

### 6. Add a build script

- `build_app.sh` that runs `python setup.py py2app` and produces the `.app` in `dist/`
- Optionally create a `.dmg` disk image for distribution

### 7. Update `.gitignore`

- Add `build/`, `dist/` directories (py2app output)

## Dependencies to install (build-time only)

- `py2app` (build tool, not bundled into the app)

## What the user gets

- `dist/Policy Tracker.app` -- drag into /Applications
- Double-click launches the menubar icon (dashboard server + Open/Quit controls)
- "Install CLI" menu item creates `/usr/local/bin/tracker` for terminal usage
- Fully self-contained -- no Python, pip, or any setup needed on the target Mac


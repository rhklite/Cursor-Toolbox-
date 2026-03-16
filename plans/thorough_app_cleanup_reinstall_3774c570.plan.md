---
name: Thorough app cleanup reinstall
overview: Discard stale uncommitted changes, fix the osacompile icon conflict, clear macOS icon caches, rebuild Docker to serve the current branch's dashboard, and reinstall the app cleanly.
todos:
  - id: reset-tree
    content: git checkout -- . && git clean -fd to discard previous session's uncommitted changes
    status: completed
  - id: remove-installed
    content: Remove ~/Applications and /Applications Experiment Tracker.app, and build/ directory
    status: completed
  - id: gen-icon
    content: Generate icon, produce .icns, place in source app bundle, update source Info.plist
    status: completed
  - id: fix-build-script
    content: Update build_app.sh to remove applet.icns, Assets.car, and CFBundleIconName after osacompile
    status: completed
  - id: rebuild-docker
    content: docker compose down + build --no-cache to serve current branch dashboard
    status: completed
  - id: clear-icon-cache
    content: Clear macOS icon caches and restart Dock/Finder
    status: completed
  - id: build-install
    content: Run build_app.sh to build and install the app
    status: completed
isProject: false
---

# Thorough App Cleanup and Reinstall

## Root causes found

1. **Icon conflict in osacompile plist**: The installed app's `Info.plist` has *both* `CFBundleIconFile = AppIcon` and `CFBundleIconName = applet`. On modern macOS, `CFBundleIconName` (backed by `Assets.car`) takes priority, so macOS still renders the generic AppleScript icon. The leftover `applet.icns` and `Assets.car` in Resources compound this.
2. **Dirty working tree from previous session**: Uncommitted changes (icon additions, `build_app.sh` edits, modified `Info.plist`) are floating on `feature/experiment-tracker` from work done in the previous session. These need to be discarded so we start clean.
3. **Docker image cache**: The launch script runs `docker compose up -d --build`, but Docker layer caching may still serve the old branch's `dashboard_server.py`. The image must be rebuilt with `--no-cache`.
4. **macOS icon cache**: Even after fixing the plist, macOS caches icons in `com.apple.iconservices`. This cache must be cleared.

## Steps

### 1. Reset the working tree to clean branch state

```bash
git checkout -- .
git clean -fd
```

This discards the previous session's uncommitted modifications to `build_app.sh`, `Info.plist`, and removes the untracked `AppIcon.icns` files.

### 2. Remove all installed apps

```bash
rm -rf ~/Applications/Experiment\ Tracker.app
rm -rf /Applications/Experiment\ Tracker.app
rm -rf build/
```

### 3. Generate the app icon

- Use the image generation tool to create a 1024x1024 source PNG
- Use `sips` to produce the iconset at all required sizes
- Use `iconutil -c icns` to produce `AppIcon.icns`
- Place it at `Experiment Tracker.app/Contents/Resources/AppIcon.icns`
- Add `CFBundleIconFile = AppIcon` to [Experiment Tracker.app/Contents/Info.plist](Experiment Tracker.app/Contents/Info.plist)

### 4. Fix `build_app.sh` to eliminate osacompile icon conflicts

After the `osacompile` step, the build script must:

- Copy `AppIcon.icns` into the built app's `Resources/`
- **Remove** `applet.icns` and `Assets.car` (the generic AppleScript icon assets)
- Use PlistBuddy to **set** `CFBundleIconFile` to `AppIcon`
- Use PlistBuddy to **delete** `CFBundleIconName` (which points to the `applet` asset in `Assets.car`)

This ensures macOS has no fallback to the generic icon.

### 5. Rebuild the Docker image from scratch

```bash
docker compose down --remove-orphans 2>/dev/null || true
docker compose build --no-cache
```

This ensures the dashboard serves the `feature/experiment-tracker` branch's code.

### 6. Clear macOS icon cache and rebuild

```bash
sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null
sudo find /private/var/folders -name com.apple.iconservices -exec rm -rf {} + 2>/dev/null
sudo find /private/var/folders -name com.apple.dock.iconcache -exec rm -rf {} + 2>/dev/null
killall Dock
killall Finder
```

### 7. Run build and install

```bash
bash build_app.sh
```

This produces a fresh `build/Experiment Tracker.app` with the correct icon and installs to both `~/Applications` and `/Applications`.
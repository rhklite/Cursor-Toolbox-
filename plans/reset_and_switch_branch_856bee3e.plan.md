---
name: Reset and switch branch
overview: Fetch from origin, discard all local changes, and switch to the `huh8/apple-bundle-build` feature branch hard-reset to its remote.
todos:
  - id: fetch
    content: git fetch origin
    status: completed
  - id: discard
    content: Discard local changes (checkout + clean)
    status: completed
  - id: switch
    content: Checkout huh8/apple-bundle-build and hard reset to origin
    status: completed
isProject: false
---

# Reset Local to Remote and Switch to Feature Branch

## Current state

- Branch: `development` (no remote tracking branch)
- Modified: `dashboard_server.py`
- Feature branch: `huh8/apple-bundle-build` (remote: `origin/huh8/apple-bundle-build`)

## Steps

1. **Fetch latest remote state**

```bash
   git fetch origin
   

```

1. **Discard all local changes on current branch**

```bash
   git checkout -- .
   git clean -fd
   

```

1. **Switch to feature branch and hard reset to remote**

```bash
   git checkout huh8/apple-bundle-build
   git reset --hard origin/huh8/apple-bundle-build
   

```

## Notes

- `git clean -fd` will remove untracked files/dirs (the `build/` and `dist/` artifacts). If you want to keep those, we can add them to `.gitignore` instead or skip the clean step.
- The `development` branch itself will remain as-is (just its working-tree changes are discarded).


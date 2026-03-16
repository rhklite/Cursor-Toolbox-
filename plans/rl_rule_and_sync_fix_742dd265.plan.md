---
name: RL Rule and Sync Fix
overview: Add a project-scoped Cursor rule in motion_rl that auto-invokes the rl-thinking-partner skill, and fix the sync script to remove fuyao from the target list and guard against syncing to the current host.
todos:
  - id: create-project-rule
    content: Create ~/.cursor/rules/motion-rl-thinking-partner.mdc (personal toolbox rule, path-scoped to motion_rl)
    status: completed
  - id: fix-sync-targets
    content: Remove Huh8.remote_kernel.fuyao from TARGET_ALIASES and ordered_sources in sync_toolbox.sh
    status: completed
  - id: add-self-skip
    content: Add is_self() helper and gate in sync_toolbox_destination
    status: completed
  - id: commit-push-sync
    content: Commit, push, and run sync
    status: completed
isProject: false
---

# RL Rule and Sync Fix

## Change 1 — Personal toolbox rule, path-scoped to motion_rl

**File:** `~/.cursor/rules/motion-rl-thinking-partner.mdc`

Rule lives in the personal toolbox — never touches the project repo. Cursor's `globs` frontmatter restricts activation to files under the motion_rl workspace path, so the rule fires only when working there.

```markdown
---
description: Auto-invokes the rl-thinking-partner skill when working in the motion_rl repository.
globs: '/home/huh/software/motion_rl/**'
alwaysApply: false
---

When the user is working in the motion_rl repository, read and apply the rl-thinking-partner skill from ~/.cursor/skills/rl-thinking-partner/SKILL.md.
```

The skill file stays at `~/.cursor/skills/rl-thinking-partner/SKILL.md` — untouched. This rule will trigger the sync-toolbox workflow (it lives in `~/.cursor/rules/`).

## Change 2 — Fix sync_toolbox.sh

File: `[/home/huh/.cursor/scripts/sync_toolbox.sh](/home/huh/.cursor/scripts/sync_toolbox.sh)`

### 2a — Remove fuyao from TARGET_ALIASES (line 10)

Current:

```bash
TARGET_ALIASES=("huh.desktop.us" "isaacgym" "Huh8.remote_kernel.fuyao")
```

New:

```bash
TARGET_ALIASES=("huh.desktop.us" "isaacgym")
```

### 2b — Add self-skip safeguard to `validate_alias_exists` / apply loop

The `sync_toolbox_destination` function (line 146) dispatches to either `sync_toolbox_repo_local` (for `"local"`) or `sync_toolbox_repo_remote` for all aliases — no self-check exists.

Add a helper function after line 183 that resolves an SSH alias's target hostname and compares it to `$(hostname)`. If they match, skip with a log message:

```bash
is_self() {
  local alias_name="$1"
  local resolved_host
  resolved_host="$(ssh -G "${alias_name}" 2>/dev/null | awk '/^hostname / {print $2}')"
  local self_host
  self_host="$(hostname)"
  [[ "${resolved_host}" == "${self_host}" ]] && return 0
  return 1
}
```

Then gate `sync_toolbox_destination` to call `is_self` before SSHing:

```bash
sync_toolbox_destination() {
  local destination="$1"
  local dry_run="$2"

  if [[ "${dry_run}" == "true" ]]; then
    log "DRY-RUN: ${destination} toolbox git pull/merge"
    return 0
  fi

  if [[ "${destination}" == "local" ]]; then
    sync_toolbox_repo_local "${TOOLBOX_REPO_DIR}"
  elif is_self "${destination}"; then
    log "Skipping self-sync: ${destination} resolves to this host ($(hostname))"
    return 0
  else
    sync_toolbox_repo_remote "${destination}"
  fi
}
```

Also update the hardcoded `ordered_sources` list in the Python block at line 321 to remove fuyao:

```python
ordered_sources = ["local", "huh.desktop.us", "isaacgym"]
```

## Steps

1. Create `~/.cursor/rules/motion-rl-thinking-partner.mdc` (personal toolbox, path-scoped)
2. Edit `~/.cursor/scripts/sync_toolbox.sh`:

- Line 10: remove `Huh8.remote_kernel.fuyao` from `TARGET_ALIASES`
- Line 321: remove `Huh8.remote_kernel.fuyao` from `ordered_sources` Python list
- After line 183: insert `is_self()` helper
- Lines 146-160: add `elif is_self` guard in `sync_toolbox_destination`

1. Commit and push `~/.cursor` (scripts changed → sync-toolbox rule applies)
2. Run sync to `huh.desktop.us` and `isaacgym` only — self-skip will guard against huh.desktop.us, isaacgym will be attempted

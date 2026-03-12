---
name: resolve-linter-errors
description: Resolve all linter errors in the current file or across the repo when specified. Use when the user asks to fix linter errors, resolve lint issues, fix diagnostics, or fix lint in file or whole repo.
---

# Resolve Linter Errors

## Instructions

1. **Read linter output**
   - Use the ReadLints tool. Omit path for workspace-wide diagnostics; pass a file or directory path to scope.
   - If scope is repo, call ReadLints with no path (or repo root).

2. **Resolve errors**
   - Fix each reported diagnostic (errors; include warnings if the user asked to fix those).
   - Prefer minimal, targeted edits; fix root cause and avoid unnecessary style churn.
   - After editing, run ReadLints again on the changed file(s) or scope to confirm fixes and catch regressions.

3. **Scope rules**
   - "This file" / "current file" / no scope stated → ReadLints for the current or explicitly given file path.
   - "Repo" / "whole repo" / "all files" / "entire codebase" → ReadLints with no path (or repo root), then fix across all reported files.

4. **Constraints**
   - Only fix diagnostics that are clearly fixable; do not guess user intent.
   - If a fix is ambiguous, ask the user or add a short comment and leave a TODO.

## Scope

| User intent | ReadLints call | Fix scope |
|-------------|----------------|-----------|
| Current file / this file / (none) | `ReadLints({ paths: [filePath] })` or file/dir | That file (or directory) |
| Whole repo / all files / entire codebase | `ReadLints()` or repo root | All files with diagnostics |

## Example

**File scope:** "Fix linter errors in this file" → ReadLints for that file, fix each diagnostic, re-run ReadLints.

**Repo scope:** "Fix all linter errors in the repo" → ReadLints with no path, fix diagnostics in each reported file, re-run ReadLints for changed files or full workspace.

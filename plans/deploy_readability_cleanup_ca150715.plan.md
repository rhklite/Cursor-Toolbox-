---
name: Deploy Readability Cleanup
overview: Refactor the deploy flow for readability only, with no behavior changes, primarily in the deploy script and matching command doc wording.
todos:
  - id: refactor-layout
    content: Restructure deploy_fuyao.sh into clearer sections and consistent formatting
    status: completed
  - id: comments-pass
    content: Rewrite comments for intent-focused clarity; remove redundant comments
    status: completed
  - id: doc-sync
    content: Align deploy-fuyao.md wording/order with script readability improvements only
    status: completed
  - id: sanity-verify
    content: Run bash syntax check and lightweight diagnostics for edited files
    status: completed
isProject: false
---

# Deploy Readability Cleanup Plan

## Goal

Improve human readability and maintainability without changing runtime behavior.

## Scope

- Primary: `[/home/huh/.cursor/scripts/deploy_fuyao.sh](/home/huh/.cursor/scripts/deploy_fuyao.sh)`
- Secondary wording sync: `[/home/huh/.cursor/commands/deploy-fuyao.md](/home/huh/.cursor/commands/deploy-fuyao.md)`
- No functional or workflow changes.

## Planned Changes

- Reorganize the script into clear sections with consistent headers:
  - constants/defaults
  - helpers
  - arg parsing
  - validation
  - step execution (`SSH check`, `git sync`, `remote sync`, `deploy`)
- Improve naming consistency and visual alignment for key variables used in deploy composition.
- Simplify dense blocks by extracting small readability helpers where this does not alter behavior (e.g., repeated error/echo patterns).
- Tighten comments to explain intent (why) rather than mechanics (what), and remove redundant/noisy comments.
- Standardize shell formatting for scanability:
  - consistent indentation
  - wrapped long command arrays
  - uniform case-statement layout
  - predictable blank-line spacing between logical blocks
- Sync command-doc wording to match the script’s readable structure and terminology only (no workflow or argument policy changes).

## Validation

- Run a dry parse/sanity check of the script (`bash -n`) after refactor.
- Verify that generated deploy command text is unchanged in semantics for a representative invocation.
- Quick lint/diagnostic check for edited files.

## Out of Scope

- Changing defaults, deploy flow, flag semantics, or remote/local execution behavior.
- Introducing new deployment features or preflight automation.

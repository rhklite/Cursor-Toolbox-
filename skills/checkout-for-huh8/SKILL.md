---
name: checkout-for-huh8
description: Derive and checkout huh8-prefixed git branches while preserving already-prefixed branches, and prompt for explicit suffix when creating a new branch from a huh8 source branch. Use when the user asks to create, rename, or checkout branches with huh8 naming or company-ID branch conventions.
---

# Checkout For huh8

## When To Apply

Apply this skill when user intent includes:
- checking out a new branch
- creating a branch with company-ID naming
- converting another developer's branch prefix to `huh8/`

## Branch Naming Rule

Always use this exact rule unless user explicitly overrides it:

1. Canonical prefix is `huh8/`.
2. Read source branch (current branch before checkout).
3. If source branch already starts with `huh8/`:
   - Preserve it and check out normally.
   - Do not replace prefix.
4. If source branch does not start with `huh8/`:
   - If user provides explicit suffix, use it.
   - Otherwise derive suffix from source branch:
     - If source branch contains `/`, strip everything through the first `/`.
     - If source branch has no `/`, use the full source branch.
   - Build target branch: `huh8/<suffix>`.
5. Special case: user asks to create a new branch from an already-`huh8/` source branch:
   - Require a new explicit suffix.
   - If suffix is missing or underspecified, prompt the user.
   - Build target branch: `huh8/<new_suffix>`.

Examples:
- `alice/feature-x` -> `huh8/feature-x`
- `bob/fix/a` -> `huh8/fix/a`
- `main` -> `huh8/main`
- `huh8/feature-x` + normal checkout request -> `huh8/feature-x` (preserved)
- `huh8/feature-x` + new-branch request + suffix `hotfix-1` -> `huh8/hotfix-1`

## Checkout Workflow

1. Verify repository context:
   - `git rev-parse --is-inside-work-tree`
2. Get source branch:
   - `git rev-parse --abbrev-ref HEAD`
3. Compute `target_branch` with the naming rule.
4. If local target exists:
   - `git checkout <target_branch>`
5. Otherwise create from current HEAD:
   - `git checkout -b <target_branch>`
6. Report final result with:
   - source branch
   - derived/provided suffix
   - final target branch

## Guardrails

- Keep prefix fixed as `huh8/` unless user asks otherwise.
- If in detached HEAD, ask for explicit suffix before checkout.
- If suffix is empty after derivation, ask for explicit suffix.
- If source already starts with `huh8/` and user wants a new branch, require explicit suffix.

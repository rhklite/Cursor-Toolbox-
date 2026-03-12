# Checkout For huh8

Create or switch to a branch prefixed with `huh8/`.
Invoke as `/checkout-for-huh8`.

## Inputs

- Optional: `suffix` (the branch suffix after `huh8/`).

## Branch Naming Rule

1. Canonical prefix is `huh8/`.
2. Read source branch (current branch before checkout).
3. If source branch already starts with `huh8/`:
   - Preserve it and check out that branch normally.
   - Do not replace the prefix.
4. If source branch does not start with `huh8/`:
   - If user provides `suffix`, use it.
   - Otherwise derive suffix from source branch:
     - If source branch contains `/`, strip everything through the first `/`.
     - If source branch has no `/`, use the full source branch.
   - Build target branch as `huh8/<suffix>`.
5. Special case: if user explicitly asks to create a new branch from an already-`huh8/` source branch:
   - User must provide a new suffix.
   - If suffix is missing or underspecified, prompt the user before checkout.
   - Use `huh8/<new_suffix>` as target branch.

Examples:
- `alice/feature-x` -> `huh8/feature-x`
- `bob/fix/a` -> `huh8/fix/a`
- `main` -> `huh8/main`
- `huh8/feature-x` + normal checkout request -> `huh8/feature-x` (preserved)
- `huh8/feature-x` + new-branch request + `suffix=hotfix-1` -> `huh8/hotfix-1`

## Execution Flow

1. Confirm current directory is inside a git work tree.
2. Get source branch with:
   - `git rev-parse --abbrev-ref HEAD`
3. Compute target branch from the rule above.
4. If target branch exists locally, switch to it:
   - `git checkout <target_branch>`
5. If target branch does not exist locally, create from current HEAD:
   - `git checkout -b <target_branch>`
6. Report:
   - source branch
   - derived/provided suffix
   - final target branch

## Guardrails

- Do not change prefix `huh8/` unless user explicitly requests it.
- If there is no valid source branch name (detached HEAD), ask for explicit suffix.
- If source already starts with `huh8/` and user asks for a new branch but suffix is unclear, prompt for a concrete suffix.
- Quote user-provided suffix safely in shell commands.

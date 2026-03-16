---
name: huh8-branch-workflows
overview: Create both a personal Cursor command and a personal Cursor skill for checkout flows that use lowercase `huh8/`, preserve already-`huh8/` branches, and require explicit suffix when creating new branches from an already-prefixed source branch.
todos:
  - id: author-command
    content: Create personal command `/checkout-for-huh8` with optional suffix input and checkout flow.
    status: pending
  - id: author-skill
    content: Create personal skill `checkout-for-huh8` with clear auto-trigger description and shared branch derivation rules.
    status: pending
  - id: verify-rules
    content: Validate examples against strip-first-segment rule and ensure command/skill logic matches exactly.
    status: pending
  - id: sync-toolbox
    content: Run toolbox sync workflow after file creation so updates propagate safely across configured hosts.
    status: pending
isProject: false
---

# Build Command + Skill for huh8 Branch Checkout

## Decision

Use **both** artifacts:

- a manual command for explicit invocation
- a skill for automatic application during conversational checkout requests

This gives you deterministic manual control and agent-driven convenience with identical naming behavior.

## Target Files

- `[/Users/HanHu/.cursor/commands/checkout-for-huh8.md](/Users/HanHu/.cursor/commands/checkout-for-huh8.md)`
- `[/Users/HanHu/.cursor/skills/checkout-for-huh8/SKILL.md](/Users/HanHu/.cursor/skills/checkout-for-huh8/SKILL.md)`

## Shared Branch Rule (used by both)

1. Canonical prefix is lowercase `huh8/`.
2. Read current branch (the branch being checked out **from**).
3. If current branch already starts with `huh8/`:
  - preserve it and check out that branch normally (no prefix replacement).
4. If current branch does **not** start with `huh8/`:
  - derive suffix by removing everything through the first `/` when present,
  - otherwise use the whole current branch,
  - then build target as `huh8/<suffix>`.
5. If user explicitly provides a suffix, use `huh8/<user_suffix>`.
6. Special case: user asks to create a **new** branch from an already `huh8/` branch:
  - require user-provided new suffix,
  - if suffix is missing or underspecified, prompt user before checkout.
7. Checkout behavior:
  - switch if target exists (`git checkout ...`),
  - otherwise create (`git checkout -b ...`).

## Command Content Design

In `[/Users/HanHu/.cursor/commands/checkout-for-huh8.md](/Users/HanHu/.cursor/commands/checkout-for-huh8.md)`:

- Define invocation as `/checkout-for-huh8`.
- Accept optional `suffix` input.
- Enforce the shared rule above.
- Include concise execution flow and output expectations (report source branch, derived suffix, final branch).

## Skill Content Design

In `[/Users/HanHu/.cursor/skills/checkout-for-huh8/SKILL.md](/Users/HanHu/.cursor/skills/checkout-for-huh8/SKILL.md)`:

- Add frontmatter with clear trigger terms (checkout, branch naming, `huh8/` prefix, create branch).
- Instruct agent to auto-apply this rule whenever user asks to create/switch branches unless user overrides prefix.
- Reuse the same derivation logic so behavior matches command exactly.

## Validation

- Dry-run logic checks with examples:
  - `alice/feature-x` -> `huh8/feature-x`
  - `bob/fix/a` -> `huh8/fix/a`
  - `main` -> `huh8/main`
  - `huh8/feature-x` + no new-branch request -> preserve as `huh8/feature-x`
  - `huh8/feature-x` + new-branch request + suffix `hotfix-1` -> `huh8/hotfix-1`
- Confirm command/skill wording avoids ambiguity about “strip only first segment”.

## Post-Create Sync

Because command/skill assets are modified under `~/.cursor`, run the toolbox sync workflow after creation/modification so other machines can receive the updates (policy/security-gated sync path).